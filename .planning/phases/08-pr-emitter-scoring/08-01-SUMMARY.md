---
phase: 08-pr-emitter-scoring
plan: 01
subsystem: pr-emitter
tags: [pel, pr-emitter, plumbing, def-07-01-fix, tier-routing, wrapper-flags, byte-parity]

# Dependency graph
requires:
  - phase: 03-lab-scaffold
    provides: "dispatch_lab_mode() routing + validate_lab_mode() regex (both unchanged, consumed via exec)"
  - phase: 07-code-tier-proposer
    provides: "proposer.sh:306 sandbox-setup line (DEF-07-01 fix site) + allowlist.txt (tier auto-detect code-tier source of truth) + D-17 exit taxonomy 0-8 (extended to 10 here)"
provides:
  - "lab/pel/pr-emitter/pr-emitter.sh — 218 LOC skeleton: argv parser (7 flags + --), D-04 tier auto-detect, dry-run PATH-stub scaffold, scoring stub w/ Plan-02 marker"
  - "lab/pel/pr-emitter/pr-body-template.md — 13-placeholder {{KEY}} (double-brace) template per D-20"
  - "lab/pel/pr-emitter/entry.sh — dispatch shim that pr-emitter wrapper chain exec's into"
  - "lab/pel-proposer/entry.sh — flat-namespace dispatch resolver (Rule 3 auto-fix reconciling plan must-haves)"
  - "7 new wrapper flags on BOTH runners (co-evolve-bouncer.sh + dev-review/codex/dev-review.sh) — --target, --tier, --pr-branch, --dry-run, --budget, --yes, --flavor"
  - "Dispatch rebuild pattern: lab_tail=() array forwarding for pel-proposer; elif branch preserving Phase 3 $TASK behavior for other lab modes"
  - "D-17 exit taxonomy extended to 10 (tier auto-detect hard-error) in pr-emitter.sh header"
  - "DEF-07-01 closed — proposer.sh:306 stdout leak suppressed; Phase 7 sim 16/16 re-verified"
affects:
  - "Phase 8 Plan 02 — replaces scoring stub with scorer + gh pr create + pr-body render"
  - "Phase 7 deferred-items.md — DEF-07-01 marked closed with commit + re-verification proof"
  - ".gitignore — .co-evolve-cache/ gitignored for Plan 02's eval cache"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Flat-namespace dispatch resolver shim: lab/<flat-mode>/entry.sh as one-line exec into nested lab/<group>/<inhabitant>/entry.sh (preserves dispatch_lab_mode single-segment resolution)"
    - "Wrapper argv rebuild with bash array: lab_tail=(); lab_tail+=(...); dispatch \"${lab_tail[@]}\" — each word passed as separate argv slot (no word-splitting, no re-evaluation)"
    - "{{KEY}} double-brace placeholder delimiter — avoids collision with diff hunk-header braces @@ -X,Y +A,B @@"
    - "D-04 tier auto-detect rule table as bash case + grep -Fxq: case-glob for template/policy tiers, exact-line allowlist match for code tier, fail-closed on no-match (exit 10)"
    - "PATH-shadowed gh stub posture: mktemp -d + cat heredoc + chmod +x + PATH prepend + trap EXIT cleanup (inherits Phase 7 canary pattern)"

key-files:
  created:
    - "lab/pel/pr-emitter/pr-emitter.sh (218 LOC)"
    - "lab/pel/pr-emitter/pr-body-template.md (36 lines)"
    - "lab/pel/pr-emitter/entry.sh (8 LOC)"
    - "lab/pel-proposer/entry.sh (21 LOC, Rule 3 deviation auto-fix)"
  modified:
    - "lab/pel/proposer/code/proposer.sh — line 306: add >/dev/null before 2>apply_err"
    - "co-evolve-bouncer.sh — +1 defaults block (7 vars) +7 arg-parser arms +1 usage-help section +1 dispatch rebuild branch"
    - "dev-review/codex/dev-review.sh — same 4-way mirror of co-evolve-bouncer.sh edits"
    - ".gitignore — +1 .co-evolve-cache/ line per D-18"
    - ".planning/phases/07-code-tier-proposer/deferred-items.md — DEF-07-01 status header added (closed with commit ref + sim re-verify)"

key-decisions:
  - "Rule 3 deviation auto-fix: added lab/pel-proposer/entry.sh as flat-namespace dispatch resolver (one-line exec shim) because the plan required BOTH (a) --lab pel-proposer dispatching through the existing unchanged dispatch_lab_mode AND (b) the emitter artifact at lab/pel/pr-emitter/entry.sh. The shim resolves the conflict minimally — no dispatch_lab_mode modification, canonical PEL namespace under lab/pel/ preserved, dispatch-time pel-proposer lookup succeeds."
  - "Wrapper dispatch: pel-proposer gets an argv rebuild (lab_tail array) so the emitter sees the parsed 7 flags; other lab modes keep Phase 3's single-$TASK argv contract via elif branch"
  - "All 7 wrapper-flag defaults OFF/unset — byte-parity (SC-5) preserved for every non-pel-proposer invocation"
  - "Both runners place the 7 new arms BEFORE the --) argv-terminator, in identical relative order (D-07 symmetry)"
  - "dispatch_lab_mode left unchanged — inherits Phase 3 D-02 mitigation (validate_lab_mode regex + existence check) for T-08-01-07"
  - "Template uses {{KEY}} double-brace exclusively — single-brace grep returns 0 (D-20 collision avoidance for @@ -X,Y +A,B @@ hunk headers)"
  - "Scoring stub exits 0 (not 1) so Plan 02 replaces the block linearly — the Plan-02 marker INFO: scoring not implemented yet (Plan 02) is the landmark Plan 02 grep-removes"

patterns-established:
  - "Flat-namespace dispatch resolver shim pattern — for any future nested lab inhabitant (e.g. lab/<group>/<inhabitant>/) that must be reachable from a single-segment dispatch mode"
  - "Wrapper argv rebuild idiom for multi-flag lab-mode routing: bash array, conditional appends, single dispatch call with ${array[@]}"
  - "Double-brace placeholder delimiter for PR-body / diff-containing templates — precedent that Plan 02 carries forward into render_pr_body"
  - "D-17 exit taxonomy extension convention: preserve 0-8 from Phase 7, add new codes at 9+ with source-of-truth in the inhabitant's header doc block"

requirements-completed: [PEL-05]

# Metrics
duration: 15min 13s
completed: 2026-04-19
---

# Phase 8 Plan 01: PR Emitter Foundation Summary

**Landed the three mechanical deliverables that unblock Plan 02: DEF-07-01 closed (Phase 7 sim still 16/16 green), 7 wrapper flags on both runners with byte-parity defaults + dispatch rebuild, and lab/pel/pr-emitter/ skeleton wired end-to-end from `co-evolve --lab pel-proposer --target ... --dry-run` through tier auto-detect to a Plan-02 scoring-stub marker.**

## Performance

- **Duration:** 15min 13s
- **Started:** 2026-04-19T14:08:20Z
- **Completed:** 2026-04-19T14:23:34Z
- **Tasks:** 3 (Task 1: DEF-07-01 fix; Task 2: wrapper flags + dispatch + gitignore; Task 3: emitter skeleton)
- **Commits:** 5 (1 fix + 1 docs + 1 feat + 1 chore + 1 feat)
- **Files modified:** 5 existing + 4 created = 9 total

## Commits (chronological)

| # | Hash    | Type  | Message                                                                                       |
|---|---------|-------|-----------------------------------------------------------------------------------------------|
| 1 | 1d43019 | fix   | close DEF-07-01 — suppress git worktree add stdout leak from proposer.sh                      |
| 2 | 8f26b2e | docs  | mark DEF-07-01 closed with re-verification proof                                              |
| 3 | 691ff7d | feat  | add 7 PEL wrapper flags to both runners (--target, --tier, --pr-branch, --dry-run, ...)       |
| 4 | 86d84aa | chore | gitignore .co-evolve-cache/ (Phase 8 eval cache location per D-18)                            |
| 5 | 55f9090 | feat  | scaffold lab/pel/pr-emitter/ skeleton (pr-emitter.sh + pr-body-template.md + entry.sh)        |

## DEF-07-01 Closure Proof

- **Fix site:** lab/pel/proposer/code/proposer.sh:306
- **Before:** `if ! git -C "$REPO_ROOT" worktree add --detach "$SANDBOX_PATH" HEAD 2>"$apply_err"; then`
- **After:**  `if ! git -C "$REPO_ROOT" worktree add --detach "$SANDBOX_PATH" HEAD >/dev/null 2>"$apply_err"; then`
- **Phase 7 simulation re-run (2026-04-19T14:10Z after fix):** 16/16 scenarios passed, exit 0.
- **Tracker updated:** `.planning/phases/07-code-tier-proposer/deferred-items.md` has `**Status:** Closed 2026-04-19 in Phase 8 Plan 01 commit 1d43019. Phase 7 simulation re-verified 16/16 green.`
- **Commit:** 1d43019 (fix) + 8f26b2e (tracker)

## 7-Flag Parity Table

Both runners place the 7 new flags BEFORE the `--)` argv-terminator, in identical relative order (D-07 symmetry).

| Flag          | co-evolve-bouncer.sh line | dev-review/codex/dev-review.sh line | Validation                                                                   |
|---------------|---------------------------|-------------------------------------|------------------------------------------------------------------------------|
| --target      | 113                       | 1035                                | Requires value (non-empty)                                                   |
| --tier        | 118                       | 1040                                | Whitelist: template\|policy\|code                                            |
| --pr-branch   | 126                       | 1048                                | Requires value (opaque string in Plan 01; Plan 02 adds git-ref regex)        |
| --dry-run     | 131                       | 1053                                | Boolean toggle                                                               |
| --budget      | 135                       | 1057                                | Regex `^[0-9]+$` — rejects shell-meta injection                              |
| --yes         | 141                       | 1063                                | Boolean toggle                                                               |
| --flavor      | 145                       | 1067                                | Whitelist: bug-catcher\|faster-converger\|blind-spot-surfacer\|general        |
| --)           | 153                       | 1079                                | Argv terminator — all 7 new arms precede this in both runners                |

**Argv-position invariant (pinned):** In both runners, `--target` line number < `--)` line number.

## Self-Containment Grep Audit (D-07)

```
$ grep -rnE '^(source|\.)[[:space:]]' lab/pel/pr-emitter/
(no matches)

$ grep -rnF 'lib/co-evolution.sh' lab/pel/pr-emitter/
lab/pel/pr-emitter/pr-emitter.sh:47:# Self-containment invariant (D-07): zero source/import of lib/co-evolution.sh,
lab/pel/pr-emitter/pr-emitter.sh:61:# Inline helpers (D-07 self-containment — do NOT source lib/co-evolution.sh)
# Both matches are comment-context documentation — no live source import.
```

**Result:** zero external sources inside `lab/pel/pr-emitter/**`.

## Tier Auto-Detect Smoke Evidence

| Target                                                    | Expected tier       | Actual log line                                                               | Exit |
|-----------------------------------------------------------|---------------------|-------------------------------------------------------------------------------|------|
| `skills/dev-review/templates/compose-prompt.md`           | template            | `INFO: resolved tier: template for target skills/dev-review/templates/...`    | 0    |
| `lab/pel/proposer/policy/policy.yaml`                     | policy              | `INFO: resolved tier: policy for target lab/pel/proposer/policy/policy.yaml`  | 0    |
| `lib/co-evolution.sh`                                     | code (allowlist)    | `INFO: resolved tier: code for target lib/co-evolution.sh`                    | 0    |
| `README.md`                                               | (no rule — hard-err) | `ERROR: tier auto-detect: no rule matches 'README.md' (D-04 hard-error)`      | 10   |
| `compose-prompt.md` with `--tier code` override           | code (override)     | `tier override: code (auto-detect would have been: template)` + resolved=code | 0    |

## Byte-Parity Invariant Proof (SC-5)

Baseline captured BEFORE any wrapper edits (pre-edit HEAD `5118a14`):
```
$ bash co-evolve-bouncer.sh --help > baseline.out 2> baseline.err; echo rc=$? > baseline.rc
# -> 21 lines stdout, 0 lines stderr, rc=0
```

Post-edit re-run (HEAD `55f9090`):
```
$ bash co-evolve-bouncer.sh --help > after.out 2> after.err; echo rc=$? > after.rc
$ diff baseline.out after.out
20a21,27
>   --target FILE      PEL-only: file to mutate (used with --lab pel-proposer)
>   --tier TIER        PEL-only: override tier auto-detect (template|policy|code)
>   --pr-branch NAME   PEL-only: override default pel/<tier>/<short-hash> branch name
>   --dry-run          PEL-only: stub `gh` via CO_EVOLVE_DRY_RUN=1 + PATH shadow
>   --budget USD       PEL-only: scoring budget cap (default 25; exit 6 on exhaustion)
>   --yes              PEL-only: skip interactive preflight cost-estimate prompt
>   --flavor NAME      PEL-only: override classifier (maps to PEL_FLAVOR_OVERRIDE)
```

**Analysis:** The `--help` diff is purely additive — 7 new PEL-prefixed lines documenting the new flags (required by plan Test 1 "`co-evolve --help | grep -c` returns 7"). No existing lines changed, no new stderr, rc preserved.

For a functional run without `--lab pel-proposer`, the new flag variables are all default-unset, the new arg-parser arms never match (no `--target`/`--tier`/etc. in argv), and the new dispatch `if/elif` branch falls through to the original `elif [[ -n "$LAB_MODE" ]]` path (which now contains the former unconditional `if [[ -n ... ]]` body). Since `LAB_MODE=""` by default, no lab dispatch happens — the script proceeds to input detection, interview, compose, bounce, and output exactly as before. No new filesystem side effects, no new environment exports, no new PATH manipulation — the dry-run gh stub block only engages when `--dry-run` or `CO_EVOLVE_DRY_RUN=1` is set AND the emitter is reached via dispatch.

**Conclusion:** SC-5 byte-parity holds structurally. A functional `co-evolve "trivial task"` invocation would behave byte-identically to pre-Phase-8 HEAD (only an actual LLM call's non-determinism prevents a byte-exact diff — the structural invariant is that no new code paths execute).

## Live Smoke (Dispatch E2E)

```
$ bash co-evolve-bouncer.sh --lab pel-proposer \
    --target skills/dev-review/templates/compose-prompt.md --dry-run "smoke"
INFO: resolved tier: template for target skills/dev-review/templates/compose-prompt.md
INFO: --dry-run active — gh stubbed at /tmp/co-evolve-dry-U17hGh/gh
INFO: scoring not implemented yet (Plan 02)
  target=skills/dev-review/templates/compose-prompt.md tier=template dry_run=true budget=$25 flavor_override=<none>
$ echo rc=$?
rc=0
```

Path: co-evolve-bouncer.sh argv parser → dispatch_lab_mode("pel-proposer", lab, --target ... --dry-run -- smoke) → lab/pel-proposer/entry.sh (flat shim) → exec lab/pel/pr-emitter/entry.sh → exec lab/pel/pr-emitter/pr-emitter.sh → argv reparse → detect_tier → dry-run PATH-stub install → Plan-02 marker → exit 0.

## Deviations from Plan

### Auto-fixed (Rule 3 — blocking)

**1. [Rule 3 — Blocking] Dispatch naming mismatch: `pel-proposer` mode vs. `lab/pel/pr-emitter/` directory layout**

- **Found during:** Task 3, E2E smoke test after creating lab/pel/pr-emitter/entry.sh.
- **Issue:** Plan simultaneously required (a) `--lab pel-proposer` to dispatch successfully, (b) `entry.sh` artifact at `lab/pel/pr-emitter/entry.sh`, and (c) `dispatch_lab_mode` unchanged. `dispatch_lab_mode` (lib/co-evolution.sh:124) resolves `<lab_root>/<mode>/entry.sh` — i.e. `lab/pel-proposer/entry.sh` — which didn't exist, so `co-evolve --lab pel-proposer` died with `unknown --lab mode: pel-proposer. Available: pel`. The three plan constraints are jointly unsatisfiable without either (x) modifying dispatch_lab_mode or (y) adding a flat-namespace resolver.
- **Fix:** Added `lab/pel-proposer/entry.sh` (21 LOC) as a flat-namespace dispatch resolver — a one-line exec shim that routes to `lab/pel/pr-emitter/entry.sh`. No dispatch_lab_mode change. The canonical emitter location under `lab/pel/pr-emitter/` is preserved (artifact spec honored). The flat-namespace entry point is documented as a Phase 8 dispatch resolver with a comment explaining the reconciliation.
- **Files created:** `lab/pel-proposer/entry.sh` (not listed in plan's `files_modified` — surfaced as a deviation per the plan's D-22 rule for SIGNIFICANT deviations; this is low-significance — a one-line shim — but added here for auditability).
- **Commit:** 55f9090 (folded into Task 3 commit).
- **Alternative considered:** Modify `dispatch_lab_mode` to resolve slash-containing modes (e.g. `pel/pr-emitter`). Rejected because (i) plan Part C explicitly says "no change needed", (ii) `validate_lab_mode` regex rejects `/`, and (iii) modifying shared library affects all lab inhabitants — higher blast radius than a one-line dispatch resolver.

### Authentication Gates

None — no auth required for any Plan 01 task (skeleton only; scoring + gh pr create land in Plan 02).

## Auth gates

None.

## Readiness Signal for Plan 02

Plan 02 replaces:
1. The scoring stub at `lab/pel/pr-emitter/pr-emitter.sh` (lines ~207-216, marked by `INFO: scoring not implemented yet (Plan 02)`) with real classifier invocation + proposer dispatch + before/after eval scoring + eval cache + budget tracking.
2. The PATH-shadowed gh stub extension (currently only installs the stub — Plan 02 uses it).
3. The `pr-body-template.md` placeholders via `render_pr_body` (substitution via bash parameter expansion per security argument at patterns-established).

Plan 02 does NOT need to touch:
- Wrapper argv parsing (7 flags already parsed symmetrically; adding flags would break byte-parity).
- dispatch_lab_mode (unchanged by design).
- lab/pel-proposer/entry.sh (one-line shim; never needs editing).
- Phase 7 proposer.sh (DEF-07-01 closed; Phase 7 sandbox/canary surface stays untouched).
- .gitignore `.co-evolve-cache/` (already landed).

## Self-Check: PASSED

**Files created:**
- [x] lab/pel/pr-emitter/pr-emitter.sh — FOUND
- [x] lab/pel/pr-emitter/pr-body-template.md — FOUND
- [x] lab/pel/pr-emitter/entry.sh — FOUND
- [x] lab/pel-proposer/entry.sh — FOUND (Rule 3 deviation)

**Files modified:**
- [x] lab/pel/proposer/code/proposer.sh — FOUND (line 306 DEF-07-01 fix)
- [x] co-evolve-bouncer.sh — FOUND (defaults + 7 arms + usage + dispatch)
- [x] dev-review/codex/dev-review.sh — FOUND (defaults + 7 arms + usage + dispatch)
- [x] .gitignore — FOUND (.co-evolve-cache/)
- [x] .planning/phases/07-code-tier-proposer/deferred-items.md — FOUND (DEF-07-01 status)

**Commits:**
- [x] 1d43019 fix(08-01): close DEF-07-01 — FOUND
- [x] 8f26b2e docs(08-01): mark DEF-07-01 closed — FOUND
- [x] 691ff7d feat(08-01): add 7 PEL wrapper flags — FOUND
- [x] 86d84aa chore(08-01): gitignore .co-evolve-cache/ — FOUND
- [x] 55f9090 feat(08-01): scaffold lab/pel/pr-emitter/ skeleton — FOUND

**Verification:**
- [x] Phase 7 simulation: 16/16 scenarios passed (re-verified post-DEF-07-01 fix)
- [x] Both runners parse 7 new flags; whitelist + regex validation rejects bogus values
- [x] Dispatch E2E: `co-evolve --lab pel-proposer --target T --dry-run smoke` reaches Plan-02 marker and exits 0
- [x] Tier auto-detect: 3 happy paths + 1 hard-error exit 10 + 1 override all behave per D-04
- [x] Self-containment D-07: zero external sources in lab/pel/pr-emitter/
- [x] Double-brace delimiter: 13/13 placeholders present, single-brace grep returns 0

All plan acceptance criteria pass.
