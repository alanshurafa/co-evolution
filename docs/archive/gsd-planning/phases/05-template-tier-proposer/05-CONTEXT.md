# Phase 5: Template-Tier Mutation Proposer - Context

**Gathered:** 2026-04-18
**Status:** Ready for planning
**Source:** Delegated-autonomous (CLAUDE.md Express — ROADMAP SC-1..SC-4 + pel-design-decisions.md §§1,3 + Phase 4 classifier precedent)

<domain>
## Phase Boundary

Build `lab/pel/proposer/template/` — the **template-tier mutation proposer**. First of three proposer tiers (safest). Given an eval-failure report (from Phase 2's harness) + a target template path + a flavor pick (from Phase 4's classifier), produces a **well-formed unified diff** against exactly ONE `skills/dev-review/templates/*.md` file per invocation. LLM-driven (no random search — natural-language mutation isn't safe otherwise).

In scope:
- `lab/pel/proposer/template/proposer.sh` — public entry point
- `lab/pel/proposer/template/adapter.sh` — self-contained Opus-4.7 adapter (lab isolation)
- `lab/pel/proposer/template/prompt.md` — mutation-proposer prompt (flavor-aware, single-mutation-constrained)
- `tests/template-proposer-simulation.sh` — hermetic simulation covering SC-4
- `lab/pel/proposer/README.md` (or extend existing `lab/pel/README.md`) — proposer-tier env var contract
- Synthetic eval-failure fixtures under `tests/fixtures/eval-failures/*.json` (3-5 plausible failures)
- Synthetic template copies under `tests/fixtures/templates/*.md` (copies of real templates for hermetic testing)

Out of scope (explicit):
- Policy-tier proposer (Phase 6 — parallelizable)
- Code-tier proposer (Phase 7 — hardest, has sandbox + canary requirements)
- PR emission / scoring loop (Phase 8)
- Scoring the proposed diffs (proposer EMITS diffs; scorer is part of Phase 8's pipeline)
- Multi-file mutations (v1.2 constraint: exactly one file per invocation)
- Mutating anything except `skills/dev-review/templates/*.md` (policy + code tiers are separate phases)

</domain>

<decisions>
## Implementation Decisions

### Lab isolation & invocation surface

- **D-01 — Lives under `lab/pel/proposer/template/`** (parallel to `lab/pel/classifier/`). Mirrors Phase 4's structure: separate `proposer.sh` + `adapter.sh` + `prompt.md`. No sourcing `lib/co-evolution.sh` or runner internals.
- **D-02 — Invocation: argv + env vars.** Task string via `$1` (what the user wants improved, free-form). Non-task inputs via env vars:
  - `PEL_EVAL_REPORT` — path to eval-failure JSON report (required)
  - `PEL_TEMPLATE_PATH` — path to target template .md file (required)
  - `PEL_FLAVOR` — one of `{bug-catcher, faster-converger, blind-spot-surfacer, general}` (required; typically sourced from classifier JSON)
  - `PROPOSER_MODEL` — optional override (default `claude-opus-4-7`)
- **D-03 — Missing required env var → die with specific message.** Unlike Phase 4's `unknown` degradation, this proposer requires complete inputs — the proposer is called internally by Phase 8's scoring loop which always provides all three. Missing = caller bug, should die.
- **D-04 — Task string via $1 is optional hint.** If empty, the proposer uses only the eval-failure report as signal. If present, it's incorporated as additional context (e.g., "focus the mutation on the bounce pass").

### LLM call path

- **D-05 — Self-contained adapter in `lab/pel/proposer/template/`.** Same pattern as Phase 4: adapter.sh owns the claude call. Zero dependency on `dev-review/codex/dev-review.sh`'s `invoke_claude`.
- **D-06 — Opus 4.7 default** (`claude-opus-4-7`), not Haiku. Rationale: mutation proposals are generative work with high quality bar (a bad mutation wastes eval cycles). Opus is worth the cost. Overrideable via `PROPOSER_MODEL` env var.
- **D-07 — Fail-fast on claude call failure.** Same posture as Phase 4 adapter: die with clear error if CLI missing, auth fails, rate-limited, or response malformed.

### Output format

- **D-08 — Unified diff to stdout.** Not JSON. The output IS a `diff`-format patch. Phase 8's scoring loop applies it with `git apply --check` (dry-run) before scoring. Diagnostics and logging go to stderr.
- **D-09 — Single-file constraint enforced in the proposer.** Before emitting the diff, the proposer parses it and rejects (die exit 4) if the diff touches more than one file OR touches anything outside `skills/dev-review/templates/`. This is a belt-and-suspenders check — the prompt also instructs single-file, but the check catches prompt drift.
- **D-10 — Diff must apply cleanly against the current template.** The proposer runs `git apply --check` internally against the target template before emitting. If `git apply --check` fails, the proposer dies exit 3 (malformed diff). Phase 8 gets a guaranteed-applyable diff or a clear error.

### Prompt architecture

- **D-11 — Prompt in separate file** (`prompt.md`) — mirrors Phase 4 D-10. Prompt-as-reviewable-asset, not string-literal-in-code. Cache-friendly: stable portion (instructions + flavor definitions + output format spec) ahead of variable portion (eval report + template content + flavor pick).
- **D-12 — Flavor-aware prompt.** The 4 flavor names from Phase 4's classifier have concrete meaning here:
  - `bug-catcher`: emphasize defect-detection patterns, adversarial cases, edge conditions
  - `faster-converger`: emphasize concision, fewer-rounds framing, early-exit triggers
  - `blind-spot-surfacer`: emphasize coverage of eval-DOESN'T-know-yet scenarios
  - `general`: balanced (treat as its own flavor per pel-design-decisions.md §1, NOT a neutral default)
  The prompt instructs the LLM to bias mutation toward the flavor's focus area.

### Simulation

- **D-13 — Hermetic with PATH-stubbed claude CLI.** Same pattern as Phase 4's classifier-simulation.sh. Stub returns canned diffs per scenario. Real claude API is never invoked during tests.
- **D-14 — Fixture strategy.** `tests/fixtures/eval-failures/*.json` holds 3-5 synthetic eval-failure reports (simulate Phase 2 scorer output schema). `tests/fixtures/templates/*.md` holds copies of real templates used as mutation targets. Both directories committed; test is deterministic.
- **D-15 — Simulation scenarios (SC-4):**
  - 4 scenarios: one per flavor, each produces a diff, each passes `git apply --check`
  - 1 scenario: diff touching 2 files → rejected with exit 4
  - 1 scenario: diff touching a non-template file → rejected with exit 4
  - 1 scenario: malformed diff (missing hunk header) → rejected with exit 3
  - 1 scenario: missing required env var → rejected with exit 1
  - Final line: `8/8 scenarios passed` (mirrors Phase 4's `6/6` + Phase 3's `4/4` + Phase 2's `13/13` convention)

### Claude's Discretion

- Exact prose of `prompt.md` — the LLM's mutation-proposer instructions. Researcher/planner writes based on pel-design-decisions.md §1 flavor definitions + typical mutation-as-diff framing.
- Exact structure of eval-failure JSON fixtures — must match Phase 2's scorer output schema (the scorer's JSON is the source-of-truth; fixtures mirror it).
- Whether to ship 3, 4, or 5 eval-failure fixtures.
- Exact exit code taxonomy beyond the 4 listed above. Suggest: 0 success, 1 input validation, 2 LLM call, 3 malformed diff, 4 multi-file violation.
- Whether `PEL_EVAL_REPORT` accepts a file path, a `-` for stdin, or both. Lean toward: file path only for v1.2 (simpler), stdin support deferred.
- Mutation dry-run flag (`--dry-run` prints prompt without calling claude) — useful for debug, not required for SCs.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design spec (binding)
- `.planning/notes/pel-design-decisions.md` §1 "Multi-flavor fitness" — 4 flavor definitions, the semantic of each. Drives the prompt's flavor-aware framing.
- `.planning/notes/pel-design-decisions.md` §3 "Mutable surface = templates + policy + code" — why templates are the safest first tier.
- `.planning/notes/co-evolution-lab-concept.md` — lab-isolation boundary.

### Project + milestone refs
- `.planning/ROADMAP.md` §Phase 5 — 4 success criteria.
- `.planning/REQUIREMENTS.md` §PEL-02.
- `.planning/PROJECT.md` Key Decisions: "LLM-only proposer for code tier" (template tier also LLM-only by extension; random mutation of prompts doesn't make sense either).

### Phase 4 integration (consumes classifier output)
- `.planning/phases/04-mode-classifier-frozen/04-CONTEXT.md` — flavor output schema (D-08 JSON includes `flavor` field). Proposer reads the flavor from the classifier's output when invoked by Phase 8.
- `lab/pel/classifier/classifier.sh` + `adapter.sh` + `prompt.md` — reference implementation patterns to mirror (self-contained adapter, path-based lab isolation, env-var contract).

### Phase 2 integration (eval harness output is the input)
- `evals/score-run.sh` — produces the JSON scoring output. The proposer's `PEL_EVAL_REPORT` input matches this schema.
- `evals/tests/scorer-verification.sh` — Phase 2's hermetic simulation style (PATH-stubbed runner).
- `.planning/phases/02-bash-eval-harness-port/02-03-SUMMARY.md` — scorer JSON shape reference.

### Templates being mutated (the target surface)
- `skills/dev-review/templates/compose-prompt.md`
- `skills/dev-review/templates/bounce-protocol.md`
- `skills/dev-review/templates/role-composer.md`
- `skills/dev-review/templates/role-reviewer.md`
- (and any others under `skills/dev-review/templates/*.md`)

### Analogous patterns (style mirroring)
- `lab/pel/classifier/` (Phase 4) — adapter + prompt + entry structure to mirror.
- `agent-bouncer/templates/` — prompt-as-file precedent.
- `tests/classifier-simulation.sh` (Phase 4) — hermetic simulation style with PATH-stubbed claude.

### Env var precedents
- `lib/co-evolution.sh` lines 19-34 — `: "${VAR:=default}"` default pattern.
- `lab/pel/classifier/classifier.sh` — PEL_BOUNCE_STEP / PEL_PHASE_TYPE / PEL_FLAVOR_OVERRIDE / CLASSIFIER_MODEL precedent.

### Platform assumptions
- `C:/Users/alan/.claude/projects/C--Users-alan-Project-co-evolution-lab/memory/future_tools.md` — Opus 4.7 (1M context) and prompt caching assumed infrastructure.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lab/pel/classifier/adapter.sh` — adapter shape template. Copy the overall structure; customize for diff-output instead of JSON-output, Opus instead of Haiku.
- `lab/pel/classifier/prompt.md` — prompt-as-file template. Structure: stable header + variable tail.
- `tests/classifier-simulation.sh` — simulation harness structure (per-scenario subshells, TOTAL/FAILURES counters, PATH-stubbed claude, `N/N scenarios passed` footer).
- `evals/score-run.sh` — JSON schema for eval reports that the proposer consumes.
- `skills/dev-review/templates/*.md` — the actual mutation targets. Copy a representative subset into `tests/fixtures/templates/` for hermetic testing.

### Established Patterns
- **Self-contained lab inhabitants** — Phase 4 precedent. Proposer follows same posture.
- **Prompt-as-file** — agent-bouncer and Phase 4 both use it. Proposer's prompt.md is stable (cache-friendly).
- **Simulation with PATH-injected stub CLI** — Phase 2 (fake-runner) and Phase 4 (stub claude). Phase 5 does the same.
- **`N/N scenarios passed` footer** — v1.2 gate convention (Phase 2: 13/13, Phase 3: 4/4, Phase 4: 6/6).

### Integration Points
- **Phase 8 (PR emitter) invokes this proposer** — calls `lab/pel/proposer/template/proposer.sh` with env vars set from the classifier's output + eval run's report + target-file flag.
- **Phase 4 classifier output feeds `PEL_FLAVOR`** — Phase 8 parses the classifier's JSON `.flavor` field and exports as `PEL_FLAVOR`.
- **Phase 2 eval harness output feeds `PEL_EVAL_REPORT`** — Phase 8 runs an eval + captures its report file + passes path.

### Non-obvious risks
- **Prompt-in-template-being-mutated loop.** The proposer mutates `skills/dev-review/templates/*.md`, which are the templates the `dev-review` runner uses. If Phase 5's proposer's own prompt lives at `lab/pel/proposer/template/prompt.md` (NOT under `skills/dev-review/templates/`), there's no self-mutation loop. Path-based separation is clean.
- **Diff that applies but is semantically wrong.** `git apply --check` catches structural problems; a diff that swaps "always" for "never" applies cleanly but breaks the template. That's Phase 8's scoring problem, not Phase 5's.
- **Stdout/stderr discipline for diff output.** Unified diffs use specific formatting (`@@`, `---`, `+++`). Any stderr leak to stdout breaks `git apply`. Adapter must redirect claude CLI stderr properly.
- **Argv-injection in `$1` task hint.** Free-form user input concatenated into a prompt. Standard LLM-input hygiene (treat as data, not instructions) — instructions in the prompt must make this explicit.

</code_context>

<specifics>
## Specific Ideas

- **Single-mutation constraint enforcement is belt-and-suspenders.** Prompt instructs "one file at a time"; code checks after-the-fact via diff parser. Either alone is weak; both together is robust.
- **Exit code taxonomy** signals Phase 8 how to react. 0 = apply. 1 = caller error (fix invocation). 2 = external issue (retry). 3/4 = proposer produced bad output (log + move on; don't retry with same inputs).
- **Fixture diversity matters for simulation.** 3-5 eval-failure fixtures should span: (a) compose-prompt weakness, (b) bounce-protocol weakness, (c) reviewer-role weakness, (d) missing edge case in arbitrate.md. Each fixture targets a different template so the simulation covers mutation across the template surface.
- **The prompt should NOT reference specific template contents.** It should instruct the LLM to read the template from the context (variable portion) and produce a targeted diff. Stable across template updates.

</specifics>

<deferred>
## Deferred Ideas

- **Multi-file mutations** — deferred to v1.3+. v1.2's single-mutation constraint is the safety anchor.
- **Mutations across non-template surfaces** (policy + code) — separate phases (6 and 7).
- **Diff-quality scoring** — Phase 8 scores proposed diffs against eval deltas; Phase 5 just produces diffs.
- **Prompt cache hit/miss telemetry** — same as Phase 4 deferred: assume caching works, instrument later.
- **Dry-run flag** — small ergonomic; post-v1.2.
- **Proposer self-evolution** — out of scope. Proposer-tier evolution is a v1.3+ question (alongside classifier evolution).

*No folded todos — scope fully covered by ROADMAP SC-1..4 + pel-design-decisions.md.*

</deferred>

---

*Phase: 05-template-tier-proposer*
*Context gathered: 2026-04-18 via delegated-autonomous CLAUDE.md Express*
