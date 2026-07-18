/**
 * Cross-platform process-tree kill contract for runWithDeadline.
 *
 * This test file is deliberately OS-agnostic: every platform branch lives inside
 * runWithDeadline / isProcessAlive, so the exact same assertions prove the
 * contract on Windows here and on ubuntu/macos in CI later (WP-08).
 *
 *   Test A (the gate): a parent that spawns a NON-detached grandchild is run
 *     under a short deadline; after the timeout resolves, BOTH the parent and the
 *     grandchild must be dead -- proving the killer reaped the whole tree rather
 *     than the grandchild dying by luck.
 *   Test B: a child that exits before the deadline reports "completed", no kill.
 *   Test C: a single process (no children) hits the deadline and dies cleanly.
 */
import { describe, it, expect } from "vitest";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { mkdtempSync, rmSync, existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { runWithDeadline } from "../src/index.js";
import { isProcessAlive } from "../src/proc/liveness.js";

const here = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(here, "fixtures", "proc");
const NODE = process.execPath;

const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

/** Poll for a fixture's pid file, returning the parsed (positive integer) pid. */
async function waitForPid(pidFile: string, timeoutMs: number): Promise<number> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (existsSync(pidFile)) {
      const raw = readFileSync(pidFile, "utf8").trim();
      const pid = Number(raw);
      if (Number.isInteger(pid) && pid > 0) return pid;
    }
    await sleep(25);
  }
  throw new Error(`pid file not ready within ${timeoutMs}ms: ${pidFile}`);
}

/** Poll until the pid is dead or the window elapses. Returns [dead, elapsedMs]. */
async function waitUntilDead(pid: number, timeoutMs: number): Promise<[boolean, number]> {
  const start = Date.now();
  const deadline = start + timeoutMs;
  for (;;) {
    if (!(await isProcessAlive(pid))) return [true, Date.now() - start];
    if (Date.now() >= deadline) return [false, Date.now() - start];
    await sleep(100);
  }
}

/**
 * Run the parent+grandchild tree under a ~1500ms deadline and assert the whole
 * tree is reaped. Returns timings so the caller can report them.
 */
async function runTreeKillScenario(label: string): Promise<{ durationMs: number; deathPollMs: number }> {
  const dir = mkdtempSync(join(tmpdir(), "proc-treekill-"));
  const parentPidFile = join(dir, "parent.pid");
  const grandchildPidFile = join(dir, "grandchild.pid");
  try {
    // Hold the promise so we can confirm the tree is fully up (both pid files
    // written) before the deadline reaps it -- makes the test deterministic
    // rather than racing fixture startup against the 1500ms ceiling.
    const runPromise = runWithDeadline(
      NODE,
      [join(FIXTURES, "parent.mjs"), parentPidFile, grandchildPidFile],
      { timeoutMs: 1500 },
    );

    const parentPid = await waitForPid(parentPidFile, 4000);
    const grandchildPid = await waitForPid(grandchildPidFile, 4000);
    expect(parentPid).not.toBe(grandchildPid);

    // Sanity: the tree is actually alive before the deadline fires.
    expect(await isProcessAlive(grandchildPid)).toBe(true);

    const result = await runPromise;
    expect(result.outcome).toBe("timeout");
    expect(result.durationMs).toBeGreaterThanOrEqual(1400);
    expect(result.durationMs).toBeLessThan(8000);
    expect(result.killError).toBeUndefined();

    // The gate: BOTH must be dead. Poll up to ~5s to absorb kill latency.
    const [grandchildDead, gMs] = await waitUntilDead(grandchildPid, 5000);
    const [parentDead, pMs] = await waitUntilDead(parentPid, 5000);
    expect(grandchildDead).toBe(true);
    expect(parentDead).toBe(true);

    const deathPollMs = Math.max(gMs, pMs);
    // Surfaced in the vitest run so the two Test-A timings can be reported.
    console.log(
      `[TestA] ${label} deadlineToExitMs=${result.durationMs} deathPollMs=${deathPollMs} ` +
        `parentPid=${parentPid} grandchildPid=${grandchildPid}`,
    );
    return { durationMs: result.durationMs, deathPollMs };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

describe("runWithDeadline: cross-platform process-tree kill", () => {
  // Run the gate twice to shake out flake; both must fully reap the tree.
  it(
    "Test A (run 1): kills the entire descendant tree on timeout",
    async () => {
      await runTreeKillScenario("run1");
    },
    30_000,
  );

  it(
    "Test A (run 2): kills the entire descendant tree on timeout",
    async () => {
      await runTreeKillScenario("run2");
    },
    30_000,
  );

  it(
    "Test B: child that exits before the deadline reports completed, no kill",
    async () => {
      // Exits on its own ~200ms in, well before the 5s ceiling.
      const result = await runWithDeadline(NODE, ["-e", "setTimeout(() => {}, 200)"], {
        timeoutMs: 5000,
      });
      expect(result.outcome).toBe("completed");
      expect(result.exitCode).toBe(0);
      expect(result.signal).toBe(null);
      expect(result.killError).toBeUndefined();
      expect(result.durationMs).toBeLessThan(5000);
    },
    15_000,
  );

  it(
    "Test C: single process with no children times out cleanly",
    async () => {
      const dir = mkdtempSync(join(tmpdir(), "proc-single-"));
      const pidFile = join(dir, "leaf.pid");
      try {
        // grandchild.mjs alone == one leaf process, no tree.
        const runPromise = runWithDeadline(NODE, [join(FIXTURES, "grandchild.mjs"), pidFile], {
          timeoutMs: 1500,
        });
        const pid = await waitForPid(pidFile, 4000);
        expect(await isProcessAlive(pid)).toBe(true);

        const result = await runPromise;
        expect(result.outcome).toBe("timeout");
        expect(result.durationMs).toBeGreaterThanOrEqual(1400);
        expect(result.killError).toBeUndefined();

        const [dead] = await waitUntilDead(pid, 5000);
        expect(dead).toBe(true);
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    },
    30_000,
  );
});
