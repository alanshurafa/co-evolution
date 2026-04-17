---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Phase 8 complete — Evals Absorbed landed (1 plan, 4 tasks, 4 commits, EVAL-01..03); ready for Phase 9 (Lab Folded, final milestone phase)
last_updated: "2026-04-17T22:00:00.000Z"
last_activity: 2026-04-17 -- Phase 08 execution complete
progress:
  total_phases: 9
  completed_phases: 8
  total_plans: 13
  completed_plans: 12
  percent: 92
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-06)

**Core value:** Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps
**Current focus:** Unification Absorb milestone - fold `codex-co-evolution/` + `co-evolution-lab/` into this public repo (phases 5-9)

## Current Position

Phase: 9 of 9 (Lab Folded — ready to plan; final milestone phase)
Plan: 1 of 1 in previous phase complete (08-01 landed)
Status: Ready to plan Phase 9
Last activity: 2026-04-17 -- Phase 08 execution complete
Working directory: `C:/Users/alan/Project/co-evolution-absorb/` (worktree on feat/unification-absorb)

Progress: [########.-] 8/9 phases complete (Phase 8 of Unification Absorb done)

## Performance Metrics

**Velocity:**

- Total plans completed: 12
- Average duration: 17 min
- Total execution time: 3.5 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Shared Shell Core | 1 | 0.3h | 0.3h |
| 2. Bouncer Refactor | 1 | 0.2h | 0.2h |
| 3. Codex Runtime | 1 | 0.5h | 0.5h |
| 4. Docs And Routing | 1 | 0.1h | 0.1h |
| 5. Codex PS Preservation | 1 | 0.25h | 0.25h |
| 6. Protocol Parity | 3 | 1.0h | 0.33h |
| 7. Runner Parity | 3 | 0.83h | 0.28h |
| 8. Evals Absorbed | 1 | 0.25h | 0.25h |

**Recent Trend:**

- Last 5 plans: 08-01, 07-03, 07-02, 07-01, 06-02
- Trend: Fast (Phase 8 was a pure asset-elevation phase — 15min for 4 tasks, 14 byte-identical copies plus one new README; no code changes, zero deviations beyond a README backtick fix)

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Phase 0]: Reuse `skill/templates/` and `skill/schemas/` as the v1 shared prompt contract
- [Phase 0]: Keep execution visible through stepwise commits aligned to the external implementation plan
- [Phase 0]: Use a shared-core, platform-specific-shell architecture for the Claude and Codex runtimes
- [Phase 1]: Fail validation if a short-output retry returns empty content
- [Phase 1]: Allow `fill_conditional()` to replace scalar placeholders after removing tag lines
- [Phase 2]: Route WSL Bash Codex calls through `cmd.exe /c codex` with `wslpath` conversion
- [Phase 2]: Use the shared Codex adapter for run-name generation to preserve named bouncer runs
- [Phase 3]: Normalize Windows path arguments inside the Bash runtime before directory resolution
- [Phase 3]: Treat verifier auth failures as explicit review-needed exits rather than generic parse failures
- [Phase 4]: Route Codex by task shape between direct execution, Agent Bouncer, and the standalone runtime
- [Phase 4]: Use `dev-review/codex/instructions.md` as the reusable Codex startup router for this repo
- [Phase 5]: Verbatim file copy (not subtree merge) chosen because codex-co-evolution had zero commits — no history to preserve
- [Phase 5]: Read-only declaration goes in a dedicated REFERENCE-STATUS.md file, never injected into upstream content, to preserve byte-level verbatim guarantee
- [Phase 6]: Writable-phase flag defaulted to "false" — safer posture if any caller forgets the flag (Claude refuses to write rather than silently writing garbage)
- [Phase 6]: invoke_codex path narrowed from variadic "$@" to explicit positionals with inline comment — codex has no writable analogue, but Phase 7 may revisit
- [Phase 6]: outputs/bounce-NN.txt written AFTER cp to PLAN_PATH so the structural artifact matches the canonical plan content (post-strip_human_summary)
- [Phase 6]: verify_bounce_ran is informational, not gating — distinct signal for future Phase 8 evals to consume
- [Phase 6]: Bounce protocol reconciliation is the one-and-only exception to CXPS-02 read-only, explicitly authorized by UPSTREAM-MESSAGE.md item 3
- [Phase 7]: phase_is_writable fails safe to "false" on unknown phase names — refuses elevation, downgrades to text-phase posture
- [Phase 7]: state.json has no leading dot → survives cleanup_runtime_artifacts sweep; intermediate hash manifests ARE dot-prefixed so they get swept
- [Phase 7]: Delta tracking deliberately excludes nothing beyond .git/ and runs/ — the scorer wants truth ground
- [Phase 7]: Runner exits 1 on timeout (fatal), NOT 124; 124 lives only in state.json.phases[].exit_code for observability
- [Phase 7]: Default PHASE_TIMEOUT=1800s (30min) — generous but catches the 1h 39min hang category; --timeout flag for per-run override
- [Phase 7]: timeout --foreground required (keeps signal handling with invoking shell so SIGTERM reaches network-blocked CLI children)
- [Phase 7]: invoke_agent_with_timeout re-sources lib in bash -c subshell (safer than export -f on MINGW64)
- [Phase 7]: abort_on_timeout centralizes timeout-abort — one code path records state, logs, cleans up, exits 1
- [Phase 8]: Copy, don't move — runners/codex-ps/ remains the Phase-5 byte-identical audit trail (CXPS-02); top-level copies are a parallel portable slice, not a replacement
- [Phase 8]: Schema lands at repo-root schemas/ (not evals/schemas/) because the dev-review verdict parser consumes it too, not just the eval harness
- [Phase 8]: Empty fixtures/seed-repos/ and seeded-bugs/ NOT copied — no portable content; gitignore extension covers the tmp/ and reports/ runtime paths a future Bash harness would populate
- [Phase 8]: Single sentence in evals/README.md drops backticks around `pwsh` so the literal phrase "pwsh is optional" is grep-matchable per the EVAL-03 acceptance gate; rest of README keeps inline-code formatting
- [Phase 8]: .gitignore entries placed in a named block below the runners/codex-ps/ block so the parallel structure (PS runtime vs future Bash harness runtime) is visible to future readers
- [Milestone: Unification Absorb]: Full merge of codex-co-evolution into this public repo (pseudonymity concern moot — no commits ever landed separately)
- [Milestone: Unification Absorb]: Feature branch + draft PR discipline; new worktree at `co-evolution-absorb/` isolated from `co-evolution/` (archive) and `co-evolution-clean/` (master tip)
- [Milestone: Unification Absorb]: Karpathy's `autoresearch` clone excluded from unified repo (unrelated ML training, not about bounce protocol)
- [Milestone: Unification Absorb]: Evals are the iteration mechanism (not Karpathy-style auto-research); Protocol Evolution Loop deferred as future post-absorb work
- [P0]: Required-Section blocks copied verbatim from upstream compose template to eliminate ~66% missing-section variance

### Pending Todos

- Plan Phase 9 (Lab Folded, final milestone phase) — fold co-evolution-lab/integrations/ + mempalace.yaml; exclude Karpathy's autoresearch
- Archive `C:/Users/alan/Project/codex-co-evolution/` workspace — verbatim copy safely preserved at runners/codex-ps/
- Future: Bash port of PS eval harness (~2 days, deferred post-milestone; portable assets now reachable at repo root so no blockers on asset location)
- Future: Protocol Evolution Loop (meta-bounce for self-improving prompts, post-milestone)

### Blockers/Concerns

- RNPT-05 (per-phase timeout) LANDED — upstream's 1h 39min hang category now bounded; smoke test Test A proves a 5s hang is killed in 2.07s wall-clock with exit 124.
- `pwsh` dependency documented as OPTIONAL in evals/README.md — Phase 8 completed EVAL-03; Bash runner (agent-bouncer, dev-review) remains pwsh-free end-to-end.
- Claude `--json-schema` broken on Windows in `-p` mode — must NOT be used; prompt-side JSON + parse-side validation only (PRTP-03)
- Phase 8 eval scorer now has a machine-readable ground-truth input: `$RUN_DIR/state.json` with full schema (run_id/task/agents/phases[]/marker_counts/baseline_hashes/execute_delta/verify_verdict/started_at/completed_at); portable cases + fixtures + schema all reachable from repo root.

## Session Continuity

Last session: 2026-04-17 (active)
Stopped at: Phase 8 execution complete — Evals Absorbed (EVAL-01, EVAL-02, EVAL-03) landed across 1 plan / 4 tasks / 4 commits (6f337da, 011c443, 5558d07, c6679ac, all pushed); ready for Phase 9 planning (Lab Folded — final milestone phase)
Resume file: None — use `git log feat/unification-absorb` for full context
Active PR: https://github.com/alanshurafa/co-evolution/pull/1 (draft)
Reference doc: `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` — the MUST/SHOULD/parity list (MUST-items 3-6 landed in Phase 6; parity items 1-5 all landed in Phase 7; portable artifacts table landed in Phase 8)
