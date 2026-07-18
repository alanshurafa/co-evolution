/**
 * Internal state model for a document-bounce run.
 *
 * This is the engine's in-memory representation of the on-disk `state.json`
 * that the document bouncers write (see `evals/BOUNCE-RUNNER-CONTRACT.md`,
 * schema family `bounce-state/1.x`). The serializer in `bounceState.ts` maps
 * this model back to a contract-conforming `state.json` losslessly.
 *
 * Naming: the internal concept `protocolOutcome` is the runtime's serialized
 * `convergence_status` field. This mapping is the Phase-0 RULING recorded in
 * `.planning/rebuild/TRACKER.md` — the runtime keeps `convergence_status`; the
 * contract-specific serializer owns the rename.
 */

/** Any JSON value. Used for the `passthrough` bags so we can round-trip source
 *  fields we do not model yet (forward-compat with bounce-state 1.1+). */
export type JsonValue =
  | string
  | number
  | boolean
  | null
  | JsonValue[]
  | { [key: string]: JsonValue };

/** The convergence outcome a `co-evolve-bouncer.sh` run records. Serialized as
 *  `convergence_status`. `null` means the runner did not record one (a legacy
 *  1.0 state or agent-bouncer) — treated as "unknown", never a failure. */
export type ProtocolOutcome = "converged" | "adjudicated" | "stuck";

/** One critique/compose pass. Mirrors a `state.json` `passes[]` entry. */
export interface PassRecord {
  readonly pass: number;
  readonly role: string;
  readonly agent: string;
  /** `output_raw` — raw agent output artifact (relative path). */
  readonly outputRaw: string;
  /** `output_clean` — HUMAN-SUMMARY-stripped artifact (relative path). */
  readonly outputClean: string;
  readonly contested: number;
  readonly clarify: number;
  /** `total_markers` — preserved verbatim from the source, NOT recomputed, so
   *  an inconsistent source value still round-trips byte-for-byte. */
  readonly totalMarkers: number;
  /** `word_count` — `wc -w` of the clean output. */
  readonly wordCount: number;
  /** Source pass keys we do not model, preserved verbatim for lossless
   *  serialization (forward-compat with 1.1+ pass-level additions). */
  readonly passthrough: Readonly<Record<string, JsonValue>>;
}

/** A whole bounce run. Mirrors the top level of `state.json`. */
export interface RunState {
  /** The exact `schema` string from the source (e.g. `"bounce-state/1.1"`).
   *  Preserved verbatim so it round-trips byte-identically; validated on parse
   *  to be within the accepted `bounce-state/1.x` family. */
  readonly schemaFamily: string;
  readonly runner: string;
  readonly mode: string;
  readonly task: string;
  /** `input_type` — `file | string | pipe`. */
  readonly inputType: string;
  /** `status` — lifecycle: `running | complete | aborted`. */
  readonly runStatus: string;
  /** `convergence_status` — convergence outcome, or `null`/absent when the
   *  runner did not record one. See {@link ProtocolOutcome}. */
  readonly protocolOutcome: ProtocolOutcome | null;
  readonly startedAt: string;
  readonly finishedAt: string | null;
  /** `baseline_file` — the mode-aware artifact the scorer diffs the final
   *  document against. */
  readonly baselineFile: string;
  readonly finalFile: string;
  readonly passes: readonly PassRecord[];
  /** Top-level source keys we do not model (e.g. `reviewer_persona`), preserved
   *  verbatim for lossless serialization. */
  readonly passthrough: Readonly<Record<string, JsonValue>>;
}

/** The three convergence outcomes the contract enumerates. */
export const PROTOCOL_OUTCOMES: readonly ProtocolOutcome[] = [
  "converged",
  "adjudicated",
  "stuck",
];
