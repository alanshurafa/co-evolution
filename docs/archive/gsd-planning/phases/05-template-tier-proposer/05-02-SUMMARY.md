---
phase: 05-template-tier-proposer
plan: 02
subsystem: pel
tags: [pel, template-proposer, simulation, hermetic-test, path-injection, sc-4, bash]

# Dependency graph
requires:
  - phase: 05-template-tier-proposer
    provides: "proposer.sh (D-03/D-09/D-10 gates) + adapter.sh (capture_diff, invoke_opus) + prompt.md (flavor-aware instructions) + 4 fixture templates + 4 eval-failure JSON fixtures from Plan 01"
provides:
  - "tests/template-proposer-simulation.sh (469 lines, 8 hermetic scenarios) — the SC-4 simulation gate"
  - "PATH-injected claude CLI stub pattern that reads PROPOSER_STUB_FILE; fingerprint-marker channel via PROPOSER_STUB_MARKER for future bypass-invariant proofs"
  - "Dynamic diff generation via cp + sed + diff -u so hunk line numbers track the real fixture contents (not hand-authored @@ headers that would drift on any template edit)"
affects:
  - "Phase 8 (PR emission) — the proposer surface Phase 5 shipped is now the template-tier entry point; Phase 8's pel-proposer lab mode dispatches here for --target skills/dev-review/templates/*.md invocations"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dynamic-diff simulation: generate stub diffs via `cp + sed + diff -u --label` so hunk headers compute correctly even if the fixture content shifts — avoids the fragility of hand-authored line-number examples"
    - "Fingerprint-marker channel for proving bypass invariants: stub writes a marker file on invocation, test asserts marker absence after override paths (future use — Phase 4 analog)"
    - "`N/N scenarios passed` final-line footer is the v1.2 phase-gate convention: Phase 2 13/13, Phase 3 4/4, Phase 4 6/6, Phase 5 8/8"

key-files:
  created:
    - "tests/template-proposer-simulation.sh (469 lines) — 8-scenario hermetic simulation"
    - ".planning/phases/05-template-tier-proposer/05-02-SUMMARY.md (this file)"
  modified:
    - "lab/pel/proposer/template/adapter.sh — capture_diff awk regex narrowed from ^[[:space:]]*$ to ^$ (truly-empty only) to preserve single-space context lines that represent originally-empty file lines in unified diffs"
    - "lab/pel/proposer/template/proposer.sh — git apply --check gained --whitespace=nowarn for CRLF-on-disk tolerance on Windows Git Bash; switched to printf '%s\\n' to preserve the trailing newline that command substitution strips from `$(run_adapter)`"

key-decisions:
  - "capture_diff regex fix (awk /^$/ instead of /^[[:space:]]*$/) — a single-space line in a unified diff is meaningful hunk content (empty-line context marker), not trimmable whitespace. The original over-broad regex was stripping those and breaking hunk line counts, causing git apply to reject with 'corrupt patch at line N'. Narrowed regex preserves semantic correctness while still trimming any truly-empty leading/trailing lines the LLM might insert."
  - "Dynamic-diff generation over hand-authored @@ headers — the plan's example diff used `@@ -10,7 +10,9 @@` which didn't match the real bounce-protocol.md fixture. Executor went with the plan's 'alternative approach' of `cp + sed + diff -u` so hunk headers always compute correctly against the current fixture state. Eliminates a whole class of drift bugs."
  - "`--whitespace=nowarn` on git apply --check — Windows Git Bash defaults to core.autocrlf=true, which caused spurious 'corrupt patch' rejections even on structurally-valid diffs. The flag suppresses whitespace-diff warnings without disabling the structural gate. Defensible cross-platform fix (no-op on Linux/macOS where autocrlf defaults to input or false)."
  - "Fixture CRLF state preserved as committed — earlier attempt to normalize fixtures to LF on disk was reverted. Git's autocrlf=true auto-normalizes back on checkout, and the real fix was in capture_diff, not the on-disk encoding. Keeps the fixture bit-for-bit-identical to the real templates they copy."

patterns-established:
  - "Unified-diff regex discipline: when processing unified-diff content in shell, distinguish 'truly empty line' (^$) from 'whitespace-only line' (^[[:space:]]*$). A leading single space followed by newline is a context-line marker for an originally-empty source line — trimming it by mistake breaks hunk counts. Relevant for any future tooling that parses diffs in bash/awk (Phase 6 policy proposer's delta-application, Phase 7 code proposer's sandbox patch)."
  - "Command-substitution trailing-newline recovery: `out=$(some-command)` always strips trailing newlines. If out must be piped back as a stream that requires terminal newlines (git apply, jq -e, patch), restore with `printf '%s\\n' \"$out\"`. Otherwise bash-3+ subtly corrupts the output."

requirements-completed: [PEL-02]

# Metrics
duration: ~3 min (inline fixes by orchestrator after agent hit API rate limit; agent had shipped Plan 01 + fixtures + 6/7 commits in ~25 min before cutoff)
completed: 2026-04-18
---

# Phase 5 Plan 02: Template-tier proposer simulation gate

**Hermetic 8-scenario SC-4 gate at tests/template-proposer-simulation.sh proves the Plan 01 template proposer surface (proposer.sh + adapter.sh + prompt.md) handles all 4 flavor paths correctly AND rejects all 4 adversarial paths with the correct exit codes.**

## Performance

- **Duration:** ~3 min (final inline fixes by orchestrator) + ~25 min (agent's earlier work before rate limit cutoff)
- **Completed:** 2026-04-18
- **Final commits:** 2 (fix + test)
- **Test runtime:** ~2-3 seconds end-to-end

## Accomplishments

- **8/8 scenarios green on Windows Git Bash end-to-end.** Simulation exits 0 with `8/8 scenarios passed` as the final line — matches v1.2 phase-gate footer convention.
- **Dynamic stub-diff generation so fixture edits don't invalidate the tests.** Every scenario calls `write_valid_stub_diff <dest> <repo_rel_fixture> <sed_script>` which runs `cp + sed + diff -u --label` against the live fixture. If a fixture is ever updated, the diff's hunk header recomputes automatically.
- **Two root-cause bugs in the proposer code path surfaced and fixed:**
  1. `capture_diff`'s blank-line-trim regex was too broad — `^[[:space:]]*$` matched single-space context lines (unified-diff markers for originally-empty source lines). Trimming those broke hunk counts. Narrowed to `^$` (truly-empty only).
  2. `printf "%s" "$diff_text"` in proposer.sh was missing the trailing newline stripped by command substitution. Switched to `printf "%s\n"` so git apply parses the final hunk correctly.
- **Windows Git Bash CRLF tolerance via `--whitespace=nowarn`** — defensible cross-platform fix, no-op on Linux/macOS.

## Commits

1. **fix(05-01): D-10 apply gate — preserve empty-context hunks + whitespace tolerance** — `7303cce`
2. **test(05-02): add template proposer simulation gate (SC-4)** — `9735d99`

(Plus the upstream Plan 01 commits landed earlier: prompt.md `6628b62`, adapter.sh `b9e0f88`, proposer.sh `bc9c729`, README `3c83d42`, D-05 comment rewording `86b5d75`, Plan 01 SUMMARY `1a38e3d`, fixtures `325c170`.)

## Files Created/Modified

- `tests/template-proposer-simulation.sh` (CREATED, 469 lines) — 8 hermetic scenarios with per-scenario subshells, PATH-injected claude CLI stub, dynamic diff generation, `N/N scenarios passed` footer
- `lab/pel/proposer/template/adapter.sh` (MODIFIED, +9/-2 lines net) — `capture_diff` regex narrowed, comment explains why
- `lab/pel/proposer/template/proposer.sh` (MODIFIED, +8/-6 lines net) — `--whitespace=nowarn` + `printf "%s\n"` trailing-newline recovery

## Scenario Coverage (SC-4)

| Scenario | Flavor / Adversarial case | Fixture | Exit | Gate | Status |
|----------|---------------------------|---------|------|------|--------|
| A | bug-catcher | bounce-protocol.md | 0 | positive | PASS |
| B | faster-converger | bounce-prompt-portable.md | 0 | positive | PASS |
| C | blind-spot-surfacer | review-prompt-opus.md | 0 | positive | PASS |
| D | general (empty task hint) | dev-prompt-opus.md | 0 | positive | PASS |
| E | multi-file diff | 2 files concatenated | 4 | D-09 single-file | PASS |
| F | non-template path | lab/pel/classifier/adapter.sh diff | 4 | D-09 path-prefix | PASS |
| G | malformed diff (missing @@ header) | synthetic | 3 | D-10 git-apply-check | PASS |
| H | missing PEL_EVAL_REPORT | — | 1 | D-03 fail-fast | PASS |

## Decisions Made

- **capture_diff regex narrowed to `^$`** rather than adding a prefix-check to preserve meaningful empty-context lines. The alternative (keep `^[[:space:]]*$` but not trim inside hunks) would have required tracking hunk-block boundaries in awk — more complex and fragile. Narrower regex is simpler and semantically correct.
- **Dynamic cp+sed+diff over hand-authored diffs** (Plan 02's own "alternative approach" was promoted to primary) — the planner's fixed-line-number example was incorrect for the real bounce-protocol.md fixture (error: corrupt patch at line 12). Dynamic generation eliminates drift.
- **Fixture CRLF preserved** — reverted an earlier experiment that normalized fixtures to LF on disk. Git auto-converts back on checkout via autocrlf=true, and the real fix belongs in the adapter code, not the fixture encoding.
- **Info-level checker warning (scenario E/F/G/H permissive grep) accepted as-is** for v1.2.** The error strings Plan 01 Task 3 emits include variable content (counts, model names), so a single canonical string match would be over-specified. Multi-alternative matches are idiomatic here.

## Deviations from Plan

- **W-1 (Plan 01 Tasks 2+3 contract coordination):** Executor propagated `PEL_TEMPLATE_PATH_REL` / `PEL_TEMPLATE_PATH_ABS` through adapter.sh's `compose_prompt` as the checker flagged. proposer.sh exports both forms; adapter uses REL for substitution and ABS for content read.
- **W-2 (fictional line numbers):** Resolved by dynamic diff generation — see Decisions above.
- **W-3 (fragile `contains: "review"`):** The `diff -q` byte-identical assertion in Plan 02 Task 1 is the load-bearing gate; the `contains: "review"` fallback is kept as-is because it costs nothing and the real template's title still contains "review".
- **Late-surfacing root causes (adapter awk + proposer trailing newline):** These were NOT in the original plan but were discovered at runtime when the simulation first ran red with 4/8 passing. Fixed inline by the orchestrator after the executor agent hit an API rate limit. Both fixes are defensible — the bugs pre-existed and the simulation caught them, exactly as SC-4 intends.

**Total deviations:** 0 Rule 1/2/3 auto-fixes at the agent level; 2 Rule 3 inline fixes by orchestrator after rate-limit cutoff (both documented above).

## Issues Encountered

- **Rate-limit cutoff at ~25 min into the agent's run** — API budget ran out mid-execution. Agent had landed 6 of 7 planned commits (Plan 01 complete, Plan 02 fixtures complete, simulation.sh file written but not committed, 05-02-SUMMARY not yet written). Orchestrator resumed on the unfinished work: committed the simulation.sh, debugged 4 red scenarios, fixed 2 root-cause bugs, wrote this SUMMARY.
- **Two subtle bugs the agent's test-first flow surfaced:** capture_diff regex + printf trailing-newline. Neither was visible in bash -n or unit-level testing; only the full simulation exposed them. SC-4 doing exactly its job.

## User Setup Required

None. Pure Bash + jq + git + diff + sed + awk — all established dependencies. No API keys, no service config.

## Next Phase Readiness

- **Phase 5 is 2/2 plans complete.** Template-tier proposer ships with full D-03 + D-09 + D-10 + T-05-01..05 surface verified by 8/8 simulation.
- **Phase 6 (Policy-tier proposer) is parallelizable and already in-flight** in sibling worktree `feat/v1.2-phase6-policy` — also 2/2 plans complete, 8/8 simulation.
- **Phase 8 (PR emitter) is unblocked for the template-tier path:** invokes `lab/pel/proposer/template/proposer.sh` with (PEL_EVAL_REPORT, PEL_TEMPLATE_PATH, PEL_FLAVOR) and consumes unified-diff stdout for `git apply` into the PR body.
- **No blockers carried forward.**

## Self-Check: PASSED

- [x] 8/8 scenarios pass, exact final-line match
- [x] All plan `<verify>` blocks pass
- [x] `bash -n` clean on proposer.sh + adapter.sh + simulation.sh
- [x] No outbound sources from lab/pel/proposer/template/ (grep-verified)
- [x] No FROZEN.md sentinels, no banner comments — path-based freeze preserved
- [x] STATE.md + ROADMAP.md NOT modified in this worktree (orchestrator handles centrally)
- [x] All 4 flavor picks cover all 4 ROADMAP SC flavors
- [x] T-05-01..05 threat mitigations verified end-to-end via scenarios E/F/G/H

---

*Phase: 05-template-tier-proposer*
*Completed: 2026-04-18*
