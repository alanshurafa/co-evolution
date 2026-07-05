# Co-Evolution - Cross-AI Document Refinement

Tools for bouncing questions, documents, plans, and code workflows between AI
agents using structured `[CONTESTED]` / `[CLARIFY]` markers until convergence.

## Default Rule

Three routes, lowest-ceremony first:

- **co-evolution** (default) — bounce protocol for questions, drafts, plans,
  specs, arguments, and markdown refinement.
- **dev-review** — interactive code pipeline (compose → bounce → execute →
  verify in one session) when the user wants repo files changed, a bug fixed, a
  feature implemented, or a code diff verified against a plan.
- **codex-build** — "build with codex": the session plans and reviews, Codex
  executes detached, with check-ins only at gates. Reach for this when the user
  wants Codex to grind on a build in the background while the session stays free
  (the model-ladder flavor of dev-review).

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
```

### Agent Bouncer (`agent-bouncer/`)

Legacy runner (still used by tests/experiments) that bounces any markdown
document between two agents.

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

### Codex-Build Skill (`skills/codex-build/`)

Detached orchestration skill: the session (typically Opus) plans and reviews,
Codex executes in the background, and the session is woken at gates instead of
babysitting. Kicks `dev-review.sh --preset codex-build` via a background task,
ends the turn, then runs a schema-bound ACCEPT / REVISE / ESCALATE gate on wake.

```text
/codex-build Have codex implement the retry wrapper while I review
```

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
- Bounce stops after MAX_BOUNCES=2 passes; unresolved markers are reported in the output, not auto-expired
- Agent-bouncer overwrites the input file in place; orchestrators should back up first

## Status

- v1.4 npm/MCP publish pending — a human gate, not yet shipped.
- v1.5 Phase 6 partial — degrade-path dogfood only; the rest is unbuilt.
- Current default Claude model is `claude-opus-4-6` (overridable via `CLAUDE_MODEL` / `--claude-model`).
