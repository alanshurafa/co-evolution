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
