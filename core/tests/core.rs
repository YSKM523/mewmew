use std::fs;
use std::path::PathBuf;
use std::sync::Arc;

use mewmew_core::{CoreError, MemoryKind, MewmewCore, NewMemory, ReviewRating};
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
    let fresh_cat: (Option<i64>, String) = connection
        .query_row(
            "SELECT last_interaction_at, outfit FROM cat WHERE id = 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("fresh cat should be readable");

    assert_eq!(versions, vec![4]);
    assert_eq!(cat_rows, 1);
    assert_eq!(memory_columns, 20);
    assert_eq!(fresh_cat, (None, "none".to_owned()));
}

#[test]
fn migration_v4_adds_cat_columns_and_backfills_existing_interaction_time() {
    let db = TestDb::new();
    let connection = Connection::open(&db.path).expect("legacy database should open");
    connection
        .execute_batch(
            "
            CREATE TABLE schema_version (version INTEGER NOT NULL);
            INSERT INTO schema_version (version) VALUES (3);
            CREATE TABLE cat (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              level INTEGER NOT NULL DEFAULT 1,
              xp INTEGER NOT NULL DEFAULT 0,
              fish INTEGER NOT NULL DEFAULT 0,
              mood TEXT NOT NULL DEFAULT 'content',
              updated_at INTEGER NOT NULL
            );
            INSERT INTO cat (id, level, xp, fish, mood, updated_at)
            VALUES (1, 3, 80, 2, 'content', 12345);
            ",
        )
        .expect("schema version three database should be created");
    drop(connection);

    drop(db.open_core());

    let connection = Connection::open(&db.path).expect("database should be inspectable");
    let version: i64 = connection
        .query_row("SELECT version FROM schema_version", [], |row| row.get(0))
        .expect("schema version should be readable");
    let cat: (Option<i64>, String) = connection
        .query_row(
            "SELECT last_interaction_at, outfit FROM cat WHERE id = 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("migrated cat should be readable");
    let outfit_not_null: i64 = connection
        .query_row(
            "SELECT [notnull] FROM pragma_table_info('cat') WHERE name = 'outfit'",
            [],
            |row| row.get(0),
        )
        .expect("outfit schema should be readable");

    assert_eq!(version, 4);
    assert_eq!(cat, (Some(12345), "none".to_owned()));
    assert_eq!(outfit_not_null, 1);
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
    assert_eq!(version, 4);
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

#[derive(Debug, PartialEq)]
struct FsrsState {
    due: i64,
    stability: f64,
    difficulty: f64,
    last_review: i64,
    elapsed_days: i64,
    scheduled_days: i64,
    reps: i64,
    lapses: i64,
    state: i64,
    updated_at: i64,
}

fn read_fsrs_state(db: &TestDb, id: &str) -> FsrsState {
    Connection::open(&db.path)
        .expect("database should be inspectable")
        .query_row(
            "SELECT fsrs_due, fsrs_stability, fsrs_difficulty, fsrs_last_review,
                    fsrs_elapsed_days, fsrs_scheduled_days, fsrs_reps, fsrs_lapses,
                    fsrs_state, updated_at
             FROM memories
             WHERE id = ?1",
            [id],
            |row| {
                Ok(FsrsState {
                    due: row.get(0)?,
                    stability: row.get(1)?,
                    difficulty: row.get(2)?,
                    last_review: row.get(3)?,
                    elapsed_days: row.get(4)?,
                    scheduled_days: row.get(5)?,
                    reps: row.get(6)?,
                    lapses: row.get(7)?,
                    state: row.get(8)?,
                    updated_at: row.get(9)?,
                })
            },
        )
        .expect("FSRS state should be readable")
}

#[test]
fn migration_v3_backfills_existing_cards_and_preserves_fts_recall() {
    let db = TestDb::new();
    let connection = Connection::open(&db.path).expect("legacy database should open");
    connection
        .execute_batch(
            "
            CREATE TABLE schema_version (version INTEGER NOT NULL);
            INSERT INTO schema_version (version) VALUES (2);
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
              id, kind, raw_text, title, question, answer, created_at, updated_at
            ) VALUES (
              'legacy-card', 'card', 'ephemeral 是短暂的意思', 'ephemeral',
              'ephemeral 是什么意思？', '短暂的。', 123, 123
            );

            CREATE VIRTUAL TABLE memories_fts USING fts5(
              raw_text, title, question, answer, tokenize = 'unicode61'
            );
            INSERT INTO memories_fts (rowid, raw_text, title, question, answer)
            SELECT rowid, 'ephemeral 是 短 暂 的 意 思', 'ephemeral',
                   'ephemeral 是 什 么 意 思', '短 暂 的'
            FROM memories;

            CREATE TRIGGER memories_fts_after_insert
            AFTER INSERT ON memories
            WHEN new.deleted_at IS NULL
            BEGIN
              INSERT INTO memories_fts (rowid, raw_text, title, question, answer)
              VALUES (
                new.rowid,
                mewmew_fts_tokens(new.raw_text),
                mewmew_fts_tokens(new.title),
                mewmew_fts_tokens(new.question),
                mewmew_fts_tokens(new.answer)
              );
            END;
            CREATE TRIGGER memories_fts_after_update
            AFTER UPDATE ON memories
            BEGIN
              DELETE FROM memories_fts WHERE rowid = old.rowid;
              INSERT INTO memories_fts (rowid, raw_text, title, question, answer)
              SELECT
                new.rowid,
                mewmew_fts_tokens(new.raw_text),
                mewmew_fts_tokens(new.title),
                mewmew_fts_tokens(new.question),
                mewmew_fts_tokens(new.answer)
              WHERE new.deleted_at IS NULL;
            END;
            CREATE TRIGGER memories_fts_after_delete
            AFTER DELETE ON memories
            BEGIN
              DELETE FROM memories_fts WHERE rowid = old.rowid;
            END;
            ",
        )
        .expect("schema version two database should be created");
    drop(connection);

    let core = db.open_core();
    let connection = Connection::open(&db.path).expect("database should be inspectable");
    let fsrs_due: i64 = connection
        .query_row(
            "SELECT fsrs_due FROM memories WHERE id = 'legacy-card'",
            [],
            |row| row.get(0),
        )
        .expect("legacy card should be immediately due");
    let version: i64 = connection
        .query_row("SELECT version FROM schema_version", [], |row| row.get(0))
        .expect("schema version should be readable");
    assert_eq!(fsrs_due, 123);
    assert_eq!(version, 4);
    drop(connection);

    assert_eq!(
        core.search_for_recall("短暂".to_owned(), 8)
            .expect("Chinese FTS recall should survive migration")
            .len(),
        1
    );
    core.review_card("legacy-card".to_owned(), ReviewRating::Good, fsrs_due)
        .expect("review should exercise the preserved FTS update trigger");
    assert_eq!(
        core.search_for_recall("短暂".to_owned(), 8)
            .expect("Chinese FTS recall should survive an FSRS update")
            .len(),
        1
    );
}

#[test]
fn due_cards_return_only_complete_live_cards_in_due_order_and_count_them() {
    let db = TestDb::new();
    let core = db.open_core();
    let later = core
        .add_memory(card("later", "Later", "Later?", "Yes"), 200)
        .expect("later card should be added");
    let first = core
        .add_memory(card("first", "First", "First?", "Yes"), 100)
        .expect("first card should be added");
    core.add_memory(note("not a card", "Note"), 50)
        .expect("note should be added");
    core.add_memory(
        NewMemory {
            kind: MemoryKind::Card,
            raw_text: "missing question".to_owned(),
            title: "Missing question".to_owned(),
            due_at: None,
            question: None,
            answer: Some("Answer".to_owned()),
        },
        60,
    )
    .expect("incomplete card should be added");
    core.add_memory(
        NewMemory {
            kind: MemoryKind::Card,
            raw_text: "blank answer".to_owned(),
            title: "Blank answer".to_owned(),
            due_at: None,
            question: Some("Question".to_owned()),
            answer: Some(String::new()),
        },
        70,
    )
    .expect("blank-answer card should be added");
    let deleted = core
        .add_memory(card("deleted", "Deleted", "Deleted?", "Yes"), 80)
        .expect("deleted card should be added");
    core.delete_memory(deleted.id, 90)
        .expect("card should soft-delete");

    assert_eq!(
        core.due_cards(10, 150).expect("due cards should load"),
        vec![first.clone()]
    );
    assert_eq!(
        core.due_cards(10, 200).expect("due cards should load"),
        vec![first, later]
    );
    assert_eq!(
        core.due_card_count(200)
            .expect("due card count should load"),
        2
    );
    assert!(core
        .due_cards(0, 200)
        .expect("zero limit should be accepted")
        .is_empty());
}

#[test]
fn reviewing_a_new_card_good_updates_all_fsrs_state_deterministically() {
    fn run_once() -> FsrsState {
        let db = TestDb::new();
        let core = db.open_core();
        let memory = core
            .add_memory(
                card("deterministic", "Deterministic", "Question?", "Answer."),
                1_000,
            )
            .expect("card should be added");
        let outcome = core
            .review_card(memory.id.clone(), ReviewRating::Good, 1_000)
            .expect("review should succeed");
        assert_eq!(outcome.memory.updated_at, 1_000);
        assert_eq!(outcome.next_due_at, 1_600);
        assert!(outcome.earned_fish);

        let state = read_fsrs_state(&db, &memory.id);
        assert_eq!(state.reps, 1);
        assert_eq!(state.state, 1);
        state
    }

    assert_eq!(run_once(), run_once());
}

#[test]
fn six_consecutive_good_reviews_have_strictly_increasing_intervals() {
    let db = TestDb::new();
    let core = db.open_core();
    let memory = core
        .add_memory(
            card("six goods", "Six goods", "Question?", "Answer."),
            1_000,
        )
        .expect("card should be added");
    let mut now = 1_000;
    let mut previous_interval = 0;

    for _ in 0..6 {
        let outcome = core
            .review_card(memory.id.clone(), ReviewRating::Good, now)
            .expect("review should succeed");
        let interval = outcome.next_due_at - now;
        assert!(
            interval > previous_interval,
            "interval {interval} should exceed {previous_interval}"
        );
        previous_interval = interval;
        now = outcome.next_due_at;
    }
}

#[test]
fn again_increases_lapses_and_pulls_the_due_time_nearer() {
    let db = TestDb::new();
    let core = db.open_core();
    let memory = core
        .add_memory(card("again", "Again", "Question?", "Answer."), 1_000)
        .expect("card should be added");
    let first = core
        .review_card(memory.id.clone(), ReviewRating::Good, 1_000)
        .expect("first good review should succeed");
    let second = core
        .review_card(memory.id.clone(), ReviewRating::Good, first.next_due_at)
        .expect("second good review should succeed");
    let before = read_fsrs_state(&db, &memory.id);
    let previous_interval = second.next_due_at - first.next_due_at;

    let forgotten = core
        .review_card(memory.id.clone(), ReviewRating::Again, second.next_due_at)
        .expect("again review should succeed");
    let after = read_fsrs_state(&db, &memory.id);

    assert_eq!(after.lapses, before.lapses + 1);
    assert!(forgotten.next_due_at - second.next_due_at < previous_interval);
}

#[test]
fn good_and_easy_add_fish_while_again_and_hard_do_not() {
    let db = TestDb::new();
    let core = db.open_core();
    let ratings = [
        (ReviewRating::Again, false),
        (ReviewRating::Hard, false),
        (ReviewRating::Good, true),
        (ReviewRating::Easy, true),
    ];

    for (index, (rating, earned_fish)) in ratings.into_iter().enumerate() {
        let memory = core
            .add_memory(
                card(
                    &format!("fish {index}"),
                    &format!("Fish {index}"),
                    "Question?",
                    "Answer.",
                ),
                1_000,
            )
            .expect("card should be added");
        let before = core.cat_status().expect("cat should be readable").fish;
        let outcome = core
            .review_card(memory.id, rating, 1_000)
            .expect("review should succeed");
        let after = core.cat_status().expect("cat should be readable").fish;

        assert_eq!(outcome.earned_fish, earned_fish);
        assert_eq!(after - before, i64::from(earned_fish));
    }
}

#[test]
fn review_rejects_missing_deleted_non_card_and_incomplete_cards() {
    let db = TestDb::new();
    let core = db.open_core();
    let note = core
        .add_memory(note("note", "Note"), 100)
        .expect("note should be added");
    let no_question = core
        .add_memory(
            NewMemory {
                kind: MemoryKind::Card,
                raw_text: "no question".to_owned(),
                title: "No question".to_owned(),
                due_at: None,
                question: None,
                answer: Some("Answer.".to_owned()),
            },
            100,
        )
        .expect("incomplete card should be added");
    let blank_answer = core
        .add_memory(
            NewMemory {
                kind: MemoryKind::Card,
                raw_text: "blank answer".to_owned(),
                title: "Blank answer".to_owned(),
                due_at: None,
                question: Some("Question?".to_owned()),
                answer: Some("  ".to_owned()),
            },
            100,
        )
        .expect("incomplete card should be added");
    let deleted = core
        .add_memory(card("deleted", "Deleted", "Question?", "Answer."), 100)
        .expect("card should be added");
    core.delete_memory(deleted.id.clone(), 101)
        .expect("card should soft-delete");

    assert_eq!(
        core.review_card("missing".to_owned(), ReviewRating::Good, 200),
        Err(CoreError::NotFound)
    );
    assert_eq!(
        core.review_card(deleted.id, ReviewRating::Good, 200),
        Err(CoreError::NotFound)
    );
    for id in [note.id, no_question.id, blank_answer.id] {
        assert!(matches!(
            core.review_card(id, ReviewRating::Good, 200),
            Err(CoreError::Invalid(_))
        ));
    }
    assert_eq!(core.cat_status().expect("cat should be readable").fish, 0);
}

#[test]
fn next_card_due_at_reports_the_soonest_future_card() {
    let db = TestDb::new();
    let core = db.open_core();
    let now = 1_800_000_000;

    assert_eq!(core.next_card_due_at(now).unwrap(), None);

    let soon = core
        .add_memory(card("近的", "近的", "近?", "近"), now)
        .unwrap()
        .id;
    let later = core
        .add_memory(card("远的", "远的", "远?", "远"), now)
        .unwrap()
        .id;
    // Both start due immediately; reviewing pushes them into the future.
    let soon_out = core.review_card(soon, ReviewRating::Good, now).unwrap();
    let later_out = core.review_card(later, ReviewRating::Easy, now).unwrap();
    assert!(later_out.next_due_at > soon_out.next_due_at);

    assert_eq!(
        core.next_card_due_at(now).unwrap(),
        Some(soon_out.next_due_at),
        "should report the nearest upcoming card"
    );
    assert_eq!(
        core.next_card_due_at(soon_out.next_due_at).unwrap(),
        Some(later_out.next_due_at),
        "a card at or before now is no longer upcoming"
    );
}

fn update_cat(db: &TestDb, sql: &str) {
    Connection::open(&db.path)
        .expect("database should be inspectable")
        .execute_batch(sql)
        .expect("cat fixture should update");
}

fn read_cat_cache(db: &TestDb) -> (i64, i64, i64, Option<i64>, String) {
    Connection::open(&db.path)
        .expect("database should be inspectable")
        .query_row(
            "SELECT level, xp, fish, last_interaction_at, outfit FROM cat WHERE id = 1",
            [],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            },
        )
        .expect("cat cache should be readable")
}

#[test]
fn level_boundaries_are_derived_from_xp_and_repair_the_cache() {
    let db = TestDb::new();
    let core = db.open_core();
    let cases = [
        (29, 1),
        (30, 2),
        (79, 2),
        (80, 3),
        (159, 3),
        (160, 4),
        (279, 4),
        (280, 5),
    ];

    for (xp, expected_level) in cases {
        update_cat(
            &db,
            &format!("UPDATE cat SET xp = {xp}, level = 99 WHERE id = 1;"),
        );

        let status = core
            .cat_status_at(10_000)
            .expect("derived cat status should load");
        let cached_level = read_cat_cache(&db).0;

        assert_eq!(status.xp, xp);
        assert_eq!(status.level, expected_level, "xp={xp}");
        assert_eq!(cached_level, expected_level, "xp={xp}");
    }
}

#[test]
fn mood_boundaries_are_derived_without_changing_persistent_progress() {
    let db = TestDb::new();
    let core = db.open_core();
    let now = 1_000_000;
    let cases = [
        (now - (23 * 60 * 60 + 59 * 60), "happy"),
        (now - 24 * 60 * 60, "content"),
        (now - 72 * 60 * 60, "content"),
        (now - (72 * 60 * 60 + 1), "sleepy"),
    ];

    for (last_interaction_at, expected_mood) in cases {
        update_cat(
            &db,
            &format!("UPDATE cat SET last_interaction_at = {last_interaction_at} WHERE id = 1;"),
        );

        assert_eq!(
            core.cat_status_at(now)
                .expect("derived cat status should load")
                .mood,
            expected_mood,
            "last_interaction_at={last_interaction_at}"
        );
    }

    update_cat(
        &db,
        "UPDATE cat SET last_interaction_at = NULL WHERE id = 1;",
    );
    assert_eq!(
        core.cat_status_at(now)
            .expect("new cat status should load")
            .mood,
        "happy"
    );
}

#[test]
fn ten_days_of_decay_only_changes_mood() {
    let db = TestDb::new();
    let core = db.open_core();
    update_cat(
        &db,
        "UPDATE cat
         SET fish = 7, xp = 160, level = 4, outfit = 'glasses',
             last_interaction_at = 1000
         WHERE id = 1;",
    );

    let before = core
        .cat_status_at(1_000)
        .expect("initial cat status should load");
    let after = core
        .cat_status_at(1_000 + 10 * 24 * 60 * 60)
        .expect("decayed cat status should load");

    assert_eq!(before.mood, "happy");
    assert_eq!(after.mood, "sleepy");
    assert_eq!(after.fish, before.fish);
    assert_eq!(after.xp, before.xp);
    assert_eq!(after.level, before.level);
    assert_eq!(after.outfit, before.outfit);
}

#[test]
fn feeding_consumes_fish_adds_xp_refreshes_interaction_and_recomputes_level() {
    let db = TestDb::new();
    let core = db.open_core();
    update_cat(
        &db,
        "UPDATE cat
         SET fish = 1, xp = 29, level = 1, last_interaction_at = 100
         WHERE id = 1;",
    );

    let status = core.feed_cat(50_000).expect("feeding should succeed");

    assert_eq!(status.fish, 0);
    assert_eq!(status.xp, 39);
    assert_eq!(status.level, 2);
    assert_eq!(status.mood, "happy");
    assert_eq!(
        read_cat_cache(&db),
        (2, 39, 0, Some(50_000), "none".to_owned())
    );
}

#[test]
fn feeding_without_fish_is_invalid_and_atomic() {
    let db = TestDb::new();
    let core = db.open_core();
    update_cat(
        &db,
        "UPDATE cat
         SET fish = 0, xp = 29, level = 1, outfit = 'none',
             last_interaction_at = 100
         WHERE id = 1;",
    );
    let before = read_cat_cache(&db);
    let before_full: (i64, i64, i64, String, i64, Option<i64>, String) = Connection::open(&db.path)
        .expect("database should be inspectable")
        .query_row(
            "SELECT level, xp, fish, mood, updated_at, last_interaction_at, outfit
                 FROM cat WHERE id = 1",
            [],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                    row.get(6)?,
                ))
            },
        )
        .expect("cat state should be readable");

    assert_eq!(
        core.feed_cat(50_000),
        Err(CoreError::Invalid("没有小鱼干了".to_owned()))
    );
    assert_eq!(read_cat_cache(&db), before);
    let after_full = Connection::open(&db.path)
        .expect("database should be inspectable")
        .query_row(
            "SELECT level, xp, fish, mood, updated_at, last_interaction_at, outfit
             FROM cat WHERE id = 1",
            [],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, Option<i64>>(5)?,
                    row.get::<_, String>(6)?,
                ))
            },
        )
        .expect("cat state should be readable");
    assert_eq!(after_full, before_full);
}

#[test]
fn outfits_require_their_level_and_can_be_set_after_unlocking() {
    let db = TestDb::new();
    let core = db.open_core();
    update_cat(&db, "UPDATE cat SET fish = 3 WHERE id = 1;");

    assert_eq!(
        core.unlocked_outfits()
            .expect("default outfits should load"),
        vec!["none".to_owned()]
    );
    assert!(matches!(
        core.set_outfit("scarf".to_owned(), 100),
        Err(CoreError::Invalid(_))
    ));
    assert!(matches!(
        core.set_outfit("cape".to_owned(), 100),
        Err(CoreError::Invalid(_))
    ));

    core.feed_cat(101).expect("first feeding should succeed");
    core.feed_cat(102).expect("second feeding should succeed");
    core.feed_cat(103).expect("third feeding should succeed");

    assert_eq!(
        core.unlocked_outfits()
            .expect("level two outfits should load"),
        vec!["none".to_owned(), "scarf".to_owned()]
    );
    let dressed = core
        .set_outfit("scarf".to_owned(), 200)
        .expect("newly unlocked scarf should be settable");
    assert_eq!(dressed.outfit, "scarf");
    assert_eq!(dressed.mood, "happy");
    assert_eq!(read_cat_cache(&db).3, Some(200));

    let plain = core
        .set_outfit("none".to_owned(), 201)
        .expect("unlocked outfits should be switchable");
    assert_eq!(plain.outfit, "none");

    update_cat(&db, "UPDATE cat SET xp = 160, level = 2 WHERE id = 1;");
    assert_eq!(
        core.unlocked_outfits()
            .expect("level four outfits should load"),
        vec!["none".to_owned(), "scarf".to_owned(), "glasses".to_owned()]
    );
    assert_eq!(
        core.set_outfit("glasses".to_owned(), 300)
            .expect("level four glasses should be settable")
            .outfit,
        "glasses"
    );
}

#[test]
fn legacy_cat_status_keeps_stored_mood_but_repairs_level_from_xp() {
    let db = TestDb::new();
    let core = db.open_core();
    update_cat(
        &db,
        "UPDATE cat
         SET xp = 30, level = 1, mood = 'content', outfit = 'scarf',
             last_interaction_at = 1
         WHERE id = 1;",
    );

    let status = core.cat_status().expect("legacy cat status should load");

    assert_eq!(status.level, 2);
    assert_eq!(status.mood, "content");
    assert_eq!(status.outfit, "scarf");
    assert_eq!(read_cat_cache(&db).0, 2);
}

#[test]
fn completing_a_reminder_refreshes_cat_interaction_time() {
    let db = TestDb::new();
    let core = db.open_core();
    let now = 500_000;
    let memory = core
        .add_memory(reminder("Call the vet", "Vet", now + 100), 1_000)
        .expect("reminder should be added");
    update_cat(&db, "UPDATE cat SET last_interaction_at = 1 WHERE id = 1;");

    core.complete_reminder(memory.id, now)
        .expect("reminder should complete");

    assert_eq!(read_cat_cache(&db).3, Some(now));
    assert_eq!(
        core.cat_status_at(now)
            .expect("cat status should load")
            .mood,
        "happy"
    );
}

#[test]
fn a_correct_review_refreshes_cat_interaction_time() {
    let db = TestDb::new();
    let core = db.open_core();
    let now = 500_000;
    let memory = core
        .add_memory(card("word", "Word", "Question?", "Answer."), now)
        .expect("card should be added");
    update_cat(&db, "UPDATE cat SET last_interaction_at = 1 WHERE id = 1;");

    core.review_card(memory.id, ReviewRating::Good, now)
        .expect("correct review should succeed");

    assert_eq!(read_cat_cache(&db).3, Some(now));
    assert_eq!(
        core.cat_status_at(now)
            .expect("cat status should load")
            .mood,
        "happy"
    );
}
