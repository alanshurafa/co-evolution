/**
 * Parser + serializer between the on-disk `state.json` (schema family
 * `bounce-state/1.x`, see `evals/BOUNCE-RUNNER-CONTRACT.md`) and the engine's
 * internal {@link RunState} model.
 *
 * Invariants:
 *  - Round-tripping is lossless: `parse` then `serialize` reproduces every
 *    source field (deep-equal as parsed JSON), including fields we do not model
 *    (kept in `passthrough` bags) and the exact `schema` string.
 *  - The internal `protocolOutcome` is written back as `convergence_status`,
 *    emitted only when the source schema family carries the field (1.1+) or the
 *    value is non-null — so a 1.0 state (no key) stays keyless and a 1.1 state
 *    (key present, possibly null) keeps its key.
 *  - Validation fails early and loud: every rejection names the offending field
 *    path (house rule — no silent coercion of malformed input).
 */

import type {
  JsonValue,
  PassRecord,
  ProtocolOutcome,
  RunState,
} from "./model.js";
import { PROTOCOL_OUTCOMES } from "./model.js";

/** Thrown by {@link parseBounceState} with a field-path-qualified message. */
export class BounceStateError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BounceStateError";
  }
}

/** Accept the whole `bounce-state/1.x` family; reject 2.x and malformed
 *  values. Stricter than the contract's minimum consumer check
 *  (`^bounce-state/1\.`): the minor must be numeric and terminal, so a
 *  corrupted value like `bounce-state/1.xyz` fails loud here instead of
 *  round-tripping silently. One regex serves validation and
 *  familyCarriesConvergenceStatus so the two can never drift. */
const SCHEMA_FAMILY_RE = /^bounce-state\/1\.(\d+)$/;

/** Source top-level keys the model owns; everything else is passthrough. */
const MODELED_TOP_KEYS = new Set([
  "schema",
  "runner",
  "mode",
  "task",
  "input_type",
  "baseline_file",
  "final_file",
  "status",
  "convergence_status",
  "started_at",
  "finished_at",
  "passes",
]);

/** Source pass keys the model owns; everything else is passthrough. */
const MODELED_PASS_KEYS = new Set([
  "pass",
  "role",
  "agent",
  "output_raw",
  "output_clean",
  "contested",
  "clarify",
  "total_markers",
  "word_count",
]);

// ---------------------------------------------------------------------------
// Validation helpers (fail-early, field-path-qualified)
// ---------------------------------------------------------------------------

function fail(path: string, reason: string): never {
  throw new BounceStateError(`bounce-state at ${path}: ${reason}`);
}

function typeName(v: unknown): string {
  if (v === null) return "null";
  if (Array.isArray(v)) return "array";
  return typeof v;
}

function asObject(v: unknown, path: string): Record<string, unknown> {
  if (typeof v !== "object" || v === null || Array.isArray(v)) {
    fail(path, `expected object, got ${typeName(v)}`);
  }
  return v as Record<string, unknown>;
}

function reqString(o: Record<string, unknown>, key: string, path: string): string {
  const v = o[key];
  if (typeof v !== "string") fail(`${path}.${key}`, `expected string, got ${typeName(v)}`);
  return v;
}

function reqNumber(o: Record<string, unknown>, key: string, path: string): number {
  const v = o[key];
  if (typeof v !== "number" || !Number.isFinite(v)) {
    fail(`${path}.${key}`, `expected finite number, got ${typeName(v)}`);
  }
  return v;
}

function reqStringOrNull(
  o: Record<string, unknown>,
  key: string,
  path: string,
): string | null {
  const v = o[key];
  if (v === null) return null;
  if (typeof v !== "string") fail(`${path}.${key}`, `expected string or null, got ${typeName(v)}`);
  return v;
}

/** Collect source keys not in `modeled` as a passthrough bag. Values are JSON
 *  by construction (they came from JSON.parse or a JSON-shaped object). */
function collectPassthrough(
  o: Record<string, unknown>,
  modeled: Set<string>,
): Record<string, JsonValue> {
  const bag: Record<string, JsonValue> = {};
  for (const key of Object.keys(o)) {
    if (!modeled.has(key)) bag[key] = o[key] as JsonValue;
  }
  return bag;
}

function parseProtocolOutcome(
  o: Record<string, unknown>,
  path: string,
): ProtocolOutcome | null {
  if (!("convergence_status" in o)) return null;
  const v = o["convergence_status"];
  if (v === null) return null;
  if (typeof v !== "string") {
    fail(`${path}.convergence_status`, `expected string or null, got ${typeName(v)}`);
  }
  if (!PROTOCOL_OUTCOMES.includes(v as ProtocolOutcome)) {
    fail(
      `${path}.convergence_status`,
      `expected one of ${PROTOCOL_OUTCOMES.map((s) => JSON.stringify(s)).join(", ")} or null, got ${JSON.stringify(v)}`,
    );
  }
  return v as ProtocolOutcome;
}

function parsePass(v: unknown, path: string): PassRecord {
  const o = asObject(v, path);
  return {
    pass: reqNumber(o, "pass", path),
    role: reqString(o, "role", path),
    agent: reqString(o, "agent", path),
    outputRaw: reqString(o, "output_raw", path),
    outputClean: reqString(o, "output_clean", path),
    contested: reqNumber(o, "contested", path),
    clarify: reqNumber(o, "clarify", path),
    totalMarkers: reqNumber(o, "total_markers", path),
    wordCount: reqNumber(o, "word_count", path),
    passthrough: collectPassthrough(o, MODELED_PASS_KEYS),
  };
}

// ---------------------------------------------------------------------------
// Parse
// ---------------------------------------------------------------------------

/**
 * Parse a `bounce-state/1.x` `state.json` into the internal {@link RunState}.
 *
 * @param input a parsed JSON object, or a JSON string (parsed here).
 * @throws {BounceStateError} with a field-path-qualified message on any
 *   malformed or out-of-family input.
 */
export function parseBounceState(input: unknown): RunState {
  let raw: unknown = input;
  if (typeof input === "string") {
    try {
      raw = JSON.parse(input);
    } catch (e) {
      fail("(root)", `invalid JSON: ${(e as Error).message}`);
    }
  }
  const o = asObject(raw, "(root)");

  const schema = reqString(o, "schema", "(root)");
  if (!SCHEMA_FAMILY_RE.test(schema)) {
    fail("schema", `expected a "bounce-state/1.x" value, got ${JSON.stringify(schema)}`);
  }

  const passesRaw = o["passes"];
  if (!Array.isArray(passesRaw)) {
    fail("passes", `expected array, got ${typeName(passesRaw)}`);
  }
  const passes = passesRaw.map((p, i) => parsePass(p, `passes[${i}]`));

  return {
    schemaFamily: schema,
    runner: reqString(o, "runner", "(root)"),
    mode: reqString(o, "mode", "(root)"),
    task: reqString(o, "task", "(root)"),
    inputType: reqString(o, "input_type", "(root)"),
    runStatus: reqString(o, "status", "(root)"),
    protocolOutcome: parseProtocolOutcome(o, "(root)"),
    startedAt: reqString(o, "started_at", "(root)"),
    finishedAt: reqStringOrNull(o, "finished_at", "(root)"),
    baselineFile: reqString(o, "baseline_file", "(root)"),
    finalFile: reqString(o, "final_file", "(root)"),
    passes,
    passthrough: collectPassthrough(o, MODELED_TOP_KEYS),
  };
}

// ---------------------------------------------------------------------------
// Serialize
// ---------------------------------------------------------------------------

/** Does the schema family carry `convergence_status`? Additive since 1.1, so
 *  minor >= 1 carries it; 1.0 does not. Mirrors the contract's version history. */
export function familyCarriesConvergenceStatus(schema: string): boolean {
  const m = SCHEMA_FAMILY_RE.exec(schema);
  return m !== null && Number(m[1]) >= 1;
}

function serializePass(p: PassRecord): Record<string, JsonValue> {
  const obj: Record<string, JsonValue> = {
    pass: p.pass,
    role: p.role,
    agent: p.agent,
    output_raw: p.outputRaw,
    output_clean: p.outputClean,
    contested: p.contested,
    clarify: p.clarify,
    total_markers: p.totalMarkers,
    word_count: p.wordCount,
  };
  // Restore unmodeled pass keys. Disjoint from the modeled set by construction,
  // so this never clobbers a field above.
  return Object.assign(obj, p.passthrough);
}

/**
 * Serialize a {@link RunState} back to a contract-conforming `state.json`
 * string (2-space indent, trailing newline).
 *
 * `convergence_status` is emitted when the schema family carries it (1.1+) or
 * the outcome is non-null, and omitted otherwise — so a parsed 1.0 state stays
 * keyless and a 1.1 state keeps its key (value or explicit null). All
 * passthrough fields are restored verbatim.
 */
export function serializeBounceState(state: RunState): string {
  const obj: Record<string, JsonValue> = {
    schema: state.schemaFamily,
    runner: state.runner,
    mode: state.mode,
    task: state.task,
    input_type: state.inputType,
    baseline_file: state.baselineFile,
    final_file: state.finalFile,
    status: state.runStatus,
  };

  if (familyCarriesConvergenceStatus(state.schemaFamily) || state.protocolOutcome !== null) {
    obj["convergence_status"] = state.protocolOutcome;
  }

  obj["started_at"] = state.startedAt;
  obj["finished_at"] = state.finishedAt;
  obj["passes"] = state.passes.map(serializePass);

  // Restore unmodeled top-level keys (e.g. reviewer_persona). Disjoint from the
  // modeled keys above by construction.
  Object.assign(obj, state.passthrough);

  return JSON.stringify(obj, null, 2) + "\n";
}
