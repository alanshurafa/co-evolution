# Requirements: Co-Evolution

**Core Value:** Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps. From v1.2 onward co-evolution becomes self-improving via PEL (living in `lab/`) proposing protocol mutations for human review.

> Completed requirements are archived per milestone under `.planning/milestones/`.
> This file tracks only requirements for the **active milestone**.

## Completed Milestones

- **v1.0 Unification Absorb** — 27/27 requirements Complete. See [`milestones/v1.0-REQUIREMENTS.md`](milestones/v1.0-REQUIREMENTS.md).
- **v1.1 Polish & Ergonomics** — 6/6 requirements Complete (FIX-WR-01/02/03 + RTUX-01/02/03). See [`milestones/v1.1-REQUIREMENTS.md`](milestones/v1.1-REQUIREMENTS.md).

## Active Milestone: v1.2 Protocol Evolution Loop — Proposer Only

### Post-v1.1 Fixes (folded from v1.1 review non-blockers)

- [ ] **FIX-WR-04**: Relocate `INITIAL_GIT_DIRTY` / `INITIAL_GIT_STATUS` capture so it happens AFTER `WORKDIR` is reassigned in worktree mode. Currently captured from parent repo pre-reassignment at `dev-review/codex/dev-review.sh:1106-1112`; if parent is dirty AND `--worktree auto` is active, verify is silently skipped even though the worktree is clean.
- [ ] **FIX-WR-05**: Add `--` argv terminator to `git worktree add "$path"` and `git checkout -b "$name"` calls in `lib/co-evolution.sh`. Prevents path-as-flag interpretation. Not security-exploitable (git rejects invalid refs harmlessly) — hardening best-practice gap only.

### Evals Harness Portability (prerequisite for PEL)

- [ ] **BASH-EVAL-01**: Port PowerShell eval harness (`runners/codex-ps/scripts/run-evals.ps1`, `score-run.ps1`, `compare-reports.ps1`) to Bash at a new top-level `evals/scripts/` or `evals/bin/` location. Must run in Git Bash on Windows + Linux + macOS without `pwsh`. Consumes the portable cases/fixtures/schema already elevated to top-level in v1.0 Phase 8. Produces machine-readable eval reports consumable by PEL scorer.

### Lab Scaffold

- [ ] **LAB-01**: Create `lab/` directory at repo root. Add `lab/README.md` documenting (a) the default/lab boundary from `.planning/notes/co-evolution-lab-concept.md`, (b) the promotion flow (lab proposer → draft PR → human review → merge to master → default runner upgraded transparently), (c) graduation criteria (≥4 weeks lab runtime + test parity + documented failure modes + explicit user signal + rollback path + stable name/API), (d) anti-criteria for killing rather than promoting, (e) first inhabitants list (`lab/pel/`).

### PEL Core (Option 1 Proposer — the v1.2 ship target)

- [ ] **PEL-01**: `lab/pel/classifier/` — frozen mode classifier. Given a task and a bounce-step + GSD-phase-type context, picks one of four flavors (bug-catcher / faster-converger / blind-spot-surfacer / general) and emits a transparent rationale alongside the pick. Haiku 4.5 by default. User can override via `--flavor <name>` flag on `co-evolve --lab pel-proposer`. Classifier itself does NOT evolve in v1.2 (evolving it is v1.3+).
- [ ] **PEL-02**: `lab/pel/proposer/template/` — template-tier mutation proposer. Given an eval-failure report + the current compose/bounce/review template, proposes a diff against `skills/dev-review/templates/*.md` that should raise the fitness signal. LLM-driven (Opus 4.7 or similar). Does NOT touch code or policy.
- [ ] **PEL-03**: `lab/pel/proposer/policy/` — policy-tier mutation proposer. Operates on YAML/JSON config knobs (retry caps, marker-semantics definitions, writable-phase defaults, arbitrate thresholds, max-passes, flavor weights). Same propose-score-diff contract as PEL-02. Independent of template and code tiers — can compose with either.
- [ ] **PEL-04**: `lab/pel/proposer/code/` — code-tier mutation proposer. Can propose diffs against `lib/co-evolution.sh` and runner paths. **LLM-only** (random search breaks shell syntax). Includes hard safety rails: (a) sandbox isolation — never runs against the live checkout, always a fresh clone; (b) canary smoke-test suite runs before eval scoring — mutation rejected BEFORE scoring if the runner stops working; (c) diff budget cap and file allowlist; (d) explicit exit codes distinguishing "canary failed" vs "eval regressed" vs "accepted."
- [ ] **PEL-05**: `lab/pel/pr-emitter/` — PR emission + scoring integration. Wraps PEL-01 through PEL-04 as a single invocation: `co-evolve --lab pel-proposer --target <file-or-pattern>` picks a flavor, generates a mutation, runs the eval suite on the mutated variant, drafts a PR against master with eval deltas in the body, and exits. Human reviews and merges (or closes). This IS the Option 1 ship — no auto-merge path in v1.2.

## Future (candidates for v1.3+)

Tracked explicitly in seed: `.planning/seeds/pel-auto-promote-and-explorer.md`.

- **PEL-OPT2-01..N**: Auto-Promote mode (Option 2) in `lab/pel-auto/` — PEL auto-merges mutations that pass canary + beat champion on eval. Requires: canary suite from PEL-04 proven, Goodhart findings from RQ-001, ≥4 weeks of Option 1 production data.
- **PEL-OPT3-01..N**: Explorer + Curator mode (Option 3) in `lab/pel-explorer/` — continuous sidecar exploration with protocol-graveyard logging and periodic human curation. Requires: PEL-OPT2 shipped and a curation UX design.
- **PEL-META-01**: Classifier evolution — allow the mode classifier itself to evolve based on Option 1+2 data. Requires: clean attribution signal separating protocol improvement from classifier changes.

## Out of Scope

- **Options 2 + 3 in v1.2** — explicitly deferred; seed carries the ambition with trigger conditions.
- **Goodhart mitigations beyond human review** — v1.2's mitigation IS human PR review. Deeper mitigations (held-out rotation, adversarial generators, semantic drift detection) tracked in `.planning/research/questions.md` RQ-001.
- **Auto-promotion / auto-merge anywhere in v1.2** — every mutation goes through human review.
- **Automated branch/worktree cleanup utility** — v1.1 deferred item; could be a separate utility. Not blocking anything in v1.2.
- **Workspace-agnostic ports of lab PS integration scripts** — deferred per v1.0 Phase 9 rationale.
- **Evolving the mode classifier in v1.2** — frozen; meta-meta-learning deferred.

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FIX-WR-04 | Phase 1 | Planned |
| FIX-WR-05 | Phase 1 | Planned |
| BASH-EVAL-01 | Phase 2 | Planned |
| LAB-01 | Phase 3 | Planned |
| PEL-01 | Phase 4 | Planned |
| PEL-02 | Phase 5 | Planned |
| PEL-03 | Phase 6 | Planned |
| PEL-04 | Phase 7 | Planned |
| PEL-05 | Phase 8 | Planned |

**Coverage:**
- v1.2 requirements: 9 total (2 FIX-WR folded + 1 BASH-EVAL + 1 LAB + 5 PEL)
- Mapped to phases: 9
- Unmapped: 0 ✓

---
*Active requirements reset at each milestone boundary. Historical requirements live in `milestones/vN.N-REQUIREMENTS.md`.*
