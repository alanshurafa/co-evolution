# For agents reading this repo

This repo implements the **Bounce Protocol** — a convention for structured iterative refinement between AI agents using in-document markers. If you are an agent invoked against documents in this repo, you should know how to read and emit these markers.

## The two markers

- **`[CONTESTED]`** — appears on its own line below text you disagree with. The note states the disagreement and proposes a concrete alternative. If you see one in a document you are editing, either resolve it (delete it after applying its alternative or rebutting it) or leave it for the next agent.
- **`[CLARIFY]`** — appears on its own line below ambiguous text. The note offers two interpretations or asks a question with a finite answer space. If you can disambiguate, do so and delete the marker.

Both markers **auto-expire after 2 passes**: on the final pass of any bounce, you must resolve every remaining marker and may not introduce new ones. This rule guarantees convergence.

Full spec: [`BOUNCE-PROTOCOL.md`](BOUNCE-PROTOCOL.md). Reference implementation: [`agent-bouncer/`](agent-bouncer/).

## How to interact with this repo

- If you are invoked via `/co-evolution` or `bash co-evolve-bouncer.sh`, you are
  in the general-purpose co-evolution workflow for questions, drafts, plans,
  specs, arguments, and markdown refinement
- If you are invoked via `/dev-review` (Claude Code) or `bash dev-review/codex/dev-review.sh` (Codex), you are inside the bounce pipeline — your role (reviewer / composer) and pass number are passed to you in the prompt template
- If you are invoked via `/codex-build`, you are orchestrating a detached Codex build: the session plans and reviews, Codex executes in the background under `--preset codex-build`, and the session is woken at gates (see `skills/codex-build/`)
- If you are orchestrating via `--preset claude-build`, Codex plans and reviews while Claude executes the build synchronously; this path hard-requires `claude` CLI auth because Claude is the executor (see `dev-review/codex/claude-build.md`)
- If you are invoked via `bash agent-bouncer/agent-bouncer.sh <doc>`, you are bouncing a single markdown document — same protocol applies
- If you are exploring the repo directly without an explicit role, treat the protocol section above as orientation, then read the GSD-managed sections below for project meta

## Lab features

The `lab/` subdirectory holds opt-in experimental features invoked via `--lab <mode>`. Lab features may not modify master directly — only via emitted PRs that a human reviews and merges. See [`lab/README.md`](lab/README.md) for the full contract.

This section lives outside all `<!-- GSD:*-start -->` / `<!-- GSD:*-end -->` blocks so it survives GSD regeneration sweeps.

---

# Project context (GSD-managed)

The sections below are auto-generated from `.planning/` artifacts. They describe the project's structure, conventions, and active work. Read them for context after the protocol section above.

<!-- GSD:project-start source:PROJECT.md -->
## Project

**Co-Evolution**

Co-Evolution is a tooling repo for structured iterative refinement between AI agents and humans. It already ships a standalone Agent Bouncer and a Claude Code `/dev-review` skill, and the current initiative is to add a standalone Codex runtime for the same compose-bounce-execute-verify workflow.

**Core Value:** Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps.

### Constraints

- **Tech stack**: Bash-first runtime plus Markdown templates — existing product surface should stay shell-native
- **Compatibility**: Preserve current Agent Bouncer behavior and artifact naming while extracting helpers
- **Shared assets**: Prompt templates and schema live under `skills/dev-review/` so all runtimes share one contract
- **Execution style**: Implement and commit in visible steps aligned with the external plan so progress is easy to inspect
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Snapshot
- Project type: tooling repo for cross-AI document refinement, not a deployable app or service.
- Legacy runner (still used by tests/experiments): `agent-bouncer/agent-bouncer.sh`.
- Primary orchestrator spec: `skills/dev-review/SKILL.md`.
- Supporting assets: markdown templates in `agent-bouncer/templates/` and `skills/dev-review/templates/`, plus JSON schema in `skills/dev-review/schemas/review-verdict.json`.
- Tracked source is small: one shell entrypoint, one large skill spec, supporting docs, prompts, and schema files.
## Languages And Formats
- Bash is the only tracked programming language, used in `agent-bouncer/agent-bouncer.sh`.
- Markdown is the dominant artifact format in `README.md`, `agent-bouncer/README.md`, `skills/dev-review/README.md`, `notesforhumans.md`, and all prompt/template files.
- JSON Schema is used in `skills/dev-review/schemas/review-verdict.json` to constrain verification output.
- Ignore metadata lives in `.gitignore` and `.agentignore`.
## Runtime Dependencies
- `agent-bouncer/agent-bouncer.sh` assumes a POSIX shell plus standard utilities such as `date`, `head`, `tr`, `cp`, `mv`, `rm`, `wc`, `awk`, `tee`, `mkdir`, and `cat`.
- The bouncer depends on authenticated AI CLIs: `claude` and `codex`.
- The Claude adapter defaults to model `claude-opus-4-8` (the `best` alias resolved in `lib/co-evolution.sh`), overridable via the `CLAUDE_MODEL` env var or the `--claude-model` flag; it is not hard-coded.
- The Codex adapter is hard-coded to `codex exec --full-auto --skip-git-repo-check`.
- `skills/dev-review/SKILL.md` assumes Claude Code tooling, `git`, and optionally `gh` for PR creation.
## Build And Packaging
- There is no `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, or compiled build system.
- There is no dependency lockfile.
- There is no CI configuration in the tracked repository.
- Distribution today is file-copy based: users run `agent-bouncer/agent-bouncer.sh` directly or copy `skills/dev-review/` into a Claude Code skills directory.
## Storage And Generated State
- Generated bounce artifacts are written under `runs/`.
- `.gitignore` marks `runs/` as generated output, so run logs and bounced documents stay local by default.
- The bouncer mutates the input plan file in place and also writes a clean final copy plus per-pass raw outputs into `runs/bouncer-*/`.
## Practical Takeaway
- The repo is best understood as a shell-based orchestrator plus a prompt/spec bundle.
- Operational correctness depends more on CLI behavior, prompt quality, and file contracts than on a compiled application runtime.
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Shell Coding Style
- `agent-bouncer/agent-bouncer.sh` starts with `set -euo pipefail` and relies on fail-fast shell semantics.
- Repository-wide shell style favors uppercase globals and lowercase helper/local names.
- Functions are short and single-purpose: adapter invocation, cleanup, and logging are separated.
- File-based orchestration is preferred over pipes between complex subprocess chains.
- Defensive cleanup is handled with `trap cleanup EXIT`.
## Prompt And Template Conventions
- Prompt templates use literal placeholder tokens such as `{TASK}` and `{PLAN_CONTENT}`.
- Both the bouncer and the skill embed plan content inline into prompts instead of handing Codex the canonical plan file path.
- The bounce protocol insists on editing the document directly rather than returning commentary or diffs.
- `[CONTESTED]` and `[CLARIFY]` are the shared coordination markers across the repo.
- A `## HUMAN SUMMARY` section is preserved as metadata for per-pass explanation and stripped from the clean canonical output by `agent-bouncer/agent-bouncer.sh`.
## Artifact Conventions
- Raw pass outputs are always preserved separately from the canonical working document.
- Clean outputs are named after the run label instead of a fixed filename.
- stderr is captured per pass in `runs/bouncer-*/pass-N-stderr.log`.
- Generated run artifacts are kept local and ignored through `.gitignore`.
## Documentation Conventions
- Behavior is documented close to the implementation: `agent-bouncer/README.md` for the script and `skills/dev-review/README.md` for the skill.
- The repo uses markdown tables, command examples, and file trees heavily instead of typed interfaces or generated docs.
- `notesforhumans.md` carries concept and origin context that is intentionally hidden from agent ingestion via `.agentignore`.
## Workflow Conventions
- The bounce alternates reviewer on odd passes and composer on even passes.
- Most workflows assume two passes are the high-value default.
- The skill's verification phase expects JSON-only output matching `skills/dev-review/schemas/review-verdict.json`.
- Recent git history uses imperative commit subjects such as `Fix Claude max-turns and Codex non-git-repo failures`.
## Error-Handling Conventions
- Empty agent output triggers a retry.
- Suspiciously short output triggers a retry because the agent may have returned a summary instead of the full document.
- Marker counting ignores fenced code blocks and inline backticks to reduce false positives when the docs discuss marker syntax itself.
- Adapter functions tolerate non-zero subprocess exits and rely on downstream file checks to decide whether a pass truly failed.
## What Is Not Standardized
- There is no formatter, linter, or automated style enforcement.
- There is no shared library enforcing consistency between `agent-bouncer/templates/` and `skills/dev-review/templates/`.
- Process discipline is encoded mostly in docs, prompts, and human review rather than in tests or static analysis.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## System Shape
- The repository contains two related but separate delivery surfaces:
- `agent-bouncer/agent-bouncer.sh` is a legacy runner (still used by tests/experiments) for bouncing a document between agents.
- `skills/dev-review/SKILL.md` is a declarative Claude Code workflow for compose -> bounce -> execute -> verify.
- Shared behavior is expressed through prompt templates rather than through a shared library module.
## Core Bouncer Flow
## Skill Runtime Flow
## Architectural Boundaries
- Adapter boundary: `invoke_claude()` and `invoke_codex()` isolate CLI differences inside `agent-bouncer/agent-bouncer.sh`.
- Prompt boundary: protocol and role instructions live in `agent-bouncer/templates/` and `skills/dev-review/templates/`.
- Schema boundary: `skills/dev-review/schemas/review-verdict.json` separates review data shape from prompt wording.
- Artifact boundary: raw pass output is preserved, while the working document stays clean and canonical.
## State Model
- Short-lived state lives in temp prompt/output files created by `agent-bouncer/agent-bouncer.sh`.
- Durable local state lives in `runs/` as per-pass artifacts, stderr logs, and clean final documents.
- The skill side assumes additional temp files under `/tmp/dev-review-*`, but those are described behavior rather than tracked implementation.
## Design Characteristics
- File-driven orchestration instead of API objects or in-memory pipelines.
- Prompt templates are first-class architecture, not secondary documentation.
- The repo favors explicit artifacts for auditability: original input, per-pass raw outputs, clean output, and `run.log`.
- There is no application server, UI, or internal library package abstraction.
## Practical Consequence
- Most changes are cross-cutting between executable shell logic, prompt templates, and documentation.
- Architectural drift risk is higher than in a codebase with shared typed abstractions, because behavior is split across prose, shell, and runtime assumptions.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, or `.github/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->

## npm / MCP distribution (v1.4)

The bounce protocol is also distributed as an npm package: `@alanshurafa/co-evolution-mcp` (the [`mcp/`](mcp/) subdirectory) wraps `co-evolve-bouncer.sh` as an MCP server exposing one `co_evolve` tool for external clients (Claude Desktop, Cursor, Continue). The package vendors a snapshot of the bouncer at each git tag — when changing `co-evolve-bouncer.sh`, `lib/co-evolution.sh`, the co-evolve templates, or the receipts stack (`evals/score-bounce.sh`, `evals/report-bounce.sh`), remember the change ships externally on the next tag. The MCP smoke tests (`cd mcp && npm test`) run in CI on all three platforms.
