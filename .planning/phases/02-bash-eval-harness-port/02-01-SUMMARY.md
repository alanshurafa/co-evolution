---
phase: 02-bash-eval-harness-port
plan: 01
subsystem: eval-harness
tags: [bash, yaml, jq, yq, library, eval-harness, port, self-test, pel-prerequisite]

# Dependency graph
requires:
  - phase: 01-post-v1.1-fixes
    provides: stable lib/co-evolution.sh log/die contract (declare -F guards in this plan rely on it)
provides:
  - evals/lib/co-evolution-evals.sh sourceable library exposing 8 helpers (read_yaml_file, merge_yaml_defaults, render_report, atomic_json_write, atomic_json_write_stdin, ensure_jq, ensure_yq, load_json_or_sentinel) plus idempotent log/die guards
  - evals/report-template.md byte-identical copy of PS report template so evals/ is self-contained
  - --self-test subcommand that exercises every helper against canonical fixtures and exits 0 with "ALL SELFTESTS PASSED"
affects: [02-02-score-run-port, 02-03-runner-comparator-test, pel-proposer-phases-5-8]

# Tech tracking
tech-stack:
  added: [mikefarah/yq v4.53.2 (installed via scoop; documented as D-03/D-04 allowed dep)]
  patterns:
    - "Sourceable Bash library pattern: no shebang-level strictness, declare -F guards on log/die for safe double-source"
    - "yq -o=json | jq '*' deep-merge as PS Merge-HashtablesDeep analog (lists replaced wholesale, hashtables merged recursively)"
    - "Dual-brace {{TOKEN}} render_report helper co-existing with single-brace fill_template from lib/co-evolution.sh"
    - "Atomic JSON write via mktemp -> jq -> mv with jq stderr captured in die message (T-02-01-06 repudiation mitigation)"
    - "load_json_or_sentinel name-by-reference pattern via `printf -v` for continue-on-bad-verdict scorer semantics"
    - "Embedded --self-test subcommand inside sourceable library, guarded by BASH_SOURCE[0]==0 so sourcing never triggers it"

key-files:
  created:
    - "evals/lib/co-evolution-evals.sh (277 LOC — library + self-test)"
    - "evals/report-template.md (25 lines, byte-identical to runners/codex-ps/evals/report-template.md)"
  modified: []

key-decisions:
  - "Installed mikefarah/yq v4.53.2 via `scoop install yq` (D-03/D-04 allowed dep; was missing from PATH before plan start, not a deviation from plan)"
  - "Kept atomic_json_write's 2>&1-inside-command-substitution pattern as specified in plan; conflates stdout/stderr only on failure path where we're aborting anyway"
  - "Suppressed subshell stdout/stderr in self-test 5a (the intentional YAML->jq failure) with `>/dev/null 2>&1` so the `die` ERROR line does not pollute self-test stdout"
  - "Added Test 3 coverage for `merge_yaml_defaults` case-override (01-trivial-task lowers min_word_count from 120 to 40) AND defaults-survive-in-untouched-keys (min_jaccard=0.5 retained) — tighter semantic check than the plan's original single-assertion draft"
  - "Added Test 5c for atomic_json_write_stdin round-trip (plan's TDD behavior block lists it but the self-test sketch did not include a positive path test)"
  - "Added Test 6c for load_json_or_sentinel happy path (valid JSON -> empty sentinel); plan covered only the two error paths"

patterns-established:
  - "Idempotent-source library: `declare -F fn` guard before defining log/die; survives double-source and source-alongside-lib/co-evolution.sh in either order under set -u"
  - "STRIDE-aligned threat mitigations documented in-file as comments near each helper (T-02-01-01..06 cross-referenced from plan's threat_model)"
  - "Self-test as subcommand (not external test file): keeps fixture dependencies + assertions co-located with the library they test; downstream verify step is single-command `bash <lib> --self-test`"

requirements-completed: [BASH-EVAL-01]

# Metrics
duration: 4min 30s
completed: 2026-04-18
---

# Phase 2 Plan 1: Bash Eval Harness Port — Shared Library Summary

**Sourceable Bash library (`evals/lib/co-evolution-evals.sh`) with 8 helpers wrapping jq/yq for YAML loading, deep-merge, `{{TOKEN}}` report rendering, atomic JSON writes, and sentinel-based verdict loading — plus a copy of the PS report template so the Bash harness is self-contained.**

## Performance

- **Duration:** 4 min 30 s
- **Started:** 2026-04-18T12:56:04Z
- **Completed:** 2026-04-18T13:00:34Z
- **Tasks:** 2 (Task 1 report-template copy + Task 2 library with embedded self-test)
- **Files created:** 2 (evals/report-template.md, evals/lib/co-evolution-evals.sh)
- **Self-test runtime:** ~2.1 s (reference hardware: Windows 11 MINGW64, jq 1.8.1, yq v4.53.2)

## Accomplishments

- Delivered the foundation library Plans 02-02 and 02-03 both source — breaking the contract downstream would cascade, so this was the highest-risk surface in the phase.
- Embedded a --self-test subcommand exercising all 8 helpers plus idempotent double-source and compose-with-lib/co-evolution.sh scenarios; zero manual QA needed for Plan 02-02 to start on firm ground.
- Placed evals/report-template.md under evals/ so downstream PEL phases (5-8) never need to cross-tree-reference runners/codex-ps/; byte-identity check gates the copy so future PS-side edits surface as diff.
- STRIDE threat mitigations (T-02-01-01 through T-02-01-06 from the plan's threat_model) all wired into the code with in-file comments pointing back to their threat IDs.

## API Surface Shipped

Verbatim from plan `<interfaces>` block:

```bash
# Dependency guards
ensure_yq()           # Fatal if yq not on PATH
ensure_jq()           # Fatal if jq not on PATH (already required by runner)

# YAML ops (wrapping mikefarah/yq)
read_yaml_file <path>                           # prints JSON on stdout
merge_yaml_defaults <defaults_path> <case_path> # prints merged JSON on stdout (case wins)

# Report rendering (PS Report.ps1 analog)
render_report <template_path> <key=value ...>   # substitutes {{KEY}} tokens, prints rendered markdown on stdout

# Atomic JSON write (PS-Set-Content analog, follows lib/co-evolution.sh:870-895 pattern)
atomic_json_write <jq_program> <input_json_path> <output_path>  # jq into mktemp; mv on success; rm tmp on failure
atomic_json_write_stdin <jq_program> <output_path>              # same but reads stdin for --slurpfile / jq -n style

# Guards helpful for scorer / verdict loading
load_json_or_sentinel <path> <sentinel_var_name>   # sets sentinel_var_name=missing|unparseable|'' (empty on success)
```

`log`/`die` are defined iff not already present (guarded by `declare -F`) so the library composes cleanly with or without a prior `source lib/co-evolution.sh`.

## Task Commits

Each task committed atomically:

1. **Task 1: Copy PS report template byte-identically to evals/report-template.md** — `654ab8e` (feat)
2. **Task 2: Implement evals/lib/co-evolution-evals.sh sourceable library with self-test** — `d46a955` (feat)

_Note: Plan is `tdd="true"` on Task 2, but the TDD artifact is the embedded `--self-test` block — it WAS written together with the implementation rather than as a separate RED commit. The self-test asserts every helper's behavior (including fail-closed paths in 5a and 6a-b) so the GREEN gate is carried by the same commit. Documented here for gate-compliance traceability._

**Plan metadata:** Will be added in the final `docs()` commit after STATE.md + SUMMARY.md updates.

## Files Created/Modified

- `evals/report-template.md` (NEW, 25 lines) — byte-identical copy of `runners/codex-ps/evals/report-template.md`. Contains `{{TIMESTAMP}}`, `{{CASE_COUNT}}`, `{{PASS_COUNT}}`, `{{FAIL_COUNT}}`, `{{COMPOSITE_AVG}}`, `{{CASE_TABLE}}`, `{{DETAILS_SECTIONS}}` placeholders the Bash scorer (Plan 02-02) will populate via `render_report`.
- `evals/lib/co-evolution-evals.sh` (NEW, 277 LOC) — sourceable library + `--self-test` subcommand. Exposes 8 public helpers plus guarded `log`/`die`. No `set -euo pipefail` at file top (strictness scoped inside the `--self-test` block only).

## Decisions Made

- **yq install happened out-of-band before execution:** yq was not on PATH at plan start (`which yq` empty); I ran `scoop install yq` (v4.53.2) per D-03/D-04 (mikefarah/yq explicitly allowed) so the self-test could exercise the YAML path. Documented here because downstream machines running the library will need the same install — Plan 02-03's README update should codify it.
- **Self-test extends the plan's TDD `<behavior>` spec with 3 extra assertions** that tighten the contract without deviating from it:
  - Test 3 now checks both the override path (case lowers `min_word_count` to 40) and the inherited-defaults path (`min_jaccard=0.5` untouched); the plan's original sketch only checked "defaults survive + case id present," which would have missed a deep-merge bug that drops case-override values.
  - Test 5c covers the `atomic_json_write_stdin` happy path (the plan's sketch only tested the non-stdin variant's happy path and the stdin variant's behavior was only asserted in prose).
  - Test 6c adds the load_json_or_sentinel happy path (empty sentinel for valid JSON), closing a gap where a buggy implementation returning sentinel="ok" on valid input could have passed the plan's sketch.
- **`atomic_json_write` error-capture pattern:** kept the plan's prescribed `err=$(jq ... 2>&1 >"$tmp")` pattern. The alternative (separate `$tmp.err` file) is safer but adds LOC and a second cleanup path; the failure path already conflates anyway because we abort with `die`. If Plan 02-02's fixture testing surfaces a case where jq emits meaningful stdout AND stderr simultaneously, revisit there.
- **Subshell noise suppression in self-test 5a:** added `>/dev/null 2>&1` to the expected-to-fail `atomic_json_write` subshell so the `die` helper's ERROR stdout line does not bleed into the self-test transcript. This keeps the downstream `grep -q "ALL SELFTESTS PASSED"` check clean.

## Deviations from Plan

None required auto-fixing by deviation rules. The three "extra" self-test assertions above are scope *tightening* within the plan's TDD `<behavior>` contract (the plan says the self-test should "exercise every helper against fixtures and exit 0 on success"), not additions outside scope.

## Issues Encountered

1. **yq missing at plan start (pre-execution environment gap, not a plan bug).** The plan assumes yq is installed (D-03). It wasn't on this machine. Resolved via `scoop install yq` before Task 2 — installation took ~4 s. Flagged so Plan 02-03's README update includes the install instructions prominently.
2. **Git Bash CRLF warning on commit** (`LF will be replaced by CRLF the next time Git touches it`). Cosmetic: file on disk is LF (correct for Bash scripts), Git's `core.autocrlf` default on Windows rewrites to CRLF on checkout. Self-test continues to pass because bash tolerates both line endings; no action needed.

## Known Caveats for Downstream Plans

- **Template token syntax is `{{NAME}}`, not `{NAME}`.** Do NOT use `lib/co-evolution.sh::fill_template` on `evals/report-template.md` — it expects single-brace tokens and will leave the PS-derived template untouched. Use `render_report` from this library.
- **`load_json_or_sentinel` assigns by name via `printf -v`.** Caller must pass the *name* of a pre-existing (or to-be-created) local variable, not a value. Calling `load_json_or_sentinel "$path" "$some_local"` would try to assign to a variable named after the CONTENTS of `$some_local` — not what you want. Correct pattern: `local sentinel=''; load_json_or_sentinel "$path" sentinel`.
- **`atomic_json_write` requires a FILE input.** To write JSON that needs `jq -n` / `--slurpfile` assembly, use `atomic_json_write_stdin` with a subshell: `{ jq -n ... } | atomic_json_write_stdin '.' "$output"`.
- **Self-test is coupled to the canonical fixtures `evals/cases/defaults.yaml` and `evals/cases/01-trivial-task.yaml`.** If Plan 02-02 or 02-03 needs to mutate those fixtures (unlikely per scope — they are the eval case corpus), re-verify `--self-test` passes afterward.

## Confirmation: Idempotent-Source Acceptance Test

```
$ bash -c 'set -u; source evals/lib/co-evolution-evals.sh; source evals/lib/co-evolution-evals.sh; echo ok-setu'
ok-setu
$ bash -c 'source lib/co-evolution.sh; source evals/lib/co-evolution-evals.sh; type read_yaml_file >/dev/null && echo ok'
ok
$ bash -c 'source evals/lib/co-evolution-evals.sh; source lib/co-evolution.sh; type read_yaml_file >/dev/null && echo ok'
ok
```

All three orderings pass. Both `log` and `die` retain their lib/co-evolution.sh definition when the evals library is sourced second (`declare -F` guard works).

## Next Plan Readiness

- **Plan 02-02 (score-run port)** can now `source "${SCRIPT_DIR}/lib/co-evolution-evals.sh"` and consume the 8 public helpers per the `<interfaces>` contract.
- **Plan 02-03 (runner + comparator + test)** can source the same library for YAML merge + report rendering in the runner, and for `atomic_json_write_stdin` + `load_json_or_sentinel` wherever needed.
- No blockers for downstream plans.

## Self-Check: PASSED

Verified claims before returning:

- `evals/lib/co-evolution-evals.sh` exists at `C:/Users/alan/Project/co-evolution-v12/evals/lib/co-evolution-evals.sh` (277 LOC)
- `evals/report-template.md` exists and is byte-identical to the PS source (`diff` exit 0, zero output)
- Commit `654ab8e` present in `git log --oneline` on branch `feat/v1.2-pel-proposer`
- Commit `d46a955` present in `git log --oneline` on branch `feat/v1.2-pel-proposer`
- `bash evals/lib/co-evolution-evals.sh --self-test` exits 0 with `ALL SELFTESTS PASSED` on stdout
- All 10 public helpers (log, die, ensure_jq, ensure_yq, read_yaml_file, merge_yaml_defaults, render_report, atomic_json_write, atomic_json_write_stdin, load_json_or_sentinel) resolve via `type` after sourcing

---
*Phase: 02-bash-eval-harness-port*
*Plan: 01*
*Completed: 2026-04-18*
