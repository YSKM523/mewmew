# Phase 4 规格:内化记忆(FSRS 间隔重复 + 考问会话)

Phase 3 让猫替你记。Phase 4 让猫**帮你背**:在你快忘的时候主动叼卡片来考你。这是养成机制真正开始发力的地方——答对喂鱼,鱼干喂猫。

## 已实测的 FSRS 事实(2026-07-25,`rs-fsrs` 1.2.1,勿凭记忆改)

API:
```rust
let fsrs = FSRS::new(Parameters::default());
let mut scheduler = fsrs.scheduler(card, now_utc);   // -> Box<dyn ImplScheduler>
let info: SchedulingInfo = scheduler.review(Rating::Good);
let next: Card = info.card;
```
`Rating`:Again=1 / Hard=2 / Good=3 / Easy=4。`State`:New=0 / Learning=1 / Review=2 / Relearning=3。

`Card` 字段:`due`、`stability`、`difficulty`、`elapsed_days`、`scheduled_days`、`reps`、`lapses`、`state`、`last_review`。

实测调度间隔(新卡):

| 评分 | 下次 |
|---|---|
| Again | 1 分钟 |
| Hard | 4 分钟 |
| Good | 10 分钟 |
| Easy | 15 天 |

连续答 Good:10 分钟 → 4 天 → 15 天 → 48 天 → 136 天 → 351 天。

**坑:`Card::new()` 内部调用 `Utc::now()`**,违反 core 不读时钟的约定(测试不可复现)。必须手工构造 `Card`,`due` 与 `last_review` 用调用方传入的 `now`。

## A. core:调度与评分

### 迁移 v3
`memories` 表已有 `fsrs_due/stability/difficulty/reps/lapses/state`,补三列:
`fsrs_last_review INTEGER`、`fsrs_elapsed_days INTEGER NOT NULL DEFAULT 0`、`fsrs_scheduled_days INTEGER NOT NULL DEFAULT 0`。

新建的 card 若 `fsrs_due IS NULL`,视为 State::New,`fsrs_due` 初始化为 created_at(立即可考)。迁移要把存量 card 回填成"立即可考"。

### API

```rust
fn due_cards(&self, limit: u32, now: i64) -> Result<Vec<Memory>>;
// kind=card、未软删、question/answer 均非空、fsrs_due <= now,按 fsrs_due 升序

fn review_card(&self, id: String, rating: ReviewRating, now: i64) -> Result<ReviewOutcome>;
// 1) 读出该 card 的 FSRS 状态,手工构造 rs_fsrs::Card
// 2) fsrs.scheduler(card, now).review(rating) 得到新状态,写回全部 fsrs_* 列 + updated_at
// 3) 评分 Good/Easy 时 cat.fish += 1(Again/Hard 不加也不扣——惩罚会杀掉复习习惯)
// 4) 返回 ReviewOutcome { memory, next_due_at, earned_fish: bool }

fn due_card_count(&self, now: i64) -> Result<u32>;
```

`ReviewRating` 是我们自己的 uniffi enum(Again/Hard/Good/Easy),不要直接暴露第三方类型。

### 测试要求
- 新卡 review(Good) 后 fsrs_due 前移约 10 分钟、reps=1、state=Learning。
- 连续 Good 六次,间隔单调递增(实测值见上表,断言"下一次间隔 > 上一次"即可,不要写死数字——参数升级会变)。
- Again 会增加 lapses 并把 due 拉近。
- Good/Easy 加 1 条鱼干,Again/Hard 不加。
- 软删/不存在/非 card/缺 question 的记录 → 错误。
- **不读系统时钟**:同样的 (card 状态, rating, now) 必须得到同样的结果。

## B. iOS:考问会话

### 入口
猫主页「今天」区第二张卡已经是"到期卡片 N",点进去进考问会话。N 来自 `due_card_count`。

### 会话流程
一张张过,每张分两步:
1. **提问**:大字显示 `question`,下方一个「想想…」按钮(点了才揭晓答案)。这个停顿是间隔重复起效的关键——先自己回忆,再看答案。
2. **揭晓**:显示 `answer`,底部三个评分按钮。

### 评分按钮只给三个(不是四个)

Anki 的四档对普通用户是负担。映射:

| 按钮 | Rating | 说明 |
|---|---|---|
| 不记得 | Again | 主色描边,不用红色——忘记不是错误 |
| 记得 | Good | 主色实心,默认动作 |
| 太简单 | Easy | 次级样式 |

Hard 不暴露给用户(FSRS 内部仍支持,将来要加再说)。

### 结束
全部过完显示小结:复习了 N 张,喂了猫 M 条小鱼干,猫的反应(Phase 5 会做动画,这里先文字)。
中途退出:已评分的都已落库,不丢。

### 复习提醒通知(用 Phase 3 预留的 8 个槽位)
- 只排 **1 条**:下一张卡到期的时刻,文案「🐱 有 N 张卡片等你」。
- **安静时段**:到期时刻落在 21:00–09:00 之间的,顺延到当天 09:00。半夜被猫叫醒是最快的卸载理由。
- 记忆变更 / 复习结束 / 进入前台时,与提醒通知一起重排(复用 NotificationScheduler 的全量重放)。

## 验收

1. 记一条"ephemeral 是短暂的意思" → 列表里成为卡片 → 猫主页"到期卡片 1"。
2. 进考问 → 看到问题 → 点「想想…」→ 揭晓答案 → 点「记得」→ 鱼干 +1 → 下次到期约 10 分钟后。
3. 连续复习同一张卡多次,间隔逐次拉长。
4. 点「不记得」不扣鱼干、不报错,卡片很快再出现。
5. 造一张凌晨 3 点到期的卡 → 通知排在当天 09:00,不是 3 点。
6. 会话中途杀掉 app → 已评分的进度保留。

## 不做(留后)
自定义 FSRS 参数、复习历史统计图表、卡片手动编辑、Hard 档、跨设备复习进度同步(Phase 6)。
