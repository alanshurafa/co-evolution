# /dev-review - Notes for Humans

## What This Does

Automates your workflow of bouncing plans and code between Claude Code (Opus) and
Codex. Instead of manually copying between two desktop apps, one command handles:

1. **Compose** - One agent creates the initial plan
2. **Bounce** - The plan bounces between agents, each editing it directly with
   [CONTESTED]/[CLARIFY] markers for disagreements and ambiguities
3. **Execute** - The designated agent writes the actual code
4. **Verify** (optional) - The other agent reviews the code against the plan

If you add `--live` on Windows, each Codex pass opens in a visible PowerShell
window. You can watch progress live while `/dev-review` waits for that pass to
finish, then the workflow resumes normally from the same prompt/output files.

## Your Workflow Automated

What you do now manually:

```text
Opus writes plan -> copy to Codex -> Codex reviews/edits -> copy back to Opus ->
Opus refines -> copy to Codex -> Codex refines -> copy back to Opus -> Opus executes
```

What `/dev-review` does:

```text
/dev-review --composer opus --executor opus --bounces 4 --verify Build a dashboard
```

Same 5-agent-pass workflow. Zero copy-paste.

## Quick Start

```text
# Your usual: Opus plans (3 passes), Codex reviews (2 passes), Opus executes
/dev-review --composer opus --executor opus --bounces 4 Build an API metrics dashboard

# Reverse: Codex plans (3 passes), Opus reviews (2 passes), Codex executes
/dev-review --composer codex --executor codex --bounces 4 Add retry logic to API client

# Quick 2-bounce, Codex executes (default)
/dev-review Fix the date parsing bug

# Quick 2-bounce with visible Codex windows on Windows
/dev-review --live --bounces 2 Fix the date parsing bug

# Just plan, don't execute yet (review the plan yourself first)
/dev-review --plan-only Design the notification system architecture

# Skip planning, just build and verify
/dev-review --skip-plan --verify Rename getUserData to fetchUserProfile
```

## How the Bounce Works

The plan is a single living document. Each pass, the receiving agent:
- **Agrees** -> improves the text directly
- **Disagrees** -> adds `[CONTESTED]` below the line with a counter-argument
- **Confused** -> adds `[CLARIFY]` with two interpretations or a question
- **Resolves** any markers from the previous pass

After the bounces, the plan reads clean - as if one person wrote it. No tracked
changes, no revision history, no conversation clutter.

Markers must resolve within 2 passes. If stuck, the agent makes a decision.

## Parameters

| Flag | Default | What it does |
|------|---------|-------------|
| `--composer opus\|codex` | opus | Who creates the initial plan |
| `--executor opus\|codex` | codex | Who writes the final code |
| `--bounces N` | 4 | Total passes (4 = 2 round trips) |
| `--verify` | off | Final code review after execution |
| `--worktree` | off | Isolate work in a git worktree |
| `--model MODEL` | Codex default | Override Codex model |
| `--skip-plan` | off | Jump straight to execution |
| `--plan-only` | off | Stop after bounce phase |
| `--live` | off | Open a visible Windows PowerShell window for each Codex pass; falls back to headless if unavailable |

## Live Mode

`--live` changes launch mode only. It does not change the artifact contract:
- Claude Code still writes prompt files to disk
- Codex still writes its final message to disk
- Claude Code still reads those files before moving to the next phase

Behavior:
- Windows only for the first release
- One visible terminal window per Codex pass
- Window title reflects the phase, for example `Codex - Compose` or `Codex - Bounce 1/2`
- The window stays open for about 5 seconds after Codex finishes, then closes automatically
- If the launcher cannot be resolved, `/dev-review` warns once and continues headless
- If you close the live window yourself before completion, the session treats that pass as interrupted instead of hanging

## Cost Awareness

Each Codex pass = 1 `codex exec` call = OpenAI API tokens.

| Workflow | Codex calls | Notes |
|----------|-------------|-------|
| Default (Opus compose, 4 bounces, Codex execute) | ~3 | 2 Codex review passes + 1 execute |
| Reverse (Codex compose, 4 bounces, Codex execute) | ~4 | 1 compose + 2 review + 1 execute |
| With --verify | +1-2 | Additional review pass |
| Plan-only | ~2 | Just the bounce Codex passes |

When Opus handles a pass, it uses Claude tokens (your Claude plan). No OpenAI spend.

## When to Use What

| Scenario | Config | Why |
|----------|--------|-----|
| Building something new | `--composer opus --executor codex` | Opus plans well, Codex executes fast |
| Opus-heavy (your usual) | `--composer opus --executor opus --bounces 4` | Opus plans AND executes, Codex reviews |
| Codex-heavy (your reverse) | `--composer codex --executor codex --bounces 4` | Codex plans AND executes, Opus reviews |
| Quick fix | `--bounces 2` | Short bounce, fast execution |
| Quick fix with visible Codex windows | `--live --bounces 2` | Same workflow, but you can watch each Codex pass |
| Big feature | `--bounces 6 --worktree --verify` | Thorough planning, isolated, verified |
| Experimental | `--plan-only` | Get the plan, decide execution later |

## The [CONTESTED]/[CLARIFY] Protocol

This is the coordination mechanism that replaces conversation history:

**[CONTESTED]** - "I disagree with this line." Must include:
- A counter-argument
- A concrete example

The next agent either resolves it (edits the line, removes the note) or
strengthens the counter-argument.

**[CLARIFY]** - "This is ambiguous." Must include:
- Two possible interpretations, OR
- A specific question

The next agent picks an interpretation, revises the line, removes the note.

Both types auto-expire: if unresolved after 2 passes, the current agent decides.

## Alternatives for Different Needs

If this skill doesn't fit a particular situation:

- **AgentPipe** (github.com/kevinelliott/agentpipe) - Interactive conversation relay.
  Use when you want to watch agents talk in real-time rather than run headless.
- **AgentAPI** (github.com/coder/agentapi) - HTTP API wrapping for agents.
  Use when you need 3+ agents, CI integration, or remote agents.
- **/gsd:review** - Your existing GSD cross-AI review for plans. Use when you're
  already in a GSD workflow and want peer review of phase plans.

## Files

```text
~/.claude/skills/dev-review/
  SKILL.md                          # Orchestration logic (compose->bounce->execute)
  schemas/review-verdict.json       # JSON schema for verification verdicts
  templates/
    bounce-protocol.md              # The [CONTESTED]/[CLARIFY] bounce instructions
    dev-prompt-opus.md              # Execution instructions for Opus
    dev-prompt-codex.md             # Execution instructions for Codex
    review-prompt-opus.md           # Verification instructions for Opus
    review-prompt-codex.md          # Verification instructions for Codex
  notesforhumans.md                 # This file
```
