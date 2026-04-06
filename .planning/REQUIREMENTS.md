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

- [ ] **CDRT-01**: Maintainer can run `dev-review/codex/dev-review.sh` to execute compose, bounce, execute, and optional verify phases from the shell
- [ ] **CDRT-02**: Codex runtime supports `--composer`, `--executor`, `--bounces`, `--verify`, `--plan-only`, `--skip-plan`, `--plan FILE`, `--model`, and `--workdir`
- [ ] **CDRT-03**: Codex runtime always embeds plan content inline in prompts so the canonical plan path is not exposed to the agent executor
- [ ] **CDRT-04**: Codex runtime writes durable run artifacts and returns exit codes for success, fatal failure, and revise verdicts

### Docs And Routing

- [ ] **DOCS-01**: Maintainer can use a Codex instruction file to route between `dev-review.sh`, `agent-bouncer.sh`, and direct execution
- [ ] **DOCS-02**: Repo docs explain the Codex runtime and its supported usage patterns

## v2 Requirements

### Runtime Ergonomics

- **RTUX-01**: Codex runtime can launch visible Windows terminals for live pass-by-pass observation
- **RTUX-02**: Codex runtime can create and manage dedicated branches or worktrees automatically
- **RTUX-03**: Codex runtime can loop automatically on REVISE verdicts until approval or user stop

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
| CDRT-01 | Phase 3 | Pending |
| CDRT-02 | Phase 3 | Pending |
| CDRT-03 | Phase 3 | Pending |
| CDRT-04 | Phase 3 | Pending |
| DOCS-01 | Phase 4 | Pending |
| DOCS-02 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 10 total
- Mapped to phases: 10
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-06*
*Last updated: 2026-04-06 after completing Phase 2 bouncer refactor work*
