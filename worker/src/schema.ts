export type MemoryKind = "reminder" | "card" | "note";

export interface ModelResult {
  kind: MemoryKind;
  title: string;
  due_at: string | null;
  question: string | null;
  answer: string | null;
  confidence: number;
}

export interface ParseResult {
  kind: MemoryKind;
  title: string;
  due_at: number | null;
  question: string | null;
  answer: string | null;
  confidence: number;
}

export interface RecallModelResult {
  answer: string;
  cited_ids: string[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nullableString(
  value: unknown,
  field: string,
): string | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value !== "string") {
    throw new Error(`${field} must be a string or null`);
  }
  return value;
}

function firstCharacters(value: string, count: number): string {
  return Array.from(value).slice(0, count).join("");
}

export function fallbackResult(text: string): ParseResult {
  return {
    kind: "note",
    title: firstCharacters(text, 20),
    due_at: null,
    question: null,
    answer: null,
    confidence: 0,
  };
}

export function parseModelContent(content: string): ModelResult {
  const value: unknown = JSON.parse(content);
  if (!isRecord(value)) {
    throw new Error("model content must be a JSON object");
  }

  if (
    value.kind !== "reminder" &&
    value.kind !== "card" &&
    value.kind !== "note"
  ) {
    throw new Error("kind is invalid");
  }
  if (
    typeof value.title !== "string" ||
    value.title.length === 0 ||
    Array.from(value.title).length > 20
  ) {
    throw new Error("title is missing or longer than 20 characters");
  }
  if (
    typeof value.confidence !== "number" ||
    !Number.isFinite(value.confidence) ||
    value.confidence < 0 ||
    value.confidence > 1
  ) {
    throw new Error("confidence must be between 0 and 1");
  }

  const dueAt = nullableString(value.due_at, "due_at");
  const question = nullableString(value.question, "question");
  const answer = nullableString(value.answer, "answer");

  return {
    kind: value.kind,
    title: value.title,
    due_at: value.kind === "reminder" ? dueAt : null,
    question: value.kind === "card" ? question : null,
    answer: value.kind === "card" ? answer : null,
    confidence: value.confidence,
  };
}

export function parseRecallModelContent(content: string): RecallModelResult {
  const value: unknown = JSON.parse(content);
  if (!isRecord(value)) {
    throw new Error("recall model content must be a JSON object");
  }
  if (typeof value.answer !== "string" || value.answer.length === 0) {
    throw new Error("recall answer must be a non-empty string");
  }
  if (
    !Array.isArray(value.cited_ids) ||
    !value.cited_ids.every((id) => typeof id === "string")
  ) {
    throw new Error("recall cited_ids must be an array of strings");
  }

  return {
    answer: value.answer,
    cited_ids: value.cited_ids,
  };
}
