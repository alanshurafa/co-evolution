# Stack

## Snapshot

- Project type: tooling repo for cross-AI document refinement, not a deployable app or service.
- Default runner: `co-evolve-bouncer.sh` (general document bouncing) plus the standalone Codex Bash runtime at `dev-review/codex/dev-review.sh` (code-focused compose-bounce-execute-verify).
- Legacy runner (still used by tests/experiments): `agent-bouncer/agent-bouncer.sh`.
- Primary orchestrator specs: `skills/dev-review/SKILL.md` (Claude Code) and `dev-review/codex/instructions.md` (Codex routing).
- Shared shell helpers live in `lib/co-evolution.sh`, consumed by both the bouncer and the Codex runtime.
- Supporting assets: markdown templates in `agent-bouncer/templates/`, `templates/co-evolve/`, and `skills/dev-review/templates/`; JSON schema in `schemas/review-verdict.json`, mirrored byte-for-byte in `skills/dev-review/schemas/` and the frozen `runners/codex-ps/schemas/` reference copy — CI-gated to stay in sync.
- `lab/` holds opt-in experimental machinery (currently the Protocol Evolution Loop, `lab/pel/`) reached via `--lab <mode>`; it cannot modify master directly, only via emitted PRs.
- `mcp/` wraps the bouncer as an npm-published MCP server (`@alanshurafa/co-evolution-mcp`).
- `evals/` is the portable eval harness (deterministic scorer + blind-judge tooling); `runners/codex-ps/` is a read-only reference copy of the original PowerShell implementation.

## Languages And Formats

- Bash is the primary tracked programming language: `agent-bouncer/agent-bouncer.sh`, `co-evolve-bouncer.sh`, `dev-review/codex/dev-review.sh`, `lib/co-evolution.sh`, and 31 hermetic simulation/scorer scripts under `tests/`.
- Node/TypeScript backs the MCP server package in `mcp/`, published to npm.
- Markdown is the dominant artifact format: `README.md`, `AGENTS.md`, `BOUNCE-PROTOCOL.md`, per-component READMEs, and all prompt/template files.
- JSON Schema constrains verification output (`schemas/review-verdict.json` and its two mirrored copies).
- Ignore metadata lives in `.gitignore` and `.agentignore`.

## Runtime Dependencies

- `agent-bouncer/agent-bouncer.sh` and the Codex runtime assume a POSIX shell plus standard utilities such as `date`, `head`, `tr`, `cp`, `mv`, `rm`, `wc`, `awk`, `tee`, `mkdir`, and `cat`; portability across bash 3.2 (macOS) and 5.2 (Linux) is a maintained constraint.
- Both runners depend on authenticated AI CLIs: `claude` and `codex`.
- The Claude adapter resolves model aliases in `lib/co-evolution.sh` (`best`/`opus` → `claude-opus-4-8`, `fable` → the Fable line), overridable via the `CLAUDE_MODEL` env var or the `--claude-model` flag — it is not hard-coded to a single pinned model.
- The Codex adapter is hard-coded to `codex exec --full-auto --skip-git-repo-check`.
- `skills/dev-review/SKILL.md` and `skills/codex-build/SKILL.md` assume Claude Code tooling, `git`, and optionally `gh` for PR creation.
- `evals/` and the `lab/pel/` eval-scoring path require the mikefarah/Go `yq` (v4+) — not the Python `yq` from `apt install yq`, which is incompatible — plus `xxd` for byte-level diagnostics.

## Build And Packaging

- There is no root `package.json`, `pyproject.toml`, `Cargo.toml`, or `go.mod` — the default runner surface stays shell-native.
- `mcp/` is a self-contained Node package (`package.json`, `tsconfig.json`) with its own lockfile, published on git-tag push via `.github/workflows/publish-mcp.yml`.
- CI runs on 3 OSes via `.github/workflows/ci.yml`, executing `tests/run-all.sh` plus the MCP Node smoke job.
- Distribution: file-copy for the shell surface (clone the repo, or copy `skills/` into a Claude Code skills directory) and npm install for `@alanshurafa/co-evolution-mcp`.

## Storage And Generated State

- Generated bounce artifacts are written under `runs/`.
- `.gitignore` marks `runs/` as generated output, so run logs and bounced documents stay local by default.
- The bouncer mutates the input plan file in place and also writes a clean final copy, `state.json`, and scorer/adjudication receipts plus per-pass raw outputs into `runs/bouncer-*/`.

## Practical Takeaway

- The repo is best understood as two shell-based orchestrators (a general-purpose bouncer and a code-focused Codex runtime) sharing one helper library, wrapped by a Claude Code skill layer, an MCP distribution package, and a portable eval harness.
- Operational correctness depends more on CLI behavior, prompt quality, and file contracts than on a compiled application runtime.
