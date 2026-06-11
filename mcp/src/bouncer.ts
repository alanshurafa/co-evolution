// Bridge to the vendored co-evolve-bouncer.sh (addendum D-01/D-02).
// One spawn per co_evolve call; no state lives in this process. The run
// directory the bouncer creates is the durable artifact trail.
import { spawn } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { LineBuffer, progressMessage } from "./progress.js";

const HERE = dirname(fileURLToPath(import.meta.url));
// dist/src/ -> package root -> vendor/co-evolution/
export const VENDOR_ROOT = resolve(HERE, "..", "..", "vendor", "co-evolution");

export interface BounceOptions {
  documentPath: string;
  maxBounces: number;
  reviewerAgent: "claude" | "codex";
  composerAgent: "claude" | "codex";
  outputPath: string;
  runsDir: string;
  onProgress?: (message: string) => void;
  signal?: AbortSignal;
}

export interface BounceScoresSummary {
  overall_pass: boolean;
  marker_fates: Record<string, number>;
  dimensions: Record<string, boolean>;
}

export interface BounceResult {
  output_path: string;
  content: string;
  run_dir: string;
  passes_completed: number;
  reviewer_agent: string;
  composer_agent: string;
  duration_ms: number;
  scores: BounceScoresSummary | null;
  report_path: string | null;
}

export class BounceError extends Error {
  constructor(
    message: string,
    public readonly stderrTail: string,
    public readonly runDir: string | null,
  ) {
    super(message);
  }
}

function listRunDirs(runsRoot: string): Set<string> {
  if (!existsSync(runsRoot)) return new Set();
  return new Set(
    readdirSync(runsRoot).filter((name) => name.startsWith("co-evolve-")),
  );
}

function readScores(runDir: string): BounceScoresSummary | null {
  const scoresPath = join(runDir, "bounce-scores.json");
  if (!existsSync(scoresPath)) return null;
  try {
    const raw = JSON.parse(readFileSync(scoresPath, "utf8"));
    const fates: Record<string, number> = {};
    for (const entry of raw.marker_ledger ?? []) {
      fates[entry.fate] = (fates[entry.fate] ?? 0) + 1;
    }
    const dimensions: Record<string, boolean> = {};
    for (const [name, dim] of Object.entries(raw.dimensions ?? {})) {
      dimensions[name] = Boolean((dim as { pass?: boolean }).pass);
    }
    return { overall_pass: Boolean(raw.overall_pass), marker_fates: fates, dimensions };
  } catch {
    return null;
  }
}

function countPasses(runDir: string): number {
  const statePath = join(runDir, "state.json");
  if (existsSync(statePath)) {
    try {
      const state = JSON.parse(readFileSync(statePath, "utf8"));
      if (Array.isArray(state.passes)) return state.passes.length;
    } catch {
      // fall through to artifact counting
    }
  }
  return readdirSync(runDir).filter((f) => /^pass-\d+-clean\.md$/.test(f))
    .length;
}

export async function runBounce(opts: BounceOptions): Promise<BounceResult> {
  const bouncer = join(VENDOR_ROOT, "co-evolve-bouncer.sh");
  if (!existsSync(bouncer)) {
    throw new BounceError(
      `vendored bouncer missing at ${bouncer} — broken package install`,
      "",
      null,
    );
  }

  mkdirSync(opts.runsDir, { recursive: true });
  const before = listRunDirs(opts.runsDir);
  const startedAt = Date.now();

  const args = [
    bouncer,
    "--vanilla",
    "--bounce-only",
    "--bounces",
    String(opts.maxBounces),
    "--agents",
    `${opts.reviewerAgent},${opts.composerAgent}`,
    "--output",
    opts.outputPath,
    opts.documentPath,
  ];

  const child = spawn("bash", args, {
    cwd: dirname(opts.documentPath),
    env: { ...process.env, CO_EVOLVE_RUNS_DIR: opts.runsDir },
    stdio: ["ignore", "pipe", "pipe"],
  });

  const tail: string[] = [];
  const remember = (line: string) => {
    tail.push(line);
    if (tail.length > 50) tail.shift();
  };
  const stdoutBuffer = new LineBuffer();
  const stderrBuffer = new LineBuffer();
  const handleLine = (line: string) => {
    remember(line);
    const message = progressMessage(line);
    if (message && opts.onProgress) opts.onProgress(message);
  };
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk: string) => stdoutBuffer.push(chunk, handleLine));
  child.stderr.on("data", (chunk: string) => stderrBuffer.push(chunk, handleLine));

  const onAbort = () => child.kill("SIGTERM");
  opts.signal?.addEventListener("abort", onAbort, { once: true });

  const exitCode: number = await new Promise((resolvePromise, rejectPromise) => {
    child.on("error", rejectPromise);
    child.on("close", (code) => resolvePromise(code ?? 1));
  }).finally(() => {
    opts.signal?.removeEventListener("abort", onAbort);
    stdoutBuffer.flush(handleLine);
    stderrBuffer.flush(handleLine);
  }) as number;

  const after = listRunDirs(opts.runsDir);
  const newDirs = [...after].filter((name) => !before.has(name));
  const runDir = newDirs.length > 0 ? join(opts.runsDir, newDirs.sort().pop()!) : null;

  if (exitCode !== 0) {
    throw new BounceError(
      `bounce failed (exit ${exitCode})`,
      tail.join("\n"),
      runDir,
    );
  }
  if (!existsSync(opts.outputPath)) {
    throw new BounceError(
      "bouncer exited 0 but the output file was not written",
      tail.join("\n"),
      runDir,
    );
  }
  if (runDir === null) {
    throw new BounceError(
      "bouncer exited 0 but no run directory was created",
      tail.join("\n"),
      null,
    );
  }

  const reportPath = join(runDir, "HUMAN-REPORT.md");
  return {
    output_path: opts.outputPath,
    content: readFileSync(opts.outputPath, "utf8"),
    run_dir: runDir,
    passes_completed: countPasses(runDir),
    reviewer_agent: opts.reviewerAgent,
    composer_agent: opts.composerAgent,
    duration_ms: Date.now() - startedAt,
    scores: readScores(runDir),
    report_path: existsSync(reportPath) ? reportPath : null,
  };
}
