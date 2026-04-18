# Phase 2: Bash Eval Harness Port - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-17
**Phase:** 02-bash-eval-harness-port
**Areas discussed:** 4 gray areas consolidated — user deferred to Claude's recommendation for all of them, so Claude presented a unified "decide-all-at-once" proposal that user approved.

---

## Pre-discussion scout

Actual PS harness scope discovered during scout:
- `runners/codex-ps/evals/run-evals.ps1` — 287 LOC
- `runners/codex-ps/evals/score-run.ps1` — 467 LOC
- `runners/codex-ps/evals/compare-reports.ps1` — 110 LOC
- `runners/codex-ps/evals/lib/Yaml.ps1` — 75 LOC
- `runners/codex-ps/evals/lib/Report.ps1` — 126 LOC
- `runners/codex-ps/evals/lib/Fixture.ps1` — 161 LOC
- `runners/codex-ps/evals/tests/Test-Scorer.ps1` — 142 LOC
- `runners/codex-ps/evals/tests/Test-Harness-Validate.ps1` — 32 LOC
- **Total ~1400 LOC** — refined the "~2 day" estimate framing.

Ground-truth corpus discovered under `runners/codex-ps/evals/tests/fixtures/**/EXPECTED.json`. This unlocked the "no-pwsh-at-test-time" verification strategy.

---

## Gray Area Selection (Round 1)

| Option | Description | Selected |
|--------|-------------|----------|
| Output fidelity | Byte-identical vs semantic equivalence vs "close enough for PEL scoring" | N/A |
| Dependency policy | Pure Bash vs allow `jq`/`yq`/`python3` helpers | N/A |
| Test harness scope | Port PS tests vs write minimal Bash tests fresh | N/A |
| Plan count + split | 1 / 2 / 3 plans for the port | N/A |

**User's choice:** Deferred to Claude's recommendation — "I really don't know. What do you suggest we do on this? How do we eval and verify it?"

**Notes:** User's second question ("How do we eval and verify it?") turned out to be the key that unlocked the other four. The existing PS-produced EXPECTED.json fixtures provide a ground-truth corpus usable without pwsh at test time, which flipped the fidelity question from "must match PS exactly" to "close enough for PEL + internally deterministic."

---

## Claude's Unified Recommendation (Round 2)

Claude presented a decisive recommendation for all 4 areas plus a 4-tier verification strategy.

### Output fidelity

| Option | Description | Selected |
|--------|-------------|----------|
| Byte-identical JSON (hard) | Match PS's .NET float formatting exactly | |
| Semantic equivalence + 0.001 epsilon | Structural match, numeric within 0.001 | ✓ |
| "Close enough for PEL scoring" | Only the scoring numbers stable to 3-4 decimals | |

**User's choice:** Semantic equivalence + 0.001 epsilon (via "Approve all 4")
**Notes:** Internal determinism is the actual requirement for PEL; exact PS agreement is a nice-to-have.

### Dependency policy

| Option | Description | Selected |
|--------|-------------|----------|
| Pure Bash + coreutils | No new deps, hardest to build | |
| `jq` (already required) + `yq` for YAML | Small declared toolset, no Python | ✓ |
| `jq` + `yq` + `python3` | Fully-featured stdlib helpers | |

**User's choice:** `jq` + `yq` only (via "Approve all 4")
**Notes:** `yq` flavor: mikefarah/yq (Go binary), documented in README.

### Test harness scope

| Option | Description | Selected |
|--------|-------------|----------|
| Full port of PS test harness (~174 LOC) | 2x scope but full parity | |
| Minimal Bash tests against existing EXPECTED.json fixtures | Inherit test corpus; skip runner port | ✓ |
| Hybrid (port regression scripts, skip harness-validate) | Middle ground | |

**User's choice:** Minimal Bash tests against existing fixtures (via "Approve all 4")
**Notes:** The key unlock — the existing EXPECTED.json files ARE the spec. Run Bash scorer against them; assert match.

### Plan count + split

| Option | Description | Selected |
|--------|-------------|----------|
| 1 plan covering all three scripts | Single sequential plan | |
| 2 plans (runner+scorer / comparator+tests) | Natural coarser split | |
| 3 plans (lib / scorer / runner+comparator+tests) | Fine-grained, matches layer structure | ✓ |

**User's choice:** 3 plans (via "Approve all 4")
**Notes:** Plan 02-01 = lib foundation → Plan 02-02 = scorer (hardest) → Plan 02-03 = runner + comparator + verification.

---

## Verification Strategy (Round 2 bonus)

4-tier plan explicitly presented and approved:
- **Tier 1: Golden-fixture regression** — Bash scorer vs `runners/codex-ps/evals/tests/fixtures/**/EXPECTED.json`, diff > 0.001 fails build.
- **Tier 2: E2E smoke test** — Run `run-evals.sh` against `01-trivial-task.yaml`; assert report shape.
- **Tier 3: Determinism sanity** — Run scorer twice on same input; assert byte-identical output.
- **Tier 4: PEL dogfood (future)** — Real-world validation when Phase 5 ships; not a Phase 2 gate.

Offered a Tier 0 (pwsh-optional defaults.yaml parser drift check). User declined this tier by choosing "Approve all 4 + verify strategy" rather than the "Add pwsh-optional tier-zero check" option. Deferred to CONTEXT.md Deferred section.

---

## Claude's Discretion (captured)

- Float epsilon MAY tighten below 0.001 if Plan 02-02 shows all math is effectively integer
- Internal function naming inside `co-evolution-evals.sh` — match existing `lib/co-evolution.sh` conventions
- YAML error-handling granularity — fail-fast with clear errors is the floor
- README update scope — concise; point at `runners/codex-ps/evals/` for PS legacy reference

---

## Deferred Ideas

- Parallel case execution (GNU parallel / xargs -P) — revisit when runtime > 60s
- Test-only pwsh dependency for defaults.yaml parser drift — user declined; reconsider only if scoring diverges
- PS test harness port — out of scope per D-05
- Retry / partial-fail resumption in runner — fail-fast is v1 posture
- CI integration — separate work; PS was manual-invocation by design

---

*Log written: 2026-04-17. Audit-only — downstream agents read CONTEXT.md, not this file.*
