/**
 * runWithDeadline -- spawn a child under a hard wall-clock ceiling and, when the
 * ceiling is hit, kill the ENTIRE descendant tree (not just the direct child).
 *
 * The tree-kill strategy is OS-conditional but lives entirely behind this one
 * public API so callers -- and tests -- stay platform-agnostic:
 *
 *   Windows: `taskkill /PID <pid> /T /F` walks the process tree and force-kills
 *            every descendant. Node's own `child.kill()` reaps only the direct
 *            child and would orphan grandchildren.
 *   POSIX:   the child is spawned `detached:true` so it leads its own process
 *            group; `process.kill(-pid, 'SIGTERM')` signals the whole group, and
 *            we escalate to `SIGKILL` after `graceMs` if the group ignores TERM.
 *
 * Races handled: child exits before the deadline; the deadline firing after a
 * natural exit; the killer itself failing (reported via `killError`, never
 * thrown); and double-settle of the result promise.
 */
import { spawn, execFile, type StdioOptions } from "node:child_process";
import { performance } from "node:perf_hooks";

export type RunOutcome = "completed" | "timeout";

export interface RunWithDeadlineOptions {
  /** Hard wall-clock ceiling in ms. When it elapses the whole tree is killed. */
  readonly timeoutMs: number;
  /** POSIX only: gap between SIGTERM and the escalated SIGKILL. Default 10_000. */
  readonly graceMs?: number;
  /** Child environment. Defaults to the current process env. */
  readonly env?: NodeJS.ProcessEnv;
  /** Working directory for the child. */
  readonly cwd?: string;
  /** stdio wiring passed straight through to spawn. Defaults to "ignore". */
  readonly stdio?: StdioOptions;
}

export interface RunResult {
  readonly outcome: RunOutcome;
  readonly exitCode: number | null;
  readonly signal: NodeJS.Signals | null;
  readonly durationMs: number;
  /**
   * Set only when the kill path swallowed an error (reported, never thrown) --
   * e.g. taskkill returning a non-zero code because it lost the race to a
   * natural exit. Undefined on the happy path.
   */
  readonly killError?: string;
}

const isWindows = process.platform === "win32";
const DEFAULT_GRACE_MS = 10_000;

export function runWithDeadline(
  file: string,
  args: readonly string[],
  options: RunWithDeadlineOptions,
): Promise<RunResult> {
  const graceMs = options.graceMs ?? DEFAULT_GRACE_MS;

  return new Promise<RunResult>((resolve, reject) => {
    // Validate at the boundary so misuse fails loudly instead of arming a
    // zero-delay timer or a NaN deadline.
    if (!Number.isFinite(options.timeoutMs) || options.timeoutMs <= 0) {
      reject(new TypeError(`timeoutMs must be a positive finite number, got ${String(options.timeoutMs)}`));
      return;
    }
    if (options.graceMs !== undefined && (!Number.isFinite(options.graceMs) || options.graceMs < 0)) {
      reject(new TypeError(`graceMs must be a non-negative finite number, got ${String(options.graceMs)}`));
      return;
    }

    const startedAt = performance.now();
    let settled = false;
    let timedOut = false;
    let killError: string | undefined;
    let sigkillTimer: NodeJS.Timeout | undefined;

    const child = spawn(file, [...args], {
      // POSIX: own process group so `process.kill(-pid, ...)` hits the whole
      // group. Windows has no groups; taskkill /T walks the tree, so detached
      // buys nothing (and is unsupported without a shell).
      detached: !isWindows,
      env: options.env ?? process.env,
      cwd: options.cwd,
      stdio: options.stdio ?? "ignore",
      windowsHide: true,
    });

    const deadlineTimer = setTimeout(onDeadline, options.timeoutMs);

    const finish = (result: RunResult): void => {
      if (settled) return;
      settled = true;
      clearTimeout(deadlineTimer);
      if (sigkillTimer) clearTimeout(sigkillTimer);
      resolve(result);
    };

    const fail = (err: Error): void => {
      if (settled) return;
      settled = true;
      clearTimeout(deadlineTimer);
      if (sigkillTimer) clearTimeout(sigkillTimer);
      reject(err);
    };

    child.on("error", (err) => {
      // Spawn-level failure (e.g. ENOENT): the process never ran. Surface it
      // rather than masquerading as a completed/timeout outcome.
      fail(err);
    });

    child.on("exit", (code, signal) => {
      finish({
        outcome: timedOut ? "timeout" : "completed",
        exitCode: code,
        signal,
        durationMs: Math.round(performance.now() - startedAt),
        killError,
      });
    });

    function onDeadline(): void {
      // Defensive: if a natural exit already settled us, do nothing. (finish()
      // clears this timer, so this is belt-and-suspenders against a queued fire.)
      if (settled) return;
      timedOut = true;

      const pid = child.pid;
      if (pid === undefined) {
        // Never acquired a pid; the 'error' handler will settle the promise.
        return;
      }

      if (isWindows) {
        killTreeWindows(pid);
      } else {
        killTreePosix(pid, graceMs);
      }
    }

    function killTreeWindows(pid: number): void {
      // Async so the deadline handler never blocks; the child's 'exit' event
      // is what actually settles the promise once the tree is reaped.
      void killWindowsProcessTree(pid).then((errText) => {
        if (errText === undefined) return;
        // Benign common case: exit code 128 == "process not found", i.e. the
        // tree already exited between the deadline and our kill. Report, never
        // throw, then fall back to a direct kill in case the root is still up.
        killError = errText;
        try {
          child.kill("SIGKILL");
        } catch {
          /* already dead */
        }
      });
    }

    function killTreePosix(pid: number, grace: number): void {
      // Negative pid targets the whole process group led by the detached child.
      try {
        process.kill(-pid, "SIGTERM");
      } catch (err) {
        const code = (err as NodeJS.ErrnoException).code;
        if (code === "ESRCH") {
          return; // group already gone (natural exit); nothing to escalate against
        }
        // Real failure (e.g. EPERM on a cross-uid group). The hard ceiling must
        // still hold: report it, then force-kill the direct child so the
        // promise settles instead of waiting forever on a group we cannot
        // signal.
        killError = `SIGTERM to process group failed: ${(err as Error).message}`;
        try {
          child.kill("SIGKILL");
        } catch {
          /* already dead */
        }
        return;
      }
      // Escalate if the group is still alive past the grace window. Not unref'd:
      // we WANT to stay awake to deliver the SIGKILL; finish() clears it the
      // moment the child exits.
      sigkillTimer = setTimeout(() => {
        try {
          process.kill(-pid, "SIGKILL");
        } catch {
          /* ESRCH: group gone, which is the goal */
        }
      }, grace);
    }
  });
}

/**
 * Windows-only: force-kill the process tree rooted at `pid` via
 * `taskkill /PID <pid> /T /F` (/T = tree, /F = force). Resolves with an error
 * description when taskkill itself failed (reported, never thrown), undefined
 * on success.
 *
 * There is deliberately no generic POSIX tree-kill here: POSIX tree kills go
 * through process groups, which exist only for children spawned
 * `detached: true` (see runWithDeadline). Signaling `-pid` for a NON-detached
 * child would target the caller's own group.
 */
export function killWindowsProcessTree(pid: number): Promise<string | undefined> {
  return new Promise((resolve) => {
    execFile("taskkill", ["/PID", String(pid), "/T", "/F"], { windowsHide: true }, (err) => {
      if (!err) {
        resolve(undefined);
        return;
      }
      const code = (err as { code?: unknown }).code;
      resolve(`taskkill failed (code ${String(code)}): ${err.message.trim()}`);
    });
  });
}
