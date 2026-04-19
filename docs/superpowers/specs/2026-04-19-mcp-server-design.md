---
title: MCP Server Wrapper for co-evolution (`@alanshurafa/co-evolution-mcp`)
date: 2026-04-19
status: design — pending implementation plan
related:
  - .planning/notes/post-v12-visibility-plan.md (Item B)
  - ~/.claude/projects/C--Users-alan-Project-co-evolution/memory/brainstorm_competitive_adoption.md
---

# MCP Server Wrapper for co-evolution

## 1. Context & goal

Co-evolution today is `git clone`-only. External MCP clients (Claude Desktop, Cursor, Continue) can't reach it. Every competitor in the multi-agent-debate space ships either npm, pip, or a plugin marketplace. This spec designs a Node/TypeScript MCP server that wraps `agent-bouncer.sh`, exposing one tool (`co_evolve`) so external clients can invoke the bounce protocol without cloning the repo.

**Goal:** ship `@alanshurafa/co-evolution-mcp` to npm. A user types `npm i -g @alanshurafa/co-evolution-mcp`, adds a stanza to their MCP client config, and can call `co_evolve` from inside any MCP-capable chat surface.

**Non-goal (v0.1):** wrapping `dev-review/codex/dev-review.sh` or any `lab/pel/` machinery. Bouncer-only surface to keep the first release tight and the blast radius low.

## 2. Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Tool surface | Bouncer only (`co_evolve`) | Smallest, lowest-blast-radius. `dev_review` deferred to v0.2 once external demand is signaled. |
| 2 | Invocation mechanism | Shell out to `agent-bouncer.sh`; defer API-direct rewrite | Single source of truth. API-direct is premature optimization for an unproven distribution channel. |
| 3 | Implementation language | Node/TypeScript | MCP ecosystem center of gravity is npm. Official SDK is the spec reference. |
| 4 | Bouncer delivery | Vendor + version-pin | Self-contained `npm i -g`. CI pins npm package version to git tag. |
| 5 | Input file behavior | Caller chooses `in_place`; default non-destructive | Chat-driven invocation has no "are you sure" gate. Overwrite-by-default is a footgun. |
| 6 | Long-running operation handling | Blocking with progress notifications | Standard MCP pattern. Progress is the heartbeat that keeps the call alive. |
| 7 | Tool input schema | Match CLI + `output_path` + `in_place` | Full parity with CLI; explicit safer defaults. `progress_verbosity` is YAGNI. |
| 8 | Repo location + npm name | `mcp/` subdirectory; `@alanshurafa/co-evolution-mcp` (scoped) | Same git history enforces version-pin discipline. Scoped name avoids squatting risk. |

## 3. Architecture

```
┌──────────────────────────┐
│ MCP client               │  Claude Desktop / Cursor / Continue
│ (e.g., Claude Desktop)   │
└────────────┬─────────────┘
             │ stdio (JSON-RPC)
             ▼
┌──────────────────────────┐
│ MCP server (Node)        │  @alanshurafa/co-evolution-mcp
│                          │
│  ├─ server.ts            │  registers `co_evolve` tool, routes requests
│  ├─ preflight.ts         │  detects bash + claude + codex on startup
│  ├─ bouncer.ts           │  spawns vendored bash script, manages lifecycle
│  └─ progress.ts          │  parses bouncer stderr → MCP progress notifications
└────────────┬─────────────┘
             │ child_process.spawn
             ▼
┌──────────────────────────┐
│ vendored agent-bouncer.sh│  copy of agent-bouncer/ from same git tag
└────────────┬─────────────┘
             │ shells out
             ▼
       claude CLI + codex CLI (user-installed prerequisites)
```

Four small TypeScript files. No state in the server process — each `co_evolve` call is independent. The bouncer's existing `runs/` directory is the source of truth for artifacts.

**`runs_dir` mechanism:** The bouncer doesn't accept a runs-directory flag — it creates `runs/bouncer-{name}-{timestamp}/` relative to its current working directory. The MCP server controls the location by setting the spawned process's cwd to `runs_dir`'s parent (creating it first if needed). This keeps the bouncer untouched and lets the MCP server enforce the `<document_dir>/.co-evolve/runs/` default cleanly.

## 4. Tool contract

### Input schema

```ts
{
  document_path: string,                         // required, absolute or cwd-relative
  max_bounces?: number,                          // default 2, range 1-5
  reviewer_agent?: "claude" | "codex",           // default "claude"
  composer_agent?: "claude" | "codex",           // default "codex"
  in_place?: boolean,                            // default false
  output_path?: string,                          // default <input>.bounced.md (when in_place=false)
  runs_dir?: string                              // default <document_dir>/.co-evolve/runs/
}
```

### Output schema (success)

```ts
{
  output_path: string,                           // where the bounced doc lives
  content: string,                               // bounced doc content (full text)
  run_dir: string,                               // path to bouncer-{name}-{timestamp}/
  passes_completed: number,
  reviewer_agent: string,
  composer_agent: string,
  duration_ms: number
}
```

### Output schema (preflight failure — returned as MCP error)

```ts
{
  error: "missing_prerequisite",
  missing: ("claude" | "codex" | "bash")[],
  install_instructions: {
    claude?: string,                             // "https://docs.claude.com/claude-code/install"
    codex?: string,                              // "https://github.com/openai/codex"
    bash?: string                                // "https://gitforwindows.org/" (on Windows)
  }
}
```

### Progress notifications

Emitted via the MCP SDK's `progress` notification mechanism during the bounce:

- `"Pass 1/2: reviewer (claude) running..."`
- `"Pass 1/2: composer (codex) running..."`
- `"Pass 1/2 complete (3 markers resolved, 0 remaining)"`
- `"Pass 2/2: reviewer (claude) running..."`
- ...

Source: parsed from `agent-bouncer.sh` stderr, which already emits structured phase markers.

## 5. Repo layout

```
co-evolution/
├── mcp/                                          # NEW
│   ├── package.json                              # name: "@alanshurafa/co-evolution-mcp"
│   ├── tsconfig.json
│   ├── README.md                                 # install + Claude Desktop config snippet
│   ├── src/
│   │   ├── server.ts                             # MCP server entry, tool registration
│   │   ├── preflight.ts                          # CLI detection
│   │   ├── bouncer.ts                            # spawn + lifecycle
│   │   └── progress.ts                           # stderr → MCP progress
│   ├── vendor/                                   # gitignored, populated by `npm run build:vendor`
│   │   └── agent-bouncer/                        # copy of ../agent-bouncer/ from same git tag
│   ├── tests/
│   │   ├── smoke.test.ts                         # in-process MCP client + 1-pass bounce
│   │   └── fixtures/
│   │       └── tiny-doc.md
│   └── dist/                                     # gitignored, CI-built
├── .github/workflows/
│   └── publish-mcp.yml                           # NEW — on v* tag, build + smoke + publish
└── .gitignore                                    # adds mcp/node_modules/, mcp/dist/, mcp/vendor/
```

### What "vendoring" means here

Vendoring = bundling a copy of an external dependency *inside* your own package, instead of fetching it at runtime.

Today, `agent-bouncer.sh` lives at `co-evolution/agent-bouncer/` (repo root). The npm package only ships what's inside `mcp/`. So at build time, we **copy** `agent-bouncer/` into `mcp/vendor/agent-bouncer/`. The vendored copy ships with the npm package; users `npm i -g` once and have everything.

Tradeoff: every bouncer change requires republishing the npm package. The CI release pipeline (Section 6) makes that automatic. Two distribution channels exist (repo + npm), but the version-pin discipline guarantees they never drift — the npm package is always a snapshot of a tagged repo state.

## 6. Release pipeline

GitHub Action `.github/workflows/publish-mcp.yml`:

1. **Trigger:** push of tag matching `v*` (e.g., `v1.2`, `v1.3.0`)
2. **Steps:**
   - Checkout at the tag
   - `cd mcp && npm ci`
   - `npm run build:vendor` — copies `../agent-bouncer/` into `mcp/vendor/`
   - `npm run build` — TypeScript compile to `mcp/dist/`
   - `npm test` — smoke test (CLIs stubbed, see Section 8)
   - `npm version <tag>` — set package version to match git tag (e.g., tag `v1.3.0` → package `1.3.0`)
   - `npm publish --access public` — publish to npm using `NPM_TOKEN` repo secret

**Result:** tagging `v1.3` in this repo automatically publishes `@alanshurafa/co-evolution-mcp@1.3.0`. Bouncer source and npm package version stay in lockstep.

## 7. Error handling

| Failure | Behavior |
|---------|----------|
| Missing CLI (preflight) | Return MCP error with `install_instructions` mapping. Don't try to fall back. |
| Bouncer non-zero exit | Return MCP error with bouncer's stderr tail (last ~50 lines) + path to `run_dir` for debugging. |
| `document_path` doesn't exist or unreadable | MCP error before spawning bouncer. |
| `output_path` parent dir doesn't exist | MCP error. Don't auto-create — surprising behavior. |
| Process killed mid-bounce (client disconnect, signal) | MCP server cleans up spawned bouncer process via `child.kill('SIGTERM')` in shutdown handler. |
| `runs_dir` not writable | MCP error before spawning bouncer. |
| `max_bounces` outside `1-5` | MCP validation error (handled by SDK schema validator). |
| `reviewer_agent` / `composer_agent` not in enum | MCP validation error. |

## 8. Testing

### Smoke test

`mcp/tests/smoke.test.ts` — runs in CI:

- Start MCP server in-process via `@modelcontextprotocol/sdk` test harness
- Stub `claude` and `codex` CLIs by prepending a fake-bin directory to `PATH` containing shell scripts that emit a known marker pattern (sufficient to exercise the bouncer's marker-handling logic without needing real LLM calls or auth)
- Call `co_evolve` with `tiny-doc.md`, `max_bounces=1`, `reviewer_agent="claude"`, `composer_agent="codex"`
- Assert: tool returns success, `output_path` exists, `content` is non-empty, `passes_completed === 1`, `run_dir` contains expected per-pass artifacts
- Assert: at least one progress notification was emitted

### Preflight unit test

- Mock `which` to verify the missing-CLI error path produces the documented `install_instructions` payload

### CI auth wrinkle

GitHub-hosted runners can't easily run real `claude` / `codex` CLIs (auth tokens, account state). The CLI-stub approach above tests the wrapper, not the real bounce — sufficient for v0.1 because real-bounce coverage already exists at the bash level via `tests/lab-routing-simulation.sh` and friends.

A self-hosted runner with CLIs pre-authed is a v0.2 follow-up if signal warrants it.

## 9. README & install UX

`mcp/README.md` covers:

- One-line install: `npm i -g @alanshurafa/co-evolution-mcp`
- Prerequisites callout: bash, `claude` CLI, `codex` CLI (with install links per OS)
- Claude Desktop config snippet (paste into `claude_desktop_config.json`):
  ```json
  {
    "mcpServers": {
      "co-evolution": {
        "command": "co-evolution-mcp"
      }
    }
  }
  ```
- Cursor and Continue config snippets (parallel structure)
- Tool reference (input/output schema)
- Common errors & fixes (one row per error from Section 7)
- Link back to the main repo for the underlying bouncer documentation

## 10. Repo-level changes

Beyond the new `mcp/` directory, three small repo-root changes:

- **`.gitignore`** — append `mcp/node_modules/`, `mcp/dist/`, `mcp/vendor/`
- **`README.md`** — add a third row to the entrypoint table: "External MCP client (Claude Desktop, Cursor) → `npm i -g @alanshurafa/co-evolution-mcp`"
- **`AGENTS.md`** — add the npm package as a discovery surface (note: the AGENTS.md rewrite from `post-v12-visibility-plan.md` Item A will overhaul this file separately; this is a minimal additive change)

## 11. Open / deferred

| Item | Status |
|------|--------|
| API-direct mode (skip CLI shell-out) | Deferred to v0.2 if external adoption signals install-friction is the blocker |
| `dev_review` tool (full compose-bounce-execute-verify pipeline) | Deferred to v0.2 if external demand surfaces |
| `pel_propose` tool (lab/pel/ exposure) | Deliberately excluded — would expose experimental lab features through a "stable" npm package, contradicting lab/ promise |
| Self-hosted CI runner for real-bounce smoke tests | Deferred to v0.2 if CLI-stub coverage proves insufficient |
| `progress_verbosity` parameter (silent/phase/verbose) | YAGNI until someone complains |
| MCP registry submission | Post-v0.1 ship; submit after first round of dogfood |
| Awesome-MCP-list PR | Post-v0.1 ship; submit ~1 week after npm publish |

## 11a. Pre-publish verification

The npm scope `@alanshurafa` is assumed to be the user's npm namespace but has not been verified during this design pass. Before the first `npm publish`:

- Confirm `@alanshurafa` is registered to the user on npmjs.com (or substitute the correct scope and update all references in this spec, the package.json, and the README)
- Generate an `NPM_TOKEN` with publish rights to that scope and add it as a GitHub repo secret named `NPM_TOKEN`
- Reserve the unscoped `co-evolution-mcp` name as a defensive measure if desired (optional)

## 12. Success criteria

This work is done when:

1. `npm i -g @alanshurafa/co-evolution-mcp` works on a clean machine (Mac, Linux, Windows with Git Bash) with prerequisites installed
2. Adding the Claude Desktop config snippet exposes `co_evolve` as a callable tool in Claude Desktop
3. A round-trip call (`co_evolve` against a real markdown doc) completes successfully and emits progress notifications visible in Claude Desktop
4. Smoke test passes in CI on tag push
5. `git tag v1.3.0 && git push --tags` publishes `@alanshurafa/co-evolution-mcp@1.3.0` automatically
6. README install instructions are followable by someone who has never seen the repo before

---

*Spec authored 2026-04-19 via brainstorming dialogue. Decisions traceable to Q1–Q8 in session transcript. Ready for implementation plan via `superpowers:writing-plans`.*
