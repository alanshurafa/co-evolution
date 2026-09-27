# Phase 3: Lab Scaffold - Context

**Gathered:** 2026-04-18
**Status:** Ready for planning
**Source:** PRD Express Path (`.planning/notes/co-evolution-lab-concept.md`)

<domain>
## Phase Boundary

Establish `lab/` as a first-class subdirectory inside the `co-evolution` repo — the documented beta channel for experimental features that could break the core runner if deployed prematurely. Plus wire `--lab <mode>` flag parsing into both `co-evolve-bouncer.sh` and `dev-review/codex/dev-review.sh` so opt-in routing works, while preserving byte-parity for default invocations (users who never pass `--lab`).

In scope:
- `lab/` directory created at repo root with `lab/README.md` encoding all documented conventions
- `co-evolve-bouncer.sh` accepts `--lab <mode>` and routes to `lab/<mode>/` dispatcher (or errors with a clear "unknown lab mode" message)
- `dev-review/codex/dev-review.sh` same — accepts `--lab <mode>` with matching semantics
- Simulation test demonstrating (a) default-path byte-parity when `--lab` absent, (b) `--lab <mode>` routing works, (c) unknown-mode rejection
- `lab/README.md` content completeness (boundary, lab-worthy rubric, graduation criteria, anti-criteria, sandbox guarantee, current + planned inhabitants)

Out of scope (explicit):
- Creating any actual `lab/<mode>/` inhabitant (that's Phases 4-8 for PEL; `lab/pel-auto/` and `lab/pel-explorer/` noted in README as v1.3+ placeholders NOT created now)
- Moving `co-evolution-lab-concept.md` from `.planning/notes/` into `lab/README.md` — concept note is the spec; `lab/README.md` is user-facing shorter version
- Any runtime dispatcher code inside `lab/` (the routing logic lives in the runner scripts; `lab/<mode>/` subdirectories will house their own entry points in later phases)
- Deprecating or touching `C:/Users/alan/Project/co-evolution-lab/` (the peer workspace) — distinct thing, concept note explicitly disambiguates
</domain>

<decisions>
## Implementation Decisions

### Boundary & naming

- **L-01 — `lab/` is a new in-repo subdirectory, distinct from the peer `co-evolution-lab/` workspace.** The README must explicitly state this disambiguation. Concept note §"What's NOT the lab" is the source — copy its three-item disambiguation list into `lab/README.md` verbatim.
- **L-02 — Flag syntax: `--lab <mode>`.** NOT `--lab-mode`, NOT positional, NOT env-var-only. Long-form only in v1.2 (no `-l` short form until someone asks).

### Routing & invariants

- **L-03 — Byte-parity when `--lab` absent.** Users who never pass the flag see zero behavior change. The simulation test must prove this (hash the default-path output pre- and post-Phase-3 for ≥1 representative invocation; hashes must match).
- **L-04 — Routing target: `lab/<mode>/` subdirectory must exist and contain an entry point the runner invokes.** If `<mode>` resolves to a non-existent directory: fail-fast with `unknown --lab mode: <mode>. Available: <list from lab/<mode>/ glob>`. Don't silently fall through.
- **L-05 — Sandbox guarantee (documented in README, not enforced in Phase 3).** `--lab <mode>` runs cannot modify master directly — only via emitted PRs. The actual enforcement mechanism ships with each lab inhabitant (e.g., PEL Phase 7's code-tier proposer ships its own sandbox). Phase 3 just writes the guarantee into `lab/README.md` as a contract future phases must honor.

### Graduation & anti-criteria (load-bearing for future phases)

- **L-06 — Graduation checklist is 6 items, ALL must be true to promote.** Runtime signal ≥4 weeks on real workloads, test parity, documented failure modes, user signal (multiple opt-ins across tasks), rollback path, API stable. Copy verbatim from concept note §"Graduation criteria". Future milestone reviews will check against this list — don't paraphrase.
- **L-07 — Anti-criteria explicit.** 4 conditions under which a lab feature should be killed rather than promoted (user dormancy, unstable fitness signal, obviated by core pattern, unfixable without full rewrite). Also copy verbatim.
- **L-08 — "Lab-worthy" rubric is also copied verbatim.** 5 qualification conditions (could brick core, multi-week correctness signal, safety-for-power tradeoff, missing infrastructure, architectural bet).

### First inhabitants documentation

- **L-09 — README lists `lab/pel/` (v1.2 current) + `lab/pel-auto/` and `lab/pel-explorer/` as v1.3+ placeholders.** Explicitly note the placeholders are NOT created in Phase 3 — they're there to reserve the namespace so PEL v1.3+ work has an obvious home. Reference `.planning/seeds/pel-auto-promote-and-explorer.md` for their graduation prerequisites.

### Claude's Discretion

- Exact prose / heading structure of `lab/README.md` — concept note is 100-line; README can be 120-180 lines of user-facing content with looser prose. Do not drop any of the 3 disambiguation items, 5 lab-worthy conditions, 6 graduation criteria, or 4 anti-criteria — those are locked.
- CLI arg-parsing implementation detail in `co-evolve-bouncer.sh` and `dev-review.sh` — whether to extend the existing `while [[ $# -gt 0 ]]; do case "$1" in` block or add a pre-pass. Whatever keeps the diff minimal and easy to review.
- Unknown-mode error message wording, as long as it lists available modes via a `ls lab/` glob.
- Whether `lab/README.md` also includes a "How to add a new lab inhabitant" section (short checklist: create `lab/<name>/`, add entry point, add README entry, optional tests). Recommend yes, but short (≤15 lines).
- Simulation test file location — `tests/lab-routing-simulation.sh` follows the v1.1 pattern; use that unless a stronger reason.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design spec (THE PRD — every `L-*` decision comes from here)

- `.planning/notes/co-evolution-lab-concept.md` — full concept note (100 lines). Boundary, lab-worthy rubric, graduation criteria, anti-criteria, first inhabitants, generalization rationale. Copy verbatim for README body content per L-06/L-07/L-08.
- `.planning/notes/pel-design-decisions.md` — why `lab/pel/` is v1.2's first inhabitant (PEL Proposer-Only ships here).
- `.planning/seeds/pel-auto-promote-and-explorer.md` — graduation prerequisites for the two v1.3+ placeholder inhabitants. README should link to this seed from the `lab/pel-auto/` and `lab/pel-explorer/` mentions.

### Project-level refs

- `.planning/ROADMAP.md` §Phase 3 — 4 success criteria (all 4 must be addressable by plan acceptance).
- `.planning/REQUIREMENTS.md` §LAB-01 — requirement spec.
- `.planning/PROJECT.md` — byte-parity invariants that L-03 must honor.

### Runner entry points (where `--lab <mode>` wiring lands)

- `co-evolve-bouncer.sh` — primary `co-evolve` entry point. Extend its arg parser.
- `dev-review/codex/dev-review.sh` — `dev-review` entry point. Extend its arg parser identically (same flag semantics).
- `lib/co-evolution.sh` — shared library. If a `parse_lab_flag` helper reduces duplication across both runners, add it here; otherwise inline.

### Analogous patterns (for style mirroring)

- `tests/worktree-management-simulation.sh` — v1.1 simulation-test pattern. Mirror structure for `tests/lab-routing-simulation.sh`.
- `evals/tests/scorer-verification.sh` — v1.2 Phase 2 simulation gate (extended v1.1 pattern with PASS/FAIL scenario counters). Another style reference.
- v1.2 Phase 2 `--runner-path` flag implementation in `evals/run-evals.sh` — recent precedent for "add a new long-form flag with documentation + acceptance grep".

### Disambiguation (do NOT touch)

- `C:/Users/alan/Project/co-evolution-lab/` (peer workspace) — pre-existing, distinct from this `lab/`. Concept note §"What's NOT the lab" calls this out explicitly. README must include the same disambiguation.
- `runners/codex-ps/` — read-only reference impl. Not a lab. Leave untouched.
- `experiments/` — design-doc archive. Not a runtime lab. Leave untouched.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`lib/co-evolution.sh`** — shared library with `log`/`die` helpers, arg-parsing patterns (`while [[ $# -gt 0 ]]; do case`), and snake_case conventions. Any new `parse_lab_flag` helper should live here if shared across both runners.
- **Existing arg parsers** in `co-evolve-bouncer.sh` and `dev-review/codex/dev-review.sh` already handle flags like `--composer`, `--executor`, `--bounces`, `--verify`, `--autonomous`, `--worktree`, and (v1.2) `--runner-path`. The `--lab <mode>` flag extends this pattern — no new parser framework needed.
- **Simulation test pattern** from v1.1 (`tests/worktree-management-simulation.sh`) and v1.2 Phase 2 (`evals/tests/scorer-verification.sh`) — hermetic, per-scenario subshell, FAILURES counter, trap cleanup. Byte-parity and routing scenarios will follow this pattern.

### Established Patterns

- **Byte-parity when flag absent** is the consistent v1.1 and v1.2 invariant. Every new flag must preserve default behavior — L-03 is not a new constraint, it's the standard.
- **Fail-fast with clear messages** for unknown inputs. v1.2 Phase 2 `--runner-path` validates file existence and errors out on miss; `--lab <mode>` mirrors this with directory existence + available-modes list.
- **Documentation co-located with the flag** — v1.2 Phase 2 added a README section documenting `--runner-path` and a `grep -c '--runner-path' evals/README.md` acceptance. Phase 3 does the same for `--lab <mode>`.

### Integration Points

- **`lab/<mode>/` invocation contract.** The runner's `--lab <mode>` logic determines how `lab/<mode>/` entry points are called. Suggested: if `lab/<mode>/entry.sh` exists, exec it with the remaining argv; else fail with unknown-mode error. This is open for Claude's discretion but must be documented in `lab/README.md` §"How to add a new lab inhabitant".
- **PEL Phase 4 (Mode Classifier) expects `lab/pel/` to exist.** Phase 3 creates the `lab/` scaffold + placeholder inhabitants but does NOT create `lab/pel/classifier/` — that's Phase 4's job. Phase 3 just ensures the directory discipline is in place.

### Non-obvious risks

- **Silent routing bugs.** If `--lab <mode>` with an unknown mode silently falls through to default behavior, users won't notice they typed wrong — and lab behavior gets gaslit. Fail-fast with listing is critical per L-04.
- **Argv position.** If `--lab <mode>` appears after `--` (bash argv terminator), it must be treated as a positional argument to the task, not as a flag. Both runners already handle `--` correctly; the new flag logic must sit before `--` processing.
- **README drift.** If the concept note in `.planning/notes/` and `lab/README.md` diverge over time, the authoritative source ambiguity becomes a problem. Recommend: `lab/README.md` links to `.planning/notes/co-evolution-lab-concept.md` for the "deep why", user-facing README keeps the operational bits.

</code_context>

<specifics>
## Specific Ideas

- **The README's graduation table should be copy-pasteable into future PR bodies.** When someone proposes "graduate feature X to core", the PR checklist should reference `lab/README.md#graduation-criteria` and check off each of the 6 items. Write the README so this flow is natural.
- **Use `grep -c` acceptance for every copy-verbatim section** (6 graduation items, 4 anti-criteria, 5 lab-worthy conditions, 3 disambiguation items). Don't trust prose matching — pin each item with a grep. Example: `grep -c '^- \*\*Runtime signal' lab/README.md` returns exactly 1. This catches future edits that accidentally drop an item.
- **Simulation test minimum scenarios (3):** (1) default `co-evolve "task"` → hash output, compare to pre-phase hash — byte-parity. (2) `co-evolve --lab pel-proposer "task"` → fails with "unknown --lab mode" since `lab/pel-proposer/` doesn't exist yet in Phase 3. (3) `dev-review --lab pel-proposer "task"` → same fail-fast behavior. Scenario 2 and 3 prove the routing logic is wired even though no inhabitants exist.
- **When the first real inhabitant lands in Phase 4 (`lab/pel/classifier/`), its PR can include a 4th simulation scenario** demonstrating `--lab pel` successfully routes. Not Phase 3's job.
- **`--lab-help` sub-command?** OPTIONAL. If easy, add `co-evolve --lab-help` that prints available modes from `lab/` glob. If messy, skip — a `--lab <bogus>` invocation already lists them via the error path.
</specifics>

<deferred>
## Deferred Ideas

- **Creating actual `lab/<mode>/` inhabitants** — PEL Phases 4-8 ship the `lab/pel/` subtree. `lab/pel-auto/` and `lab/pel-explorer/` are v1.3+ (documented as placeholders only).
- **Lab-wide invariant enforcement (sandbox, diff budgets, file allowlists)** — each lab inhabitant ships its own enforcement in its own phase. Phase 3 writes the L-05 guarantee into README but does not implement universal enforcement.
- **`--lab` short form (`-l`)** — skip until someone asks. Long-form only in v1.2.
- **Lab graduation automation** — a tool that checks the 6 criteria and surfaces PR-readiness is a nice-to-have for v1.3+, not v1.2.
- **Automated drift detection between `.planning/notes/co-evolution-lab-concept.md` and `lab/README.md`** — linting for content drift. Deferred; low-value right now.

*No folded todos — all concept-note items either locked as L-01..L-09 or explicitly deferred above.*
</deferred>

---

*Phase: 03-lab-scaffold*
*Context gathered: 2026-04-18 via PRD Express Path*
*PRD source: `.planning/notes/co-evolution-lab-concept.md`*
