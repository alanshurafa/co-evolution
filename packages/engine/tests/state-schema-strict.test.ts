import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { BounceStateError, parseBounceState } from "../src/state/index.js";

const base = JSON.parse(
  readFileSync(
    new URL("./fixtures/state/codex-build-opus-plan-1.0/state.json", import.meta.url),
    "utf8",
  ),
) as Record<string, unknown>;

describe("schema family strictness", () => {
  it.each(["bounce-state/1.xyz", "bounce-state/1.", "bounce-state/1.0-beta", "bounce-state/2.0"])(
    "rejects malformed or out-of-family schema %s instead of coercing silently",
    (schema) => {
      expect(() => parseBounceState({ ...base, schema })).toThrow(BounceStateError);
    },
  );

  it("accepts future numeric minors in the 1.x family", () => {
    expect(() => parseBounceState({ ...base, schema: "bounce-state/1.7" })).not.toThrow();
  });
});
