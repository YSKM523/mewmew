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

    assert_eq!(versions, vec![1]);
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
