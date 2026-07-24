import { describe, expect, it } from "vitest";

import { zonedLocalIsoToUnixSeconds } from "../src/timezone";

describe("zonedLocalIsoToUnixSeconds", () => {
  it("converts Toronto winter local time using standard time", () => {
    expect(
      zonedLocalIsoToUnixSeconds(
        "2026-01-15T09:30:00",
        "America/Toronto",
      ),
    ).toBe(Date.UTC(2026, 0, 15, 14, 30, 0) / 1_000);
  });

  it("converts Toronto summer local time using daylight time", () => {
    expect(
      zonedLocalIsoToUnixSeconds(
        "2026-07-15T09:30:00",
        "America/Toronto",
      ),
    ).toBe(Date.UTC(2026, 6, 15, 13, 30, 0) / 1_000);
  });
});

describe("DST transition edges", () => {
  it("rejects the local hour that the spring switch skips", () => {
    expect(() =>
      zonedLocalIsoToUnixSeconds("2026-03-08T02:30:00", "America/Toronto"),
    ).toThrow();
  });

  it("resolves the repeated autumn hour to its first occurrence", () => {
    expect(
      zonedLocalIsoToUnixSeconds("2026-11-01T01:30:00", "America/Toronto"),
    ).toBe(Date.UTC(2026, 10, 1, 5, 30, 0) / 1_000);
  });
});
