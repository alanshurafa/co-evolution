/**
 * Adapter result + call contract for cross-AI CLI invocations.
 *
 * The result is a discriminated union that mirrors the outcome ladder ported
 * from the Bash runtime's `validate_agent_artifact` (lib/co-evolution.sh):
 *   - `artifact` — the CLI produced a usable document.
 *   - `empty`    — the CLI produced nothing and gave no fatal signature; the
 *                  CALLER may retry once (retry lives outside the adapter).
 *   - `fatal`    — retrying cannot help. `reason` distinguishes the cause so
 *                  callers can surface the right operator message.
 */

export type FatalReason = "auth" | "missing-cli" | "timeout" | "spawn";

export interface ArtifactResult {
  readonly kind: "artifact";
  /** Raw stdout of the CLI (the document). */
  readonly text: string;
  /** Tail of stderr, retained for diagnostics even on success. */
  readonly stderrTail: string;
}

export interface EmptyResult {
  readonly kind: "empty";
  readonly stderrTail: string;
}

export interface FatalResult {
  readonly kind: "fatal";
  readonly reason: FatalReason;
  /** Human-readable cause, safe to log. */
  readonly detail: string;
  readonly stderrTail: string;
}

export type AdapterResult = ArtifactResult | EmptyResult | FatalResult;

export interface AdapterCallOptions {
  /** Model id passed through to `--model`. */
  readonly model: string;
  /** Prompt fed to the CLI on stdin. */
  readonly promptText: string;
  /** Hard deadline in milliseconds. Defaults to {@link DEFAULT_TIMEOUT_MS}. */
  readonly timeoutMs?: number;
  /** Binary to spawn. Defaults to {@link DEFAULT_BIN_PATH} (`"claude"`). */
  readonly binPath?: string;
  /** Optional reasoning effort passed through to `--effort` when set. */
  readonly effort?: string;
  /**
   * Internal test seam (NOT part of the public call contract): arguments
   * inserted between the binary and the generated CLI flags. Hermetic tests
   * set `binPath` to `process.execPath` and `binPrefixArgs` to `[stubScript]`
   * so a Node stub runs cross-platform with no `.cmd`/`.ps1` shim. Empty on the
   * production path, which keeps the spawned argv byte-identical to the Bash
   * runtime.
   */
  readonly binPrefixArgs?: readonly string[];
}

/** 30 minutes — matches the Bash runtime's long-form invocation budget. */
export const DEFAULT_TIMEOUT_MS = 1_800_000;

/** Default CLI binary name; resolved on PATH by the OS. */
export const DEFAULT_BIN_PATH = "claude";
