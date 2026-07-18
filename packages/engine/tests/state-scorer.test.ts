/**
 * The scorer proof: the TS serializer must be *score-invariant*. We take the
 * real corpus fixture, replace its `state.json` with our re-serialized output,
 * and run the REAL deterministic scorer (`evals/score-bounce.sh`) against both
 * the original and the re-serialized copy. The two scorecards must be identical
 * (modulo the `scored_at` timestamp), both must take the STATE path (not the
 * run.log artifact fallback), and the exit codes must match.
 *
 * Hermetic: the scorer shells out to bash/jq/yq only — no model calls. Working
 * copies live in an OS temp dir, so nothing lands in the repo.
 *
 * Portability: skips cleanly (with a clear reason) if no bash that can run the
 * scorer (bash + jq + mikefarah yq) is found. On Windows the PATH `bash` is
 * often WSL bash, which cannot see the Windows jq/yq — so we resolve Git Bash
 * explicitly and verify it can actually run the scorer before using it.
 */

import { spawnSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { parseBounceState, serializeBounceState } from "../src/state/index.js";

const TEST_DIR = dirname(fileURLToPath(import.meta.url));
const WORKTREE_ROOT = resolve(TEST_DIR, "..", "..", "..");
const SCORER_REL = "evals/score-bounce.sh";
const FIXTURE_DIR = join(TEST_DIR, "fixtures", "state", "codex-build-opus-plan-1.0");

/** A bash that can run the scorer: bash + jq + mikefarah yq all reachable. */
function canRunScorer(bashPath: string): boolean {
  try {
    const r = spawnSync(
      bashPath,
      [
        "-c",
        "command -v jq >/dev/null && command -v yq >/dev/null && yq --version 2>/dev/null | grep -qi mikefarah",
      ],
      { encoding: "utf8" },
    );
    return r.status === 0;
  } catch {
    return false;
  }
}

/** Resolve a scorer-capable bash, preferring Git Bash over the PATH `bash`
 *  (which is WSL bash on this machine and cannot see the Windows jq/yq). */
function resolveScorerBash(): string | null {
  const candidates: string[] = [];
  if (process.env["WP06_BASH"]) candidates.push(process.env["WP06_BASH"]!);
  if (process.platform === "win32") {
    candidates.push("C:\\Program Files\\Git\\bin\\bash.exe");
    candidates.push("C:\\Program Files\\Git\\usr\\bin\\bash.exe");
    candidates.push("C:\\Program Files (x86)\\Git\\bin\\bash.exe");
    try {
      const ep = spawnSync("git", ["--exec-path"], { encoding: "utf8" });
      if (ep.status === 0 && ep.stdout.trim()) {
        // <root>/mingw64/libexec/git-core -> <root>/bin/bash.exe
        const root = dirname(dirname(dirname(ep.stdout.trim())));
        candidates.push(join(root, "bin", "bash.exe"));
      }
    } catch {
      /* git not found; fall through */
    }
  } else {
    candidates.push("bash", "/bin/bash", "/usr/bin/bash");
  }
  for (const c of candidates) {
    if (canRunScorer(c)) return c;
  }
  return null;
}

const BASH = resolveScorerBash();
const SCORER_READY = BASH !== null && existsSync(join(WORKTREE_ROOT, SCORER_REL));
if (!SCORER_READY) {
  const why =
    BASH === null
      ? "no bash with jq + mikefarah yq found"
      : `scorer not found at ${join(WORKTREE_ROOT, SCORER_REL)}`;
  // eslint-disable-next-line no-console
  console.warn(`[state-scorer] SKIPPING scorer proof: ${why}`);
}
const runIf = SCORER_READY ? it : it.skip;

/** Windows path -> forward-slash form Git Bash accepts (C:/Users/...). */
const toBashPath = (p: string): string => p.replace(/\\/g, "/");

interface ScorerResult {
  status: number | null;
  stdout: string;
  stderr: string;
  scorecardPath: string;
}

function runScorer(runDirNative: string): ScorerResult {
  const r = spawnSync(BASH!, [SCORER_REL, "--run-dir", toBashPath(runDirNative)], {
    cwd: WORKTREE_ROOT,
    encoding: "utf8",
  });
  if (r.error) {
    throw new Error(`failed to spawn scorer via ${BASH}: ${String(r.error)}`);
  }
  return {
    status: r.status,
    stdout: r.stdout ?? "",
    stderr: r.stderr ?? "",
    scorecardPath: join(runDirNative, "bounce-scores.json"),
  };
}

/** Copy the fixture into `<parent>/run` (basename "run" so the scorecard's
 *  `run_dir` field matches across copies), dropping any stale scorecard. */
function stageRun(parent: string): string {
  const runDir = join(parent, "run");
  cpSync(FIXTURE_DIR, runDir, { recursive: true });
  const stale = join(runDir, "bounce-scores.json");
  if (existsSync(stale)) rmSync(stale);
  return runDir;
}

function readScorecard(path: string): Record<string, unknown> {
  return JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
}

describe("bounce-state serializer is score-invariant against the real scorer", () => {
  let tempRoot = "";
  let origRes: ScorerResult;
  let serRes: ScorerResult;
  let origScore: Record<string, unknown>;
  let serScore: Record<string, unknown>;

  beforeAll(() => {
    if (!SCORER_READY) return;
    tempRoot = mkdtempSync(join(tmpdir(), "wp06-scorer-"));

    // Copy A: unmodified original (the exit-code + scorecard oracle).
    const origRun = stageRun(join(tempRoot, "orig"));

    // Copy B: replace state.json with our TS-serialized output.
    const serRun = stageRun(join(tempRoot, "ser"));
    const fixtureStateRaw = readFileSync(join(FIXTURE_DIR, "state.json"), "utf8");
    const serialized = serializeBounceState(parseBounceState(fixtureStateRaw));
    writeFileSync(join(serRun, "state.json"), serialized);

    origRes = runScorer(origRun);
    serRes = runScorer(serRun);
    origScore = readScorecard(origRes.scorecardPath);
    serScore = readScorecard(serRes.scorecardPath);
    // The scorer shells out to bash/jq/yq twice; on Windows Git Bash each run
    // is ~10s of subprocess spawns, so the default 10s hook timeout is too low.
  }, 120_000);

  afterAll(() => {
    if (tempRoot) rmSync(tempRoot, { recursive: true, force: true });
  });

  runIf("writes a bounce-scores.json for both copies", () => {
    expect(existsSync(origRes.scorecardPath)).toBe(true);
    expect(existsSync(serRes.scorecardPath)).toBe(true);
  });

  runIf("takes the STATE path (not the run.log artifact fallback) for both", () => {
    // `source: "state"` is the scorer's observable state-mode signal
    // (score-bounce.sh sets SOURCE="state" only when the schema test passes).
    expect(origScore["source"]).toBe("state");
    expect(serScore["source"]).toBe("state");
    expect(origRes.stdout).toContain("source=state");
    expect(serRes.stdout).toContain("source=state");
  });

  runIf("produces identical scorecards modulo the scored_at timestamp", () => {
    const a = { ...origScore };
    const b = { ...serScore };
    // scored_at is the only intentionally-volatile field (per the scorer's
    // determinism contract); run_dir is pinned by the shared "run" basename.
    delete a["scored_at"];
    delete b["scored_at"];
    expect(b).toEqual(a);
    expect(serScore["run_dir"]).toBe(origScore["run_dir"]);
  });

  runIf("yields the same exit code as the unmodified run", () => {
    expect(serRes.status).toBe(origRes.status);
  });

  runIf("exit code matches the scorecard verdict (0 pass / 1 fail)", () => {
    const expected = origScore["overall_pass"] === true ? 0 : 1;
    expect(origRes.status).toBe(expected);
    expect(serRes.status).toBe(expected);
  });
});
