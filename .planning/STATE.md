---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: Polish & Ergonomics
status: in-progress
stopped_at: Phase 3 execution complete — Visible Live Mode (RTUX-01) landed across 1 plan / 3 tasks / 3 commits (5c09fc1, cd84c13, 7c15e33, all pushed to feat/v1.1-polish); smoke test passes three scenarios (absent / non-Windows / simulated-Windows) in <1s; default LIVE_MODE=false preserves Phase 2 byte-parity; 2 of 3 RTUX requirements closed in v1.1 (RTUX-01+RTUX-03); only RTUX-02 (Phase 4 worktree management) remains
last_updated: "2026-04-17T23:30:00.000Z"
last_activity: 2026-04-17 -- Phase 03 execution complete; RTUX-01 live mode shipped on feat/v1.1-polish
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 4
  completed_plans: 3
  percent: 75
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-06)

**Core value:** Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps
**Current focus:** v1.1 Polish & Ergonomics — address v1.0 code-review warnings, then deliver the three deferred runtime-ergonomics requirements (RTUX-01/02/03)

## Current Position

Phase: 3 of 4 — Visible Live Mode COMPLETE; only Phase 4 (Worktree Management, RTUX-02) remains
Plan: 03-01 complete (3 tasks, 3 commits)
Status: v1.1 in progress — 3 of 4 phases complete (Phase 1 FIX-WR fixes + Phase 2 RTUX-03 auto-loop + Phase 3 RTUX-01 live mode all landed on feat/v1.1-polish)
Last activity: 2026-04-17 -- Phase 03 complete; RTUX-01 live mode shipped
Working directory: `C:/Users/alan/Project/co-evolution-v11/` (feat/v1.1-polish branch)

Progress: [###.......] 3/4 phases complete — v1.1 Polish & Ergonomics in progress

## Performance Metrics

**Velocity:**

- Total plans completed: 14
- Average duration: 16 min
- Total execution time: 3.9 hours

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
| 9. Lab Folded | 1 | 0.03h | 0.03h |

**Recent Trend:**

- Last 5 plans: 09-01, 08-01, 07-03, 07-02, 07-01
- Trend: Fastest (Phase 9 — single-artifact fold plus one exclusion-documentation README — landed in 2min with zero deviations, first-pass clean on all 8 README acceptance gates and all 7 phase-level verification gates)

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
- [Phase 9]: Copy-not-move on co-evolution-lab/mempalace.yaml — lab source stays intact so the peer workspace can be archived non-destructively at the user's discretion
- [Phase 9]: integrations/ at repo root follows Phase 8 top-level adjacent-folder pattern (evals/, schemas/, runners/, integrations/) — no nesting under runners/ or dev-review/
- [Phase 9]: integrations/README.md defers autoresearch decision authority to PROJECT.md Key Decisions table (no rationale restatement) — README points at it rather than duplicating
- [Phase 9]: Lab PS integration scripts marked deferred, not out-of-scope — door left open for future workspace-agnostic ports without polluting the current milestone
- [Milestone: Unification Absorb]: Full merge of codex-co-evolution into this public repo (pseudonymity concern moot — no commits ever landed separately)
- [Milestone: Unification Absorb]: Feature branch + draft PR discipline; new worktree at `co-evolution-absorb/` isolated from `co-evolution/` (archive) and `co-evolution-clean/` (master tip)
- [Milestone: Unification Absorb]: Karpathy's `autoresearch` clone excluded from unified repo (unrelated ML training, not about bounce protocol)
- [Milestone: Unification Absorb]: Evals are the iteration mechanism (not Karpathy-style auto-research); Protocol Evolution Loop deferred as future post-absorb work
- [P0]: Required-Section blocks copied verbatim from upstream compose template to eliminate ~66% missing-section variance
- [v1.1 Phase 2]: REVISE auto-loop default (`REVISE_LOOP_MAX=0`) preserves v1.0 behavior byte-for-byte — opt-in only via `--revise-loop N` CLI flag or exported env var
- [v1.1 Phase 2]: Retry-pass state.json names chosen as `execute-N`/`verify-N` (bare names kept for pass 1) so existing consumers see extra attempts rather than breaking schema
- [v1.1 Phase 2]: `phase_is_writable` anchored regex `^execute-[0-9]+$` accepts numbered retry passes without enumerating every possible pass number; fails safe on injection-style names (T-02-01)
- [v1.1 Phase 2]: Loop body extracted into `_run_revise_loop` so simulation test and main flow share one implementation — divergence impossible without test breakage (planner's recommendation)
- [v1.1 Phase 2]: Reviewer-authored fields rendered via `jq -r` before reaching the execute prompt — T-02-02 defense-in-depth beyond the existing "Do NOT deviate" prompt rule
- [v1.1 Phase 3]: `LIVE_MODE` default "false" preserves Phase 2 byte-parity; banner gains one "Live mode: false" log line (analogous to Phase 2's "Timeout:" addition) — opt-in only via `--live` CLI flag or `LIVE_MODE=true` env var
- [v1.1 Phase 3]: `maybe_launch_live_window` always returns 0 — wt.exe/cmd.exe launcher failures log a WARNING but never block the main phase (must-not-block invariant); backgrounded + disowned so main shell never waits
- [v1.1 Phase 3]: Platform detection priority `$OSTYPE msys*/cygwin* → wt.exe → cmd.exe` — first match wins; `is_windows_host` function can be overridden in tests to simulate any platform
- [v1.1 Phase 3]: Single `maybe_launch_live_window "verify"` call before the codex/opus verifier branch covers both paths (shared `$review_stderr_file`) — avoids duplicating the call in each branch
- [v1.1 Phase 3]: Retry branches (execute-retry, bounce-retry-via-ensure_valid_plan_output) NOT wrapped per CONTEXT.md — keeps window count reasonable during recovery scenarios
- [v1.1 Phase 3]: Smoke test stubs `wt.exe` via PATH-shadowing + overrides `is_windows_host` function per scenario — runs on any OS without a real Windows host, so CI can exercise the full launcher path

### Pending Todos

- Archive `C:/Users/alan/Project/codex-co-evolution/` workspace — verbatim copy safely preserved at runners/codex-ps/ (CXPS-01)
- Archive `C:/Users/alan/Project/co-evolution-lab/` workspace — mempalace.yaml folded (LABF-01); all other items explicitly excluded with rationale in integrations/README.md (LABF-02)
- Open draft PR for review: https://github.com/alanshurafa/co-evolution/pull/1 — milestone done, ready for final review
- Future: Bash port of PS eval harness (~2 days, deferred post-milestone; portable assets now reachable at repo root so no blockers on asset location)
- Future: Protocol Evolution Loop (meta-bounce for self-improving prompts, post-milestone)
- Future: Workspace-agnostic ports of lab PS integration scripts (deferred per Phase 9 README — not out-of-scope, just not part of this milestone)

### Blockers/Concerns

- RNPT-05 (per-phase timeout) LANDED — upstream's 1h 39min hang category now bounded; smoke test Test A proves a 5s hang is killed in 2.07s wall-clock with exit 124.
- `pwsh` dependency documented as OPTIONAL in evals/README.md — Phase 8 completed EVAL-03; Bash runner (agent-bouncer, dev-review) remains pwsh-free end-to-end.
- Claude `--json-schema` broken on Windows in `-p` mode — must NOT be used; prompt-side JSON + parse-side validation only (PRTP-03)
- Phase 8 eval scorer now has a machine-readable ground-truth input: `$RUN_DIR/state.json` with full schema (run_id/task/agents/phases[]/marker_counts/baseline_hashes/execute_delta/verify_verdict/started_at/completed_at); portable cases + fixtures + schema all reachable from repo root.

## Session Continuity

Last session: 2026-04-17 (active)
Stopped at: Phase 3 execution complete — Visible Live Mode (RTUX-01) landed across 1 plan / 3 tasks / 3 commits (5c09fc1, cd84c13, 7c15e33, all pushed to feat/v1.1-polish); smoke test covers absent / non-Windows / simulated-Windows scenarios in <1s; default LIVE_MODE=false preserves Phase 2 byte-parity; 2 of 3 RTUX requirements closed in v1.1 (RTUX-01+RTUX-03); only Phase 4 (RTUX-02 worktree management) remains
Resume file: `.planning/phases/03-visible-live-mode/03-SUMMARY.md` — phase-level summary; `03-01-SUMMARY.md` for plan-level detail
Active PR: None yet on v1.1; branch `feat/v1.1-polish` accumulating commits
Reference doc: `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` — original MUST/SHOULD/parity list (all v1.0 items closed); `.planning/phases/03-visible-live-mode/03-01-PLAN.md` for the canonical implementation contract of this phase
