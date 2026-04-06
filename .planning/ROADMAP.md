# Roadmap: Co-Evolution

## Overview

This roadmap adds a standalone Codex runtime to the existing Co-Evolution toolkit without destabilizing the current Agent Bouncer or Claude Code skill. The work proceeds from shared shell foundations, to a behavior-preserving bouncer refactor, to the new Codex runtime, and finally to the instruction and documentation layer that makes the new runtime discoverable.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Shared Shell Core** - Extract reusable shell helpers into a common library
- [ ] **Phase 2: Bouncer Refactor** - Move Agent Bouncer onto the shared shell core without behavior drift
- [ ] **Phase 3: Codex Runtime** - Add the standalone Codex `dev-review` runtime script
- [ ] **Phase 4: Docs And Routing** - Add Codex instructions and repo docs for the new runtime

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
- [ ] 02-01: Refactor Agent Bouncer onto shared library helpers

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
- [ ] 03-01: Create Codex `dev-review` runtime script

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
- [ ] 04-01: Add Codex runtime instructions and documentation

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Shared Shell Core | 1/1 | Complete | 2026-04-06 |
| 2. Bouncer Refactor | 0/1 | Not started | - |
| 3. Codex Runtime | 0/1 | Not started | - |
| 4. Docs And Routing | 0/1 | Not started | - |
