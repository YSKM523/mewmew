# mewmew-worker 规格(Phase 2 起)

CF Worker(`worker/`,wrangler + TS),App 唯一的服务端。职责:LLM 代理(key 不进客户端)+ 后续 OTP/同步。

## Phase 2 范围:POST /v1/parse

请求:`{ "text": "<用户口述/键入原文>", "tz": "America/Toronto", "now": "2026-07-24T15:00:00" }`

响应:

```json
{
  "kind": "reminder | card | note",
  "title": "短标题(≤20字)",
  "due_at": "2026-07-29T15:00:00",     // reminder 才有,本地 ISO8601;解析不出为 null
  "question": "...", "answer": "...",   // card 才有
  "confidence": 0.92
}
```

Worker 把 `due_at` 按 `tz` 换算成 unix 秒返回给客户端(客户端 core 只吃 unix 秒)。

### 已验证的 system prompt(2026-07-24 实测 8/8 正确,勿随意重写)

```
你是记忆助手的分流器。把用户的一句话分类并结构化,只输出 JSON,不要解释。

kind 三选一:
- reminder: 含时间意图或需要在某时刻提醒的事(交费、赴约、吃药、截止)
- card: 用户想背下来的知识/单词/人名/概念(以后要考自己的)
- note: 其余(物品位置、事实记录、随想)

字段:
- kind: 上述之一
- title: ≤20字的短标题
- due_at: reminder 才有,ISO8601 本地时间字符串;解析不出填 null。其余 kind 填 null
- question/answer: card 才有,生成一问一答;其余填 null
- confidence: 0-1

当前时间: {now},时区 {tz}
```

实测样本与结果(deepseek-v4-flash,temperature 0,response_format json_object,max_tokens 2048):

| 输入 | kind | 提取 | 耗时 |
|---|---|---|---|
| 下周三下午三点提醒我交电费 | reminder | due 2026-07-29T15:00 | 3.5s |
| 明天早上八点吃药 | reminder | due 2026-07-25T08:00 | 2.1s |
| ephemeral 是短暂的意思 | card | Q/A 生成 | 3.0s |
| Rust 所有权规则… | card | Q/A 生成 | 2.0s |
| 护照放在书房第二个抽屉里 | note | — | 1.8s |
| 王医生的电话是 807-555-0199 | note | — | 1.9s |
| 我车停在 P3 层 B 区 42 号 | note | — | 2.0s |
| 周末想去那家新开的书店看看 | note | — | 2.0s |

### 实现约束

- 模型 `deepseek-v4-flash`(已确认现役;另有 `deepseek-v4-pro`)。**max_tokens ≥1024**——思考型模型给小了 content 会空(已知坑),实测用 2048。
- `temperature: 0` + `response_format: {"type":"json_object"}`;只读 `content`,不碰 `reasoning_content`。
- 服务端 schema 校验:kind 不在枚举内、title 缺失 → 降级 `kind=note, title=前20字`。
- 鉴权:Phase 2 用固定 app token(header `X-Mewmew-Token`),Phase 6 换用户会话。
- 限流:per-token 每日配额(KV 计数),超限 429——免费层限额的地基。
- 超时:LLM 调用 8s 上限,超时/异常一律降级返回 `kind=note`(客户端已先落库,capture 永不丢)。

## 部署

`wrangler deploy`(注意 exit 144 非失败惯例);secret:`DEEPSEEK_API_KEY`。**生产部署由用户确认后执行。**

## 客户端契约(重要)

capture 是这个 app 的生死线,必须零摩擦、永不丢:

1. 用户说完/打完 → **立即本地落库**(`kind=note`,title 取前 20 字)→ 猫立刻显示"记住啦!"。
2. 后台异步调 `/v1/parse`,成功后用返回结果升级这条记忆(kind/title/due_at/question/answer)。
3. 网络失败/超时 → 什么都不做,这条记忆就以 note 形式留着,用户零感知。

因此 core 需新增:

```rust
fn reclassify_memory(&self, id: String, kind: MemoryKind, title: String,
                     due_at: Option<i64>, question: Option<String>,
                     answer: Option<String>, now: i64) -> Result<Memory, CoreError>;
```

(软删过的记录应拒绝 reclassify;reclassify 不改 created_at。)
