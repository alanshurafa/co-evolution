# Co-Evolution - Cross-AI Document Refinement

Tools for bouncing questions, documents, plans, and code workflows between AI
agents using structured `[CONTESTED]` / `[CLARIFY]` markers until convergence.

## Default Rule

Use general co-evolution by default. Reach for `dev-review` only when the user
specifically wants repo files changed, a bug fixed, a feature implemented, or a
code diff verified against a plan.

## Components

### Co-Evolution Skill (`skills/co-evolution/`)

Default Claude Code skill for questions, ideas, drafts, plans, specs, arguments,
prompts, and markdown document refinement.

```text
/co-evolution Stress test this launch plan
```

### Co-Evolve Bouncer (`co-evolve-bouncer.sh`)

Primary standalone runner. It can compose from a prompt, bounce an existing
document, or run staged critique -> defend -> tighten passes.

```bash
bash ./co-evolve-bouncer.sh --vanilla "What is the strongest version of this argument?"
bash ./co-evolve-bouncer.sh --vanilla --bounce-only docs/plan.md
bash ./co-evolve-bouncer.sh --vanilla --chain "Should we ship this migration?"
bash ./co-evolve-bouncer.sh --vanilla --single-model "Stress test this" # both roles on claude
```

`--single-model [claude|codex]` pins both roles onto one agent (bare two-role
mode by default — empirical winner on dense technical docs per 2026-05-24 A/B).
Use when only one model is available, or to A/B against cross-model runs.

Add `--persona-discipline` to prepend the divergence preface
(`templates/co-evolve/single-model-preface.md`) that asks the model to
deliberately read against its own prior turn. Best paired with compose-then-
bounce of your own draft, where the shared-author bias actually applies.
On `--bounce-only` of external docs the preface tends to suppress the model's
natural investigatory impulse — use bare mode there.

### Agent Bouncer (`agent-bouncer/`)

Legacy standalone script that bounces any markdown document between two agents.

```bash
bash agent-bouncer/agent-bouncer.sh <document.md> [max-bounces] [reviewer-agent] [composer-agent]
```

- Default: 2 passes, Claude as reviewer, Codex as composer
- Output: `runs/bouncer-{name}-{timestamp}/` with per-pass artifacts and clean final output
- Most value comes in the first 2 passes

### Dev-Review Skill (`skills/dev-review/`)

Code-focused compose-bounce-execute-verify pipeline integrated with Claude Code.

```text
/dev-review [--composer opus|codex] [--executor opus|codex] [--bounces N|auto] [--verify] [--live] <code task>
```

Key flags: `--skip-plan` executes a pre-existing plan, `--plan-only` stops after
bounce, and `--live` opens visible Windows terminals for Codex passes.

### Codex Runtime (`dev-review/codex/`)

Standalone Bash runtime for the code-focused compose-bounce-execute-verify flow
outside Claude Code.

- Entry script: `dev-review/codex/dev-review.sh`
- Codex routing doc: `dev-review/codex/instructions.md`
- Shares `skills/dev-review/templates/` and `skills/dev-review/schemas/` as the prompt contract

### Templates

- `templates/co-evolve/` - general co-evolution role and chain prompts
- `agent-bouncer/templates/bounce-protocol.md` - core marker protocol
- `skills/dev-review/templates/` - code execution and verification prompts

### Schemas

- `skills/dev-review/schemas/review-verdict.json` - structured JSON schema for verification verdicts

## GSD Integration

Co-evolution tools are integrated into GSD workflows:

- `/gsd:plan-phase --bounce` bounces `PLAN.md` through agent-bouncer after plan-checker passes
- `/gsd:execute-phase --cross-ai` delegates plan execution to dev-review's code pipeline
- `/gsd:ship --review` uses Codex plus the review-verdict schema for a code review gate before PR

## Conventions

- Plan content is embedded inline in prompts, never passed as a canonical file path
- Markers auto-expire after 2 passes to guarantee convergence
- Agent-bouncer overwrites the input file in place; orchestrators should back up first
