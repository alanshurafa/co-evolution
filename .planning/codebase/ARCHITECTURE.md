# Architecture

## System Shape

- The repository contains two related but separate delivery surfaces:
- `agent-bouncer/agent-bouncer.sh` is the executable runtime for bouncing a document between agents.
- `skill/SKILL.md` is a declarative Claude Code workflow for compose -> bounce -> execute -> verify.
- Shared behavior is expressed through prompt templates rather than through a shared library module.

## Core Bouncer Flow

1. `agent-bouncer/agent-bouncer.sh` validates the requested adapters by checking for `invoke_<agent>` functions.
2. It derives `SCRIPT_DIR`, `REPO_ROOT`, `RUNS_DIR`, and `WORKDIR`.
3. It asks Codex for a descriptive run label, then creates `runs/bouncer-<label>-<timestamp>/`.
4. It snapshots the source document to `runs/.../original.md`.
5. For each pass, it loads `agent-bouncer/templates/role-reviewer.md` or `agent-bouncer/templates/role-composer.md`.
6. It appends `agent-bouncer/templates/bounce-protocol.md`, injects placeholders, and writes a prompt temp file.
7. It invokes Claude or Codex, captures raw output, strips the `## HUMAN SUMMARY` trailer, and overwrites the canonical plan file.
8. It counts `[CONTESTED]` and `[CLARIFY]` markers with `awk` and stops early on convergence.

## Skill Runtime Flow

1. `skill/SKILL.md` parses `/dev-review` flags and task text.
2. It performs environment detection for git, Codex availability, and optional Windows live mode.
3. It composes a plan using either Opus or Codex.
4. It bounces the plan between agents using the same marker protocol.
5. It executes the refined plan with the designated executor.
6. It optionally verifies the diff against the plan using structured JSON output from `skill/schemas/review-verdict.json`.

## Architectural Boundaries

- Adapter boundary: `invoke_claude()` and `invoke_codex()` isolate CLI differences inside `agent-bouncer/agent-bouncer.sh`.
- Prompt boundary: protocol and role instructions live in `agent-bouncer/templates/` and `skill/templates/`.
- Schema boundary: `skill/schemas/review-verdict.json` separates review data shape from prompt wording.
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
