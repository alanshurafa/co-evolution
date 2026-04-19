---
phase: 02-bash-eval-harness-port
plan: 02
subsystem: eval-harness
tags: [bash, jq, awk, scoring, port, fitness-signal, pel-prerequisite, levenshtein, jaccard]

# Dependency graph
requires:
  - phase: 02-bash-eval-harness-port
    provides: evals/lib/co-evolution-evals.sh library (Plan 02-01) providing read_yaml_file, merge_yaml_defaults, atomic_json_write_stdin, load_json_or_sentinel
provides:
  - evals/score-run.sh 7-dimension fitness scorer (675 LOC) producing scores.json per run
  - Jaccard + Levenshtein helper functions (inline in scorer) for Plan 02-03 reuse if needed
  - Baseline composite values for all 10 fixtures (see "Composite Baseline" section below) — Plan 02-03's comparator can sanity-check against these
affects: [02-03-runner-comparator-test, pel-proposer-phases-5-8]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Seven-dimension scoring loop: extracts state.json + plan.md + verdict.json + outputs/*.log, applies per-dimension heuristics, weighted-mean composite"
    - "Jaccard helper via jq set arithmetic (|A ∩ B| / |A ∪ B| with both-empty = 1.0)"
    - "Levenshtein helper via awk 2-row Wagner-Fischer DP with 4000-char cap (matches PS)"
    - "ISO8601 parser in jq handling PS-emitted 7-digit fractional seconds + numeric TZ offsets (workaround for jq's fromdateiso8601 only accepting %Y-%m-%dT%H:%M:%SZ)"
    - "UTF-8 BOM strip on plan.md and outputs/*.txt files (PS-produced fixtures are BOM-prefixed; Bash grep on ^# would otherwise miss '# Plan')"
    - "MINGW grep -iF abort workaround: awk tolower + index() for case-insensitive fixed-string matching"
    - "Atomic JSON write via atomic_json_write_stdin '.' (identity program) so jq -n --arg constructions write atomically"
    - "changed_files polymorphism handling (string OR array from state.json) via jq type-dispatch"

key-files:
  created:
    - "evals/score-run.sh (675 LOC — CLI + 7-dim scoring + helpers + composite + atomic write)"
  modified: []

key-decisions:
  - "Added explicit UTF-8 BOM strip on plan.md (fixtures 02-10 all have BOM; PS reads them transparently, Bash grep -qE '^#' doesn't)"
  - "awk tolower + index() replaces grep -qiF in verify_accuracy keyword matching — MINGW/MSYS grep 3.0 aborts when -i combined with -F (reproducible on this machine); -iE with escaped pattern would also work but awk is clearer"
  - "jq's fromdateiso8601 only parses Z-suffixed ISO8601; PS emits '...−04:00'. Replicated in jq via parseiso UDF that trims fractional seconds, extracts numeric TZ offset, parses base with Z suffix, subtracts offset in seconds"
  - "Plan-files extraction uses awk to scan the '## Files to Change' section (bounded by the next '##' heading) then per-line regex match — mirrors PS Get-FilesFromPlan's two-pass structure"
  - "Composite uses jq's '(x * 1000 | round) / 1000' to match PS [Math]::Round(x, 3); on 01-all-pass (6 PASS + 1 N/A, robustness weight 2) the expected and actual composite = 1.0"
  - "Hardcoded fallback heading groups match PS literal default (Plan|Approach|Strategy + Risks|Concerns|Caveats) rather than defaults.yaml's expanded groups — scorer is invoked WITHOUT --defaults-file against fixtures, so PS's hardcoded fallback is the ground truth"
  - "Determinism: scorer uses only jq -S, find | sort, no $RANDOM / uuidgen / nanosecond clock; scored_at via date +%Y-%m-%dT%H:%M:%SZ (stripped before comparison)"
  - "Sparse Task 1 details_json kept minimal; acceptance criteria don't require per-dimension metadata, and Plan 02-03 can expand later if the comparator needs it"

patterns-established:
  - "Scorer composability: the Jaccard/Levenshtein helpers sit inside score-run.sh (not extracted to co-evolution-evals.sh) because they are scorer-specific and the plan 02-01 API boundary is closed"
  - "PS-to-Bash numerical fidelity: for enum-string outputs (PASS/PARTIAL/FAIL/N/A) string equality on jq -S is sufficient; float epsilon only becomes relevant for composite comparisons, which EXPECTED.json doesn't carry"
  - "Polymorphic field handling: state.json's changed_files appears as both string and array across fixtures; jq's type-dispatch ('if type == \"string\" then [$f] elif type == \"array\" then $f else [] end') handles both without branching Bash"
  - "grep flag compatibility: on MINGW/MSYS, prefer regex (-E) over fixed-string (-F) when -i is needed; awk fallback is clear and works everywhere"

requirements-completed: [BASH-EVAL-01]

# Metrics
duration: "20min 53s"
started: "2026-04-18T13:10:39Z"
completed: "2026-04-18T13:31:32Z"
tasks: 2
files_created: 1
files_modified: 0
fixtures_passed: 10/10
determinism_verified: true
---

# Phase 2 Plan 2: score-run.sh — 7-Dimension Fitness Scorer Summary

**Ported runners/codex-ps/evals/score-run.ps1 (467 LOC) to evals/score-run.sh (675 LOC): 7-dimension fitness scorer consuming state.json + plan.md + verdict.json + outputs/*.log, producing scores.json matching PS output on all 10 golden fixtures.**

## Performance

- **Duration:** 20 min 53 s
- **Started:** 2026-04-18T13:10:39Z
- **Completed:** 2026-04-18T13:31:32Z
- **Tasks:** 2 (Task 1 scaffold + 3 easy dimensions + Task 2 hard dimensions + helpers)
- **Files created:** 1 (evals/score-run.sh)
- **Fixtures passing (Tier 1 regression gate):** 10/10

## Accomplishments

- All 10 Tier 1 fixture suites (the complete corpus, not a sample) produce `.scores` objects byte-equal to EXPECTED.json under `jq -S`. Primary regression gate from D-09 is green.
- Determinism verified on fixtures 01-all-pass (simple, no outputs/) and 10-cross-ai-genuine-bounce (non-trivial, Levenshtein + bounce outputs): two invocations on the same input produce byte-identical scores.json after stripping `.scored_at`.
- Malformed verdict.json (fixture 08) handled without abort: scorer exits 0, `scores.verify_accuracy == "FAIL"`, and all other dimensions score correctly.
- Cross-AI diversity Levenshtein math reproduces PS's `1 - dist/max(n,m)` semantics with 4000-char cap in awk — verified correct direction for both fixture 09 (identical texts → FAIL) and fixture 10 (genuinely different → PASS).

## API Surface Shipped

CLI contract (ports score-run.ps1 param block 1:1):

```bash
evals/score-run.sh --case-file PATH --run-dir PATH [--defaults-file PATH] [--output-dir PATH] [--help]
```

Output: `<OUTPUT_DIR>/scores.json` with shape (stable, jq -S sorted):

```json
{
  "case_id":   "01-all-pass",
  "title":     "All-PASS baseline fixture",
  "run_id":    "fixture-01-all-pass",
  "scores": {
    "convergence":        "PASS",
    "cost":               "PASS",
    "cross_ai_diversity": "N/A",
    "execution_fidelity": "PASS",
    "plan_quality":       "PASS",
    "robustness":         "PASS",
    "verify_accuracy":    "PASS"
  },
  "composite": 1,
  "details":   { "robustness": {...}, "cost": {...}, "cross_ai_diversity": {...} },
  "scored_at": "2026-04-18T13:15:01Z"
}
```

Exit codes:
- 0 on successful score emission
- 1 on fatal error (missing state.json, invalid JSON, jq failure, etc.)

Determinism contract (D-02): two runs on the same inputs produce byte-identical output after stripping `.scored_at`. No `$RANDOM`, no `uuidgen`, no nanosecond clock sources anywhere in the hot path.

## Task Commits

1. **Task 1: Scaffold CLI + artifact loading + Robustness/Cost/Cross-AI-N/A guard** — `c52fe2d` (feat)
   - 304 LOC. Sources lib/co-evolution.sh + evals/lib/co-evolution-evals.sh.
   - Robustness (state.status + UnhandledException grep), Cost (wall_clock via ISO8601 parser), Cross-AI N/A guard (composer == reviewer).
   - Placeholder FAIL for the four hard dimensions so scores.json shape is complete.
   - 01-all-pass produces robustness=PASS + cost=PASS + cross_ai=N/A; 02-robustness-fail produces robustness=FAIL.

2. **Task 2: Jaccard + Levenshtein + 4 hard dimensions + full cross-AI** — `9945ce4` (feat)
   - +384 LOC. Added jaccard() and levenshtein() helpers; replaced all placeholders with full implementations.
   - Convergence: marker_counts.total + bounce structural check.
   - Plan Quality: word count + heading group matching (PS hardcoded fallback: Plan|Approach|Strategy + Risks|Concerns|Caveats).
   - Execution Fidelity: Jaccard of plan-declared files vs state.changed_files with no-op special case.
   - Verify Accuracy: sentinel handling (missing/unparseable → FAIL); must_catch_issue branch (REVISE + keyword hit → PASS); allow_verdict branch (verdict in list → PASS).
   - Cross-AI Diversity: full Levenshtein comparison, change_ratio vs min_edit_distance threshold.
   - UTF-8 BOM stripping on plan.md and compose/bounce text files.

**Plan metadata commit will follow** (docs + STATE.md + ROADMAP.md).

## Fixture Verification Matrix (Tier 1)

| Fixture | Expected (EXPECTED.json `.scores`) | Actual | Status |
|---|---|---|---|
| 01-all-pass | 6×PASS + cross_ai=N/A | Matches | OK |
| 02-robustness-fail | robustness=FAIL, verify=FAIL, 5×PASS-ish | Matches | OK |
| 03-convergence-partial | convergence=PARTIAL | Matches | OK |
| 04-plan-quality-fail | plan_quality=FAIL | Matches | OK |
| 05-exec-fidelity-mismatch | execution_fidelity=FAIL | Matches | OK |
| 06-verify-catches-hallucination | verify_accuracy=PASS (must_catch + keyword_hit) | Matches | OK |
| 07-verify-misses-hallucination | verify_accuracy=FAIL (APPROVED when REVISE expected) | Matches | OK |
| 08-unparseable-verdict | verify_accuracy=FAIL (unparseable sentinel, no abort) | Matches | OK |
| 09-cross-ai-rubber-stamp | cross_ai_diversity=FAIL (identical compose/bounce) | Matches | OK |
| 10-cross-ai-genuine-bounce | cross_ai_diversity=PASS (change_ratio=0.844 >> 0.15) | Matches | OK |

**All 10 fixtures pass `jq -S '.scores'` string-equality check.**

## Composite Baseline (for Plan 02-03 sanity-check)

Computed per score-run.ps1:428-446 (robustness weight 2, others weight 1; PASS=1.0, PARTIAL=0.5, FAIL=0.0, N/A=excluded):

| Fixture | Composite |
|---|---|
| 01-all-pass | 1.000 |
| 02-robustness-fail | 0.571 |
| 03-convergence-partial | 0.929 |
| 04-plan-quality-fail | 0.857 |
| 05-exec-fidelity-mismatch | 0.857 |
| 06-verify-catches-hallucination | 1.000 |
| 07-verify-misses-hallucination | 0.857 |
| 08-unparseable-verdict | 0.857 |
| 09-cross-ai-rubber-stamp | 0.875 |
| 10-cross-ai-genuine-bounce | 1.000 |

These values are the Bash baseline. PS-produced EXPECTED.json files do NOT carry a `composite` field (only `.scores`), so no PS-vs-Bash epsilon check is possible at this layer. Plan 02-03's inter-run stability test (D-09 Tier 3) will verify the Bash composite is stable across runs.

## Files Created/Modified

- `evals/score-run.sh` (NEW, 675 LOC, executable) — complete 7-dimension scorer. Sources lib/co-evolution.sh + evals/lib/co-evolution-evals.sh. Contains two helpers (jaccard, levenshtein) plus the main scoring body. No trap-cleanup — all inline path cleanup via `rm -f "$tmpfile"` after use.

## Decisions Made

- **UTF-8 BOM stripping was required.** Fixtures 02–10 have BOM on plan.md (and compose/bounce text files). PS reads these transparently; Bash `grep -qE '^#'` does NOT match the first `#` after a BOM byte. Added explicit `${plan_text#$'\xef\xbb\xbf'}` strip on plan_text load and a bom-detect + substring skip inside the awk Levenshtein. Alternative would have been to `sed -i` the fixtures, but that mutates PS-generated ground truth — rejected.
- **MINGW grep `-i` + `-F` combination aborts.** Reproducible on this machine with GNU grep 3.0 on Git Bash: `grep -qiF "kw" file` dies with "Aborted" regardless of content. Tested every combination; the bug is specifically `-i` + `-F`. Workaround: use awk's `index(tolower(text), tolower(kw))` for case-insensitive fixed-string matching. Heading match uses regex (`-qE`) which is unaffected.
- **jq `fromdateiso8601` only parses Zulu timestamps.** PS emits `...−04:00` with 7-digit fractional seconds. Built a jq UDF `parseiso` that trims fractional seconds, extracts numeric offset via `capture("^(?<base>.+T[0-9:]+)(?<sign>[+-])(?<h>[0-9]{2}):(?<m>[0-9]{2})$")`, parses `base + "Z"` with `fromdateiso8601`, subtracts offset seconds. Character class `[.]` used instead of `\\.` to dodge shell-single-quote + jq-regex double-escape issues.
- **Hardcoded heading group fallback matches PS, not defaults.yaml.** Fixtures are invoked WITHOUT `--defaults-file`, so the PS scorer's hardcoded fallback `@(@('Plan','Approach','Strategy'), @('Risks','Concerns','Caveats'))` is the ground truth. The Bash scorer mirrors this literal default. Fixture plan.md files have `# Plan` as the top heading and `## Risks` near the end, so both groups match (plan_grp=1, risks_grp=1) — except fixture 04 (plan.md is "Short.") where both fail → FAIL ✓.
- **plan_quality uses case-sensitive regex to match PS default.** PS `-match` with `"(?m)^#+\s+" + [regex]::Escape($h)` has no `(?i)` flag — case-sensitive. Using `-qE` (not `-qiE`) in Bash mirrors this. If a future fixture adds a lowercase heading like `## plan`, this will diverge; acceptable per D-01 semantic-equivalence bar.
- **Jaccard `both-empty` returns 1.0, not undefined.** Matches PS `if ((-not $A -or $A.Count -eq 0) -and (-not $B -or $B.Count -eq 0)) { return 1.0 }`. This is load-bearing for fixture 04 (no-op plan + no changes), though the scorer also has an explicit special case at the callsite for belt-and-suspenders.
- **Verify accuracy's keyword_hit is case-INsensitive.** PS `-match` on a string is case-insensitive by default. Bash replication uses `awk 'BEGIN { exit (index(tolower(text), tolower(kw)) > 0) ? 0 : 1 }'`. Fixture 06's keywords are `['RetryAsync','does not exist']` with exact case; the test would pass either way, but a future lowercase keyword would break case-sensitive match.

## Deviations from Plan

The plan's `<action>` blocks had two specific quirks I adapted during implementation (tracked as Rule 1/2 fixes but not plan-level deviations since the plan's own Recovery Protocol anticipates divergence from its sketch):

1. **[Rule 1 - Bug] Convergence logic** — the plan sketch heuristically used "bounce-*.txt presence → PASS, else PARTIAL". The actual PS heuristic is `marker_counts.total == 0 → PASS, ≤ 2 → PARTIAL, > 2 → FAIL`, THEN structural check that downgrades to FAIL if expects_bounces but no bounces ran. Ported the actual PS semantics. All fixtures match.
2. **[Rule 1 - Bug] Plan-quality heading matching** — the plan sketch assumed `must_contain_any` always came from YAML. Fixtures don't include it; PS falls back to hardcoded `@(@('Plan','Approach','Strategy'), @('Risks','Concerns','Caveats'))`. Added explicit fallback when case YAML omits the key.
3. **[Rule 1 - Bug] changed_files polymorphism** — the plan sketch assumed always-array; some fixtures encode it as a scalar string. Added jq type-dispatch to normalize.
4. **[Rule 1 - Bug] UTF-8 BOM handling** — plan sketch didn't mention BOM; fixtures 02-10 all have BOM on plan.md. Added strip on plan_text load and inside the awk Levenshtein.
5. **[Rule 3 - Blocking] MINGW grep `-iF` abort** — discovered mid-implementation; swapped to awk-based case-insensitive fixed-string matching. Without this, keyword_hit on fixture 06 would always return false → verify_accuracy=PARTIAL instead of PASS.
6. **[Rule 3 - Blocking] jq fromdateiso8601 + TZ offset** — PS timestamps are not Z-suffixed. Wrote a jq parseiso UDF.

None of these are architectural changes (Rule 4). All are correctness fixes that keep the plan's interfaces and semantics intact. The plan's own `<action>` section acknowledged all six would likely surface ("Re-read PS source line range... Do NOT invent new semantics — port PS's logic literally") and provided a recovery protocol — I followed it.

## Issues Encountered

1. **jq 1.8.1 `fromdateiso8601` rejects non-Z ISO8601.** Fixed via parseiso UDF. 150-second wall_clock correctly computed on fixture 01.
2. **MINGW grep 3.0 aborts on `-iF` combos.** Workaround via awk `tolower()` + `index()`. This is a latent portability concern — Plan 02-03's scorer-verification.sh may also hit this if it adds its own grep calls; recommend documenting in the test helper.
3. **UTF-8 BOM collision with `^#` anchor.** Fixed via explicit BOM strip. If future fixtures are generated as UTF-8 without BOM, the strip is a no-op, so this is permanently safe.
4. **`trap ... RETURN` absent.** The plan explicitly forbade this (acceptance criterion: `grep -cE "trap .* RETURN" evals/score-run.sh` returns 0). The scorer uses inline `rm -f` after each mktemp block — linear flow, no function scoping needed. Verified: 0 occurrences.

## Known Caveats for Plan 02-03

- **CLI flags runner must pass:** `--case-file` (YAML), `--run-dir` (with state.json + plan.md + verdict.json + outputs/), optionally `--defaults-file` (if merge with defaults.yaml is desired) and `--output-dir` (defaults to --run-dir).
- **scores.json fields the comparator must read:** `.case_id`, `.scores.{all 7 keys}`, `.composite` (float, 3-decimal rounded). The `details` object is sparse and schema-optional — comparator should tolerate missing sub-keys.
- **EXPECTED.json shape:** only `.scores` (no composite, no details). Tier 1 regression is `jq -S '.scores'` equality, NOT full-file diff. Plan 02-03's scorer-verification.sh must reflect this.
- **Determinism stripping:** `.scored_at` is the only non-deterministic field. Strip with `jq 'del(.scored_at)'` before any inter-run diff.
- **BOM is everywhere.** If Plan 02-03 compares text files (e.g. comparing two plan.md renderings), do the BOM strip explicitly.
- **`grep -iF` is unsafe on MINGW.** Document in co-evolution-evals.sh or comparator that the pattern is disallowed.

## Self-Check: PASSED

Verified claims before returning:

- `evals/score-run.sh` exists at `C:/Users/alan/Project/co-evolution-v12/evals/score-run.sh` (675 LOC)
- `head -1 evals/score-run.sh` → `#!/usr/bin/env bash`
- `bash evals/score-run.sh --help` exits 0 and mentions all 4 flags
- `bash evals/score-run.sh` (no args) exits 1 with `--case-file is required` on stderr
- Commit `c52fe2d` present in `git log --oneline` on branch `feat/v1.2-pel-proposer` (Task 1)
- Commit `9945ce4` present in `git log --oneline` on branch `feat/v1.2-pel-proposer` (Task 2)
- All 10 fixtures produce `.scores` objects byte-equal to EXPECTED.json under `jq -S`
- Determinism: 2× run on same input → byte-identical after stripping `.scored_at` (verified on 01-all-pass AND 10-cross-ai-genuine-bounce)
- No `$RANDOM` / `uuidgen` / nanosecond timestamp anywhere (`grep -cE '\$RANDOM|uuidgen|date \+%s%N'` returns 0)
- No `trap ... RETURN` anywhere (`grep -cE "trap .* RETURN"` returns 0)
- `jaccard()` and `levenshtein()` helpers defined at global scope (1 occurrence each)
- Composite for fixture 01-all-pass equals 1.0 (expected: 7/7 weighted sum)

---
*Phase: 02-bash-eval-harness-port*
*Plan: 02*
*Completed: 2026-04-18*
