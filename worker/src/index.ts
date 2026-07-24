import {
  fallbackResult,
  parseModelContent,
  type ModelResult,
  type ParseResult,
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

async function callDeepSeek(input: ParseInput, apiKey: string): Promise<ModelResult> {
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
          { role: "system", content: promptFor(input) },
          { role: "user", content: input.text },
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

    return parseModelContent(modelContent(await response.json()));
  } finally {
    clearTimeout(timeout);
  }
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
    const model = await callDeepSeek(input, env.DEEPSEEK_API_KEY);
    return jsonResponse(toParseResult(model, input.tz));
  } catch {
    return jsonResponse(fallbackResult(input.text));
  }
}

export default {
  async fetch(
    request: Request,
    env: Env,
    _context: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/v1/parse") {
      return jsonResponse({ error: "not found" }, 404);
    }
    return handleParse(request, env);
  },
};
