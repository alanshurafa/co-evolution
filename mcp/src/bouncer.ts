// Bridge to the vendored co-evolve-bouncer.sh (addendum D-01/D-02).
// One spawn per co_evolve call; no state lives in this process. The run
// directory the bouncer creates is the durable artifact trail.
import { spawn } from "node:child_process";
import {
  accessSync,
  constants,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { LineBuffer, progressMessage } from "./progress.js";
import { findOnPath } from "./preflight.js";

const HERE = dirname(fileURLToPath(import.meta.url));
// dist/src/ -> package root -> vendor/co-evolution/
export const VENDOR_ROOT = resolve(HERE, "..", "..", "vendor", "co-evolution");

export const AGENTS = ["claude", "codex", "glm", "kimi"] as const;
export type Agent = (typeof AGENTS)[number];

export interface BounceOptions {
  documentPath: string;
  maxBounces: number;
  reviewerAgent: Agent;
  composerAgent: Agent;
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
    public readonly code?: "missing_prerequisite" | "unknown_agent",
    public readonly details: Record<string, unknown> = {},
  ) {
    super(message);
  }
}

function isAgent(value: string): value is Agent {
  return (AGENTS as readonly string[]).includes(value);
}

function readable(path: string): boolean {
  try {
    accessSync(path, constants.R_OK);
    return true;
  } catch {
    return false;
  }
}

function executable(path: string): boolean {
  try {
    accessSync(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function namedEnvValue(path: string, name: string): string | null {
  if (!readable(path)) return null;
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const assignment = new RegExp(
    `^\\s*(?:export\\s+)?${escaped}\\s*=\\s*(.*?)\\s*$`,
  );
  for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
    const match = assignment.exec(line);
    if (!match) continue;
    let value = match[1].trim();
    if (
      value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'")))
    ) {
      value = value.slice(1, -1);
    }
    return value.length > 0 ? value : null;
  }
  return null;
}

function runtimeError(
  agent: string,
  missing: string,
  message: string,
): BounceError {
  return new BounceError(message, message, null, "missing_prerequisite", {
    agent,
    missing: [missing],
  });
}

function findBash(): string | null {
  if (process.platform === "win32") {
    const programFiles = process.env.ProgramFiles ?? "C:\\Program Files";
    const gitBash = join(programFiles, "Git", "bin", "bash.exe");
    if (executable(gitBash)) return gitBash;
  }
  return findOnPath("bash");
}

function isWslLauncher(bashPath: string | null): boolean {
  return /[/\\]windows[/\\]system32[/\\]bash\.exe$/i.test(bashPath ?? "");
}

function pathForBash(path: string, bashPath: string | null): string {
  if (process.platform !== "win32") return path;
  const forward = path.replaceAll("\\", "/");
  // Windows' system bash.exe is the WSL launcher, which needs /mnt/<drive>.
  if (isWslLauncher(bashPath)) {
    return forward.replace(/^([A-Za-z]):\//, (_, drive: string) =>
      `/mnt/${drive.toLowerCase()}/`
    );
  }
  return forward;
}

/** Validate new-seat requirements and return the child-only environment. */
export function runtimePrerequisites(
  opts: BounceOptions,
  bashPath: string | null = findBash(),
): NodeJS.ProcessEnv {
  const childEnv: NodeJS.ProcessEnv = { ...process.env };
  const agents = [opts.reviewerAgent as string, opts.composerAgent as string];
  for (const agent of agents) {
    if (!isAgent(agent)) {
      throw new BounceError(
        `Unknown agent: ${agent}`,
        `Unknown agent: ${agent}`,
        null,
        "unknown_agent",
        { agent },
      );
    }
  }

  if (agents.includes("glm")) {
    if (!findOnPath("curl")) {
      throw runtimeError(
        "glm",
        "curl",
        "glm seat requires curl for the direct Z.AI API",
      );
    }
    if (!findOnPath("jq")) {
      throw runtimeError(
        "glm",
        "jq",
        "glm seat requires jq for Z.AI request and response handling",
      );
    }

    let key = process.env.ZAI_API_KEY?.trim() || null;
    if (!key) {
      const candidates = [
        resolve(process.cwd(), ".env.local"),
        resolve(dirname(opts.documentPath), ".env.local"),
      ];
      for (const candidate of new Set(candidates)) {
        key = namedEnvValue(candidate, "ZAI_API_KEY");
        if (key) break;
      }
    }
    if (!key) {
      throw runtimeError(
        "glm",
        "ZAI_API_KEY",
        "glm seat requires ZAI_API_KEY in the process environment or targeted .env.local",
      );
    }
    // Child-scoped only. Never write this back to process.env or error output.
    childEnv.ZAI_API_KEY = key;
  }

  if (agents.includes("kimi")) {
    const home = process.env.HOME || process.env.USERPROFILE || homedir();
    const portable = [
      join(home, ".kimi-code", "bin", "kimi"),
      join(home, ".kimi-code", "bin", "kimi.exe"),
    ].find(executable);
    if (!findOnPath("kimi") && !portable) {
      throw runtimeError(
        "kimi",
        "kimi",
        "kimi seat requires the kimi CLI on PATH (or under ~/.kimi-code/bin)",
      );
    }
    if (!findOnPath("jq")) {
      throw runtimeError(
        "kimi",
        "jq",
        "kimi seat requires jq to extract raw assistant Markdown from stream-json output",
      );
    }
    if (!readable(join(home, ".kimi-code", "config.toml"))) {
      throw runtimeError(
        "kimi",
        "~/.kimi-code/config.toml",
        "kimi seat requires readable Kimi config at ~/.kimi-code/config.toml",
      );
    }
    if (!readable(join(home, ".kimi-code", "credentials", "kimi-code.json"))) {
      throw runtimeError(
        "kimi",
        "kimi_login",
        "kimi seat is not logged in; run 'kimi login --region mainland-cn'",
      );
    }
    if (!childEnv.HOME) childEnv.HOME = home;
  }

  return childEnv;
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

  // Keep every new-seat failure ahead of directory creation and child spawn.
  const bashPath = findBash();
  const childEnv = runtimePrerequisites(opts, bashPath);

  mkdirSync(opts.runsDir, { recursive: true });
  const before = listRunDirs(opts.runsDir);
  const startedAt = Date.now();

  const args = [
    pathForBash(bouncer, bashPath),
    "--vanilla",
    "--bounce-only",
    "--bounces",
    String(opts.maxBounces),
    "--agents",
    `${opts.reviewerAgent},${opts.composerAgent}`,
    "--output",
    pathForBash(opts.outputPath, bashPath),
    pathForBash(opts.documentPath, bashPath),
  ];

  const child = spawn(bashPath ?? "bash", args, {
    cwd: dirname(opts.documentPath),
    env: {
      ...childEnv,
      CO_EVOLVE_RUNS_DIR: pathForBash(opts.runsDir, bashPath),
    },
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
