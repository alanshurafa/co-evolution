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
bash ./co-evolve-bouncer.sh --vanilla --adversarial --bounce-only docs/plan.md
bash ./co-evolve-bouncer.sh --vanilla --adversarial --agents claude,claude "Same-model adversarial review"
```

`--adversarial` swaps the reviewer's 1-line role for a structured falsification
persona (vendored from the compound-engineering adversarial-document-reviewer;
templates/co-evolve/role-reviewer-adversarial.md). Cross-AI by default; with
`--agents claude,claude` it is an internal same-model adversarial review. Pair
with `--chain` or `--bounces 3` on dense documents (marker-flooding risk).

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
- Convergence is honest, never forced-silent. A `co-evolve-bouncer.sh` run ends in one of three recorded states (`state.json.convergence_status`): **converged** (markers hit 0 within the configured passes), **adjudicated** (markers survived, so one forced-adjudication pass resolved each one and wrote `adjudication-report.md` mapping every stripped marker to the chosen text + a one-line rationale), or **stuck** (adjudication could not defensibly resolve every marker — the working document is preserved WITH its markers, labeled NOT-final, and fails the scorer gate). A naturally-converging run is byte-identical to the pre-adjudication bouncer; the adjudication pass fires only when markers survive. Exit semantics by design: a stuck document run still exits 0 — the `CO-EVOLVE:STUCK` label and the failing scorer gate carry the signal, not the exit code; only `--execute` refuses a stuck plan, with exit 1.
- Agent-bouncer overwrites the input file in place; orchestrators should back up first

## Status

- v1.4 npm/MCP publish pending — a human gate, not yet shipped.
- v1.5 Phase 6 partial — degrade-path dogfood only; the rest is unbuilt.
- Current default Claude model is `claude-opus-4-8` (the `best` alias; overridable via `CLAUDE_MODEL` / `--claude-model`).

## Model Routing

Seats and defaults (env/flag overridable; state.json `seat_models` must always show a concrete model for preset seats):

| Work | Component | Model |
|------|-----------|-------|
| Code execution + mechanical verify | dev-review executor seat (`codex exec`) | `gpt-5.5` @ `xhigh` — pinned in presets, not inherited from local config.toml |
| Plan composition | dev-review composer seat / document composer role | `best` alias → `claude-opus-4-8` @ high |
| Verification verdicts | dev-review verifier seat | codex-build: opus @ max; claude-build: `gpt-5.5` @ xhigh |
| Bounce critique (document pipeline reviewer role) | co-evolve-bouncer | `gpt-5.5` @ xhigh via codex (cross-vendor disagreement is the point) |
| Accept / bounce / escalate decisions, adjudication passes | orchestrating session | fable-5 preferred, opus-4.8 acceptable |
| Plan review before execution | session or `/codex:adversarial-review` | fable-5 or opus-4.8; optionally add a gpt-5.5 pass as an independent second perspective |
| Blind quality judging | `evals/judge-bounce.sh` | fable-5 @ high (existing default) |
| Glue/scout subagents inside Claude Code | Agent tool | sonnet-5; **Haiku is not used anywhere in this repo** (workspace-level Haiku automations elsewhere are unaffected) |

Rules:
- These are defaults, not limits. Standing permission: if a cheaper model's output misses the bar, redo with a smarter model without asking. Judge the output, not the price tag.
- When axes conflict on anything that ships: intelligence > taste > cost. Cost is a tie-breaker only.
- Bulk/mechanical work (clear-spec implementation, migrations, data transforms) → gpt-5.5. It is cheap under the Codex plan but **not free**: the codex-guard daily cap applies; batch calls, never poll-loop them.
- Anything user-facing (docs prose, README, API/CLI surface design) needs high taste → opus-4.8 or fable-5 authors/reviews it.
- gpt-5.5 is reachable only through the Codex CLI (`codex exec`, `codex review`). Inside Agent/Workflow calls (model param takes Claude models only), use the wrapper pattern: a thin sonnet wrapper agent (effort low) that writes a self-contained codex prompt, runs `codex exec` via Bash (`-s read-only` for investigation work), and returns only the final message.

### Seat selection

The document pipeline can use four agents: `claude`, `codex`, `glm` (GLM-5.3-Flash through Z.AI), and `kimi` (Kimi K3 through Kimi Code). Choose seats with the procedure below instead of treating today's roster as policy. When another agent arrives, run the same procedure again.

**Step 1: classify the run.** Classify its stakes as user-facing, internal, or throwaway. Then classify the task as draft, critique, adjudicate, execute, or verify. Both dimensions affect the panel; a throwaway critique does not need the same seats as a spec that will ship.

**Step 2: assign seats by constraint, in order.**

1. The adjudicator or orchestrator is the highest-trust model with the full session context. Today that is the session Claude, preferably fable-5 and otherwise opus-4.8. Document-only seats never adjudicate.
2. The reviewer comes from a different vendor than the composer. The point of the bounce is to surface cross-vendor disagreement. If Claude composes, Codex, GLM, or Kimi can review.
3. Fill any remaining seats cheapest-first (`kimi`, then pay-as-you-go `glm`). If an output misses the bar, escalate that seat without asking. Judge the output, not its price.
4. Break ties in this order: intelligence > taste > cost. Cost matters only when the other factors are equal.

**Step 3: size the panel.** Use one reviewer for routine documents. For high-stakes work, run two independent critique chains with the `--agents` order flipped. A third cross-vendor pass can be low-cost; for example, `--agents claude,glm` adds a GLM critique.

The table below is a worked result of the procedure, not a canonical assignment. Re-run the steps when the roster or task changes.

| Role | Current agent | Reason |
|------|---------------|--------|
| Adjudicator / orchestrator | session Claude (fable-5 or opus-4.8) | Holds the full context and meets the trust bar |
| Composer | `claude` (`best` resolves to opus-4.8) | Strong fit for user-facing prose |
| Primary reviewer | `codex` (`gpt-5.5` at xhigh) | Different vendor from the default composer |
| Extra reviewer | `glm` (`glm-5.3-flash`) | Low-cost cross-vendor critique through Z.AI |
| Alternate extra reviewer | `kimi` (Kimi K3) | Another free cross-vendor critique when a second read helps |

The dev-review executor and verifier do not change. Code execution stays on `codex` (`gpt-5.5`), with verification on opus or `gpt-5.5` according to the preset. GLM and Kimi are document-pipeline seats in this phase; they do not enter the execution or verification paths. See [docs/agent-seats.md](docs/agent-seats.md) for account, launcher, and web chat setup.

## Token Discipline

Return contracts (a wall of raw output is a failed task even when the work was correct):
- Scout/discovery reports: <=15 lines; file:line refs + one-sentence facts; never pasted file contents.
- Build reports: <=20 lines; files + line ranges changed, what was run to verify, pass/fail; diffs only when <=30 lines.
- Deep review reports: <=40 lines, conclusion first.
- Test/lint runs report failures only; passing output is one line ("N passed").
- Verifier verdicts: `summary` <=40 words; <=5 `issues`, one line each with file:line.

Working style:
- Grep before read. Read line ranges, not whole files. Never re-read an unchanged file already in context.
- Noisy operations (tests/run-all.sh, log inspection, large-file summaries) run in an isolated subagent so only the summary reaches the main thread. Gate decisions read `dev-review-status.sh --json`, never raw runner logs.
- Escalation ladder: one retry with a tighter prompt, then escalate upward carrying the prior failure evidence. Disagreements resolve upward, never re-litigated sideways. Ambiguity in high-risk areas — path normalization, git history, anything under runners/codex-ps/ — stops and surfaces immediately.

Delegation template (exactly four parts, nothing else):
1. **Goal** — one sentence.
2. **Scope** — in bounds and explicitly out of bounds.
3. **Contract** — which return format above.
4. **Done means** — the observable check.

## Interactive vs Pipeline Boundary

**Pipeline (scripted, reproducible, headless):** `co-evolve-bouncer.sh`, `dev-review/codex/dev-review.sh`, `runners/codex-ps/` (frozen reference). No plugin slash commands, no advisor tool, no live-session dependencies. Anything here must run unattended and produce stable output.

**Interactive (live Claude Code sessions on this repo):** the official Codex plugin (`openai/codex-plugin-cc`) is allowed and encouraged:
- `/codex:adversarial-review` before letting the bouncer pass a risky plan.
- The `codex:codex-rescue` subagent when a session is stuck.
- `/codex:transfer` to hand work between Claude and Codex; `/codex:status` / `/codex:result` / `/codex:cancel` for job control.
- The review gate (Stop hook) stays **off** (`/codex:setup --disable-review-gate`): this repo already has a review engine; a second automatic one would loop against it and burn Codex usage.

**Advisor tool (Anthropic API beta, header `advisor-tool-2026-03-01`):** valid only inside API agent loops (Messages API `advisor_20260301`-type tool); never available to bash scripts, `claude -p`, or Claude Code sessions. If/when this repo grows an API-driven layer, pair a Sonnet executor with an **opus-4.8 advisor** — its advice returns readable and can be logged in the dev-review trail; a fable-5 advisor returns encrypted advice that cannot be audited. Timing discipline: consult before the first write, when stuck, and before declaring work done.
