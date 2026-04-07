# Co-Evolution Codex Runtime

`dev-review/codex/dev-review.sh` is the standalone Bash runtime for the Co-Evolution `dev-review` workflow. It lets Codex compose a plan, bounce it with the other agent, execute the work, and optionally run a verification pass without going through the Claude Code skill.

## When To Use It

Use this runtime when the task is a real repo change and you want more structure than direct execution:

- compose a fresh plan from a task description
- bounce the plan before code changes start
- execute against a specific `--workdir`
- reuse an approved plan with `--skip-plan --plan`
- optionally review the resulting diff with `--verify`

If the output is only a markdown document, use `agent-bouncer/agent-bouncer.sh` instead. If the task is tiny and low risk, execute directly without the full pipeline. See [instructions.md](instructions.md) for the routing rules.

## Quick Start

```bash
# Compose, bounce, execute
bash dev-review/codex/dev-review.sh "Add smoke-test notes for the Codex runtime"

# Compose, bounce, execute, then verify
bash dev-review/codex/dev-review.sh --verify "Document runtime exit codes"

# Produce the plan artifact only
bash dev-review/codex/dev-review.sh --plan-only "Draft the rollout notes for the next runtime pass"

# Execute an approved plan file
bash dev-review/codex/dev-review.sh --skip-plan --plan .planning/phases/04-docs-and-routing/04-01-PLAN.md
```

## CLI Options

| Flag | Meaning |
|------|---------|
| `--composer opus|codex` | Choose who writes the initial plan |
| `--executor opus|codex` | Choose who executes the approved plan |
| `--bounces N|auto` | Use a fixed pass count or auto-converge up to 6 passes; `auto` exits `2` and skips execution if markers remain after the budget (changed from prior behavior which warned and continued) |
| `--verify` | Run a verifier pass after execution |
| `--plan-only` | Stop after compose + bounce and keep the plan artifact |
| `--skip-plan` | Skip compose + bounce and execute an existing plan |
| `--plan FILE` | Plan file used with `--skip-plan` |
| `--model MODEL` | Override the Codex model for Codex-backed passes |
| `--workdir DIR` | Execute against a target working directory |

## Common Workflows

### Safe first pass

```bash
bash dev-review/codex/dev-review.sh --plan-only --bounces 2 "Refactor the runtime README"
```

Use this for medium- or high-risk tasks when you want to inspect the bounced plan before any code changes happen.

### Plan reuse after approval

```bash
bash dev-review/codex/dev-review.sh \
  --skip-plan \
  --plan .planning/phases/04-docs-and-routing/04-01-PLAN.md \
  --workdir C:/Users/alan/Project/co-evolution
```

This is the clean handoff path once a plan has already been reviewed or bounced elsewhere.

### Verification-aware run

```bash
bash dev-review/codex/dev-review.sh --verify "Tighten the runtime docs"
```

`--verify` compares the executed work to the plan through the verifier prompt. When execution starts from a clean repo state, the runtime diffs from the pre-execute baseline to the current worktree so the verifier sees committed and uncommitted tracked changes from the same run together. If the repo was already dirty before execution started, or the run leaves untracked files behind, verification exits `2` instead of guessing which changes belong to this run.

Verifier auth failures, malformed JSON, fenced-plus-prose responses, and contradictory verdicts are surfaced as review-needed `exit 2` paths instead of being treated as successful verification.

## Using It With Codex Startup Instructions

The companion router file is [instructions.md](instructions.md). Point Codex at that file when you want it to choose between direct execution, `agent-bouncer.sh`, and `dev-review.sh` before it starts.

If your Codex wrapper supports an `--instructions` flag, point it at `dev-review/codex/instructions.md`. A portable fallback is to feed the same file through stdin before the task prompt:

```bash
Get-Content -Raw dev-review/codex/instructions.md | codex exec -C C:/Users/alan/Project/co-evolution -
```

## Workdir And Trust Caveats

- The runtime uses unattended `codex exec --full-auto --skip-git-repo-check` for Codex-backed passes. Only point it at a repo or sandbox you trust.
- Set `--workdir` explicitly when running from outside the target repo so execution does not happen in the wrong directory.
- Under WSL, Codex-backed calls are routed through `cmd.exe /c codex` and the runtime normalizes Windows paths for `--workdir` and `--plan`.
- If the work is risky, prefer `--plan-only` first and only rerun with execution after the plan is approved.

## Exit Behavior

- `0`: success
- `1`: fatal runtime failure
- `2`: review-needed path, including compose/bounce auth or error payloads, invalid plan artifacts after retry, auto-bounce non-convergence, no-op execute runs, dirty-start or untracked-file verification, revise verdicts, or unusable verifier output

## How This Fits The Repo

- `agent-bouncer/` is the generic markdown bounce engine.
- `skills/dev-review/` is the Claude Code `/dev-review` skill and remains the Claude-side runtime.
- `dev-review/codex/` is the standalone Codex runtime surface built on the same prompt and schema assets under `skills/dev-review/`.
