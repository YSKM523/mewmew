# Phase 3 Core and Worker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use test-driven-development and verification-before-completion while implementing this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Phase 3 reminder and recall APIs in Rust core and the `/v1/recall` Cloudflare Worker endpoint without changing `ios/`.

**Architecture:** Core keeps reminder operations in the existing `MewmewCore` export and adds a schema-versioned FTS5 index synchronized by SQLite triggers. Chinese text is transformed into unicode61-compatible per-Han-character tokens at index and query time. Worker reuses the parse endpoint's authentication, shared KV quota, DeepSeek settings, and timeout while giving recall its own strict JSON schema and explicit HTTP-200 fallback.

**Tech Stack:** Rust 2021, rusqlite bundled SQLite/FTS5, UniFFI, TypeScript, Cloudflare Workers, Vitest.

## Global Constraints

- Treat `docs/phase3-spec.md` as authoritative.
- Do not modify anything below `ios/`.
- Do not commit or deploy.
- Every new core API is exported through the existing `#[uniffi::export]` implementation.
- Run every quality-gate command requested by the user and report its fresh output.

---

### Task 1: Core reminder APIs

**Files:**
- Modify: `core/tests/core.rs`
- Modify: `core/src/lib.rs`

**Interfaces:**
- Produces: `pending_reminders(&self, limit: u32, now: i64) -> Result<Vec<Memory>, CoreError>`
- Produces: `snooze_reminder(&self, id: String, new_due_at: i64, now: i64) -> Result<Memory, CoreError>`

- [ ] **Step 1: Write failing reminder tests**

Add integration tests that create future, past, completed, soft-deleted, and non-reminder rows. Assert strict future filtering, due-time ordering, limit behavior, updated snooze timestamps, and `NotFound`/`Invalid` error classes.

- [ ] **Step 2: Verify the tests fail for missing APIs**

Run:

```bash
cd core
CARGO_HOME=/tmp/mewmew-cargo-home cargo test pending_reminders
CARGO_HOME=/tmp/mewmew-cargo-home cargo test snooze_reminder
```

Expected: compilation failure because the two methods do not exist.

- [ ] **Step 3: Implement minimal SQL-backed APIs**

Use `deleted_at IS NULL`, `completed_at IS NULL`, `kind = 'reminder'`, and `due_at > ?` for pending reminders. For snooze, fetch the visible row, validate kind and completion, then update `due_at` and `updated_at`.

- [ ] **Step 4: Verify reminder tests pass**

Run the two filtered test commands again and expect all matching tests to pass.

### Task 2: Core FTS5 recall search

**Files:**
- Modify: `core/Cargo.toml`
- Modify: `core/tests/core.rs`
- Modify: `core/src/lib.rs`

**Interfaces:**
- Produces: migration version 2 with `memories_fts` and INSERT/UPDATE/DELETE triggers
- Produces: `search_for_recall(&self, query: String, limit: u32) -> Result<Vec<Memory>, CoreError>`

- [ ] **Step 1: Write failing recall and upgrade tests**

Add tests for Chinese substring search (`护照` against `护照放在书房第二个抽屉里`), Chinese multi-term search, English search, a miss, soft deletion, limits, and upgrading an existing schema-version-1 database with pre-existing rows.

- [ ] **Step 2: Verify the Chinese test fails before implementation**

Run:

```bash
cd core
CARGO_HOME=/tmp/mewmew-cargo-home cargo test recall_search_matches_a_chinese_word_inside_an_unspaced_sentence
```

Expected: compilation failure because `search_for_recall` is absent.

- [ ] **Step 3: Implement FTS5 migration and tokenizer bridge**

Enable rusqlite scalar functions, register a deterministic `mewmew_fts_tokens` function before migrations, create a unicode61 FTS5 table, backfill all live existing rows, and install triggers that keep all four searchable fields synchronized. Transform Han characters into individual tokens while preserving contiguous English words, and build a quoted `AND` query from the same tokens.

- [ ] **Step 4: Implement ranked recall search**

Join FTS rowids to `memories`, exclude soft-deleted rows defensively, order by `bm25(memories_fts)` ascending then `updated_at` descending, and apply the requested limit.

- [ ] **Step 5: Verify all core tests pass**

Run:

```bash
cd core
CARGO_HOME=/tmp/mewmew-cargo-home cargo test
```

Expected: all unit, integration, and doc tests pass.

### Task 3: Worker recall endpoint

**Files:**
- Modify: `worker/test/index.test.ts`
- Modify: `worker/src/schema.ts`
- Modify: `worker/src/index.ts`

**Interfaces:**
- Consumes: `POST /v1/recall` JSON `{ question, memories }`
- Produces: JSON `{ answer, cited_ids }`

- [ ] **Step 1: Write failing endpoint tests**

Add tests for a successful model response and exact DeepSeek options, empty memories without a model call, network failure fallback, filtering unknown cited IDs, and recall-specific authentication and quota responses.

- [ ] **Step 2: Verify recall tests fail with 404**

Run:

```bash
cd worker
npm test -- --run test/index.test.ts
```

Expected: new recall tests fail because the route is not implemented.

- [ ] **Step 3: Add recall schemas and strict model parsing**

Validate the request memory shape and model JSON response. Keep only cited IDs present in the request and remove duplicates while preserving model order.

- [ ] **Step 4: Add recall DeepSeek call and routing**

Use `deepseek-v4-flash`, temperature `0`, JSON-object output, `max_tokens: 2048`, and the existing eight-second abort behavior. Send structured question and memories, and require grounded answers of no more than two sentences.

- [ ] **Step 5: Add explicit recall outcomes**

Return `我没记过这个` for an empty memory list. Return `猫有点困,先看看这些记忆吧` and no citations for invalid input, model, timeout, configuration, or network failures, always with HTTP 200 after authentication/quota succeeds.

- [ ] **Step 6: Verify worker tests and types**

Run:

```bash
cd worker
npm test
npx tsc --noEmit
```

Expected: all tests pass and TypeScript emits no diagnostics.

### Task 4: Final quality gates and scope review

**Files:**
- Inspect only: all changed files and `git status`

- [ ] **Step 1: Run the exact core quality gate**

```bash
cd core
CARGO_HOME=/tmp/mewmew-cargo-home cargo test
CARGO_HOME=/tmp/mewmew-cargo-home cargo clippy -- -D warnings
CARGO_HOME=/tmp/mewmew-cargo-home cargo fmt --check
```

- [ ] **Step 2: Run the exact worker quality gate**

```bash
cd worker
npm test
npx tsc --noEmit
```

- [ ] **Step 3: Review scope and report**

Confirm no `ios/` path changed, no commit was created, list every changed file, quote command outputs, name the passing Chinese regression test, and document decisions and deviations.
