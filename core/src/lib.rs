//! Core domain and persistence library for mewmew.

use std::sync::{Arc, Mutex, MutexGuard};

use rusqlite::types::Type;
use rusqlite::{params, Connection, OptionalExtension, Row};
use uuid::Uuid;

#[derive(Debug, PartialEq, Eq, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    #[error("database error: {0}")]
    Db(String),
    #[error("memory not found")]
    NotFound,
    #[error("invalid operation: {0}")]
    Invalid(String),
}

impl From<rusqlite::Error> for CoreError {
    fn from(error: rusqlite::Error) -> Self {
        Self::Db(error.to_string())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum MemoryKind {
    Reminder,
    Card,
    Note,
}

impl MemoryKind {
    fn as_db_value(self) -> &'static str {
        match self {
            Self::Reminder => "reminder",
            Self::Card => "card",
            Self::Note => "note",
        }
    }

    fn from_db_value(value: &str) -> rusqlite::Result<Self> {
        match value {
            "reminder" => Ok(Self::Reminder),
            "card" => Ok(Self::Card),
            "note" => Ok(Self::Note),
            other => Err(rusqlite::Error::FromSqlConversionFailure(
                1,
                Type::Text,
                format!("unknown memory kind: {other}").into(),
            )),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct Memory {
    pub id: String,
    pub kind: MemoryKind,
    pub raw_text: String,
    pub title: String,
    pub due_at: Option<i64>,
    pub completed_at: Option<i64>,
    pub question: Option<String>,
    pub answer: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CatStatus {
    pub level: i64,
    pub xp: i64,
    pub fish: i64,
    pub mood: String,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NewMemory {
    pub kind: MemoryKind,
    pub raw_text: String,
    pub title: String,
    pub due_at: Option<i64>,
    pub question: Option<String>,
    pub answer: Option<String>,
}

#[derive(uniffi::Object)]
pub struct MewmewCore {
    connection: Mutex<Connection>,
}

#[uniffi::export]
impl MewmewCore {
    #[uniffi::constructor]
    pub fn new(db_path: String) -> Result<Arc<Self>, CoreError> {
        let mut connection = Connection::open(db_path)?;
        run_migrations(&mut connection)?;

        Ok(Arc::new(Self {
            connection: Mutex::new(connection),
        }))
    }

    pub fn add_memory(&self, memory: NewMemory, now: i64) -> Result<Memory, CoreError> {
        let connection = self.lock_connection()?;
        let id = Uuid::new_v4().to_string();

        connection.execute(
            "INSERT INTO memories (
                id, kind, raw_text, title, due_at, completed_at, question, answer,
                created_at, updated_at
             ) VALUES (?1, ?2, ?3, ?4, ?5, NULL, ?6, ?7, ?8, ?8)",
            params![
                id,
                memory.kind.as_db_value(),
                memory.raw_text,
                memory.title,
                memory.due_at,
                memory.question,
                memory.answer,
                now,
            ],
        )?;

        fetch_memory(&connection, &id)
    }

    pub fn get_memory(&self, id: String) -> Result<Memory, CoreError> {
        let connection = self.lock_connection()?;
        fetch_memory(&connection, &id)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn reclassify_memory(
        &self,
        id: String,
        kind: MemoryKind,
        title: String,
        due_at: Option<i64>,
        question: Option<String>,
        answer: Option<String>,
        now: i64,
    ) -> Result<Memory, CoreError> {
        let connection = self.lock_connection()?;
        let changed = connection.execute(
            "UPDATE memories
             SET kind = ?1, title = ?2, due_at = ?3, question = ?4, answer = ?5,
                 updated_at = ?6
             WHERE id = ?7 AND deleted_at IS NULL",
            params![kind.as_db_value(), title, due_at, question, answer, now, id,],
        )?;

        if changed == 0 {
            Err(CoreError::NotFound)
        } else {
            fetch_memory(&connection, &id)
        }
    }

    pub fn list_memories(&self, kind: Option<MemoryKind>) -> Result<Vec<Memory>, CoreError> {
        let connection = self.lock_connection()?;

        if let Some(kind) = kind {
            let mut statement = connection.prepare(
                "SELECT id, kind, raw_text, title, due_at, completed_at, question, answer,
                        created_at, updated_at
                 FROM memories
                 WHERE deleted_at IS NULL AND kind = ?1
                 ORDER BY updated_at DESC, id DESC",
            )?;
            let rows = statement.query_map([kind.as_db_value()], memory_from_row)?;
            Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
        } else {
            let mut statement = connection.prepare(
                "SELECT id, kind, raw_text, title, due_at, completed_at, question, answer,
                        created_at, updated_at
                 FROM memories
                 WHERE deleted_at IS NULL
                 ORDER BY updated_at DESC, id DESC",
            )?;
            let rows = statement.query_map([], memory_from_row)?;
            Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
        }
    }

    pub fn complete_reminder(&self, id: String, now: i64) -> Result<Memory, CoreError> {
        let mut connection = self.lock_connection()?;
        let transaction = connection.transaction()?;
        let existing = fetch_memory(&transaction, &id)?;

        if existing.kind != MemoryKind::Reminder {
            return Err(CoreError::Invalid(
                "only reminders can be completed".to_owned(),
            ));
        }
        if existing.completed_at.is_some() {
            return Err(CoreError::Invalid(
                "reminder is already completed".to_owned(),
            ));
        }

        transaction.execute(
            "UPDATE memories
             SET completed_at = ?1, updated_at = ?1
             WHERE id = ?2 AND deleted_at IS NULL",
            params![now, id],
        )?;
        transaction.execute(
            "UPDATE cat SET fish = fish + 1, updated_at = ?1 WHERE id = 1",
            [now],
        )?;

        let completed = fetch_memory(&transaction, &id)?;
        transaction.commit()?;
        Ok(completed)
    }

    pub fn delete_memory(&self, id: String, now: i64) -> Result<(), CoreError> {
        let connection = self.lock_connection()?;
        let changed = connection.execute(
            "UPDATE memories
             SET deleted_at = ?1, updated_at = ?1
             WHERE id = ?2 AND deleted_at IS NULL",
            params![now, id],
        )?;

        if changed == 0 {
            Err(CoreError::NotFound)
        } else {
            Ok(())
        }
    }

    pub fn cat_status(&self) -> Result<CatStatus, CoreError> {
        let connection = self.lock_connection()?;
        Ok(connection.query_row(
            "SELECT level, xp, fish, mood FROM cat WHERE id = 1",
            [],
            |row| {
                Ok(CatStatus {
                    level: row.get(0)?,
                    xp: row.get(1)?,
                    fish: row.get(2)?,
                    mood: row.get(3)?,
                })
            },
        )?)
    }

    pub fn search(&self, query_text: String) -> Result<Vec<Memory>, CoreError> {
        let connection = self.lock_connection()?;
        let pattern = format!("%{query_text}%");
        let mut statement = connection.prepare(
            "SELECT id, kind, raw_text, title, due_at, completed_at, question, answer,
                    created_at, updated_at
             FROM memories
             WHERE deleted_at IS NULL
               AND (
                   raw_text LIKE ?1
                   OR title LIKE ?1
                   OR question LIKE ?1
                   OR answer LIKE ?1
               )
             ORDER BY updated_at DESC, id DESC",
        )?;
        let rows = statement.query_map([pattern], memory_from_row)?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }
}

impl MewmewCore {
    fn lock_connection(&self) -> Result<MutexGuard<'_, Connection>, CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::Db("database mutex was poisoned".to_owned()))
    }
}

fn fetch_memory(connection: &Connection, id: &str) -> Result<Memory, CoreError> {
    connection
        .query_row(
            "SELECT id, kind, raw_text, title, due_at, completed_at, question, answer,
                    created_at, updated_at
             FROM memories
             WHERE id = ?1 AND deleted_at IS NULL",
            [id],
            memory_from_row,
        )
        .optional()?
        .ok_or(CoreError::NotFound)
}

fn memory_from_row(row: &Row<'_>) -> rusqlite::Result<Memory> {
    let kind: String = row.get(1)?;

    Ok(Memory {
        id: row.get(0)?,
        kind: MemoryKind::from_db_value(&kind)?,
        raw_text: row.get(2)?,
        title: row.get(3)?,
        due_at: row.get(4)?,
        completed_at: row.get(5)?,
        question: row.get(6)?,
        answer: row.get(7)?,
        created_at: row.get(8)?,
        updated_at: row.get(9)?,
    })
}

fn migrations() -> Vec<&'static str> {
    vec![
        "
        CREATE TABLE IF NOT EXISTS memories (
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
        CREATE INDEX IF NOT EXISTS idx_memories_kind ON memories(kind);
        CREATE INDEX IF NOT EXISTS idx_memories_due
          ON memories(due_at) WHERE due_at IS NOT NULL;

        CREATE TABLE IF NOT EXISTS cat (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          level INTEGER NOT NULL DEFAULT 1,
          xp INTEGER NOT NULL DEFAULT 0,
          fish INTEGER NOT NULL DEFAULT 0,
          mood TEXT NOT NULL DEFAULT 'content',
          updated_at INTEGER NOT NULL
        );
        INSERT OR IGNORE INTO cat (id, updated_at) VALUES (1, 0);
        ",
    ]
}

fn run_migrations(connection: &mut Connection) -> Result<(), CoreError> {
    let transaction = connection.transaction()?;
    transaction
        .execute_batch("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL);")?;

    let current_version = transaction
        .query_row("SELECT version FROM schema_version LIMIT 1", [], |row| {
            row.get::<_, i64>(0)
        })
        .optional()?
        .unwrap_or(0);

    for (index, migration) in migrations().iter().enumerate() {
        let version = i64::try_from(index + 1)
            .map_err(|_| CoreError::Db("migration version overflow".to_owned()))?;
        if version <= current_version {
            continue;
        }

        transaction.execute_batch(migration)?;
        transaction.execute("DELETE FROM schema_version", [])?;
        transaction.execute(
            "INSERT INTO schema_version (version) VALUES (?1)",
            [version],
        )?;
    }

    transaction.commit()?;
    Ok(())
}

uniffi::setup_scaffolding!();
