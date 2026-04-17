# Requirements: Co-Evolution

**Defined:** 2026-04-06
**Core Value:** Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps

## v1 Requirements

### Shared Shell Core

- [x] **CORE-01**: Maintainer can source `lib/co-evolution.sh` without triggering side effects at source time
- [x] **CORE-02**: Shared library exposes reusable shell helpers for agent invocation, marker counting, HUMAN SUMMARY stripping, output validation, template filling, conditional block handling, logging, and verdict parsing

### Agent Bouncer

- [x] **BNCR-01**: Agent Bouncer sources the shared library instead of duplicating helper implementations
- [x] **BNCR-02**: Agent Bouncer preserves its current run artifact names, clean-output behavior, marker counting behavior, and retry logic after the refactor

### Codex Runtime

- [x] **CDRT-01**: Maintainer can run `dev-review/codex/dev-review.sh` to execute compose, bounce, execute, and optional verify phases from the shell
- [x] **CDRT-02**: Codex runtime supports `--composer`, `--executor`, `--bounces`, `--verify`, `--plan-only`, `--skip-plan`, `--plan FILE`, `--model`, and `--workdir`
- [x] **CDRT-03**: Codex runtime always embeds plan content inline in prompts so the canonical plan path is not exposed to the agent executor
- [x] **CDRT-04**: Codex runtime writes durable run artifacts and returns exit codes for success, fatal failure, and revise verdicts

### Docs And Routing

- [x] **DOCS-01**: Maintainer can use a Codex instruction file to route between `dev-review.sh`, `agent-bouncer.sh`, and direct execution
- [x] **DOCS-02**: Repo docs explain the Codex runtime and its supported usage patterns

## v2 Requirements

### Runtime Ergonomics

- **RTUX-01**: Codex runtime can launch visible Windows terminals for live pass-by-pass observation
- **RTUX-02**: Codex runtime can create and manage dedicated branches or worktrees automatically
- **RTUX-03**: Codex runtime can loop automatically on REVISE verdicts until approval or user stop

## v3 Requirements — Unification Absorb (2026-04-17)

Source: `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` (after Phase 5 absorb). Adopts MUST-items from the private Codex reference implementation, ports runner parity features, and absorbs the eval harness.

### Codex PS Preservation

- [x] **CXPS-01**: `runners/codex-ps/` contains the full `codex-co-evolution/` tree verbatim (scripts, templates, schemas, docs, evals)
- [x] **CXPS-02**: `runners/codex-ps/` is documented as a read-only reference impl; subsequent phases do not extend it

### Protocol Parity

- [x] **PRTP-01**: Claude adapter uses `--disallowedTools "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch"` on text-producing phases (compose, bounce, review, arbitrate)
- [x] **PRTP-02**: Claude adapter uses `--permission-mode bypassPermissions --allowedTools "Edit,Write,Read,Glob,Grep,Bash(git status),Bash(git diff)" --add-dir <workdir>` on write-producing phases (execute, fix)
- [x] **PRTP-03**: No code path passes `--json-schema` to Claude (confirmed broken on Windows in `-p` mode as of 2026-04-17)
- [x] **PRTP-04**: Verification layer checks for `outputs/bounce-NN.txt` files alongside semantic marker counts to distinguish "converged in 0 passes" from "bounce skipped entirely"
- [x] **PRTP-05**: `runners/codex-ps/templates/bounce-protocol.md` is reconciled to match the main repo's stronger version ("complete document" + SCOPE CONTROL clauses preserved)

### Runner Parity

- [x] **RNPT-01**: One agent dispatcher function routes by provider; phase code calls it instead of hard-coding provider names
- [x] **RNPT-02**: Write-phase vs text-phase is a flag; drives Claude permission mode + allowed-tools selection
- [x] **RNPT-03**: Pre-execute baseline snapshot hashes every repo file; post-execute produces a `{modified, added, deleted}` delta consumed by verify and the `execution_fidelity` scorer
- [x] **RNPT-04**: One structured `state.json` per run captures phase history, marker counts, changed files, and verify verdict as ground truth
- [x] **RNPT-05**: Per-phase timeout aborts runaway phases and records the timeout in `state.json`

### Evals Absorbed

- **EVAL-01**: `evals/cases/*.yaml` (with `defaults.yaml`) live at the top level, available to any runner
- **EVAL-02**: `evals/fixtures/`, `evals/VERIFICATION-PLAN.md`, and `schemas/review-verdict.json` live at the top level
- **EVAL-03**: PS-specific harness (`run-evals.ps1`, `score-run.ps1`, `compare-reports.ps1`) stays under `runners/codex-ps/`; `pwsh` documented as optional dependency for running evals

### Lab Folded

- **LABF-01**: `co-evolution-lab/integrations/` contents folded under the unified repo's `integrations/` (or deleted if empty/stale)
- **LABF-02**: `mempalace.yaml` preserved as a reference integration config; Karpathy's `autoresearch` explicitly excluded with rationale documented in PROJECT.md

## Out of Scope

| Feature | Reason |
|---------|--------|
| Visible live mode in this pass | Adds platform-specific complexity before the core runtime is proven |
| Automatic worktree or branch management | Useful later, but not required to prove the runtime orchestration |
| Repo-wide `skill/` restructure | Separate concern from the Codex runtime delivery |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CORE-01 | Phase 1 | Complete |
| CORE-02 | Phase 1 | Complete |
| BNCR-01 | Phase 2 | Complete |
| BNCR-02 | Phase 2 | Complete |
| CDRT-01 | Phase 3 | Complete |
| CDRT-02 | Phase 3 | Complete |
| CDRT-03 | Phase 3 | Complete |
| CDRT-04 | Phase 3 | Complete |
| DOCS-01 | Phase 4 | Complete |
| DOCS-02 | Phase 4 | Complete |
| CXPS-01 | Phase 5 | Complete |
| CXPS-02 | Phase 5 | Complete |
| PRTP-01 | Phase 6 | Complete |
| PRTP-02 | Phase 6 | Complete |
| PRTP-03 | Phase 6 | Complete |
| PRTP-04 | Phase 6 | Complete |
| PRTP-05 | Phase 6 | Complete |
| RNPT-01 | Phase 7 | Complete |
| RNPT-02 | Phase 7 | Complete |
| RNPT-03 | Phase 7 | Complete |
| RNPT-04 | Phase 7 | Complete |
| RNPT-05 | Phase 7 | Complete |
| EVAL-01 | Phase 8 | Planned |
| EVAL-02 | Phase 8 | Planned |
| EVAL-03 | Phase 8 | Planned |
| LABF-01 | Phase 9 | Planned |
| LABF-02 | Phase 9 | Planned |

**Coverage:**
- v1 requirements: 10 total (all Complete)
- v3 requirements: 17 total — 12 Complete (CXPS-01/02 + PRTP-01..05 + RNPT-01..05), 5 Planned (EVAL-01..03 + LABF-01/02)
- Mapped to phases: 27
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-06*
*Last updated: 2026-04-17 — RNPT-01..05 marked Complete after Phase 7 execution*
