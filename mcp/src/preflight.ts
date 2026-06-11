// Preflight dependency checks — doctor.sh semantics (see scripts/doctor.sh
// in the main repo and addendum D-03): hard requirements fail the call with
// install instructions; missing receipt tools degrade honestly.
import { accessSync, constants, existsSync } from "node:fs";
import { delimiter, join } from "node:path";

export interface PreflightResult {
  ok: boolean;
  missing: string[];
  receipts: { jq: boolean; yq: boolean };
  installInstructions: Record<string, string>;
}

const INSTALL: Record<string, string> = {
  bash: "macOS/Linux ship bash; on Windows install Git for Windows (https://gitforwindows.org/) and run your MCP client where Git Bash is on PATH",
  claude: "https://docs.claude.com/claude-code/install — then run `claude` once interactively to log in",
  codex: "https://github.com/openai/codex — required only when an agent argument selects codex",
  jq: "https://jqlang.org/download/ — enables state.json + behavior scores on each run",
  yq: "https://github.com/mikefarah/yq (the Go build, v4+) — enables the deterministic scorer",
};

export function findOnPath(cmd: string): string | null {
  const pathVar = process.env.PATH ?? "";
  const exts =
    process.platform === "win32" ? ["", ".exe", ".cmd", ".bat"] : [""];
  for (const dir of pathVar.split(delimiter)) {
    if (!dir) continue;
    for (const ext of exts) {
      const candidate = join(dir, cmd + ext);
      if (!existsSync(candidate)) continue;
      try {
        accessSync(candidate, constants.X_OK);
        return candidate;
      } catch {
        // not executable — keep scanning
      }
    }
  }
  return null;
}

export function preflight(agents: string[]): PreflightResult {
  const required = new Set<string>(["bash", "claude"]);
  if (agents.includes("codex")) required.add("codex");

  const missing = [...required].filter((cmd) => findOnPath(cmd) === null);
  const installInstructions: Record<string, string> = {};
  for (const cmd of missing) installInstructions[cmd] = INSTALL[cmd];

  return {
    ok: missing.length === 0,
    missing,
    receipts: {
      jq: findOnPath("jq") !== null,
      yq: findOnPath("yq") !== null,
    },
    installInstructions,
  };
}
