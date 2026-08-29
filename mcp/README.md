# @alanshurafa/co-evolution-mcp

MCP server for the [co-evolution bounce protocol](https://github.com/alanshurafa/co-evolution):
two AI agents (a reviewer and a composer) iteratively refine a markdown
document through structured `[CONTESTED]` / `[CLARIFY]` disagreement markers
until it converges — and every run produces receipts: a machine-readable
state trail, a deterministic behavior scorecard (did the agents *resolve*
disagreements or quietly delete them?), and a human-readable report.

In blind order-swapped judging by a frontier model, gate-passing bounce runs
were rated better than their inputs in 7 of 7 historical cases (0 regressed).

## Install

```bash
npm i -g @alanshurafa/co-evolution-mcp
```

### Prerequisites

| Tool | Needed for | Install |
|------|-----------|---------|
| bash | running the bouncer | ships with macOS/Linux; Windows: [Git for Windows](https://gitforwindows.org/) |
| `claude` CLI (logged in) | the default reviewer agent | [docs.claude.com/claude-code/install](https://docs.claude.com/claude-code/install), then run `claude` once to log in |
| `codex` CLI | the default composer agent (skippable: set both agents to `claude`) | [github.com/openai/codex](https://github.com/openai/codex) |
| `jq` *(optional except required by `kimi`)* | raw Kimi Markdown extraction; per-run state + behavior scores | [jqlang.org/download](https://jqlang.org/download/) |
| `yq` v4+, mikefarah build *(optional)* | the deterministic scorer | [github.com/mikefarah/yq](https://github.com/mikefarah/yq) |

Missing optional tools never fail a call: you get the bounced document and a
`receipts_note` telling you what to install for the full scorecard. The `kimi`
seat is the exception because it needs `jq` to extract raw assistant Markdown
from Kimi's stream output.

## Client configuration

**Claude Desktop** (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "co-evolution": {
      "command": "co-evolution-mcp"
    }
  }
}
```

**Cursor** (`.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "co-evolution": { "command": "co-evolution-mcp" }
  }
}
```

**Continue** (`config.json`, under `experimental.modelContextProtocolServers`):

```json
{ "transport": { "type": "stdio", "command": "co-evolution-mcp" } }
```

## The `co_evolve` tool

| Input | Type | Default | Notes |
|-------|------|---------|-------|
| `document_path` | string | *(required)* | markdown document to bounce |
| `max_bounces` | int 1–5 | 2 | passes between the agents |
| `reviewer_agent` | `claude` \| `codex` | `claude` | |
| `composer_agent` | `claude` \| `codex` | `codex` | |
| `in_place` | boolean | `false` | overwrite the input document |
| `output_path` | string | `<input>.bounced.md` | ignored when `in_place` |
| `runs_dir` | string | `<document_dir>/.co-evolve/runs` | where run artifacts accumulate |

Returns JSON: `output_path`, `content` (the bounced document),
`run_dir` (artifact trail: `state.json`, per-pass outputs,
`bounce-scores.json`, `HUMAN-REPORT.md`), `passes_completed`, agents,
`duration_ms`, `scores` (overall pass/fail, per-dimension results, and the
marker-fate ledger summary — or `null` without jq/yq), `report_path`.

Progress notifications stream pass-by-pass while the bounce runs.

## Common errors

| Error | Fix |
|-------|-----|
| `missing_prerequisite` with `missing: ["claude"]` | install the claude CLI and log in (`claude`, then follow the prompt) |
| `missing_prerequisite` with `missing: ["codex"]` | install codex, or call with `reviewer_agent`/`composer_agent` set to `claude` |
| auth failure mentioned in `log_tail` | the agent CLI is installed but not logged in — run it once interactively |
| `document_path does not exist` | pass an absolute path; relative paths resolve against the *server's* cwd, which MCP clients set unpredictably |
| `output_path parent directory does not exist` | create the directory first — the server never auto-creates it |
| bounce failed (exit N) with `log_tail` | inspect `run_dir` — `run.log` holds the full transcript |

## Versioning

The npm version mirrors the git tag of the
[co-evolution repo](https://github.com/alanshurafa/co-evolution) it was
built from; the bouncer scripts inside the package are a vendored snapshot
of that exact tag.
