# Dev-Review Claude Code Skill

`/dev-review` is the code-focused Co-Evolution skill. It wraps the bounce
protocol in a compose -> bounce -> execute -> verify workflow for repo changes.

For general questions, drafts, arguments, plans, specs, or document refinement,
install and use `skills/co-evolution/` instead.

## What It Does

Unlike the general Co-Evolution skill, this skill runs the complete code pipeline
inside Claude Code:

1. **Compose** - One agent creates the initial implementation plan from your task description.
2. **Bounce** - The plan bounces between agents with `[CONTESTED]`/`[CLARIFY]` markers until refined.
3. **Execute** - The designated agent writes code from the converged plan.
4. **Verify** - Optional: the other agent reviews the code diff against the plan.

## Usage

Inside Claude Code:

```text
# Default: Opus composes, Codex reviews, auto-converge, Codex executes
/dev-review Build a dashboard for API metrics

# Opus-heavy: Opus composes and executes, Codex reviews
/dev-review --composer opus --executor opus --bounces 4 Add retry logic

# Plan only: stop after bounce, do not execute
/dev-review --plan-only Design the notification system

# With verification pass after execution
/dev-review --verify Fix the date parsing bug

# Watch Codex passes in visible terminal windows (Windows)
/dev-review --live --bounces 2 Fix a billing bug
```

## Flags

| Flag | Default | Effect |
|------|---------|--------|
| `--composer opus\|codex` | opus | Who creates the initial plan |
| `--executor opus\|codex` | codex | Who writes the final code |
| `--bounces N\|auto` | auto | Pass count or auto-converge, up to 6 |
| `--verify` | off | Code review after execution |
| `--worktree` | off | Isolate work in a git worktree |
| `--model MODEL` | Codex default | Override Codex model |
| `--skip-plan` | off | Jump straight to execution |
| `--plan-only` | off | Stop after bounce phase |
| `--live` | off | Visible PowerShell window per Codex pass on Windows |

## How It Differs From General Co-Evolution

| | Co-Evolution Skill | Dev-Review Skill |
|---|---|---|
| Runs in | Claude Code | Claude Code |
| Primary use | Answers, drafts, plans, documents | Repo code changes |
| Phases | Compose + Bounce | Compose + Bounce + Execute + Verify |
| Code execution | No | Yes |
| Default runner | `co-evolve-bouncer.sh` | `dev-review/codex/dev-review.sh` |

## Installation

Install this only when you want the code workflow:

```bash
mkdir -p ~/.claude/skills/dev-review
cp -R skills/dev-review/* ~/.claude/skills/dev-review/
```

The skill will be available as `/dev-review` in Claude Code.

## Files

```text
skills/dev-review/
  SKILL.md                          - orchestration logic
  schemas/
    review-verdict.json             - JSON schema for verification output
  templates/
    bounce-protocol.md              - core bounce protocol
    bounce-prompt-portable.md       - alternate bounce prompt
    dev-prompt-opus.md              - execution instructions for Opus
    dev-prompt-codex.md             - execution instructions for Codex
    review-prompt-opus.md           - verification instructions for Opus
    review-prompt-codex.md          - verification instructions for Codex
```

## Cost Awareness

Each Codex pass is one `codex exec` call. Opus passes use Claude tokens.

| Workflow | Codex calls |
|----------|-------------|
| Default: Opus compose, 4 bounces, Codex execute | about 3 |
| With `--verify` | +1 to 2 |
| `--plan-only` | about 2 |
