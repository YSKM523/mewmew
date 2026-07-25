use std::fs;
use std::path::PathBuf;
use std::sync::Arc;

use mewmew_core::{CoreError, MemoryKind, MewmewCore, NewMemory};
use rusqlite::Connection;
use uuid::Uuid;

struct TestDb {
    path: PathBuf,
}

impl TestDb {
    fn new() -> Self {
        Self {
            path: std::env::temp_dir().join(format!("mewmew-core-{}.sqlite", Uuid::new_v4())),
        }
    }

    fn path_string(&self) -> String {
        self.path.to_string_lossy().into_owned()
    }

    fn open_core(&self) -> Arc<MewmewCore> {
        MewmewCore::new(self.path_string()).expect("test database should open")
    }
}

impl Drop for TestDb {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
        let _ = fs::remove_file(self.path.with_extension("sqlite-shm"));
        let _ = fs::remove_file(self.path.with_extension("sqlite-wal"));
    }
}

fn note(raw_text: &str, title: &str) -> NewMemory {
    NewMemory {
        kind: MemoryKind::Note,
        raw_text: raw_text.to_owned(),
        title: title.to_owned(),
        due_at: None,
        question: None,
        answer: None,
    }
}

fn reminder(raw_text: &str, title: &str, due_at: i64) -> NewMemory {
    NewMemory {
        kind: MemoryKind::Reminder,
        raw_text: raw_text.to_owned(),
        title: title.to_owned(),
        due_at: Some(due_at),
        question: None,
        answer: None,
    }
}

fn card(raw_text: &str, title: &str, question: &str, answer: &str) -> NewMemory {
    NewMemory {
        kind: MemoryKind::Card,
        raw_text: raw_text.to_owned(),
        title: title.to_owned(),
        due_at: None,
        question: Some(question.to_owned()),
        answer: Some(answer.to_owned()),
    }
}

#[test]
fn crud_adds_gets_lists_filters_and_soft_deletes_memories() {
    let db = TestDb::new();
    let core = db.open_core();

    let first = core
        .add_memory(note("Remember the blue door", "Blue door"), 100)
        .expect("note should be added");
    let second = core
        .add_memory(
            card(
                "Rust ownership question",
                "Ownership",
                "Who owns a moved value?",
                "The receiving binding",
            ),
            200,
        )
        .expect("card should be added");

    assert_ne!(first.id, second.id);
    assert_eq!(first.kind, MemoryKind::Note);
    assert_eq!(first.raw_text, "Remember the blue door");
    assert_eq!(first.title, "Blue door");
    assert_eq!(first.created_at, 100);
    assert_eq!(first.updated_at, 100);
    assert_eq!(first.due_at, None);
    assert_eq!(first.completed_at, None);
    assert_eq!(first.question, None);
    assert_eq!(first.answer, None);

    assert_eq!(
        core.get_memory(first.id.clone())
            .expect("stored note should be readable"),
        first
    );

    assert_eq!(
        core.list_memories(None).expect("all memories should list"),
        vec![second.clone(), first.clone()]
    );
    assert_eq!(
        core.list_memories(Some(MemoryKind::Card))
            .expect("cards should list"),
        vec![second.clone()]
    );
    assert!(core
        .list_memories(Some(MemoryKind::Reminder))
        .expect("empty kind should list")
        .is_empty());

    core.delete_memory(second.id.clone(), 300)
        .expect("card should soft-delete");

    assert_eq!(core.get_memory(second.id.clone()), Err(CoreError::NotFound));
    assert_eq!(
        core.list_memories(None)
            .expect("deleted memory should be hidden"),
        vec![first]
    );
    assert_eq!(core.delete_memory(second.id, 301), Err(CoreError::NotFound));
}

#[test]
fn migrations_are_automatic_and_idempotent() {
    let db = TestDb::new();

    drop(db.open_core());
    drop(db.open_core());

    let connection = Connection::open(&db.path).expect("database should be inspectable");
    let versions: Vec<i64> = connection
        .prepare("SELECT version FROM schema_version")
        .expect("schema_version should exist")
        .query_map([], |row| row.get(0))
        .expect("schema_version should be readable")
        .collect::<Result<_, _>>()
        .expect("version rows should decode");
    let cat_rows: i64 = connection
        .query_row("SELECT COUNT(*) FROM cat WHERE id = 1", [], |row| {
            row.get(0)
        })
        .expect("cat row should exist");
    let memory_columns: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM pragma_table_info('memories')",
            [],
            |row| row.get(0),
        )
        .expect("memories table should exist");

    assert_eq!(versions, vec![2]);
    assert_eq!(cat_rows, 1);
    assert_eq!(memory_columns, 17);
}

#[test]
fn completing_a_reminder_sets_time_and_adds_one_fish() {
    let db = TestDb::new();
    let core = db.open_core();
    let memory = core
        .add_memory(reminder("Call the vet", "Vet", 5_000), 1_000)
        .expect("reminder should be added");

    let before = core.cat_status().expect("cat should be readable");
    assert_eq!(before.level, 1);
    assert_eq!(before.xp, 0);
    assert_eq!(before.fish, 0);
    assert_eq!(before.mood, "content");

    let completed = core
        .complete_reminder(memory.id, 2_000)
        .expect("reminder should complete");
    let after = core.cat_status().expect("cat should remain readable");

    assert_eq!(completed.completed_at, Some(2_000));
    assert_eq!(completed.updated_at, 2_000);
    assert_eq!(after.fish, before.fish + 1);
}

#[test]
fn completing_a_non_reminder_is_invalid_and_does_not_add_fish() {
    let db = TestDb::new();
    let core = db.open_core();
    let memory = core
        .add_memory(note("Just a note", "Note"), 100)
        .expect("note should be added");

    assert!(matches!(
        core.complete_reminder(memory.id, 200),
        Err(CoreError::Invalid(_))
    ));
    assert_eq!(core.cat_status().expect("cat should be readable").fish, 0);
}

#[test]
fn pending_reminders_returns_only_live_incomplete_future_rows_in_due_order() {
    let db = TestDb::new();
    let core = db.open_core();
    let later = core
        .add_memory(reminder("Later", "Later", 400), 1)
        .expect("later reminder should be added");
    let earliest = core
        .add_memory(reminder("Earliest", "Earliest", 200), 2)
        .expect("earliest reminder should be added");
    let middle = core
        .add_memory(reminder("Middle", "Middle", 300), 3)
        .expect("middle reminder should be added");
    core.add_memory(reminder("Due now", "Due now", 100), 4)
        .expect("due-now reminder should be added");
    core.add_memory(reminder("Past", "Past", 99), 5)
        .expect("past reminder should be added");
    core.add_memory(note("Future note", "Future note"), 6)
        .expect("note should be added");
    let completed = core
        .add_memory(reminder("Completed", "Completed", 250), 7)
        .expect("completed reminder should be added");
    core.complete_reminder(completed.id, 8)
        .expect("reminder should complete");
    let deleted = core
        .add_memory(reminder("Deleted", "Deleted", 275), 9)
        .expect("deleted reminder should be added");
    core.delete_memory(deleted.id, 10)
        .expect("reminder should soft-delete");

    assert_eq!(
        core.pending_reminders(2, 100)
            .expect("pending reminders should load"),
        vec![earliest.clone(), middle.clone()]
    );
    assert_eq!(
        core.pending_reminders(10, 100)
            .expect("all pending reminders should load"),
        vec![earliest, middle, later]
    );
    assert!(core
        .pending_reminders(0, 100)
        .expect("a zero limit should be valid")
        .is_empty());
}

#[test]
fn snooze_reminder_updates_due_and_updated_times() {
    let db = TestDb::new();
    let core = db.open_core();
    let memory = core
        .add_memory(reminder("Call the vet", "Vet", 5_000), 1_000)
        .expect("reminder should be added");

    let snoozed = core
        .snooze_reminder(memory.id, 7_000, 2_000)
        .expect("reminder should snooze");

    assert_eq!(snoozed.due_at, Some(7_000));
    assert_eq!(snoozed.updated_at, 2_000);
    assert_eq!(snoozed.created_at, 1_000);
    assert_eq!(snoozed.completed_at, None);
}

#[test]
fn snooze_reminder_rejects_non_reminders_and_completed_reminders() {
    let db = TestDb::new();
    let core = db.open_core();
    let note = core
        .add_memory(note("Just a note", "Note"), 100)
        .expect("note should be added");
    let completed = core
        .add_memory(reminder("Already done", "Done", 500), 100)
        .expect("reminder should be added");
    core.complete_reminder(completed.id.clone(), 200)
        .expect("reminder should complete");

    assert!(matches!(
        core.snooze_reminder(note.id, 600, 300),
        Err(CoreError::Invalid(_))
    ));
    assert!(matches!(
        core.snooze_reminder(completed.id, 600, 300),
        Err(CoreError::Invalid(_))
    ));
}

#[test]
fn snooze_reminder_treats_missing_and_soft_deleted_rows_as_not_found() {
    let db = TestDb::new();
    let core = db.open_core();
    let deleted = core
        .add_memory(reminder("Deleted", "Deleted", 500), 100)
        .expect("reminder should be added");
    core.delete_memory(deleted.id.clone(), 200)
        .expect("reminder should soft-delete");

    assert_eq!(
        core.snooze_reminder(deleted.id, 600, 300),
        Err(CoreError::NotFound)
    );
    assert_eq!(
        core.snooze_reminder("missing".to_owned(), 600, 300),
        Err(CoreError::NotFound)
    );
}

#[test]
fn search_matches_text_fields_and_returns_empty_for_a_miss() {
    let db = TestDb::new();
    let core = db.open_core();
    let title_hit = core
        .add_memory(note("A quiet observation", "Buy oat milk"), 100)
        .expect("note should be added");
    let answer_hit = core
        .add_memory(
            card(
                "Geography study",
                "European capitals",
                "Capital of France?",
                "Paris",
            ),
            200,
        )
        .expect("card should be added");
    core.add_memory(note("Unrelated", "Read a novel"), 300)
        .expect("second note should be added");

    assert_eq!(
        core.search("oat".to_owned())
            .expect("title search should work"),
        vec![title_hit]
    );
    assert_eq!(
        core.search("Paris".to_owned())
            .expect("answer search should work"),
        vec![answer_hit]
    );
    assert!(core
        .search("no such memory".to_owned())
        .expect("miss should be successful")
        .is_empty());
}

#[test]
fn deleted_memories_are_excluded_from_search() {
    let db = TestDb::new();
    let core = db.open_core();
    let memory = core
        .add_memory(note("Unique searchable phrase", "Search me"), 100)
        .expect("note should be added");
    core.delete_memory(memory.id, 200)
        .expect("note should soft-delete");

    assert!(core
        .search("Unique searchable".to_owned())
        .expect("search should work")
        .is_empty());
}

#[test]
fn recall_search_matches_a_chinese_word_inside_an_unspaced_sentence() {
    let db = TestDb::new();
    let core = db.open_core();
    let memory = core
        .add_memory(note("护照放在书房第二个抽屉里", "护照的位置"), 100)
        .expect("Chinese note should be added");

    assert_eq!(
        core.search_for_recall("护照".to_owned(), 8)
            .expect("Chinese recall search should work"),
        vec![memory]
    );
}

#[test]
fn recall_search_matches_multiple_chinese_terms() {
    let db = TestDb::new();
    let core = db.open_core();
    let matching = core
        .add_memory(note("护照放在书房第二个抽屉里", "护照的位置"), 100)
        .expect("matching note should be added");
    core.add_memory(note("护照已经过期了", "更新护照"), 200)
        .expect("partial note should be added");
    core.add_memory(note("抽屉里有备用钥匙", "备用钥匙"), 300)
        .expect("other partial note should be added");

    assert_eq!(
        core.search_for_recall("护照 抽屉".to_owned(), 8)
            .expect("multi-term Chinese recall search should work"),
        vec![matching]
    );
}

#[test]
fn recall_search_matches_english_and_returns_empty_for_a_miss() {
    let db = TestDb::new();
    let core = db.open_core();
    let memory = core
        .add_memory(
            note("The passport is in the desk drawer", "Passport location"),
            100,
        )
        .expect("English note should be added");

    assert_eq!(
        core.search_for_recall("passport drawer".to_owned(), 8)
            .expect("English recall search should work"),
        vec![memory]
    );
    assert!(core
        .search_for_recall("garden umbrella".to_owned(), 8)
        .expect("a recall miss should be successful")
        .is_empty());
}

#[test]
fn recall_search_excludes_soft_deleted_rows() {
    let db = TestDb::new();
    let core = db.open_core();
    let memory = core
        .add_memory(note("Unique passport location", "Passport"), 100)
        .expect("note should be added");
    core.delete_memory(memory.id, 200)
        .expect("note should soft-delete");

    assert!(core
        .search_for_recall("passport".to_owned(), 8)
        .expect("recall search should work")
        .is_empty());
}

#[test]
fn recall_search_tracks_updates_to_searchable_fields() {
    let db = TestDb::new();
    let core = db.open_core();
    let memory = core
        .add_memory(note("A neutral observation", "Oldterm"), 100)
        .expect("note should be added");

    core.reclassify_memory(
        memory.id,
        MemoryKind::Note,
        "Newterm".to_owned(),
        None,
        None,
        None,
        200,
    )
    .expect("note should be updated");

    assert!(core
        .search_for_recall("Oldterm".to_owned(), 8)
        .expect("old term search should work")
        .is_empty());
    assert_eq!(
        core.search_for_recall("Newterm".to_owned(), 8)
            .expect("new term search should work")
            .len(),
        1
    );
}

#[test]
fn recall_search_honors_limit_and_uses_updated_at_for_rank_ties() {
    let db = TestDb::new();
    let core = db.open_core();
    core.add_memory(note("passport drawer", "Location"), 100)
        .expect("older note should be added");
    let newer = core
        .add_memory(note("passport drawer", "Location"), 200)
        .expect("newer note should be added");

    assert_eq!(
        core.search_for_recall("passport drawer".to_owned(), 1)
            .expect("limited recall search should work"),
        vec![newer]
    );
    assert!(core
        .search_for_recall("passport".to_owned(), 0)
        .expect("a zero limit should be valid")
        .is_empty());
}

#[test]
fn recall_migration_backfills_existing_schema_version_one_rows() {
    let db = TestDb::new();
    let connection = Connection::open(&db.path).expect("legacy database should open");
    connection
        .execute_batch(
            "
            CREATE TABLE schema_version (version INTEGER NOT NULL);
            INSERT INTO schema_version (version) VALUES (1);
            CREATE TABLE memories (
              id TEXT PRIMARY KEY,
              kind TEXT NOT NULL,
              raw_text TEXT NOT NULL,
              title TEXT NOT NULL,
              due_at INTEGER,
              completed_at INTEGER,
              question TEXT,
              answer TEXT,
              fsrs_due INTEGER,
              fsrs_stability REAL,
              fsrs_difficulty REAL,
              fsrs_reps INTEGER NOT NULL DEFAULT 0,
              fsrs_lapses INTEGER NOT NULL DEFAULT 0,
              fsrs_state INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER
            );
            CREATE TABLE cat (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              level INTEGER NOT NULL DEFAULT 1,
              xp INTEGER NOT NULL DEFAULT 0,
              fish INTEGER NOT NULL DEFAULT 0,
              mood TEXT NOT NULL DEFAULT 'content',
              updated_at INTEGER NOT NULL
            );
            INSERT INTO cat (id, updated_at) VALUES (1, 0);
            INSERT INTO memories (
              id, kind, raw_text, title, created_at, updated_at
            ) VALUES (
              'legacy-memory', 'note', '护照放在书房第二个抽屉里',
              '护照的位置', 100, 100
            );
            ",
        )
        .expect("legacy schema and row should be created");
    drop(connection);

    let core = db.open_core();
    let results = core
        .search_for_recall("护照".to_owned(), 8)
        .expect("backfilled row should be searchable");

    assert_eq!(results.len(), 1);
    assert_eq!(results[0].id, "legacy-memory");

    let connection = Connection::open(&db.path).expect("upgraded database should open");
    let version: i64 = connection
        .query_row("SELECT version FROM schema_version", [], |row| row.get(0))
        .expect("schema version should be readable");
    let indexed_rows: i64 = connection
        .query_row("SELECT COUNT(*) FROM memories_fts", [], |row| row.get(0))
        .expect("FTS table should be readable");
    assert_eq!(version, 2);
    assert_eq!(indexed_rows, 1);
}

#[test]
fn reclassifying_a_memory_updates_classification_fields_but_preserves_created_at() {
    let db = TestDb::new();
    let core = db.open_core();
    let memory = core
        .add_memory(note("明天下午三点交电费", "明天下午三点交电费"), 1_000)
        .expect("initial note should be added");

    let reclassified = core
        .reclassify_memory(
            memory.id,
            MemoryKind::Reminder,
            "交电费".to_owned(),
            Some(2_000),
            None,
            None,
            1_500,
        )
        .expect("note should be reclassified");

    assert_eq!(reclassified.kind, MemoryKind::Reminder);
    assert_eq!(reclassified.title, "交电费");
    assert_eq!(reclassified.due_at, Some(2_000));
    assert_eq!(reclassified.question, None);
    assert_eq!(reclassified.answer, None);
    assert_eq!(reclassified.created_at, 1_000);
    assert_eq!(reclassified.updated_at, 1_500);
}

#[test]
fn reclassifying_a_soft_deleted_memory_returns_not_found() {
    let db = TestDb::new();
    let core = db.open_core();
    let memory = core
        .add_memory(note("Soft deleted", "Deleted"), 100)
        .expect("note should be added");
    core.delete_memory(memory.id.clone(), 200)
        .expect("note should soft-delete");

    assert_eq!(
        core.reclassify_memory(
            memory.id,
            MemoryKind::Card,
            "Card".to_owned(),
            None,
            Some("Question?".to_owned()),
            Some("Answer.".to_owned()),
            300,
        ),
        Err(CoreError::NotFound)
    );
}

#[test]
fn reclassifying_a_memory_does_not_change_cat_fish() {
    let db = TestDb::new();
    let core = db.open_core();
    let memory = core
        .add_memory(note("ephemeral 是短暂的意思", "ephemeral 是短暂"), 100)
        .expect("note should be added");
    let fish_before = core.cat_status().expect("cat should be readable").fish;

    core.reclassify_memory(
        memory.id,
        MemoryKind::Card,
        "ephemeral".to_owned(),
        None,
        Some("ephemeral 是什么意思？".to_owned()),
        Some("短暂的。".to_owned()),
        200,
    )
    .expect("note should be reclassified");

    assert_eq!(
        core.cat_status().expect("cat should remain readable").fish,
        fish_before
    );
}
