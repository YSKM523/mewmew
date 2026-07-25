import { webcrypto } from "node:crypto";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import worker, { type Env } from "../src/index";

const VALID_INPUT = {
  text: "下周三下午三点提醒我交电费",
  tz: "America/Toronto",
  now: "2026-07-24T15:00:00",
};

const VALID_MODEL_RESULT = {
  kind: "reminder",
  title: "交电费",
  due_at: "2026-07-29T15:00:00",
  question: null,
  answer: null,
  confidence: 0.92,
};

const VALID_RECALL_INPUT = {
  question: "我把护照放哪了？",
  memories: [
    {
      id: "memory-1",
      kind: "note",
      title: "护照的位置",
      raw_text: "护照放在书房第二个抽屉里",
      created_at: 1_721_836_800,
    },
  ],
};

const VALID_RECALL_RESULT = {
  answer: "你把护照放在书房第二个抽屉里。",
  cited_ids: ["memory-1"],
};

const EXPECTED_SYSTEM_PROMPT = `你是记忆助手的分流器。把用户的一句话分类并结构化,只输出 JSON,不要解释。

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

当前时间: 2026-07-24T15:00:00,时区 America/Toronto`;

const EXPECTED_RECALL_SYSTEM_PROMPT = `你是记忆助手的召回答案器。只输出 JSON,不要解释。

只依据用户消息中给出的 memories 回答 question。没有足够依据时必须明确说不知道,严禁补充、猜测或编造任何记忆中没有的信息。
answer 最多两句话。
cited_ids 必须列出答案实际引用的 memory id,且只能使用输入 memories 中存在的 id;没有引用时返回空数组。

输出格式:
{"answer":"回答","cited_ids":["memory-id"]}`;

function request(token = "app-secret", input = VALID_INPUT): Request {
  return new Request("https://mewmew.example/v1/parse", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Mewmew-Token": token,
    },
    body: JSON.stringify(input),
  });
}

function recallRequest(
  token = "app-secret",
  input: unknown = VALID_RECALL_INPUT,
): Request {
  return new Request("https://mewmew.example/v1/recall", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Mewmew-Token": token,
    },
    body: JSON.stringify(input),
  });
}

function createKv(initialValue: string | null = null): {
  namespace: KVNamespace;
  get: ReturnType<typeof vi.fn>;
  put: ReturnType<typeof vi.fn>;
} {
  let value = initialValue;
  const get = vi.fn(async () => value);
  const put = vi.fn(async (_key: string, nextValue: string) => {
    value = nextValue;
  });

  return {
    namespace: { get, put } as unknown as KVNamespace,
    get,
    put,
  };
}

function createEnv(
  namespace: KVNamespace,
  overrides: Partial<Env> = {},
): Env {
  return {
    APP_TOKEN: "app-secret",
    DEEPSEEK_API_KEY: "deepseek-secret",
    RATE_LIMIT: namespace,
    ...overrides,
  };
}

function modelResponse(result: unknown = VALID_MODEL_RESULT): Response {
  return new Response(
    JSON.stringify({
      choices: [{ message: { content: JSON.stringify(result) } }],
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
}

async function dispatch(requestValue: Request, env: Env): Promise<Response> {
  return worker.fetch(requestValue, env, {} as ExecutionContext);
}

describe("POST /v1/parse", () => {
  beforeEach(() => {
    vi.stubGlobal("crypto", webcrypto);
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("returns 500 when APP_TOKEN is not configured", async () => {
    const kv = createKv();
    const response = await dispatch(
      request(),
      createEnv(kv.namespace, { APP_TOKEN: undefined }),
    );

    expect(response.status).toBe(500);
    expect(kv.get).not.toHaveBeenCalled();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("returns 401 before rate limiting when the token does not match", async () => {
    const kv = createKv();
    const response = await dispatch(request("wrong"), createEnv(kv.namespace));

    expect(response.status).toBe(401);
    expect(kv.get).not.toHaveBeenCalled();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("returns 429 before DeepSeek when the default daily quota is exhausted", async () => {
    const kv = createKv("200");
    const response = await dispatch(request(), createEnv(kv.namespace));

    expect(response.status).toBe(429);
    expect(kv.get).toHaveBeenCalledOnce();
    expect(kv.put).not.toHaveBeenCalled();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("increments KV then calls DeepSeek with the approved prompt and options", async () => {
    const kv = createKv("199");
    vi.mocked(fetch).mockResolvedValue(modelResponse());

    const response = await dispatch(request(), createEnv(kv.namespace));
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(kv.put).toHaveBeenCalledWith(
      expect.any(String),
      "200",
      expect.objectContaining({ expirationTtl: expect.any(Number) }),
    );
    expect(fetch).toHaveBeenCalledOnce();
    const [url, init] = vi.mocked(fetch).mock.calls[0];
    expect(url).toBe("https://api.deepseek.com/chat/completions");
    expect(init?.headers).toMatchObject({
      Authorization: "Bearer deepseek-secret",
      "Content-Type": "application/json",
    });
    const deepSeekBody = JSON.parse(String(init?.body));
    expect(deepSeekBody).toMatchObject({
      model: "deepseek-v4-flash",
      temperature: 0,
      response_format: { type: "json_object" },
      max_tokens: 2048,
    });
    expect(deepSeekBody.messages).toEqual([
      { role: "system", content: EXPECTED_SYSTEM_PROMPT },
      { role: "user", content: VALID_INPUT.text },
    ]);
    expect(body).toEqual({
      ...VALID_MODEL_RESULT,
      due_at: Date.UTC(2026, 6, 29, 19, 0, 0) / 1_000,
    });
  });

  it("keeps the reminder when its local time cannot exist in the timezone", async () => {
    const kv = createKv();
    // 02:30 on the spring-forward date never happens in Toronto.
    vi.mocked(fetch).mockResolvedValue(
      modelResponse({ ...VALID_MODEL_RESULT, due_at: "2026-03-08T02:30:00" }),
    );

    const response = await dispatch(request(), createEnv(kv.namespace));
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({ ...VALID_MODEL_RESULT, due_at: null });
  });

  it("returns a note with HTTP 200 when DeepSeek fails", async () => {
    const kv = createKv();
    vi.mocked(fetch).mockRejectedValue(new Error("network down"));

    const response = await dispatch(request(), createEnv(kv.namespace));

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      kind: "note",
      title: VALID_INPUT.text,
      due_at: null,
    });
  });

  it("returns a note with HTTP 200 for invalid model JSON", async () => {
    const kv = createKv();
    vi.mocked(fetch).mockResolvedValue(
      new Response(
        JSON.stringify({ choices: [{ message: { content: "not-json" } }] }),
      ),
    );

    const response = await dispatch(request(), createEnv(kv.namespace));

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      kind: "note",
      title: VALID_INPUT.text,
    });
  });

  it("returns a note with HTTP 200 for model schema errors", async () => {
    const kv = createKv();
    vi.mocked(fetch).mockResolvedValue(
      modelResponse({ ...VALID_MODEL_RESULT, kind: "event" }),
    );

    const response = await dispatch(request(), createEnv(kv.namespace));

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      kind: "note",
      title: VALID_INPUT.text,
    });
  });

  it("aborts DeepSeek after 8 seconds and returns a note with HTTP 200", async () => {
    vi.useFakeTimers();
    const kv = createKv();
    let resolveFetchStarted!: () => void;
    const fetchStarted = new Promise<void>((resolve) => {
      resolveFetchStarted = resolve;
    });
    vi.mocked(fetch).mockImplementation(
      (_url: string | URL | Request, init?: RequestInit) =>
        new Promise((_resolve, reject) => {
          resolveFetchStarted();
          init?.signal?.addEventListener("abort", () => {
            reject(new DOMException("Aborted", "AbortError"));
          });
        }),
    );

    const responsePromise = dispatch(request(), createEnv(kv.namespace));
    await fetchStarted;
    await vi.advanceTimersByTimeAsync(8_000);
    const response = await responsePromise;

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      kind: "note",
      title: VALID_INPUT.text,
    });
    const [, init] = vi.mocked(fetch).mock.calls[0];
    expect(init?.signal?.aborted).toBe(true);
  });
});

describe("POST /v1/recall", () => {
  beforeEach(() => {
    vi.stubGlobal("crypto", webcrypto);
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("returns a grounded answer and calls DeepSeek with recall settings", async () => {
    const kv = createKv("10");
    vi.mocked(fetch).mockResolvedValue(modelResponse(VALID_RECALL_RESULT));

    const response = await dispatch(
      recallRequest(),
      createEnv(kv.namespace),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(VALID_RECALL_RESULT);
    expect(kv.put).toHaveBeenCalledWith(
      expect.any(String),
      "11",
      expect.objectContaining({ expirationTtl: expect.any(Number) }),
    );
    expect(fetch).toHaveBeenCalledOnce();
    const [url, init] = vi.mocked(fetch).mock.calls[0];
    expect(url).toBe("https://api.deepseek.com/chat/completions");
    expect(init?.headers).toMatchObject({
      Authorization: "Bearer deepseek-secret",
      "Content-Type": "application/json",
    });
    expect(JSON.parse(String(init?.body))).toEqual({
      model: "deepseek-v4-flash",
      messages: [
        { role: "system", content: EXPECTED_RECALL_SYSTEM_PROMPT },
        { role: "user", content: JSON.stringify(VALID_RECALL_INPUT) },
      ],
      temperature: 0,
      response_format: { type: "json_object" },
      max_tokens: 2048,
    });
  });

  it("answers locally without DeepSeek when no memories matched", async () => {
    const kv = createKv();

    const response = await dispatch(
      recallRequest("app-secret", {
        question: "我把雨伞放哪了？",
        memories: [],
      }),
      createEnv(kv.namespace),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      answer: "我没记过这个",
      cited_ids: [],
    });
    expect(kv.put).toHaveBeenCalledOnce();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("returns the explicit HTTP 200 fallback when DeepSeek fails", async () => {
    const kv = createKv();
    vi.mocked(fetch).mockRejectedValue(new Error("network down"));

    const response = await dispatch(
      recallRequest(),
      createEnv(kv.namespace),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      answer: "猫有点困,先看看这些记忆吧",
      cited_ids: [],
    });
  });

  it("filters forged and duplicate cited ids from the model response", async () => {
    const kv = createKv();
    vi.mocked(fetch).mockResolvedValue(
      modelResponse({
        ...VALID_RECALL_RESULT,
        cited_ids: ["memory-1", "forged-id", "memory-1"],
      }),
    );

    const response = await dispatch(
      recallRequest(),
      createEnv(kv.namespace),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(VALID_RECALL_RESULT);
  });

  it("reuses authentication before quota and DeepSeek", async () => {
    const kv = createKv();

    const response = await dispatch(
      recallRequest("wrong"),
      createEnv(kv.namespace),
    );

    expect(response.status).toBe(401);
    expect(kv.get).not.toHaveBeenCalled();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("reuses the shared daily quota before DeepSeek", async () => {
    const kv = createKv("200");

    const response = await dispatch(
      recallRequest(),
      createEnv(kv.namespace),
    );

    expect(response.status).toBe(429);
    expect(kv.get).toHaveBeenCalledOnce();
    expect(kv.put).not.toHaveBeenCalled();
    expect(fetch).not.toHaveBeenCalled();
  });
});
