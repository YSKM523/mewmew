import { describe, expect, it } from "vitest";

import { fallbackResult, parseModelContent } from "../src/schema";

describe("schema and fallback", () => {
  it("falls back to a note with the first 20 characters", () => {
    expect(fallbackResult("一二三四五六七八九十一二三四五六七八九十尾巴")).toEqual({
      kind: "note",
      title: "一二三四五六七八九十一二三四五六七八九十",
      due_at: null,
      question: null,
      answer: null,
      confidence: 0,
    });
  });

  it("rejects malformed JSON", () => {
    expect(() => parseModelContent("{")).toThrow();
  });

  it("rejects an unknown kind", () => {
    expect(() =>
      parseModelContent(
        JSON.stringify({
          kind: "event",
          title: "交电费",
          due_at: null,
          question: null,
          answer: null,
          confidence: 0.9,
        }),
      ),
    ).toThrow();
  });

  it("rejects a missing title", () => {
    expect(() =>
      parseModelContent(
        JSON.stringify({
          kind: "note",
          due_at: null,
          question: null,
          answer: null,
          confidence: 0.9,
        }),
      ),
    ).toThrow();
  });
});
