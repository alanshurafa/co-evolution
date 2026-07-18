import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  BounceStateError,
  familyCarriesConvergenceStatus,
  parseBounceState,
  serializeBounceState,
} from "../src/state/index.js";

const TEST_DIR = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(TEST_DIR, "fixtures", "state");

/** The real corpus fixture: a genuine `co-evolve-bouncer.sh` run (schema
 *  bounce-state/1.0, bounce-only, 2 passes). Provenance:
 *  co-evolve-tmp-codex-build-opus-plan-md-20260613-124738-cbf801. */
const REAL_1_0 = join(FIXTURES, "codex-build-opus-plan-1.0", "state.json");
/** Hand-authored bounce-state/1.1 with convergence_status + passthrough. */
const SYNTHETIC_1_1 = join(FIXTURES, "synthetic-1.1", "state.json");

function readJson(path: string): Record<string, unknown> {
  return JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
}

/** parse -> serialize -> parse, returning the re-parsed JSON for deep compare. */
function roundtrip(original: unknown): Record<string, unknown> {
  const state = parseBounceState(original);
  const out = serializeBounceState(state);
  expect(out.endsWith("\n"), "serialized output ends with a trailing newline").toBe(true);
  return JSON.parse(out) as Record<string, unknown>;
}

describe("bounce-state round-trip: real 1.0 corpus fixture", () => {
  const original = readJson(REAL_1_0);

  it("preserves every field (deep-equal as parsed JSON, key order free)", () => {
    const reparsed = roundtrip(original);
    expect(reparsed).toEqual(original);
  });

  it("preserves the exact schema string byte-for-byte", () => {
    const reparsed = roundtrip(original);
    expect(reparsed["schema"]).toBe(original["schema"]);
    expect(reparsed["schema"]).toBe("bounce-state/1.0");
  });

  it("keeps a 1.0 state keyless for convergence_status (family does not carry it)", () => {
    expect("convergence_status" in original).toBe(false);
    const reparsed = roundtrip(original);
    expect("convergence_status" in reparsed).toBe(false);
  });

  it("round-trips all pass records including counts and artifacts", () => {
    const reparsed = roundtrip(original);
    expect(reparsed["passes"]).toEqual(original["passes"]);
  });
});

describe("bounce-state round-trip: synthetic 1.1 fixture", () => {
  const original = readJson(SYNTHETIC_1_1);

  it("preserves every field, including passthrough (deep-equal)", () => {
    const reparsed = roundtrip(original);
    expect(reparsed).toEqual(original);
  });

  it("preserves schema and convergence_status byte-for-byte", () => {
    const reparsed = roundtrip(original);
    expect(reparsed["schema"]).toBe("bounce-state/1.1");
    expect(reparsed["convergence_status"]).toBe("adjudicated");
    expect(reparsed["convergence_status"]).toBe(original["convergence_status"]);
  });

  it("restores unmodeled top-level fields (reviewer_persona, forward-compat)", () => {
    const reparsed = roundtrip(original);
    expect(reparsed["reviewer_persona"]).toBe("adversarial");
    expect(reparsed["future_field_unmodeled"]).toEqual(original["future_field_unmodeled"]);
  });

  it("restores unmodeled pass-level fields (latency_ms) verbatim", () => {
    const original1_1 = readJson(SYNTHETIC_1_1);
    const passes = original1_1["passes"] as Array<Record<string, unknown>>;
    expect(passes[0]["latency_ms"]).toBe(41231);
    const reparsed = roundtrip(original1_1);
    const rtPasses = reparsed["passes"] as Array<Record<string, unknown>>;
    expect(rtPasses[0]["latency_ms"]).toBe(41231);
  });

  it("maps convergence_status <-> internal protocolOutcome", () => {
    const state = parseBounceState(original);
    expect(state.protocolOutcome).toBe("adjudicated");
    expect(state.schemaFamily).toBe("bounce-state/1.1");
  });
});

describe("bounce-state round-trip: convergence_status present-but-null (1.1)", () => {
  it("keeps an explicit null key (family carries the field)", () => {
    const base = readJson(SYNTHETIC_1_1);
    const withNull = { ...base, convergence_status: null };
    const reparsed = roundtrip(withNull);
    expect("convergence_status" in reparsed).toBe(true);
    expect(reparsed["convergence_status"]).toBeNull();
    expect(reparsed).toEqual(withNull);
  });
});

describe("familyCarriesConvergenceStatus", () => {
  it("1.0 does not carry, 1.1+ carries", () => {
    expect(familyCarriesConvergenceStatus("bounce-state/1.0")).toBe(false);
    expect(familyCarriesConvergenceStatus("bounce-state/1.1")).toBe(true);
    expect(familyCarriesConvergenceStatus("bounce-state/1.10")).toBe(true);
  });
});

describe("bounce-state validation (fail-early, field-path-qualified)", () => {
  const good = readJson(REAL_1_0);

  it("accepts a JSON string as well as a parsed object", () => {
    const asString = readFileSync(REAL_1_0, "utf8");
    const fromString = serializeBounceState(parseBounceState(asString));
    const fromObject = serializeBounceState(parseBounceState(good));
    expect(JSON.parse(fromString)).toEqual(JSON.parse(fromObject));
  });

  it("accepts any bounce-state/1.x schema (family, not exact match)", () => {
    const v1_5 = { ...good, schema: "bounce-state/1.5" };
    expect(() => parseBounceState(v1_5)).not.toThrow();
    expect(parseBounceState(v1_5).schemaFamily).toBe("bounce-state/1.5");
  });

  it("rejects a 2.x schema, naming the schema field", () => {
    const v2 = { ...good, schema: "bounce-state/2.0" };
    expect(() => parseBounceState(v2)).toThrow(BounceStateError);
    expect(() => parseBounceState(v2)).toThrow(/at schema:/);
  });

  it("rejects a malformed schema value", () => {
    expect(() => parseBounceState({ ...good, schema: "not-a-schema" })).toThrow(/at schema:/);
    expect(() => parseBounceState({ ...good, schema: 42 })).toThrow(/schema/);
  });

  it("rejects a missing required field, naming its path", () => {
    const noMode: Record<string, unknown> = { ...good };
    delete noMode["mode"];
    expect(() => parseBounceState(noMode)).toThrow(/\.mode:/);
  });

  it("rejects an out-of-enum convergence_status", () => {
    const bad = { ...good, schema: "bounce-state/1.1", convergence_status: "frobnicated" };
    expect(() => parseBounceState(bad)).toThrow(/convergence_status/);
  });

  it("rejects non-object and non-array-passes input", () => {
    expect(() => parseBounceState(null)).toThrow(/at \(root\):/);
    expect(() => parseBounceState("not json {")).toThrow(/invalid JSON/);
    expect(() => parseBounceState({ ...good, passes: {} })).toThrow(/at passes:/);
  });

  it("rejects a malformed pass entry, naming its index", () => {
    const badPass = { ...good, passes: [{ pass: 1, role: "reviewer" }] };
    expect(() => parseBounceState(badPass)).toThrow(/passes\[0\]/);
  });
});
