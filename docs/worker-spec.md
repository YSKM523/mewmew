# mewmew-worker 规格(Phase 2 起)

CF Worker(`worker/`,wrangler + TS),App 唯一的服务端。职责:LLM 代理(key 不进客户端)+ 后续 OTP/同步。

## Phase 2 范围:POST /v1/parse

请求:`{ "text": "<用户口述/键入原文>", "tz": "America/Toronto", "now": 1753372800 }`
响应:

```json
{
  "kind": "reminder | card | note",
  "title": "短标题(≤20字)",
  "due_at": 1753400000,          // 仅 reminder;由 LLM 相对时间解析 + tz 换算,解析不出为 null
  "question": "...", "answer": "...",  // 仅 card
  "confidence": 0.92
}
```

- LLM:DeepSeek(`deepseek-v4-flash`),**给足 max_tokens ≥1024**(思考型模型,太小 content 为空——已知坑);只用 `content` 字段,不碰 reasoning_content。强制 JSON 输出 + 服务端 schema 校验,校验失败降级返回 `kind=note`。
- 分流规则进 system prompt:含时间意图→reminder;疑问/知识/外语词→card(生成 Q/A);其余(位置、事实、随想)→note。
- 鉴权:Phase 2 先用简单 app token(header),Phase 6 换用户会话。
- 限流:per-token 每日配额(KV 计数),超限 429——免费层限额的地基。
- 超时:LLM 调用 8s 上限,超时返回 `kind=note` 降级(客户端先落库,保证 capture 永不丢)。

## 部署

`wrangler deploy`(注意 exit 144 非失败惯例);secret:`DEEPSEEK_API_KEY`。生产部署由用户确认后执行。

## 客户端契约

- capture 流程:**先本地落库(kind=note)再调 /v1/parse**,成功后用返回结果 update kind/title/due_at——网络失败用户零感知,猫始终"记住了"。
- 该"先落库后升级"的 update 需要 core 增一个 `reclassify_memory(id, kind, title, due_at, question, answer, now)` API(Phase 2 时加进 core-spec)。
