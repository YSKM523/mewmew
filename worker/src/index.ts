import {
  fallbackResult,
  parseModelContent,
  parseRecallModelContent,
  type ModelResult,
  type ParseResult,
  type RecallModelResult,
} from "./schema";
import { zonedLocalIsoToUnixSeconds } from "./timezone";

export interface Env {
  APP_TOKEN?: string;
  DEEPSEEK_API_KEY?: string;
  DAILY_QUOTA?: string;
  RATE_LIMIT: KVNamespace;
}

interface ParseInput {
  text: string;
  tz: string;
  now: string;
}

interface RecallMemory {
  id: string;
  kind: "reminder" | "card" | "note";
  title: string;
  raw_text: string;
  created_at: number;
}

interface RecallInput {
  question: string;
  memories: RecallMemory[];
}

interface RecallResult {
  answer: string;
  cited_ids: string[];
}

const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";
const DEEPSEEK_TIMEOUT_MS = 8_000;
const DEFAULT_DAILY_QUOTA = 200;

const SYSTEM_PROMPT = `你是记忆助手的分流器。把用户的一句话分类并结构化,只输出 JSON,不要解释。

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

当前时间: {now},时区 {tz}`;

const RECALL_SYSTEM_PROMPT = `你是记忆助手的召回答案器。只输出 JSON,不要解释。

只依据用户消息中给出的 memories 回答 question。没有足够依据时必须明确说不知道,严禁补充、猜测或编造任何记忆中没有的信息。
answer 最多两句话。
cited_ids 必须列出答案实际引用的 memory id,且只能使用输入 memories 中存在的 id;没有引用时返回空数组。

输出格式:
{"answer":"回答","cited_ids":["memory-id"]}`;

const EMPTY_RECALL_RESULT: RecallResult = {
  answer: "我没记过这个",
  cited_ids: [],
};

const FALLBACK_RECALL_RESULT: RecallResult = {
  answer: "猫有点困,先看看这些记忆吧",
  cited_ids: [],
};

function jsonResponse(value: unknown, status = 200): Response {
  return Response.json(value, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseInput(value: unknown): ParseInput {
  if (
    !isRecord(value) ||
    typeof value.text !== "string" ||
    typeof value.tz !== "string" ||
    typeof value.now !== "string"
  ) {
    throw new Error("request body is invalid");
  }
  return { text: value.text, tz: value.tz, now: value.now };
}

function isMemoryKind(value: unknown): value is RecallMemory["kind"] {
  return value === "reminder" || value === "card" || value === "note";
}

function parseRecallInput(value: unknown): RecallInput {
  if (
    !isRecord(value) ||
    typeof value.question !== "string" ||
    !Array.isArray(value.memories)
  ) {
    throw new Error("recall request body is invalid");
  }

  const memories = value.memories.map((memory): RecallMemory => {
    if (
      !isRecord(memory) ||
      typeof memory.id !== "string" ||
      memory.id.length === 0 ||
      !isMemoryKind(memory.kind) ||
      typeof memory.title !== "string" ||
      typeof memory.raw_text !== "string" ||
      typeof memory.created_at !== "number" ||
      !Number.isSafeInteger(memory.created_at)
    ) {
      throw new Error("recall memory is invalid");
    }
    return {
      id: memory.id,
      kind: memory.kind,
      title: memory.title,
      raw_text: memory.raw_text,
      created_at: memory.created_at,
    };
  });

  return { question: value.question, memories };
}

function quotaFromEnv(value: string | undefined): number {
  if (value === undefined) {
    return DEFAULT_DAILY_QUOTA;
  }
  const parsed = Number.parseInt(value, 10);
  return Number.isSafeInteger(parsed) && parsed > 0
    ? parsed
    : DEFAULT_DAILY_QUOTA;
}

function secondsUntilNextUtcDay(now: Date): number {
  const nextDay = Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate() + 1,
  );
  return Math.max(60, Math.ceil((nextDay - now.getTime()) / 1_000));
}

async function tokenDigest(token: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

async function consumeQuota(env: Env, token: string): Promise<boolean> {
  const now = new Date();
  const date = now.toISOString().slice(0, 10);
  const key = `parse:${date}:${await tokenDigest(token)}`;
  const currentValue = await env.RATE_LIMIT.get(key);
  const parsedCount =
    currentValue === null ? 0 : Number.parseInt(currentValue, 10);
  const count =
    Number.isSafeInteger(parsedCount) && parsedCount >= 0 ? parsedCount : 0;

  if (count >= quotaFromEnv(env.DAILY_QUOTA)) {
    return false;
  }

  await env.RATE_LIMIT.put(key, String(count + 1), {
    expirationTtl: secondsUntilNextUtcDay(now),
  });
  return true;
}

async function guardRequest(request: Request, env: Env): Promise<Response | null> {
  if (env.APP_TOKEN === undefined || env.APP_TOKEN.length === 0) {
    return jsonResponse({ error: "APP_TOKEN is not configured" }, 500);
  }

  const token = request.headers.get("X-Mewmew-Token");
  if (token !== env.APP_TOKEN) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  if (!(await consumeQuota(env, token))) {
    return jsonResponse({ error: "daily quota exceeded" }, 429);
  }

  return null;
}

function promptFor(input: ParseInput): string {
  return SYSTEM_PROMPT.replace("{now}", input.now).replace("{tz}", input.tz);
}

function modelContent(value: unknown): string {
  if (!isRecord(value) || !Array.isArray(value.choices)) {
    throw new Error("DeepSeek response is missing choices");
  }
  const choice = value.choices[0];
  if (!isRecord(choice) || !isRecord(choice.message)) {
    throw new Error("DeepSeek response is missing a message");
  }
  const content = choice.message.content;
  if (typeof content !== "string" || content.length === 0) {
    throw new Error("DeepSeek response content is empty");
  }
  return content;
}

async function callDeepSeek(
  systemPrompt: string,
  userContent: string,
  apiKey: string,
): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DEEPSEEK_TIMEOUT_MS);

  try {
    const response = await fetch(DEEPSEEK_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "deepseek-v4-flash",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userContent },
        ],
        temperature: 0,
        response_format: { type: "json_object" },
        max_tokens: 2048,
      }),
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`DeepSeek returned HTTP ${response.status}`);
    }

    return modelContent(await response.json());
  } finally {
    clearTimeout(timeout);
  }
}

async function parseWithDeepSeek(
  input: ParseInput,
  apiKey: string,
): Promise<ModelResult> {
  const content = await callDeepSeek(
    promptFor(input),
    input.text,
    apiKey,
  );
  return parseModelContent(content);
}

async function recallWithDeepSeek(
  input: RecallInput,
  apiKey: string,
): Promise<RecallModelResult> {
  const content = await callDeepSeek(
    RECALL_SYSTEM_PROMPT,
    JSON.stringify(input),
    apiKey,
  );
  return parseRecallModelContent(content);
}

function toRecallResult(
  model: RecallModelResult,
  input: RecallInput,
): RecallResult {
  const allowedIds = new Set(input.memories.map((memory) => memory.id));
  const seenIds = new Set<string>();
  const citedIds = model.cited_ids.filter((id) => {
    if (!allowedIds.has(id) || seenIds.has(id)) {
      return false;
    }
    seenIds.add(id);
    return true;
  });
  return { answer: model.answer, cited_ids: citedIds };
}

function toParseResult(model: ModelResult, timeZone: string): ParseResult {
  if (model.kind !== "reminder" || model.due_at === null) {
    return { ...model, due_at: null };
  }

  try {
    return { ...model, due_at: zonedLocalIsoToUnixSeconds(model.due_at, timeZone) };
  } catch {
    // An unconvertible instant (the clock-skip hour on the spring DST switch,
    // or a malformed date from the model) costs us the time, not the whole
    // classification: keep it a reminder the user can re-time by hand.
    return { ...model, due_at: null };
  }
}

async function handleParse(request: Request, env: Env): Promise<Response> {
  const guardResponse = await guardRequest(request, env);
  if (guardResponse !== null) {
    return guardResponse;
  }

  let rawBody: unknown;
  try {
    rawBody = await request.json();
  } catch {
    return jsonResponse(fallbackResult(""));
  }

  const fallbackText =
    isRecord(rawBody) && typeof rawBody.text === "string" ? rawBody.text : "";
  let input: ParseInput;
  try {
    input = parseInput(rawBody);
  } catch {
    return jsonResponse(fallbackResult(fallbackText));
  }

  try {
    if (
      env.DEEPSEEK_API_KEY === undefined ||
      env.DEEPSEEK_API_KEY.length === 0
    ) {
      throw new Error("DEEPSEEK_API_KEY is not configured");
    }
    const model = await parseWithDeepSeek(input, env.DEEPSEEK_API_KEY);
    return jsonResponse(toParseResult(model, input.tz));
  } catch {
    return jsonResponse(fallbackResult(input.text));
  }
}

async function handleRecall(request: Request, env: Env): Promise<Response> {
  const guardResponse = await guardRequest(request, env);
  if (guardResponse !== null) {
    return guardResponse;
  }

  let input: RecallInput;
  try {
    input = parseRecallInput(await request.json());
  } catch {
    return jsonResponse(FALLBACK_RECALL_RESULT);
  }

  if (input.memories.length === 0) {
    return jsonResponse(EMPTY_RECALL_RESULT);
  }

  try {
    if (
      env.DEEPSEEK_API_KEY === undefined ||
      env.DEEPSEEK_API_KEY.length === 0
    ) {
      throw new Error("DEEPSEEK_API_KEY is not configured");
    }
    const model = await recallWithDeepSeek(input, env.DEEPSEEK_API_KEY);
    return jsonResponse(toRecallResult(model, input));
  } catch {
    return jsonResponse(FALLBACK_RECALL_RESULT);
  }
}

export default {
  async fetch(
    request: Request,
    env: Env,
    _context: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "POST") {
      if (url.pathname === "/v1/parse") {
        return handleParse(request, env);
      }
      if (url.pathname === "/v1/recall") {
        return handleRecall(request, env);
      }
    }
    return jsonResponse({ error: "not found" }, 404);
  },
};
