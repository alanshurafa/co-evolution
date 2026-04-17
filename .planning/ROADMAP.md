# Roadmap: Co-Evolution

## Overview

This roadmap adds a standalone Codex runtime to the existing Co-Evolution toolkit without destabilizing the current Agent Bouncer or Claude Code skill. The work proceeds from shared shell foundations, to a behavior-preserving bouncer refactor, to the new Codex runtime, and finally to the instruction and documentation layer that makes the new runtime discoverable.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Shared Shell Core** - Extract reusable shell helpers into a common library
- [x] **Phase 2: Bouncer Refactor** - Move Agent Bouncer onto the shared shell core without behavior drift
- [x] **Phase 3: Codex Runtime** - Add the standalone Codex `dev-review` runtime script
- [x] **Phase 4: Docs And Routing** - Add Codex instructions and repo docs for the new runtime

### Milestone: Unification Absorb (2026-04-17)

Absorb the private `codex-co-evolution/` reference implementation + eval harness and selected `co-evolution-lab/` contents into this public repo. Parity the Bash runner with the Codex PS reference. P0 quick win (Required-Section blocks) landed in `8b741ba` before milestone planning.

- [x] **Phase 5: Codex PS Preservation** - Copy `codex-co-evolution/` contents verbatim into `runners/codex-ps/` as read-only reference impl + audit trail
- [x] **Phase 6: Protocol Parity** - Adopt MUST-items 3-6 from upstream (Claude adapter tool-gating, skip `--json-schema`, structural bounce check, bounce-protocol reconciliation)
- [ ] **Phase 7: Runner Parity** - Port 5 features Bash lacks (agent dispatcher, writable-phase flag, delta tracking, structured `state.json`, per-phase timeout)
- [ ] **Phase 8: Evals Absorbed** - Elevate portable eval assets to top-level `evals/`; keep runner-specific harness under `runners/codex-ps/`
- [ ] **Phase 9: Lab Folded** - Fold `co-evolution-lab/integrations/` + `mempalace.yaml` into unified repo; exclude Karpathy's auto-research (unrelated ML training)

## Phase Details

### Phase 1: Shared Shell Core
**Goal**: Create a reusable shell library that captures the helper logic currently embedded in Agent Bouncer and needed by future runtimes.
**Depends on**: Nothing (first phase)
**Requirements**: [CORE-01, CORE-02]
**Success Criteria** (what must be TRUE):
  1. `lib/co-evolution.sh` exists and can be sourced without side effects
  2. Shared helpers cover current bouncer needs for agent invocation, output validation, marker counting, template filling, and verdict parsing
  3. The library is ready to be sourced by both Agent Bouncer and the future Codex runtime
**Plans**: 1 plan

Plans:
- [x] 01-01: Create shared shell core library

### Phase 2: Bouncer Refactor
**Goal**: Refactor Agent Bouncer to use the shared library while preserving current behavior.
**Depends on**: Phase 1
**Requirements**: [BNCR-01, BNCR-02]
**Success Criteria** (what must be TRUE):
  1. `agent-bouncer/agent-bouncer.sh` sources `lib/co-evolution.sh`
  2. Existing run artifact names and clean-output behavior are preserved
  3. Script-level validation confirms the refactor did not introduce syntax regressions
**Plans**: 1 plan

Plans:
- [x] 02-01: Refactor Agent Bouncer onto shared library helpers

### Phase 3: Codex Runtime
**Goal**: Build a standalone Codex runtime for the `dev-review` workflow.
**Depends on**: Phase 2
**Requirements**: [CDRT-01, CDRT-02, CDRT-03, CDRT-04]
**Success Criteria** (what must be TRUE):
  1. `dev-review/codex/dev-review.sh` can parse runtime flags and orchestrate compose, bounce, execute, and optional verify phases
  2. Prompt assembly reuses the existing shared templates and keeps plan content inline
  3. Runtime exits with distinct codes for success, fatal failure, and revise verdicts
**Plans**: 1 plan

Plans:
- [x] 03-01: Create Codex `dev-review` runtime script

### Phase 4: Docs And Routing
**Goal**: Make the new Codex runtime discoverable and safely routable from repo instructions and docs.
**Depends on**: Phase 3
**Requirements**: [DOCS-01, DOCS-02]
**Success Criteria** (what must be TRUE):
  1. `dev-review/codex/instructions.md` tells Codex when to use the runtime versus Agent Bouncer or direct execution
  2. Repo docs describe the Codex runtime and its common commands
  3. Project instructions include the new runtime context without disturbing unrelated local changes
**Plans**: 1 plan

Plans:
- [x] 04-01: Add Codex runtime instructions and documentation

### Phase 5: Codex PS Preservation
**Goal**: Land the private `codex-co-evolution/` reference implementation inside the public repo as `runners/codex-ps/`, preserving it verbatim as an audit trail for the parity work that follows.
**Depends on**: Phase 4
**Requirements**: [CXPS-01, CXPS-02]
**Success Criteria** (what must be TRUE):
  1. `runners/codex-ps/` exists at the repo root containing the full codex-co-evolution tree (scripts, templates, schemas, docs, evals)
  2. Directory documented as read-only reference — not extended during subsequent phases
  3. Original `C:/Users/alan/Project/codex-co-evolution/` can be archived without losing content
**Plans**: 1 plan

Plans:
- [x] 05-01: Copy codex-co-evolution tree verbatim to runners/codex-ps/ and declare it read-only

### Phase 6: Protocol Parity
**Goal**: Bring the Bash runner's Claude adapter and verification layer in line with the MUST-items from `evals/UPSTREAM-MESSAGE.md` (items 3-6; items 1-2 landed in P0).
**Depends on**: Phase 5
**Requirements**: [PRTP-01, PRTP-02, PRTP-03, PRTP-04, PRTP-05]
**Success Criteria** (what must be TRUE):
  1. Claude adapter passes `--disallowedTools` on text-producing phases (compose/bounce/review) to prevent silent write-to-file behavior
  2. Claude adapter passes `--permission-mode bypassPermissions --allowedTools ... --add-dir <workdir>` on write-producing phases (execute/fix)
  3. No code path passes `--json-schema` to Claude (confirmed broken on Windows in `-p` mode)
  4. Verification layer checks for `outputs/bounce-NN.txt` structural signal alongside semantic marker counts
  5. `runners/codex-ps/templates/bounce-protocol.md` matches the main repo's stronger version (SCOPE CONTROL + "complete document" clauses preserved)
**Plans**: 3 plans

Plans:
- [x] 06-01: Claude adapter tool gating (PRTP-01, PRTP-02, PRTP-03)
- [x] 06-02: Structural bounce-check signal (PRTP-04)
- [x] 06-03: Bounce-protocol reconciliation (PRTP-05)

### Phase 7: Runner Parity
**Goal**: Port the five features the Bash runner lacks relative to the Codex PS reference, so both runners pass the same eval case suite.
**Depends on**: Phase 6
**Requirements**: [RNPT-01, RNPT-02, RNPT-03, RNPT-04, RNPT-05]
**Success Criteria** (what must be TRUE):
  1. One agent dispatcher function routes by provider — phase code calls a single entrypoint instead of hard-coding `codex` or `claude`
  2. Write-phase vs text-phase is a flag; drives Claude permission mode + allowed-tools choice per phase
  3. Pre-execute baseline snapshot hashes every repo file; post-execute produces a `{modified, added, deleted}` delta consumed by verify and the `execution_fidelity` scorer
  4. One structured `state.json` per run captures phase history, marker counts, changed files, and verify verdict as ground truth
  5. Per-phase timeout prevents runaway phases (the single most painful gap flagged by upstream — one PS case hung 1h 39min)
**Plans**: 3 plans

Plans:
- [ ] 07-01: Agent dispatcher hardening + writable-phase abstraction (RNPT-01, RNPT-02)
- [ ] 07-02: state.json + delta tracking helpers and wiring (RNPT-03, RNPT-04)
- [ ] 07-03: Per-phase timeout wrapper + --timeout CLI flag (RNPT-05)

### Phase 8: Evals Absorbed
**Goal**: Make evals cross-runner by elevating portable assets (cases, fixtures, plan) to the top level, while leaving the runner-specific PS harness under `runners/codex-ps/`.
**Depends on**: Phase 7
**Requirements**: [EVAL-01, EVAL-02, EVAL-03]
**Success Criteria** (what must be TRUE):
  1. `evals/cases/` + `evals/fixtures/` + `evals/VERIFICATION-PLAN.md` + `schemas/review-verdict.json` reachable at the repo root for any runner
  2. PS-specific harness (`run-evals.ps1`, `score-run.ps1`, `compare-reports.ps1`) stays under `runners/codex-ps/` with a note that a Bash port is a future item
  3. `pwsh` dependency is documented as optional — required only to run the PS harness, not the Bash runner itself
**Plans**: 1 plan

### Phase 9: Lab Folded
**Goal**: Fold the unique contributions of `co-evolution-lab/` (integrations + memory config) into the unified repo; explicitly exclude Karpathy's `autoresearch` clone as unrelated ML training work.
**Depends on**: Phase 5
**Requirements**: [LABF-01, LABF-02]
**Success Criteria** (what must be TRUE):
  1. `co-evolution-lab/integrations/` contents folded under the unified repo's `integrations/` (or deleted if empty/stale)
  2. `mempalace.yaml` preserved as a reference integration config
  3. Karpathy's `autoresearch` clone left outside the unified repo; decision documented in PROJECT.md
  4. Obsolete lab directories (mirror clone of public repo, empty subdirs) are noted for archival
**Plans**: 1 plan

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9 (Phase 9 may parallelize with 6-8 if needed)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Shared Shell Core | 1/1 | Complete | 2026-04-06 |
| 2. Bouncer Refactor | 1/1 | Complete | 2026-04-06 |
| 3. Codex Runtime | 1/1 | Complete | 2026-04-06 |
| 4. Docs And Routing | 1/1 | Complete | 2026-04-06 |
| 5. Codex PS Preservation | 1/1 | Complete | 2026-04-17 |
| 6. Protocol Parity | 3/3 | Complete | 2026-04-17 |
| 7. Runner Parity | 0/3 | Planned | - |
| 8. Evals Absorbed | 0/1 | Planned | - |
| 9. Lab Folded | 0/1 | Planned | - |
