# Co-Evolution Claude Code Skill

`/dev-review` — a Claude Code skill that wraps the co-evolution bounce protocol in a full compose-bounce-execute-verify workflow.

## What It Does

Unlike the Agent Bouncer (which only bounces documents), the skill runs the complete pipeline inside Claude Code:

1. **Compose** — One agent creates the initial plan from your task description
2. **Bounce** — The plan bounces between agents with `[CONTESTED]`/`[CLARIFY]` markers until refined
3. **Execute** — The designated agent writes code from the converged plan
4. **Verify** (optional) — The other agent reviews the code diff against the plan

## Usage

Inside Claude Code:

```text
# Default: Opus composes, Codex reviews, auto-converge, Codex executes
/dev-review Build a dashboard for API metrics

# Opus-heavy: Opus composes AND executes, Codex reviews
/dev-review --composer opus --executor opus --bounces 4 Add retry logic

# Plan only: stop after bounce, don't execute
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
| `--bounces N\|auto` | auto | Pass count or auto-converge (up to 6) |
| `--verify` | off | Code review after execution |
| `--worktree` | off | Isolate work in a git worktree |
| `--model MODEL` | Codex default | Override Codex model |
| `--skip-plan` | off | Jump straight to execution |
| `--plan-only` | off | Stop after bounce phase |
| `--live` | off | Visible PowerShell window per Codex pass (Windows) |

## How It Differs from the Agent Bouncer

| | Agent Bouncer | Skill |
|---|---|---|
| Runs in | Any terminal | Claude Code only |
| Phases | Bounce only | Compose + Bounce + Execute + Verify |
| Agents | Any adapter | Claude Code (Opus) + Codex CLI |
| Code execution | No | Yes |
| Artifact saving | Always (runs/) | On request (--save-run) |
| Live mode | No | Yes (--live, Windows) |

## Installation

Copy the `skill/` directory to your Claude Code skills location:

```bash
cp -r skill/ ~/.claude/skills/dev-review/
```

The skill will be available as `/dev-review` in Claude Code.

## Files

```
skill/
  SKILL.md                          — orchestration logic (Claude reads this)
  schemas/
    review-verdict.json             — JSON schema for verification output
  templates/
    bounce-protocol.md              — core bounce protocol
    bounce-prompt-portable.md       — alternate bounce prompt
    dev-prompt-opus.md              — execution instructions for Opus
    dev-prompt-codex.md             — execution instructions for Codex
    review-prompt-opus.md           — verification instructions for Opus
    review-prompt-codex.md          — verification instructions for Codex
```

## Cost Awareness

Each Codex pass = one `codex exec` call = OpenAI API tokens. Opus passes use Claude tokens.

| Workflow | Codex calls |
|----------|-------------|
| Default (Opus compose, 4 bounces, Codex execute) | ~3 |
| With --verify | +1-2 |
| --plan-only | ~2 |
