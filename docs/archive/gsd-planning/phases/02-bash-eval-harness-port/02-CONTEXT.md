# Phase 2: Bash Eval Harness Port - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Port the PowerShell eval harness (~1400 LOC under `runners/codex-ps/evals/`) to Bash so eval runs work without `pwsh`. The harness is PEL's fitness signal: every mutation proposer in v1.2 Phases 5-8 needs a deterministic, runnable scorer. Phase 2 is a hard prerequisite — PEL cannot score mutations without it.

In scope:
- `evals/lib/co-evolution-evals.sh` — shared Bash library mirroring PS `lib/Yaml.ps1` + `lib/Report.ps1` + `lib/Fixture.ps1`
- `evals/score-run.sh` — scorer port of PS `score-run.ps1` (~467 LOC of fitness math)
- `evals/run-evals.sh` — runner port of PS `run-evals.ps1` (~287 LOC orchestrator)
- `evals/compare-reports.sh` — comparator port of PS `compare-reports.ps1` (~110 LOC)
- `evals/tests/scorer-verification.sh` — regression test against existing PS-produced EXPECTED.json fixtures
- `evals/README.md` — update to reflect Bash as default, PS as legacy reference

Out of scope (explicit):
- Porting the PS test harness itself (Test-Scorer.ps1, Test-Harness-Validate.ps1, regression scripts) — we inherit their TEST CORPUS by reusing the existing EXPECTED.json fixtures, but don't port the test runner
- Parallelization (GNU parallel / xargs -P) — serial execution in v1; revisit if PEL's 100-mutation cycles prove too slow
- Adding new eval cases beyond the existing 9 in `evals/cases/`
- Any fidelity-preservation gymnastics to match PS's .NET float formatting byte-for-byte
</domain>

<decisions>
## Implementation Decisions

### Output fidelity

- **D-01 — Semantic equivalence with 0.001 float epsilon.** Scorer outputs must match PS outputs structurally (same JSON keys, same value types) and numerically within 0.001 on every float field. NOT byte-identical. The internal determinism invariant (same input → same output, always) is what matters for PEL; exact agreement with PS is a bonus, not the bar.
- **D-02 — Internal determinism is load-bearing.** PEL's before/after mutation comparison trusts the scorer to be stable. Non-determinism (random IDs, timestamp leakage into reports, map-iteration order) is a blocker. Determinism test is Tier 3 of the verification strategy.

### Dependency policy

- **D-03 — Allowed deps: `bash`, coreutils, `jq`, `yq`.** `jq` is already required by the runner; adding `yq` is the only new dependency, and it's widely available on apt/brew/scoop/Git-Bash add-on. No Python dependency — `jq`'s float math + structural operations cover what we need.
- **D-04 — `yq` flavor: mikefarah/yq (Go, not Python-based).** Most broadly available on Windows via scoop; single static binary; its YAML-to-JSON conversion composes cleanly with jq. Document this in README.

### Test harness scope

- **D-05 — Don't port the PS test runner. Inherit the test corpus.** The ~174 LOC of PS test scripts (Test-Scorer.ps1, Test-Harness-Validate.ps1, 4 regression scripts, Build-Fixtures/Build-Regressions) are NOT ported. Instead, Plan 02-03 writes a minimal Bash test (`evals/tests/scorer-verification.sh`, target ~100 LOC) that runs the Bash scorer against existing `runners/codex-ps/evals/tests/fixtures/**/EXPECTED.json` fixtures and asserts output matches.
- **D-06 — The existing EXPECTED.json files ARE the spec.** They were produced by the PS scorer against known-good inputs. Using them as regression targets means we match PS scorer behavior by construction, WITHOUT requiring pwsh at test time.

### Plan count + split

- **D-07 — 3 plans.** Matches ROADMAP's "2-3 plans" target.
  - **Plan 02-01** — `evals/lib/co-evolution-evals.sh` Bash library: YAML loading (yq wrapper + normalization), report utilities (JSON schema validation, markdown rendering), fixture loading. Foundation for both downstream plans.
  - **Plan 02-02** — `evals/score-run.sh` scorer port (hardest plan, 400+ LOC target). All fitness-signal math; produces `scores.json` + `report.md` per run.
  - **Plan 02-03** — `evals/run-evals.sh` runner + `evals/compare-reports.sh` comparator + `evals/tests/scorer-verification.sh` verification test. Runner orchestrates cases, comparator diffs two reports, verification test is the gold-standard regression gate.

- **D-08 — Sequential execution, serial dependencies.** Plan 02-01 → 02-02 → 02-03. No parallelization across plans (02-02 needs lib from 02-01; 02-03 needs scorer from 02-02 to meaningfully test).

### Verification strategy (the "how do we eval the eval harness" answer)

- **D-09 — 4-tier verification.**
  - **Tier 1: Golden-fixture regression** (primary gate). Bash scorer runs against `runners/codex-ps/evals/tests/fixtures/**/EXPECTED.json` fixtures. Any diff > 0.001 on a float field fails Plan 02-02/02-03. 2+ fixture suites available; coverage expanded as new fixtures are added.
  - **Tier 2: End-to-end smoke test** (secondary). `evals/run-evals.sh` runs against `01-trivial-task.yaml`; assert the produced report exists, is non-empty, matches the report schema via jq. Does NOT assert specific score values.
  - **Tier 3: Determinism sanity** (invariant). Run the scorer twice on the same input; assert byte-identical stdout/artifact output. Catches non-determinism (random IDs, timestamp leakage, map iteration).
  - **Tier 4: PEL dogfood** (future, not a Phase 2 gate). When v1.2 Phase 5 (template proposer) lands, it exercises the scorer in production-realistic conditions. Failures surface there if Tiers 1-3 missed anything.

### Claude's Discretion

- Float-comparison epsilon MAY tighten below 0.001 if Plan 02-02 reveals all math is effectively integer — do whatever keeps the fixture tests green without masking real divergence.
- Internal Bash function naming inside `co-evolution-evals.sh` — match Bash style of existing `lib/co-evolution.sh` (snake_case, `log`/`die` helpers already in scope).
- Error-handling granularity for malformed YAML — fail fast with a clear error is the floor; fancy recovery is Claude's call.
- README.md update scope — concise is fine; point at `runners/codex-ps/evals/` for PS legacy reference.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### PS source (port targets — read every line)

- `runners/codex-ps/evals/run-evals.ps1` — runner orchestrator (287 LOC). The spec for `evals/run-evals.sh`.
- `runners/codex-ps/evals/score-run.ps1` — scorer (467 LOC). The spec for `evals/score-run.sh`. Contains all fitness-signal math that PEL depends on.
- `runners/codex-ps/evals/compare-reports.ps1` — report comparator (110 LOC). The spec for `evals/compare-reports.sh`.
- `runners/codex-ps/evals/lib/Yaml.ps1` — YAML parser (~75 LOC). Port pattern for `yq`-wrapping in `co-evolution-evals.sh`.
- `runners/codex-ps/evals/lib/Report.ps1` — report rendering (~126 LOC). Port pattern for the markdown+JSON rendering helpers.
- `runners/codex-ps/evals/lib/Fixture.ps1` — fixture loading (~161 LOC). Port pattern for fixture discovery and shape validation.

### Verification corpus (ground truth — DO NOT PORT, just consume)

- `runners/codex-ps/evals/tests/fixtures/01-all-pass/` — fixture case.yaml + expected outputs (EXPECTED.json, run/scores.json, run/verdict.json, run/state.json, run/plan.md).
- `runners/codex-ps/evals/tests/fixtures/02-robustness-fail/` — second fixture suite.
- Any additional `runners/codex-ps/evals/tests/fixtures/**/EXPECTED.json` files — all become Tier 1 regression targets.

### Portable assets (already at top-level from v1.0 Phase 8 — read for shape)

- `evals/cases/*.yaml` (10 files including defaults.yaml) — the production eval case library the runner will iterate over.
- `evals/cases/defaults.yaml` — shared defaults for all cases; parser must handle the "merge defaults" semantics correctly.
- `evals/fixtures/mock-report.md` and `evals/fixtures/mock-scores.json` — shape references for what the scorer produces.
- `evals/VERIFICATION-PLAN.md` — the original 5-tier verification strategy the PS harness was validated against; Phase 2's new 4-tier plan is the Bash analog.
- `evals/README.md` — current user-facing doc; update as Plan 02-03's final step.
- `schemas/review-verdict.json` — JSON schema the scorer validates against when parsing `verdict.json`. Must stay compatible.

### Project-level refs

- `.planning/PROJECT.md` — constraints (byte-parity, dep minimalism, lab/core split).
- `.planning/ROADMAP.md` §Phase 2 — success criteria (4 items).
- `.planning/REQUIREMENTS.md` §BASH-EVAL-01 — requirement spec.
- `.planning/notes/pel-design-decisions.md` — why this phase matters (PEL's fitness signal is the whole point).

### Design / PS-side history (optional background)

- `runners/codex-ps/evals/PLAN.md` — the original PS harness design doc; useful context for "why does score-run.ps1 compute X?"
- `runners/codex-ps/evals/NEXT.md` and `runners/codex-ps/evals/ROLL-UP-TO-MAIN.md` — PS-side evolution notes; skim if confused about a particular design choice.
- `runners/codex-ps/evals/BASELINE-SUMMARY.md` — baseline run results the scorer produced historically; gives a feel for what "normal" output looks like.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`lib/co-evolution.sh`** — shared runner library (established pattern for Bash helpers in this repo). The new `evals/lib/co-evolution-evals.sh` should mirror its conventions: `log`/`die` helpers from the existing lib can be sourced, `snake_case` function naming, `$var` explicit quoting, `set -euo pipefail` at file top when appropriate for tests.
- **`jq`** — already required by `dev-review/codex/dev-review.sh` for state.json manipulation. Available on every target platform. No install friction.
- **`evals/cases/*.yaml`** — 9 production cases + defaults.yaml already in place from v1.0 Phase 8. The runner only needs to iterate them, not create them.
- **`runners/codex-ps/evals/tests/fixtures/`** — ~2 suites of ready-made (case.yaml + run/ + EXPECTED.json) triples that become the Tier 1 regression corpus.

### Established Patterns

- **Byte-parity when feature unset** — every v1.1 feature preserved default behavior when its flag was off. Phase 2 is additive infrastructure (new files); existing runner behavior unchanged.
- **Simulation-script tests** — v1.1 Phases 2-4 produced `tests/*-simulation.sh` hermetic tests that work on Git Bash + Linux + macOS. Plan 02-03's verification test should follow this pattern.
- **State.json as machine-readable ground truth** — the dev-review runner writes structured `state.json`; the scorer is one of its consumers. Any scorer changes must continue to parse v1.1-compatible state.json without regression.

### Integration Points

- **Invocation surface**: `evals/run-evals.sh [--case NAME] [--out DIR]` mirrors `evals/run-evals.ps1`'s CLI. Matches how a PS user would have invoked the old harness.
- **Scorer-runner contract**: Runner writes per-case run/ dirs (with plan.md, state.json, verdict.json, etc.); scorer reads them and produces scores.json + report.md. Same shape PS used — v1.0 Phase 8 already elevated the artifacts that make this contract portable.
- **PEL Phase 5 will invoke** `evals/run-evals.sh` to score mutated protocols. Phase 2's surface area is what Phase 5 depends on — don't add extra invocation modes unless they're needed for PEL's usage pattern.

### Non-obvious risks

- **Float arithmetic divergence** — jq handles doubles but differs from .NET in rounding. Plan 02-02 must test this early on a representative numeric case; tighten epsilon only if safe.
- **YAML merge semantics** — `defaults.yaml` is merged into each case.yaml. Confirm yq's merge behavior matches PS's (shallow vs deep merge, array semantics). First-class test in Plan 02-01.
- **Map ordering** — JSON object key ordering is not guaranteed by jq. Don't write tests that assert specific key ordering in outputs; the Tier 1 check should use `jq -S` (sort keys) for normalization.
- **Line endings on Windows** — Git Bash + PS can produce different trailing-newline behavior on string outputs. The determinism test (Tier 3) should normalize line endings before diffing.

</code_context>

<specifics>
## Specific Ideas

- **Keep the port's output schema identical to PS's output schema.** PEL's proposers (Phases 5-8) will parse `scores.json` and `report.md`. Don't invent new fields; don't rename existing ones; don't change array/object nesting. If PS emitted a field Bash doesn't naturally produce, produce it empty (or with a `null`) rather than omitting it.
- **Use `jq -S` for all JSON diffs in verification.** Sorting keys removes ordering noise and makes comparison deterministic.
- **Runtime determinism over PS agreement.** If a Bash-side rounding quirk produces `0.8502` where PS produces `0.8501`, and the Bash result is deterministic across runs, that's acceptable. What's NOT acceptable is a Bash result that varies across runs.
- **README note: `yq` install.** On Git Bash Windows: `scoop install yq`. On apt: `apt install yq` (or via go-install for mikefarah's flavor). On brew: `brew install yq`. Document this in `evals/README.md` Plan 02-03.
- **Consider a `--no-yq` fallback in Plan 02-01** — if yq isn't installed, fall back to a pure-Bash YAML parser ONLY for the subset of YAML used in `evals/cases/*.yaml` (simple key-value, no anchors/aliases). Claude's discretion whether this is worth the complexity; skip if it's > ~50 LOC.
</specifics>

<deferred>
## Deferred Ideas

- **Parallel case execution** (GNU parallel / xargs -P) — serial is fine for v1 since PEL's mutation cycles won't be the bottleneck for a while. Revisit when eval runtime > 60s.
- **Test-only pwsh dependency for defaults.yaml parser drift check** — user explicitly chose NOT to add this (chose "Approve all 4 + verify strategy" without the Tier 0 option). If scoring diverges during Plan 02-02, reconsider.
- **Porting PS test harness (Test-Scorer.ps1, regression scripts)** — explicitly out of scope per D-05. The fixture corpus alone is sufficient regression coverage.
- **Fancy error recovery in the runner** — fail-fast with clear messages is the v1 posture. Retry logic, partial-fail resumption, etc. are v1.3+ if PEL's long mutation runs justify them.
- **Continuous integration wiring** — the PS harness was explicitly manual-invocation per its original PLAN.md. Bash port stays manual-invocation; CI integration is separate work.

*No folded todos — none surfaced during discussion.*
</deferred>

---

*Phase: 02-bash-eval-harness-port*
*Context gathered: 2026-04-17*
