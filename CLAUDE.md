# Co-Evolution — Cross-AI Document Refinement

Tools for bouncing documents and plans between AI agents (Claude + Codex) using structured [CONTESTED]/[CLARIFY] markers until convergence.

## Components

### Agent Bouncer (`agent-bouncer/`)
Standalone bash script that bounces any markdown document between two agents.

```bash
bash agent-bouncer/agent-bouncer.sh <document.md> [max-bounces] [reviewer-agent] [composer-agent]
```

- Default: 2 passes, Claude as reviewer, Codex as composer
- Output: `runs/bouncer-{name}-{timestamp}/` with per-pass artifacts and clean final output
- Most value comes in the first 2 passes

### Dev-Review Skill (`skills/dev-review/`)
Full compose-bounce-execute-verify pipeline integrated with Claude Code.

```
/dev-review [--composer opus|codex] [--executor opus|codex] [--bounces N|auto] [--verify] [--live] <task>
```

Key flags: `--skip-plan` (execute pre-existing plan), `--plan-only` (stop after bounce), `--live` (visible Windows terminals).

### Codex Runtime (`dev-review/codex/`)
Standalone Bash runtime for the same compose-bounce-execute-verify flow outside Claude Code.

- Entry script: `dev-review/codex/dev-review.sh`
- Codex routing doc: `dev-review/codex/instructions.md`
- Shares `skills/dev-review/templates/` and `skills/dev-review/schemas/` as the prompt contract
- Leaves the Claude-side `/dev-review` skill implementation untouched; this is an additional runtime surface, not a replacement

### Templates (`skills/dev-review/templates/`)
- `bounce-protocol.md` - core marker protocol
- `dev-prompt-opus.md` / `dev-prompt-codex.md` - execution prompts
- `review-prompt-opus.md` / `review-prompt-codex.md` - verification prompts

### Schemas (`skills/dev-review/schemas/`)
- `review-verdict.json` — structured JSON schema for verification verdicts (APPROVED/REVISE)

## GSD Integration
Co-evolution tools are integrated into GSD workflows:
- `/gsd:plan-phase --bounce` — bounces PLAN.md through agent-bouncer after plan-checker passes
- `/gsd:execute-phase --cross-ai` — delegates plan execution to dev-review's cross-AI pipeline
- `/gsd:ship --review` — uses Codex + review-verdict schema for code review gate before PR

## Conventions
- Plan content is always embedded inline in prompts, never passed as file paths (prevents Codex from modifying the canonical plan directly)
- Markers auto-expire after 2 passes to guarantee convergence
- Agent-bouncer overwrites the input file in place; orchestrators should back up first
