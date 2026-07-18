/**
 * Read-only `claude` CLI adapter.
 *
 * Ports the read-phase behavior of `invoke_claude` +
 * `validate_agent_artifact` / `file_contains_auth_failure` from
 * lib/co-evolution.sh into a typed, hermetically testable function.
 *
 * Deliberate scope choices vs. the Bash source (reported, not accidental):
 *   - Only the READ (non-writable) tool profile is ported. The write-phase
 *     permission set (`--permission-mode bypassPermissions` + allow-list +
 *     `--add-dir`) is a later work package.
 *   - The output-path auth ladder ports CURRENT master semantics
 *     (`output_is_auth_failure`, A-2 + C-8): an anchored head-scan over the
 *     first 20 non-empty, non-code lines catches long auth-error pages, and
 *     the loose regex under the <50-word ceiling still catches a bare banner
 *     the anchor deliberately excludes.
 *   - Caller contract (Phase 1 turn layer, NOT this adapter): retry-once on
 *     `empty`, and `validate_output`-style size/structure sanity checks — an
 *     `artifact` here means "the CLI produced a document", not "the document
 *     is adequate".
 *   - The Bash "command not found in stderr → fatal" branch is subsumed by the
 *     spawn ENOENT path: Node surfaces a missing binary directly as an `error`
 *     event with `code === "ENOENT"`, so no stderr text-scan is needed.
 *   - Token-capture JSON mode and the WSL `cmd.exe` bridge are out of scope.
 */

import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { killWindowsProcessTree } from "../proc/deadline.js";
import { findCmdUnsafeArg, resolveSpawn } from "./resolveBin.js";
import {
  DEFAULT_BIN_PATH,
  DEFAULT_TIMEOUT_MS,
  type AdapterCallOptions,
  type AdapterResult,
} from "./types.js";

/**
 * Read-phase tool restriction, verbatim from lib/co-evolution.sh:435.
 * Text phases run with tools disabled so `claude -p` cannot edit the repo.
 */
export const DISALLOWED_TOOLS = "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch";

/**
 * RNPT-06: the six harness env vars stripped before exec'ing `claude`.
 *
 * Authoritative list from lib/co-evolution.sh:460-467 (the "salvageable lib
 * fix" living in the main checkout's working tree). When this code runs inside
 * a live Claude Code session these are inherited, and `claude -p` would launch
 * a NEW interactive session instead of answering — blocking on stdin with zero
 * output until killed. Keep the list narrow; removing more risks disabling auth.
 */
export const HARNESS_ENV_VARS = [
  "CLAUDECODE",
  "CLAUDE_CODE_EFFORT_LEVEL",
  "CLAUDE_CODE_ENTRYPOINT",
  "CLAUDE_CODE_EXECPATH",
  "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST",
  "CLAUDE_CODE_OAUTH_TOKEN",
] as const;

/**
 * Auth-failure matcher, ported verbatim from `file_contains_auth_failure`
 * (lib/co-evolution.sh:594) — `grep -qiE`, hence the `i` flag. `.` does not
 * cross newlines here, matching grep's line-oriented `Please run .* login`.
 */
export const AUTH_FAILURE_REGEX =
  /Failed to authenticate|authentication_error|Not authenticated|Not logged in|Unauthorized|login required|Please run .* login|Please run \/login/i;

/**
 * A-2: anchored auth-banner matcher for the head-scan. A genuine CLI auth
 * failure prints a short banner that STANDS ALONE at the start of a line
 * before any work is done; leading whitespace/quote/bullet punctuation is
 * tolerated. Ported from `output_contains_auth_banner`
 * (lib/co-evolution.sh:616-646). Deliberately excludes a bare
 * "Unauthorized"/"Not authenticated" — those are prose tokens far more often
 * than banners; the loose matcher plus word ceiling still covers them (C-8).
 */
const AUTH_BANNER_REGEX =
  /^[\s\p{P}\p{S}]*(Not logged in|You are not logged in|Please run \S*login|Please sign in|Please log ?in|Login required|Authentication failed|Failed to authenticate|authentication_error|Your organization does not have access|Invalid API key|Session (has )?expired)/iu;

/** Shells' missing-binary signatures on stderr. The cmd.exe bridge spawns
 * successfully even when the resolved shim is broken, so Node-level ENOENT
 * never fires on that path — this text is the only signal. */
const COMMAND_NOT_FOUND_REGEX =
  /command not found|No such file or directory|is not recognized as an internal or external command/i;

/** Head-scan window: only this many non-empty lines are banner-eligible. */
const AUTH_BANNER_WINDOW = 20;

/**
 * A-2 head-scan, ported from `output_contains_auth_banner`. Scans the first
 * 20 non-empty lines; skips ``` fenced regions (the fence line toggles state
 * and is never matched), 4-space/tab indented code, and `>` blockquotes — a
 * document ABOUT auth handling legitimately quotes banners in those contexts,
 * while a real banner prints at column 0 outside any code context.
 */
export function outputContainsAuthBanner(text: string): boolean {
  let nonempty = 0;
  let inFence = false;
  for (const line of text.split(/\r?\n/)) {
    if (/^\s*$/.test(line)) continue; // blank: not counted
    nonempty += 1;
    if (nonempty > AUTH_BANNER_WINDOW) break; // window exhausted
    if (/^\s*```/.test(line)) {
      inFence = !inFence; // fence marker: counted, never matched
      continue;
    }
    if (inFence) continue; // inside ``` fence
    if (line.startsWith("    ") || line.startsWith("\t")) continue; // indented code
    if (/^\s*>/.test(line)) continue; // blockquote
    if (AUTH_BANNER_REGEX.test(line)) return true;
  }
  return false;
}

/** Retain at most this many trailing chars of stderr on the result. */
const STDERR_TAIL_CHARS = 2000;

/** The deb4669 ceiling: only a short output can be an auth banner. */
const AUTH_WORD_CEILING = 50;

/**
 * Build the exact argv for a read-phase invocation.
 *
 * PRTP-03: passing ANY schema flag (`--output-schema`) hangs `claude -p` in
 * headless mode on Windows. This builder has no code path that can emit one —
 * the only output flag is `--output-format text`. The PRTP-03 unit test asserts
 * that invariant across every option combination. Do not add a schema flag here.
 *
 * Order mirrors lib/co-evolution.sh: `-p --output-format text --model <m>
 * [--effort <e>] --disallowedTools <list>`.
 */
export function buildClaudeReadArgs(opts: AdapterCallOptions): string[] {
  const args = ["-p", "--output-format", "text", "--model", opts.model];
  if (opts.effort) {
    args.push("--effort", opts.effort);
  }
  args.push("--disallowedTools", DISALLOWED_TOOLS);
  return args;
}

/** Copy the parent env and strip the RNPT-06 harness vars. */
function buildChildEnv(): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = { ...process.env };
  for (const key of HARNESS_ENV_VARS) {
    delete env[key];
  }
  return env;
}

function tailChars(text: string, limit: number): string {
  return text.length <= limit ? text : text.slice(text.length - limit);
}

/** Whitespace-delimited word count, matching `wc -w`. */
function wordCount(text: string): number {
  const trimmed = text.trim();
  return trimmed === "" ? 0 : trimmed.split(/\s+/).length;
}

/**
 * Pure outcome classifier — the ported Bash ladder. Takes the full stdout and
 * full stderr; computes the retained stderr tail for the result.
 */
export function classifyClaudeOutput(
  stdout: string,
  stderr: string,
): AdapterResult {
  const stderrTail = tailChars(stderr, STDERR_TAIL_CHARS);

  if (stdout.length > 0) {
    // Non-empty output — `output_is_auth_failure` (A-2 + C-8): the anchored
    // head-scan catches a long auth-error page, and the loose matcher under
    // the <50-word ceiling still catches a bare banner the anchor excludes. A
    // long document that merely mentions auth mid-body passes both (deb4669
    // false-positive guard).
    if (outputContainsAuthBanner(stdout)) {
      return {
        kind: "fatal",
        reason: "auth",
        detail: "authentication banner in output head (A-2 anchored scan)",
        stderrTail,
      };
    }
    if (wordCount(stdout) < AUTH_WORD_CEILING && AUTH_FAILURE_REGEX.test(stdout)) {
      return {
        kind: "fatal",
        reason: "auth",
        detail: "authentication failure banner in output (under 50 words)",
        stderrTail,
      };
    }
    return { kind: "artifact", text: stdout, stderrTail };
  }

  // Empty output — check stderr for a fatal cause before the caller burns a
  // retry on a CLI that is not installed (the cmd.exe bridge spawns fine even
  // when the shim is broken) or not logged in. Order mirrors
  // validate_agent_artifact: missing-CLI first, then auth.
  if (stderr.length > 0 && COMMAND_NOT_FOUND_REGEX.test(stderr)) {
    return {
      kind: "fatal",
      reason: "missing-cli",
      detail: "shell reported the CLI missing (empty output)",
      stderrTail,
    };
  }
  if (stderr.length > 0 && AUTH_FAILURE_REGEX.test(stderr)) {
    return {
      kind: "fatal",
      reason: "auth",
      detail: "authentication failure in stderr with empty output",
      stderrTail,
    };
  }

  return { kind: "empty", stderrTail };
}

/**
 * Invoke `claude` in read-only mode and classify the outcome.
 *
 * Spawns with an argv ARRAY and never `shell: true` (avoids shell-metacharacter
 * injection from prompt/model). The prompt is written to stdin. On the deadline
 * the child is signalled and the call resolves `fatal/timeout`.
 */
export function invokeClaudeRead(
  opts: AdapterCallOptions,
): Promise<AdapterResult> {
  const binPath = opts.binPath ?? DEFAULT_BIN_PATH;
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  // Validate at the boundary so misuse fails loudly instead of arming a
  // zero-delay timer that masquerades as a real timeout (mirrors
  // runWithDeadline's guard).
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    throw new TypeError(`timeoutMs must be a positive finite number, got ${String(timeoutMs)}`);
  }
  const args = [...(opts.binPrefixArgs ?? []), ...buildClaudeReadArgs(opts)];
  const env = buildChildEnv();

  return new Promise<AdapterResult>((resolve) => {
    let settled = false;
    let timedOut = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];

    const finish = (result: AdapterResult): void => {
      if (settled) {
        return;
      }
      settled = true;
      if (timer) {
        clearTimeout(timer);
      }
      resolve(result);
    };

    const currentStderrTail = (): string =>
      tailChars(Buffer.concat(stderrChunks).toString("utf8"), STDERR_TAIL_CHARS);

    // Windows: `claude` is usually a .cmd shim, which bare spawn cannot
    // execute (ENOENT on the name; EINVAL on the file since CVE-2024-27980).
    // Resolve it and, for batch shims, bridge through cmd.exe — guarded, since
    // cmd.exe re-parses its command line (the prompt itself rides stdin and is
    // never exposed to this).
    const resolved = resolveSpawn(binPath);
    let spawnFile = resolved.file;
    let spawnArgs = args;
    if (resolved.argsPrefix.length > 0) {
      const unsafe = findCmdUnsafeArg(args);
      if (unsafe !== undefined) {
        finish({
          kind: "fatal",
          reason: "spawn",
          detail: `refusing cmd.exe passthrough: unsafe argument ${JSON.stringify(unsafe)}`,
          stderrTail: "",
        });
        return;
      }
      spawnArgs = [...resolved.argsPrefix, ...args];
    }

    let child: ChildProcessWithoutNullStreams;
    try {
      child = spawn(spawnFile, spawnArgs, { env, stdio: "pipe" });
    } catch (err) {
      const e = err as NodeJS.ErrnoException;
      finish(
        e.code === "ENOENT"
          ? {
              kind: "fatal",
              reason: "missing-cli",
              detail: `claude CLI not found (ENOENT): ${binPath}`,
              stderrTail: "",
            }
          : {
              kind: "fatal",
              reason: "spawn",
              detail: `failed to spawn claude (${e.code ?? "unknown"}): ${e.message}`,
              stderrTail: "",
            },
      );
      return;
    }

    timer = setTimeout(() => {
      timedOut = true;
      // Windows: the direct child is usually the cmd.exe bridge and the real
      // CLI is its grandchild — bare child.kill() would leak it, so reap the
      // whole tree with the proven proc helper. POSIX: claude runs as this
      // single non-detached child (no bridge), so a direct kill is the
      // correctly-scoped action. Unifying both paths under one managed-spawn
      // primitive (resolve + env hygiene + capture + deadline + tree-kill) is
      // the first Phase 1 work item.
      const pid = child.pid;
      if (process.platform === "win32" && pid !== undefined) {
        void killWindowsProcessTree(pid).then((errText) => {
          if (errText !== undefined) {
            try {
              child.kill();
            } catch {
              /* already dead */
            }
          }
        });
      } else {
        child.kill();
      }
    }, timeoutMs);

    child.on("error", (err: Error) => {
      const e = err as NodeJS.ErrnoException;
      finish(
        e.code === "ENOENT"
          ? {
              kind: "fatal",
              reason: "missing-cli",
              detail: `claude CLI not found (ENOENT): ${binPath}`,
              stderrTail: currentStderrTail(),
            }
          : {
              kind: "fatal",
              reason: "spawn",
              detail: `failed to spawn claude (${e.code ?? "unknown"}): ${e.message}`,
              stderrTail: currentStderrTail(),
            },
      );
    });

    child.stdout.on("data", (chunk: Buffer) => stdoutChunks.push(chunk));
    child.stderr.on("data", (chunk: Buffer) => stderrChunks.push(chunk));

    child.on("close", () => {
      if (settled) {
        return;
      }
      const stdout = Buffer.concat(stdoutChunks).toString("utf8");
      const stderr = Buffer.concat(stderrChunks).toString("utf8");
      if (timedOut) {
        finish({
          kind: "fatal",
          reason: "timeout",
          detail: `timed out after ${timeoutMs}ms`,
          stderrTail: tailChars(stderr, STDERR_TAIL_CHARS),
        });
        return;
      }
      finish(classifyClaudeOutput(stdout, stderr));
    });

    // Feed the prompt on stdin, then close it. If the child already exited
    // (e.g. a failed spawn), the write raises EPIPE — swallow it; the outcome
    // is decided by the error/close handlers above.
    child.stdin.on("error", () => {
      /* ignore EPIPE from an early-exiting child */
    });
    try {
      child.stdin.write(opts.promptText);
      child.stdin.end();
    } catch {
      /* ignore synchronous stdin failure on an already-dead child */
    }
  });
}
