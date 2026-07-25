//! Core domain and persistence library for mewmew.

use std::sync::{Arc, Mutex, MutexGuard};

use chrono::{DateTime, Utc};
use rs_fsrs::{Card, Parameters, Rating, State, FSRS};
use rusqlite::functions::FunctionFlags;
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
    pub outfit: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ReviewRating {
    Again,
    Hard,
    Good,
    Easy,
}

impl ReviewRating {
    fn as_fsrs_rating(self) -> Rating {
        match self {
            Self::Again => Rating::Again,
            Self::Hard => Rating::Hard,
            Self::Good => Rating::Good,
            Self::Easy => Rating::Easy,
        }
    }

    fn earns_fish(self) -> bool {
        matches!(self, Self::Good | Self::Easy)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ReviewOutcome {
    pub memory: Memory,
    pub next_due_at: i64,
    pub earned_fish: bool,
}

struct StoredFsrsCard {
    due: Option<i64>,
    stability: Option<f64>,
    difficulty: Option<f64>,
    elapsed_days: i64,
    scheduled_days: i64,
    reps: i32,
    lapses: i32,
    state: i64,
    last_review: Option<i64>,
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
        register_sqlite_functions(&connection)?;
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
                fsrs_due, created_at, updated_at
             ) VALUES (
                ?1, ?2, ?3, ?4, ?5, NULL, ?6, ?7,
                CASE WHEN ?2 = 'card' THEN ?8 ELSE NULL END, ?8, ?8
             )",
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
                 fsrs_due = CASE
                     WHEN ?1 = 'card' AND fsrs_due IS NULL THEN created_at
                     ELSE fsrs_due
                 END,
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

    pub fn pending_reminders(&self, limit: u32, now: i64) -> Result<Vec<Memory>, CoreError> {
        let connection = self.lock_connection()?;
        let mut statement = connection.prepare(
            "SELECT id, kind, raw_text, title, due_at, completed_at, question, answer,
                    created_at, updated_at
             FROM memories
             WHERE deleted_at IS NULL
               AND kind = 'reminder'
               AND completed_at IS NULL
               AND due_at > ?1
             ORDER BY due_at ASC, id ASC
             LIMIT ?2",
        )?;
        let rows = statement.query_map(params![now, i64::from(limit)], memory_from_row)?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    pub fn due_cards(&self, limit: u32, now: i64) -> Result<Vec<Memory>, CoreError> {
        let connection = self.lock_connection()?;
        let mut statement = connection.prepare(
            "SELECT id, kind, raw_text, title, due_at, completed_at, question, answer,
                    created_at, updated_at
             FROM memories
             WHERE deleted_at IS NULL
               AND kind = 'card'
               AND length(trim(question)) > 0
               AND length(trim(answer)) > 0
               AND fsrs_due <= ?1
             ORDER BY fsrs_due ASC, id ASC
             LIMIT ?2",
        )?;
        let rows = statement.query_map(params![now, i64::from(limit)], memory_from_row)?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    pub fn due_card_count(&self, now: i64) -> Result<u32, CoreError> {
        let connection = self.lock_connection()?;
        let count: i64 = connection.query_row(
            "SELECT COUNT(*)
             FROM memories
             WHERE deleted_at IS NULL
               AND kind = 'card'
               AND length(trim(question)) > 0
               AND length(trim(answer)) > 0
               AND fsrs_due <= ?1",
            [now],
            |row| row.get(0),
        )?;
        u32::try_from(count).map_err(|_| CoreError::Db("due card count overflow".to_owned()))
    }

    /// When the soonest not-yet-due card comes up, for scheduling the review
    /// notification. Returns None when nothing is waiting in the future.
    pub fn next_card_due_at(&self, now: i64) -> Result<Option<i64>, CoreError> {
        let connection = self.lock_connection()?;
        Ok(connection
            .query_row(
                "SELECT MIN(fsrs_due)
                 FROM memories
                 WHERE deleted_at IS NULL
                   AND kind = 'card'
                   AND length(trim(question)) > 0
                   AND length(trim(answer)) > 0
                   AND fsrs_due > ?1",
                [now],
                |row| row.get::<_, Option<i64>>(0),
            )
            .optional()?
            .flatten())
    }

    pub fn review_card(
        &self,
        id: String,
        rating: ReviewRating,
        now: i64,
    ) -> Result<ReviewOutcome, CoreError> {
        let now_utc = unix_timestamp(now)?;
        let mut connection = self.lock_connection()?;
        let transaction = connection.transaction()?;
        let stored = fetch_review_card(&transaction, &id, now_utc)?;
        let fsrs = FSRS::new(Parameters::default());
        let mut scheduler = fsrs.scheduler(stored, now_utc);
        let next = scheduler.review(rating.as_fsrs_rating()).card;
        let earned_fish = rating.earns_fish();

        transaction.execute(
            "UPDATE memories
             SET fsrs_due = ?1,
                 fsrs_stability = ?2,
                 fsrs_difficulty = ?3,
                 fsrs_elapsed_days = ?4,
                 fsrs_scheduled_days = ?5,
                 fsrs_reps = ?6,
                 fsrs_lapses = ?7,
                 fsrs_state = ?8,
                 fsrs_last_review = ?9,
                 updated_at = ?10
             WHERE id = ?11 AND deleted_at IS NULL",
            params![
                next.due.timestamp(),
                next.stability,
                next.difficulty,
                next.elapsed_days,
                next.scheduled_days,
                next.reps,
                next.lapses,
                state_db_value(next.state),
                next.last_review.timestamp(),
                now,
                id,
            ],
        )?;

        if earned_fish {
            transaction.execute(
                "UPDATE cat
                 SET fish = fish + 1, last_interaction_at = ?1, updated_at = ?1
                 WHERE id = 1",
                [now],
            )?;
        }

        let memory = fetch_memory(&transaction, &id)?;
        let outcome = ReviewOutcome {
            memory,
            next_due_at: next.due.timestamp(),
            earned_fish,
        };
        transaction.commit()?;
        Ok(outcome)
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
            "UPDATE cat
             SET fish = fish + 1, last_interaction_at = ?1, updated_at = ?1
             WHERE id = 1",
            [now],
        )?;

        let completed = fetch_memory(&transaction, &id)?;
        transaction.commit()?;
        Ok(completed)
    }

    pub fn snooze_reminder(
        &self,
        id: String,
        new_due_at: i64,
        now: i64,
    ) -> Result<Memory, CoreError> {
        let connection = self.lock_connection()?;
        let existing = fetch_memory(&connection, &id)?;

        if existing.kind != MemoryKind::Reminder {
            return Err(CoreError::Invalid(
                "only reminders can be snoozed".to_owned(),
            ));
        }
        if existing.completed_at.is_some() {
            return Err(CoreError::Invalid(
                "completed reminders cannot be snoozed".to_owned(),
            ));
        }

        connection.execute(
            "UPDATE memories
             SET due_at = ?1, updated_at = ?2
             WHERE id = ?3 AND deleted_at IS NULL",
            params![new_due_at, now, id],
        )?;
        fetch_memory(&connection, &id)
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
        fetch_cat_status(&connection, None)
    }

    pub fn cat_status_at(&self, now: i64) -> Result<CatStatus, CoreError> {
        let connection = self.lock_connection()?;
        fetch_cat_status(&connection, Some(now))
    }

    pub fn feed_cat(&self, now: i64) -> Result<CatStatus, CoreError> {
        let mut connection = self.lock_connection()?;
        let transaction = connection.transaction()?;
        let changed = transaction.execute(
            "UPDATE cat
             SET fish = fish - 1,
                 xp = xp + 10,
                 last_interaction_at = ?1,
                 updated_at = ?1
             WHERE id = 1 AND fish > 0",
            [now],
        )?;

        if changed == 0 {
            return Err(CoreError::Invalid("没有小鱼干了".to_owned()));
        }

        let status = fetch_cat_status(&transaction, Some(now))?;
        transaction.commit()?;
        Ok(status)
    }

    pub fn unlocked_outfits(&self) -> Result<Vec<String>, CoreError> {
        let connection = self.lock_connection()?;
        let level = fetch_cat_status(&connection, None)?.level;
        Ok(outfits_for_level(level)
            .into_iter()
            .map(str::to_owned)
            .collect())
    }

    pub fn set_outfit(&self, outfit: String, now: i64) -> Result<CatStatus, CoreError> {
        let required_level = outfit_required_level(&outfit)
            .ok_or_else(|| CoreError::Invalid(format!("未知装扮: {outfit}")))?;
        let mut connection = self.lock_connection()?;
        let transaction = connection.transaction()?;
        let xp: i64 =
            transaction.query_row("SELECT xp FROM cat WHERE id = 1", [], |row| row.get(0))?;
        let level = level_for_xp(xp);

        if level < required_level {
            return Err(CoreError::Invalid(format!(
                "装扮 {outfit} 需要 Lv.{required_level} 解锁"
            )));
        }

        transaction.execute(
            "UPDATE cat
             SET outfit = ?1,
                 level = ?2,
                 last_interaction_at = ?3,
                 updated_at = ?3
             WHERE id = 1",
            params![outfit, level, now],
        )?;
        let status = fetch_cat_status(&transaction, Some(now))?;
        transaction.commit()?;
        Ok(status)
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

    pub fn search_for_recall(&self, query: String, limit: u32) -> Result<Vec<Memory>, CoreError> {
        if limit == 0 {
            return Ok(Vec::new());
        }

        let Some((strict, loose)) = recall_match_queries(&query) else {
            return Ok(Vec::new());
        };

        let connection = self.lock_connection()?;
        let mut statement = connection.prepare(
            "SELECT m.id, m.kind, m.raw_text, m.title, m.due_at, m.completed_at,
                    m.question, m.answer, m.created_at, m.updated_at
             FROM memories_fts
             JOIN memories AS m ON m.rowid = memories_fts.rowid
             WHERE memories_fts MATCH ?1
               AND m.deleted_at IS NULL
             ORDER BY bm25(memories_fts) ASC, m.updated_at DESC, m.id DESC
             LIMIT ?2",
        )?;

        let mut run = |match_query: &str| -> rusqlite::Result<Vec<Memory>> {
            statement
                .query_map(params![match_query, i64::from(limit)], memory_from_row)?
                .collect()
        };

        let hits = run(&strict)?;
        // Widening only when the strict pass is empty keeps precise queries
        // precise: recall should prefer a ranked near-miss over nothing.
        if hits.is_empty() && loose != strict {
            return Ok(run(&loose)?);
        }
        Ok(hits)
    }
}

impl MewmewCore {
    fn lock_connection(&self) -> Result<MutexGuard<'_, Connection>, CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::Db("database mutex was poisoned".to_owned()))
    }
}

fn level_for_xp(xp: i64) -> i64 {
    if xp < 30 {
        return 1;
    }
    if xp < 80 {
        return 2;
    }

    fn threshold(level: i64) -> i128 {
        let level = i128::from(level);
        // Lv.3 is the recurrence seed: each following threshold adds
        // 40 × (the current level - 1).
        20 * (level - 2) * (level - 1) + 40
    }

    let xp = i128::from(xp);
    let mut low = 3;
    let mut high = 1_000_000_000;
    while low < high {
        let middle = low + (high - low + 1) / 2;
        if threshold(middle) <= xp {
            low = middle;
        } else {
            high = middle - 1;
        }
    }
    low
}

fn mood_at(last_interaction_at: Option<i64>, now: i64) -> &'static str {
    let Some(last_interaction_at) = last_interaction_at else {
        return "happy";
    };
    let elapsed = now.saturating_sub(last_interaction_at);
    if elapsed < 24 * 60 * 60 {
        "happy"
    } else if elapsed <= 72 * 60 * 60 {
        "content"
    } else {
        "sleepy"
    }
}

fn outfit_required_level(outfit: &str) -> Option<i64> {
    match outfit {
        "none" => Some(1),
        "scarf" => Some(2),
        "glasses" => Some(4),
        _ => None,
    }
}

fn outfits_for_level(level: i64) -> Vec<&'static str> {
    ["none", "scarf", "glasses"]
        .into_iter()
        .filter(|outfit| {
            outfit_required_level(outfit).is_some_and(|required_level| level >= required_level)
        })
        .collect()
}

fn fetch_cat_status(connection: &Connection, now: Option<i64>) -> Result<CatStatus, CoreError> {
    let (cached_level, xp, fish, stored_mood, last_interaction_at, outfit): (
        i64,
        i64,
        i64,
        String,
        Option<i64>,
        String,
    ) = connection.query_row(
        "SELECT level, xp, fish, mood, last_interaction_at, outfit
         FROM cat
         WHERE id = 1",
        [],
        |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get(5)?,
            ))
        },
    )?;
    let level = level_for_xp(xp);
    if cached_level != level {
        connection.execute("UPDATE cat SET level = ?1 WHERE id = 1", [level])?;
    }

    Ok(CatStatus {
        level,
        xp,
        fish,
        mood: now.map_or(stored_mood, |now| {
            mood_at(last_interaction_at, now).to_owned()
        }),
        outfit,
    })
}

fn unix_timestamp(timestamp: i64) -> Result<DateTime<Utc>, CoreError> {
    DateTime::from_timestamp(timestamp, 0)
        .ok_or_else(|| CoreError::Invalid(format!("invalid unix timestamp: {timestamp}")))
}

fn state_from_db_value(value: i64) -> Result<State, CoreError> {
    match value {
        0 => Ok(State::New),
        1 => Ok(State::Learning),
        2 => Ok(State::Review),
        3 => Ok(State::Relearning),
        other => Err(CoreError::Invalid(format!("invalid FSRS state: {other}"))),
    }
}

const fn state_db_value(state: State) -> i64 {
    match state {
        State::New => 0,
        State::Learning => 1,
        State::Review => 2,
        State::Relearning => 3,
    }
}

fn fetch_review_card(
    connection: &Connection,
    id: &str,
    now: DateTime<Utc>,
) -> Result<Card, CoreError> {
    let memory = fetch_memory(connection, id)?;
    if memory.kind != MemoryKind::Card {
        return Err(CoreError::Invalid("only cards can be reviewed".to_owned()));
    }
    if memory
        .question
        .as_deref()
        .is_none_or(|question| question.trim().is_empty())
    {
        return Err(CoreError::Invalid(
            "card must have a non-empty question".to_owned(),
        ));
    }
    if memory
        .answer
        .as_deref()
        .is_none_or(|answer| answer.trim().is_empty())
    {
        return Err(CoreError::Invalid(
            "card must have a non-empty answer".to_owned(),
        ));
    }

    let stored = connection.query_row(
        "SELECT fsrs_due, fsrs_stability, fsrs_difficulty, fsrs_elapsed_days,
                fsrs_scheduled_days, fsrs_reps, fsrs_lapses, fsrs_state,
                fsrs_last_review
         FROM memories
         WHERE id = ?1 AND deleted_at IS NULL",
        [id],
        |row| {
            Ok(StoredFsrsCard {
                due: row.get(0)?,
                stability: row.get(1)?,
                difficulty: row.get(2)?,
                elapsed_days: row.get(3)?,
                scheduled_days: row.get(4)?,
                reps: row.get(5)?,
                lapses: row.get(6)?,
                state: row.get(7)?,
                last_review: row.get(8)?,
            })
        },
    )?;

    Ok(Card {
        due: unix_timestamp(stored.due.unwrap_or(memory.created_at))?,
        stability: stored.stability.unwrap_or_default(),
        difficulty: stored.difficulty.unwrap_or_default(),
        elapsed_days: stored.elapsed_days,
        scheduled_days: stored.scheduled_days,
        reps: stored.reps,
        lapses: stored.lapses,
        state: state_from_db_value(stored.state)?,
        last_review: match stored.last_review {
            Some(timestamp) => unix_timestamp(timestamp)?,
            None => now,
        },
    })
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

fn register_sqlite_functions(connection: &Connection) -> Result<(), CoreError> {
    connection.create_scalar_function(
        "mewmew_fts_tokens",
        1,
        FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC,
        |context| {
            let value = context.get::<Option<String>>(0)?;
            Ok(value.map_or_else(String::new, |text| fts_tokens(&text)))
        },
    )?;
    Ok(())
}

fn is_cjk(character: char) -> bool {
    matches!(
        character as u32,
        0x3400..=0x4DBF
            | 0x4E00..=0x9FFF
            | 0xF900..=0xFAFF
            | 0x20000..=0x2FA1F
            | 0x30000..=0x323AF
    )
}

fn fts_tokens(value: &str) -> String {
    fn flush_current(current: &mut String, tokens: &mut Vec<String>) {
        if !current.is_empty() {
            tokens.push(std::mem::take(current));
        }
    }

    let mut tokens = Vec::new();
    let mut current = String::new();
    for character in value.chars() {
        if is_cjk(character) {
            flush_current(&mut current, &mut tokens);
            tokens.push(character.to_string());
        } else if character.is_alphanumeric() || character == '_' {
            current.extend(character.to_lowercase());
        } else {
            flush_current(&mut current, &mut tokens);
        }
    }
    flush_current(&mut current, &mut tokens);
    tokens.join(" ")
}

/// Function words and question particles. People ask "护照在哪", not "护照" —
/// under AND semantics the stray 在/哪 characters are enough to match nothing,
/// since no stored memory contains them.
const CJK_STOPWORDS: &[char] = &[
    '的', '了', '是', '在', '吗', '呢', '吧', '啊', '我', '你', '他', '她', '它', '们', '这', '那',
    '哪', '什', '么', '怎', '谁', '请', '问', '有', '把', '被', '就', '也', '还', '和', '与', '及',
    '对', '从', '给', '让', '之', '地', '得', '过', '呀', '嘛',
];

fn is_stopword(token: &str) -> bool {
    let mut chars = token.chars();
    match (chars.next(), chars.next()) {
        (Some(single), None) => CJK_STOPWORDS.contains(&single),
        _ => false,
    }
}

fn quote_tokens(tokens: &[String], joiner: &str) -> String {
    tokens
        .iter()
        .map(|token| format!("\"{}\"", token.replace('"', "\"\"")))
        .collect::<Vec<_>>()
        .join(joiner)
}

/// The strict query (every meaningful token present) and a loose fallback
/// (any token). Callers try strict first so precise queries stay precise, and
/// only widen when that finds nothing.
fn recall_match_queries(query: &str) -> Option<(String, String)> {
    let tokenized = fts_tokens(query);
    let all: Vec<String> = tokenized.split_whitespace().map(str::to_owned).collect();
    if all.is_empty() {
        return None;
    }

    let meaningful: Vec<String> = all
        .iter()
        .filter(|token| !is_stopword(token))
        .cloned()
        .collect();
    // A query of nothing but particles still deserves an attempt.
    let strict_source = if meaningful.is_empty() {
        &all
    } else {
        &meaningful
    };

    Some((
        quote_tokens(strict_source, " AND "),
        quote_tokens(&all, " OR "),
    ))
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
        "
        CREATE VIRTUAL TABLE memories_fts USING fts5(
          raw_text,
          title,
          question,
          answer,
          tokenize = 'unicode61'
        );

        INSERT INTO memories_fts (rowid, raw_text, title, question, answer)
        SELECT
          rowid,
          mewmew_fts_tokens(raw_text),
          mewmew_fts_tokens(title),
          mewmew_fts_tokens(question),
          mewmew_fts_tokens(answer)
        FROM memories
        WHERE deleted_at IS NULL;

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
        "
        ALTER TABLE memories ADD COLUMN fsrs_last_review INTEGER;
        ALTER TABLE memories
          ADD COLUMN fsrs_elapsed_days INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE memories
          ADD COLUMN fsrs_scheduled_days INTEGER NOT NULL DEFAULT 0;

        UPDATE memories
        SET fsrs_due = created_at
        WHERE kind = 'card' AND fsrs_due IS NULL;
        ",
        "
        ALTER TABLE cat ADD COLUMN last_interaction_at INTEGER;
        ALTER TABLE cat
          ADD COLUMN outfit TEXT NOT NULL DEFAULT 'none';

        UPDATE cat SET last_interaction_at = updated_at;
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

    if current_version == 0 {
        // A database created in this run has no interaction history. Legacy
        // rows still keep the v4 backfill from their previous updated_at.
        transaction.execute("UPDATE cat SET last_interaction_at = NULL WHERE id = 1", [])?;
    }

    transaction.commit()?;
    Ok(())
}

uniffi::setup_scaffolding!();
