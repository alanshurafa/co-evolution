// Hermetic smoke test: in-process MCP client <-> server over a linked
// in-memory transport, with claude/codex PATH-stubbed (same stub pattern as
// the repo's tests/bounce-state-simulation.sh). No network, no LLM cost.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, join } from "node:path";
import { test } from "node:test";
import {
  type Agent,
  BounceError,
  runtimePrerequisites,
} from "../src/bouncer.js";
import { createServer } from "../src/server.js";

const MARKER_DOC = `# Sample Plan

## Approach

The approach is sound but the rollout window is risky.
[CONTESTED] Reviewer says two weeks; the original says one. Pick one and justify it.

## Risks

Need clarity on the rollback owner. [CLARIFY] Who owns rollback during the window?
This revision keeps every original section intact while adding review notes.
`;

const CLEAN_DOC = `# Sample Plan

## Approach

The approach is sound and the rollout window is now two weeks, agreed by
both sides after the contested point was resolved with a concrete owner
and a written justification for the longer window.

## Risks

Rollback is owned by the on-call lead during the window. All markers resolved.
`;

const INPUT_DOC = `# Sample Plan

## Approach

Ship the feature in a one-week rollout window with staged percentages across
all three production regions, keeping the legacy path available throughout.

## Risks

Rollback procedure is undocumented and has no named owner at this time, and
the staged percentages have not been agreed with the capacity planning team.
`;

function writeStubs(binDir: string, counterFile: string): void {
  mkdirSync(binDir, { recursive: true });
  const claude = `#!/usr/bin/env bash
for arg in "$@"; do case "$arg" in --version|-v) echo "claude (stub)"; exit 0;; esac; done
while IFS= read -r _line; do :; done
n=0; [[ -f "${counterFile}" ]] && n=$(cat "${counterFile}"); n=$((n+1)); printf '%s' "$n" > "${counterFile}"
if (( n % 2 == 1 )); then
cat <<'DOC'
${MARKER_DOC}DOC
else
cat <<'DOC'
${CLEAN_DOC}DOC
fi
`;
  const codex = `#!/usr/bin/env bash
for arg in "$@"; do case "$arg" in --version|-v) echo "codex (stub)"; exit 0;; esac; done
output_file=""; prev=""
for arg in "$@"; do [[ "$prev" == "-o" ]] && output_file="$arg"; prev="$arg"; done
cat > /dev/null
doc=$(cat <<'DOC'
${CLEAN_DOC}DOC
)
if [[ -n "$output_file" ]]; then printf '%s\\n' "$doc" > "$output_file"; else printf '%s\\n' "$doc"; fi
`;
  writeFileSync(join(binDir, "claude"), claude);
  writeFileSync(join(binDir, "codex"), codex);
  chmodSync(join(binDir, "claude"), 0o755);
  chmodSync(join(binDir, "codex"), 0o755);
}

async function connectedClient() {
  const server = createServer();
  const client = new Client({ name: "smoke-test", version: "0.0.0" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  return client;
}

test("co_evolve round-trip with stubbed CLIs", async () => {
  const work = mkdtempSync(join(tmpdir(), "mcp-smoke-"));
  const originalPath = process.env.PATH;
  try {
    const binDir = join(work, "bin");
    writeStubs(binDir, join(work, "counter"));
    process.env.PATH = `${binDir}${delimiter}${originalPath}`;

    const docPath = join(work, "doc.md");
    writeFileSync(docPath, INPUT_DOC);

    const client = await connectedClient();
    const progressMessages: string[] = [];
    const result = await client.callTool(
      { name: "co_evolve", arguments: { document_path: docPath, max_bounces: 2 } },
      undefined,
      {
        onprogress: (progress) => {
          if (progress.message) progressMessages.push(progress.message);
        },
        timeout: 120_000,
      },
    );

    assert.equal(result.isError ?? false, false, JSON.stringify(result.content));
    const payload = JSON.parse(
      (result.content as Array<{ type: string; text: string }>)[0].text,
    );
    assert.equal(payload.output_path, `${docPath}.bounced.md`);
    assert.ok(payload.content.includes("two weeks"), "bounced content present");
    assert.ok(!payload.content.includes("[CONTESTED]"), "no live markers in output");
    assert.equal(payload.passes_completed, 2);
    assert.ok(payload.run_dir.includes(join(work, ".co-evolve", "runs")), `run_dir under .co-evolve/runs: ${payload.run_dir}`);
    assert.ok(progressMessages.length >= 1, "at least one progress notification");

    // Receipts: when jq is present on the host (it is in CI and dev), the
    // run must carry state-backed pass data; scores may be null without yq.
    assert.ok(payload.scores === null || typeof payload.scores.overall_pass === "boolean");
  } finally {
    process.env.PATH = originalPath;
    rmSync(work, { recursive: true, force: true });
  }
});

test("co_evolve in_place overwrites the input document", async () => {
  const work = mkdtempSync(join(tmpdir(), "mcp-smoke-"));
  const originalPath = process.env.PATH;
  try {
    const binDir = join(work, "bin");
    writeStubs(binDir, join(work, "counter"));
    process.env.PATH = `${binDir}${delimiter}${originalPath}`;

    const docPath = join(work, "doc.md");
    writeFileSync(docPath, INPUT_DOC);

    const client = await connectedClient();
    const result = await client.callTool({
      name: "co_evolve",
      arguments: { document_path: docPath, in_place: true },
    });
    assert.equal(result.isError ?? false, false, JSON.stringify(result.content));
    const payload = JSON.parse(
      (result.content as Array<{ type: string; text: string }>)[0].text,
    );
    assert.equal(payload.output_path, docPath);
    assert.ok(payload.content.includes("two weeks"));
  } finally {
    process.env.PATH = originalPath;
    rmSync(work, { recursive: true, force: true });
  }
});

test("preflight failure names the missing CLI with install instructions", async () => {
  const work = mkdtempSync(join(tmpdir(), "mcp-smoke-"));
  const originalPath = process.env.PATH;
  try {
    // PATH with bash but neither claude nor codex.
    const binDir = join(work, "bin");
    mkdirSync(binDir, { recursive: true });
    const essentials = ["bash", "cat", "mkdir", "dirname", "basename"];
    process.env.PATH = ["/bin", "/usr/bin", binDir].join(delimiter);
    void essentials;

    const docPath = join(work, "doc.md");
    writeFileSync(docPath, INPUT_DOC);

    const client = await connectedClient();
    const result = await client.callTool({
      name: "co_evolve",
      arguments: { document_path: docPath },
    });
    assert.equal(result.isError, true);
    const payload = JSON.parse(
      (result.content as Array<{ type: string; text: string }>)[0].text,
    );
    assert.equal(payload.error, "missing_prerequisite");
    assert.ok(payload.missing.includes("claude"));
    assert.ok(payload.install_instructions.claude.includes("claude"));
  } finally {
    process.env.PATH = originalPath;
    rmSync(work, { recursive: true, force: true });
  }
});

test("missing document_path is rejected before spawning", async () => {
  const client = await connectedClient();
  const result = await client.callTool({
    name: "co_evolve",
    arguments: { document_path: "/nonexistent/place/doc.md" },
  });
  assert.equal(result.isError, true);
});

function prerequisiteOptions(work: string, reviewerAgent: Agent, composerAgent: Agent) {
  return {
    documentPath: join(work, "doc.md"),
    maxBounces: 1,
    reviewerAgent,
    composerAgent,
    outputPath: join(work, "out.md"),
    runsDir: join(work, "runs"),
  };
}

test("glm accepts only the targeted .env.local key without mutating process.env", () => {
  const work = mkdtempSync(join(tmpdir(), "mcp-glm-prereq-"));
  const originalPath = process.env.PATH;
  const originalKey = process.env.ZAI_API_KEY;
  const originalCwd = process.cwd();
  try {
    const binDir = join(work, "bin");
    writeStubs(binDir, join(work, "counter"));
    process.env.PATH = `${binDir}${delimiter}${originalPath}`;
    delete process.env.ZAI_API_KEY;
    process.chdir(work);
    writeFileSync(join(work, ".env.local"), "UNRELATED=value\nZAI_API_KEY=test-only-key\n");

    const childEnv = runtimePrerequisites(prerequisiteOptions(work, "glm", "claude"));
    assert.equal(childEnv.ZAI_API_KEY, "test-only-key");
    assert.equal(process.env.ZAI_API_KEY, undefined);
  } finally {
    process.chdir(originalCwd);
    process.env.PATH = originalPath;
    if (originalKey === undefined) delete process.env.ZAI_API_KEY;
    else process.env.ZAI_API_KEY = originalKey;
    rmSync(work, { recursive: true, force: true });
  }
});

test("glm direct API accepts WSL without Windows Claude dispatch", () => {
  const work = mkdtempSync(join(tmpdir(), "mcp-glm-wsl-"));
  const originalPath = process.env.PATH;
  const originalKey = process.env.ZAI_API_KEY;
  const originalWsl = process.env.WSL_DISTRO_NAME;
  try {
    const binDir = join(work, "bin");
    mkdirSync(binDir, { recursive: true });
    const suffix = process.platform === "win32" ? ".cmd" : "";
    writeFileSync(join(binDir, `cmd.exe${suffix}`), "exit 0\n");
    writeFileSync(join(binDir, `claude${suffix}`), "exit 0\n");
    chmodSync(join(binDir, `cmd.exe${suffix}`), 0o755);
    chmodSync(join(binDir, `claude${suffix}`), 0o755);
    process.env.PATH = `${binDir}${delimiter}${originalPath}`;
    process.env.ZAI_API_KEY = "test-only-key";
    process.env.WSL_DISTRO_NAME = "test";

    const childEnv = runtimePrerequisites(prerequisiteOptions(work, "glm", "claude"));
    assert.equal(childEnv.ZAI_API_KEY, "test-only-key");
  } finally {
    process.env.PATH = originalPath;
    if (originalKey === undefined) delete process.env.ZAI_API_KEY;
    else process.env.ZAI_API_KEY = originalKey;
    if (originalWsl === undefined) delete process.env.WSL_DISTRO_NAME;
    else process.env.WSL_DISTRO_NAME = originalWsl;
    rmSync(work, { recursive: true, force: true });
  }
});

test("glm direct API ignores the Windows System32 WSL launcher", () => {
  const work = mkdtempSync(join(tmpdir(), "mcp-glm-wsl-launcher-"));
  const originalKey = process.env.ZAI_API_KEY;
  try {
    process.env.ZAI_API_KEY = "test-only-key";
    const childEnv = runtimePrerequisites(
      prerequisiteOptions(work, "glm", "claude"),
      "C:\\Windows\\System32\\bash.exe",
    );
    assert.equal(childEnv.ZAI_API_KEY, "test-only-key");
  } finally {
    if (originalKey === undefined) delete process.env.ZAI_API_KEY;
    else process.env.ZAI_API_KEY = originalKey;
    rmSync(work, { recursive: true, force: true });
  }
});

test("kimi accepts only the targeted .env.local API key without mutating process.env", () => {
  const work = mkdtempSync(join(tmpdir(), "mcp-kimi-prereq-"));
  const originalKey = process.env.KIMI_API_KEY;
  const originalCwd = process.cwd();
  try {
    delete process.env.KIMI_API_KEY;
    process.chdir(work);
    writeFileSync(join(work, ".env.local"), "UNRELATED=value\nKIMI_API_KEY=test-only-kimi-key\n");

    const childEnv = runtimePrerequisites(prerequisiteOptions(work, "kimi", "kimi"));
    assert.equal(childEnv.KIMI_API_KEY, "test-only-kimi-key");
    assert.equal(process.env.KIMI_API_KEY, undefined);

    rmSync(join(work, ".env.local"));
    assert.throws(
      () => runtimePrerequisites(prerequisiteOptions(work, "kimi", "kimi")),
      (error: unknown) =>
        error instanceof BounceError &&
        error.code === "missing_prerequisite" &&
        error.details.missing instanceof Array &&
        error.details.missing.includes("KIMI_API_KEY"),
    );
  } finally {
    process.chdir(originalCwd);
    if (originalKey === undefined) delete process.env.KIMI_API_KEY;
    else process.env.KIMI_API_KEY = originalKey;
    rmSync(work, { recursive: true, force: true });
  }
});

test("unknown agents produce a structured error", () => {
  const work = mkdtempSync(join(tmpdir(), "mcp-agent-prereq-"));
  try {
    const opts = prerequisiteOptions(work, "claude", "codex");
    opts.composerAgent = "nonsense" as Agent;
    assert.throws(
      () => runtimePrerequisites(opts),
      (error: unknown) =>
        error instanceof BounceError &&
        error.code === "unknown_agent" &&
        error.details.agent === "nonsense" &&
        error.runDir === null,
    );
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
});
