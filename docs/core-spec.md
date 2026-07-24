# mewmew-core 规格(Phase 1)

Rust crate,承载全部领域逻辑,通过 UniFFI 暴露给 Swift。Phase 1 只做数据层骨架 + 绑定链路,FSRS/猫状态机后续 Phase 再进。

## 数据模型(SQLite,rusqlite)

统一 `memories` 表 + kind 判别,而不是三张表——capture 时 LLM 可能改判类型,单表改 kind 最省事。

```sql
CREATE TABLE memories (
  id TEXT PRIMARY KEY,            -- uuid v4
  kind TEXT NOT NULL,             -- 'reminder' | 'card' | 'note'
  raw_text TEXT NOT NULL,         -- 用户原话(口述转写/键入)
  title TEXT NOT NULL,            -- LLM 提炼的短标题
  -- reminder 专用
  due_at INTEGER,                 -- unix 秒,提醒时间
  completed_at INTEGER,
  -- card 专用(FSRS 字段 Phase 4 启用,先建列)
  question TEXT,
  answer TEXT,
  fsrs_due INTEGER,
  fsrs_stability REAL,
  fsrs_difficulty REAL,
  fsrs_reps INTEGER NOT NULL DEFAULT 0,
  fsrs_lapses INTEGER NOT NULL DEFAULT 0,
  fsrs_state INTEGER NOT NULL DEFAULT 0,
  -- 通用
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER              -- 软删,同步需要
);
CREATE INDEX idx_memories_kind ON memories(kind);
CREATE INDEX idx_memories_due ON memories(due_at) WHERE due_at IS NOT NULL;

CREATE TABLE cat (                -- 单行表,id 恒为 1
  id INTEGER PRIMARY KEY CHECK (id = 1),
  level INTEGER NOT NULL DEFAULT 1,
  xp INTEGER NOT NULL DEFAULT 0,
  fish INTEGER NOT NULL DEFAULT 0,
  mood TEXT NOT NULL DEFAULT 'content',
  updated_at INTEGER NOT NULL
);

CREATE TABLE schema_version (version INTEGER NOT NULL);
```

迁移:内置 `migrations: Vec<&str>`,按 `schema_version` 顺序执行,打开 DB 时自动跑。

## UniFFI 接口(proc-macro 风格,`#[uniffi::export]`,不用 UDL 文件)

```rust
// 错误
#[derive(uniffi::Error)]
pub enum CoreError { Db(String), NotFound, Invalid(String) }

// 记录(uniffi Record)
pub struct Memory { id, kind, raw_text, title, due_at: Option<i64>, completed_at: Option<i64>,
                    question: Option<String>, answer: Option<String>, created_at, updated_at }
pub enum MemoryKind { Reminder, Card, Note }
pub struct CatStatus { level, xp, fish, mood }
pub struct NewMemory { kind, raw_text, title, due_at: Option<i64>,
                       question: Option<String>, answer: Option<String> }

// 入口对象(uniffi Object,内部 Mutex<Connection>)
impl MewmewCore {
  #[uniffi::constructor] fn new(db_path: String) -> Result<Arc<Self>>;  // 打开+迁移
  fn add_memory(&self, m: NewMemory, now: i64) -> Result<Memory>;
  fn get_memory(&self, id: String) -> Result<Memory>;
  fn list_memories(&self, kind: Option<MemoryKind>) -> Result<Vec<Memory>>; // 未删,updated_at 倒序
  fn complete_reminder(&self, id: String, now: i64) -> Result<Memory>;      // 顺手 +1 fish
  fn delete_memory(&self, id: String, now: i64) -> Result<()>;              // 软删
  fn cat_status(&self) -> Result<CatStatus>;
  fn search(&self, query_text: String) -> Result<Vec<Memory>>;              // Phase 1 先 LIKE,召回 LLM 化在 Phase 3
}
```

约定:**时间一律由调用方传入 `now`**(unix 秒)——core 不读系统时钟,便于测试和未来同步对账。

## 工程要求

- crate 名 `mewmew-core`,lib name `mewmew_core`;`crate-type = ["lib", "staticlib", "cdylib"]`(iOS 静态链接 + 本机测试)。
- 依赖:`rusqlite (bundled)`、`uniffi`(latest 0.29.x)、`uuid (v4)`、`thiserror`。不要引入 tokio/async——全同步,Swift 侧自行调度线程。
- `uniffi-bindgen` 二进制 target(官方推荐的 `uniffi-bindgen` bin crate 模式),脚本 `core/build-swift.sh`:aarch64-apple-ios + aarch64-apple-ios-sim 双 target 构建 + xcframework 打包 + Swift 绑定生成(本机没有 Apple target 也要能写好脚本,CI 上跑)。
- 测试:CRUD 全覆盖 + 迁移幂等 + complete_reminder 加鱼 + search 命中/不命中 + 软删后 list 不可见。`cargo test` Linux 全绿。
- rustfmt + clippy 干净(`cargo clippy -- -D warnings`)。
