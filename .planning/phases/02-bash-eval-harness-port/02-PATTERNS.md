# Phase 2: Bash Eval Harness Port - Pattern Map

**Mapped:** 2026-04-17
**Files analyzed:** 6 (4 new Bash + 1 new test + 1 doc update)
**Analogs found:** 6 / 6 (all files have at least one role-match analog — zero "no analog" cases)
**Project root:** `C:/Users/alan/Project/co-evolution-v12`

## Scope Summary

Port ~1400 LOC of PowerShell eval harness under `runners/codex-ps/evals/` to Bash so evals run on Git Bash / Linux / macOS without `pwsh`. This is PEL's fitness signal — every Phase 5-8 mutation proposer reads `scores.json` produced by this harness. Sequential plans 02-01 → 02-02 → 02-03 with serial dependencies.

## File Classification

| New/Modified File | Role | Data Flow | Closest Bash Analog | Closest PS Source | Match Quality |
|-------------------|------|-----------|---------------------|-------------------|---------------|
| `evals/lib/co-evolution-evals.sh` | shared library | transform + file-I/O | `lib/co-evolution.sh` (999 LOC) | `runners/codex-ps/evals/lib/{Yaml,Report,Fixture}.ps1` (362 LOC total) | role-exact |
| `evals/score-run.sh` | scorer CLI | transform (read artifacts → emit JSON) | `dev-review/codex/dev-review.sh` (1326 LOC, arg parsing + jq); `lib/co-evolution.sh::validate_review_verdict` (lines 453-571) | `runners/codex-ps/evals/score-run.ps1` (467 LOC) | role-match |
| `evals/run-evals.sh` | orchestrator CLI | batch (iterate cases → invoke runner → capture artifacts) | `dev-review/codex/dev-review.sh` (CLI + phase orchestration) | `runners/codex-ps/evals/run-evals.ps1` (287 LOC) | role-match |
| `evals/compare-reports.sh` | diff utility | transform (read two JSONs → emit markdown) | `lib/co-evolution.sh::compute_execute_delta` (lines 782-803) | `runners/codex-ps/evals/compare-reports.ps1` (110 LOC) | role-match |
| `evals/tests/scorer-verification.sh` | regression test | batch (iterate fixtures → diff actual vs EXPECTED) | `tests/worktree-management-simulation.sh` (160 LOC); `tests/live-mode-simulation.sh` (102 LOC); `tests/revise-loop-simulation.sh` (171 LOC) | none (new test — PS's Test-Scorer.ps1 is NOT ported per D-05) | role-exact (simulation-script pattern) |
| `evals/README.md` | doc update | n/a | `evals/README.md` (existing 103 lines) | n/a | update-in-place |

## Fixture Corpus Inventory (Tier 1 regression ground truth)

CONTEXT.md stated "2+ fixture suites." **Actual count: 10 suites** under `runners/codex-ps/evals/tests/fixtures/`:

| Suite | Expected Outcome |
|-------|------------------|
| `01-all-pass/` | All dimensions PASS (cross_ai N/A) |
| `02-robustness-fail/` | Robustness FAIL, verify FAIL |
| `03-convergence-partial/` | Convergence PARTIAL |
| `04-plan-quality-fail/` | Plan quality FAIL |
| `05-exec-fidelity-mismatch/` | Execution fidelity FAIL |
| `06-verify-catches-hallucination/` | Verify catches seeded issue |
| `07-verify-misses-hallucination/` | Verify misses seeded issue |
| `08-unparseable-verdict/` | Verify FAIL on malformed JSON |
| `09-cross-ai-rubber-stamp/` | Cross-AI diversity FAIL |
| `10-cross-ai-genuine-bounce/` | Cross-AI diversity PASS |

Each suite contains: `case.yaml` (case spec) + `EXPECTED.json` (expected `scores` output) + `run/` (with `plan.md`, `state.json`, `verdict.json`, `scores.json` sample). **All 10 become Tier 1 regression targets** — plan 02-03 should iterate every suite, not just 2.

Note: `EXPECTED.json` carries only the `scores` object (no `composite`, no `details`, no `run_id`). The Tier 1 comparison should be `jq -S '.scores'` on actual output vs `EXPECTED.json` (not full-file diff).

## Portable Assets Status (already in place — no port work)

These assets were elevated to top-level in v1.0 Phase 8 and are byte-portable — the Bash runner only needs to iterate/read them:

- `evals/cases/*.yaml` — 9 production cases + `defaults.yaml` (10 files total; simple YAML, no anchors/aliases)
- `evals/cases/defaults.yaml` — shared thresholds; shallow merge into each case
- `evals/fixtures/mock-scores.json` — scorer output shape reference
- `evals/fixtures/mock-report.md` — report output shape reference
- `schemas/review-verdict.json` — draft-07 schema for verdict validation
- `runners/codex-ps/evals/report-template.md` — markdown template with `{{TIMESTAMP}}`, `{{CASE_TABLE}}`, `{{DETAILS_SECTIONS}}` etc. placeholders (plan 02-01 should COPY this to `evals/report-template.md` as part of the port so the Bash harness has its own template root, and verify byte-identity to the PS source)

---

## Pattern Assignments

### `evals/lib/co-evolution-evals.sh` (shared library)

**Bash analog:** `lib/co-evolution.sh` (C:/Users/alan/Project/co-evolution-v12/lib/co-evolution.sh)
**PS sources (spec):** `runners/codex-ps/evals/lib/Yaml.ps1` (75 LOC), `Report.ps1` (126 LOC), `Fixture.ps1` (161 LOC)

**Module header / helpers pattern** — copy from `lib/co-evolution.sh:1-17`:

```bash
#!/usr/bin/env bash

log() {
  local message="${1:-}"

  if [[ -n "${LOG_FILE:-}" ]]; then
    echo "$message" | tee -a "$LOG_FILE"
  else
    echo "$message"
  fi
}

die() {
  local message="${1:-Fatal error}"
  log "ERROR: $message"
  exit 1
}
```

Note: This file is SOURCED, not run directly — it does NOT have `set -euo pipefail` at top (matches `lib/co-evolution.sh` which also has no shebang-level strict mode so it composes cleanly when sourced). Scripts that source it (scorer/runner/comparator/test) set their own strictness.

**Mandatory-arg pattern** (for library helpers) — copy from `lib/co-evolution.sh:742-744`:

```bash
snapshot_workdir_hashes() {
  local workdir="${1:?snapshot_workdir_hashes requires a workdir}"
  local output_path="${2:?snapshot_workdir_hashes requires an output path}"
  ...
}
```

Use `${N:?message}` for every required arg in new library functions. Error message surfaces immediately with a clear attribution.

**jq + mktemp + mv atomic write** — copy from `lib/co-evolution.sh:870-895` (write_state_phase):

```bash
write_state_phase() {
  local state_path="${1:?state path required}"
  ...
  if command -v jq >/dev/null 2>&1; then
    local tmp
    tmp=$(mktemp)
    # FIX-WR-02: clean up $tmp on any exit path (jq failure, script interrupt).
    if jq --arg name "$phase_name" ... '.phases += [{...}]' "$state_path" > "$tmp"; then
      mv "$tmp" "$state_path"
    else
      rm -f "$tmp"
      log "WARNING: jq failed in write_state_phase ($phase_name) — state.json unchanged"
    fi
  else
    log "WARNING: jq unavailable — write_state_phase skipping ($phase_name)"
  fi
}
```

Use this atomic-write pattern for any JSON produced by the scorer. NOTE: Per CONTEXT.md D-03, `jq` is mandatory for the eval harness (no fallback branch needed). Drop the `command -v jq` guard for the new library (it IS a required dep now); keep the mktemp → mv atomic pattern.

**Port `Read-YamlFile` (Yaml.ps1:21-46)** — Bash wrapper around `yq`:

Source Ensure-YamlModule pattern (`Yaml.ps1:4-19`):

```powershell
function Ensure-YamlModule {
    if (-not (Get-Module -Name powershell-yaml)) {
        $available = Get-Module -ListAvailable -Name powershell-yaml
        if (-not $available) {
            throw @"Module 'powershell-yaml' is not installed. ..."@
        }
        Import-Module powershell-yaml -ErrorAction Stop | Out-Null
    }
}
```

Bash equivalent (fold into `co-evolution-evals.sh`; follow the `command -v` + `die` style from `lib/co-evolution.sh:966-967`):

```bash
ensure_yq() {
  command -v yq >/dev/null 2>&1 || die "yq not found. Install mikefarah/yq: 'scoop install yq' (Windows), 'brew install yq' (macOS), 'apt install yq' (Linux)."
}

read_yaml_file() {
  local path="${1:?read_yaml_file requires a path}"
  ensure_yq
  [[ -f "$path" ]] || die "YAML file not found: $path"
  yq -o=json "$path"  # pipe-friendly; scorer will pipe to jq
}
```

**Port `Merge-HashtablesDeep` (Yaml.ps1:48-75)** — PS does recursive deep-merge, lists are replaced wholesale (not concatenated). yq has `*` operator; the v1 port should use yq's deep-merge with `--slurp` or jq's `*` operator (both do the same replacement semantics PS does). Sanity test on `cases/defaults.yaml` + `cases/01-trivial-task.yaml` in plan 02-01 — this is CONTEXT.md's "non-obvious risk" callout about YAML merge semantics.

**Port `Render report` (Report.ps1:1-127)** — template substitution with `{{PLACEHOLDER}}` tokens. Bash analog for token substitution already exists in `lib/co-evolution.sh:661-678` (`fill_template`):

```bash
fill_template() {
  local template_path="$1"
  shift
  local rendered
  local pair
  local key
  local value

  rendered=$(cat "$template_path")

  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    rendered="${rendered//\{$key\}/$value}"
  done

  printf '%s' "$rendered"
}
```

Caveat: PS template uses `{{TOKEN}}` (double braces); `fill_template` expects single-brace `{TOKEN}`. Plan 02-01 should add a `render_report` helper that handles `{{...}}` (or normalize `report-template.md` to single-brace, but that breaks PS byte-parity). Prefer adding a new helper that matches the PS token syntax so the same template file serves both harnesses.

**Port `New-Fixture` / `Remove-Fixture` / `Copy-RunArtifacts` (Fixture.ps1:9-162)** — CRITICAL: this is a large chunk of PS code but most of it is NOT needed for Phase 2.

Per CONTEXT.md scope, the Bash runner consumes pre-existing `evals/cases/*.yaml` and writes per-case `run/` dirs. The PS fixture code creates tmp dirs, copies scripts/templates/schemas into them, initializes a git repo, seeds files, and tears down. Bash port needs analogs for:
- `mktemp -d` per case (replaces `New-Item -Path $fixtureBase -Force` + CaseId-timestamp naming)
- `cp -r scripts/ templates/ schemas/ $fixture/` (replaces `Copy-Item -Path $src -Destination $fixtureDir -Recurse -Force`)
- `git init -q` + minimal git config inside fixture (replaces `Fixture.ps1:45-56`)
- Seed files writer: iterate YAML `setup.seed_files[]` and write content to `$fixture/$path` (replaces `Fixture.ps1:61-74`)
- Copy-from writer: iterate `setup.copy_from[]` and `cp $src $fixture/$dst` (replaces `Fixture.ps1:78-94`)
- Teardown: `rm -rf $fixture` unless `--keep-fixtures` (replaces `Remove-Fixture`)
- Artifact capture: find newest `.co-evolution/runs/*/` under fixture and copy to `reports/$ts/runs/$caseid/` (replaces `Copy-RunArtifacts`)

Trap-based cleanup for fixtures: FOLLOW the test pattern from `tests/worktree-management-simulation.sh:18-20`:

```bash
TEST_DIR=$(mktemp -d -t wt-sim-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
```

`lib/co-evolution.sh` has NO trap-based cleanup (main runner doesn't use it). Only the test scripts do. Apply trap-cleanup in `evals/run-evals.sh` (the orchestrator) and `evals/tests/scorer-verification.sh` (the test), NOT inside `evals/lib/co-evolution-evals.sh`. CONTEXT.md's hint about trap-based cleanup was misleading for the library itself — the trap lives in the SCRIPT that calls the library.

---

### `evals/score-run.sh` (scorer — the hardest plan, 02-02)

**Bash analog for CLI shell:** `dev-review/codex/dev-review.sh` (arg parsing lines 926-1028, 100-line while-loop parser)
**Bash analog for jq-heavy validation:** `lib/co-evolution.sh::validate_review_verdict` lines 453-571
**PS source (spec):** `runners/codex-ps/evals/score-run.ps1` (467 LOC) — read every line

**Strict-mode header + SCRIPT_DIR + source lib** — copy from `dev-review/codex/dev-review.sh:1-8`:

```bash
#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "${REPO_ROOT}/lib/co-evolution.sh"
source "${SCRIPT_DIR}/lib/co-evolution-evals.sh"
```

(The second source pulls in the new evals library. Order matters — evals lib depends on `log`/`die` from core lib.)

**CLI arg parsing** — copy the while/case/shift pattern from `dev-review.sh:926-1020`:

```bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    --case-file)
      [[ $# -gt 1 ]] || die "--case-file requires a value"
      CASE_FILE="$2"
      shift 2
      ;;
    --run-dir)
      [[ $# -gt 1 ]] || die "--run-dir requires a value"
      RUN_DIR="$2"
      shift 2
      ;;
    --defaults-file)
      [[ $# -gt 1 ]] || die "--defaults-file requires a value"
      DEFAULTS_FILE="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -gt 1 ]] || die "--output-dir requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    -*)
      die "Unknown flag: $1"
      ;;
    *)
      die "Unexpected positional arg: $1"
      ;;
  esac
done
```

PS source has 4 named params (CaseFile, RunDir, DefaultsFile, OutputDir) — port them 1:1 to these flags. Unlike `dev-review.sh`, there is no positional `TASK`; all args are flagged.

**Seven-dimension scoring loop** — port from `score-run.ps1:229-446` verbatim. Key semantic excerpts:

PS Robustness check (`score-run.ps1:234-251`):
```powershell
$robust = 'PASS'
$status = [string]$state.status
if ($status -ne 'completed') {
    $robust = 'FAIL'
}
$hadException = $false
if (Test-Path -LiteralPath $outputsDir) {
    Get-ChildItem -LiteralPath $outputsDir -Filter '*.log' -ErrorAction SilentlyContinue | ForEach-Object {
        $c = Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue
        if ($c -match '(?im)\bUnhandledException\b|\bFullyQualifiedErrorId\b.*\bRuntimeException\b') {
            $hadException = $true
        }
    }
}
if ($hadException -and $robust -eq 'PASS') { $robust = 'PARTIAL' }
```

Bash port using jq for state.status + grep for exception pattern (shape-preserving):
```bash
status=$(jq -r '.status // "unknown"' "$RUN_DIR/state.json")
robust="PASS"
[[ "$status" != "completed" ]] && robust="FAIL"
had_exception=false
if [[ -d "$RUN_DIR/outputs" ]]; then
  if grep -qiE '\bUnhandledException\b|\bFullyQualifiedErrorId\b.*\bRuntimeException\b' "$RUN_DIR/outputs/"*.log 2>/dev/null; then
    had_exception=true
  fi
fi
[[ "$had_exception" == "true" && "$robust" == "PASS" ]] && robust="PARTIAL"
```

PS Convergence structural-bounce check (`score-run.ps1:253-301`) — non-trivial state.history inspection + outputs/bounce-*.txt presence. Port must preserve "bounce-NN.txt files → bounce phases ran" heuristic exactly (it's the Tier 4 regression A invariant).

PS Execution fidelity with Jaccard (`score-run.ps1:102-133` helper + `:322-337` scoring):

```powershell
function Jaccard {
    param([string[]]$A, [string[]]$B)
    if ((-not $A -or $A.Count -eq 0) -and (-not $B -or $B.Count -eq 0)) { return 1.0 }
    ...
    if ($union.Count -eq 0) { return 0.0 }
    return [double]$inter.Count / [double]$union.Count
}
```

Bash port using jq array intersection/union (pure jq, no external math tool needed):
```bash
jaccard() {
  local a_file="$1" b_file="$2"  # each contains JSON array of strings
  jq -n --slurpfile a "$a_file" --slurpfile b "$b_file" '
    ($a[0] // []) as $A | ($b[0] // []) as $B |
    if ($A|length)==0 and ($B|length)==0 then 1.0
    else
      ($A - ($A - $B)) as $inter |
      (($A + $B) | unique) as $union |
      if ($union|length)==0 then 0.0
      else ($inter|length) / ($union|length) end
    end
  '
}
```

PS Levenshtein (`score-run.ps1:135-169`) — 4000-char cap + 2D int array DP. Bash port: implement in awk (awk does 2D arrays well) or skip the cap and use a pure-jq approach. Awk is likely simpler. Keep the 4000-char cap to preserve PS runtime characteristics.

**Composite weighting** (`score-run.ps1:428-446`) — port 1:1:
```bash
# weight map + value map + weighted mean
composite=$(jq -n --argjson scores "$scores_json" '
  {cross_ai_diversity:1, convergence:1, plan_quality:1, execution_fidelity:1, verify_accuracy:1, cost:1, robustness:2} as $W |
  {PASS:1.0, PARTIAL:0.5, FAIL:0.0, "N/A":null} as $V |
  ($scores | to_entries | map(
    ($W[.key]) as $w | ($V[.value]) as $v |
    if $v==null then null else {sum_w:$w, sum_s: ($w * $v)} end
  ) | map(select(.!=null))) as $rows |
  if ($rows|length)==0 then 0
  else (($rows | map(.sum_s) | add) / ($rows | map(.sum_w) | add) * 1000 | round / 1000) end
')
```

Uses jq's `round` on `*1000` then `/1000` to get 3-decimal rounding (matches PS `[Math]::Round($sumS / $sumW, 3)`).

**Output format** — PS writes `scores.json` via `ConvertTo-Json -Depth 20 | Set-Content`. Bash port:
```bash
jq -n --arg case_id "$CASE_ID" ... '{
  case_id: $case_id,
  title: $title,
  run_id: $run_id,
  scores: $scores,
  composite: $composite,
  details: $details,
  scored_at: $now
}' > "$OUTPUT_DIR/scores.json"
```

**Determinism watch** (Tier 3 of 4-tier verification):
- jq's object-key ordering — use `jq -S` when writing final `scores.json` OR explicitly construct the object in a fixed key order to guarantee byte-stable output
- No `date +%s%N` / `$RANDOM` / `uuidgen` anywhere in the scorer hot path
- `scored_at` timestamp is non-deterministic BY DESIGN — Tier 3 comparison must strip `.scored_at` with `jq 'del(.scored_at)'` before diff. Mirror PS: PS's `scored_at` also drifts; PS-produced EXPECTED.json files OMIT it, so they're already stripped.

---

### `evals/run-evals.sh` (orchestrator — plan 02-03)

**Bash analog for CLI shell + phase loop:** `dev-review/codex/dev-review.sh:926-1028` (arg parsing); `dev-review.sh:162-168` (select_verifier pattern)
**PS source (spec):** `runners/codex-ps/evals/run-evals.ps1` (287 LOC)

**Header + arg parsing** — same pattern as `score-run.sh` (copy from `dev-review.sh:1-8` and the while/case block above).

PS CLI params to port (run-evals.ps1:34-53): `-Cases`, `-Validate`, `-KeepFixtures`, `-SkipScoring`, `-FakeRunner`, `-UseRunner`, `-Repeat`. All map cleanly to Bash flags. `-FakeRunner` and `-UseRunner` are test-harness shortcuts; plan 02-03 can defer them (`--fake-runner` / `--use-runner`) if scope pressure demands, but the core `--case`/`--cases` + `--validate` + `--keep-fixtures` + `--skip-scoring` + `--repeat` are Phase 2 gates.

**Case iteration loop** — port `run-evals.ps1:105-252` (the foreach over `$caseFiles`). Core shape:

PS `run-evals.ps1:70-72` case discovery:
```powershell
$allCaseFiles = Get-ChildItem -LiteralPath $CasesDir -Filter '*.yaml' -File |
    Where-Object { $_.Name -ne 'defaults.yaml' } |
    Sort-Object Name
```

Bash analog (glob + sort):
```bash
mapfile -t all_case_files < <(find "$CASES_DIR" -maxdepth 1 -name '*.yaml' ! -name 'defaults.yaml' -type f | sort)
```

PS `run-evals.ps1:110-111` case-merge pattern:
```powershell
$caseRaw = Read-YamlFile -Path $caseFile.FullName
$case = Merge-HashtablesDeep -Base $defaults -Override $caseRaw
```

Bash port — use `read_yaml_file` (new lib helper) + yq's deep-merge or jq's `*` operator:
```bash
case_json=$(yq -o=json "$case_file" | jq --slurpfile d <(yq -o=json "$DEFAULTS_FILE") '$d[0] * .')
```

**Runner invocation with stdout/stderr capture** — PS uses `Start-Process ... -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath` (run-evals.ps1:206-208). Bash analog is trivially `> "$stdout" 2> "$stderr"`.

PS `run-evals.ps1:197-199`:
```powershell
$cmd = @"
& '$runnerPath' -Task '$escapedTask' -Composer $composer -Reviewer $reviewer -Executor $executor -Bounces '$bounces' -Verify:$verifyTok -Autonomous:$autonomousTok
"@
```

Bash target: invoke `dev-review/codex/dev-review.sh` (which IS the Bash runner — the harness runs the real runner, no PS involvement). Build the flag list from merged case YAML:
```bash
bash "$REPO_ROOT/dev-review/codex/dev-review.sh" \
  --composer "$composer" --executor "$executor" \
  --bounces "$bounces" \
  ${verify:+--verify} \
  "$task" \
  > "$stdout_path" 2> "$stderr_path" || exit_code=$?
```

Note: The PS harness has no `-Reviewer` analog in the Bash runner (Bash uses `select_verifier()` which hardcodes opus when executor==codex per `dev-review.sh:162-168`). Plan 02-03 should decide: either (a) pass `--reviewer` through with a new runner flag (out of scope for Phase 2), or (b) silently drop the reviewer field from case merge and document the divergence in README. Claude's discretion per CONTEXT.md.

**raw-scores.json emission** (run-evals.ps1:260-264):
```powershell
$rawScores | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath $rawPath -Encoding UTF8
```

Bash port — collect per-case JSON objects into an array and emit with jq:
```bash
# Each iteration appends one JSON object to a temp array file
# At end: jq -s '.' "$tmp_records" > "$report_dir/raw-scores.json"
```

**Exit code policy** (run-evals.ps1:275-287) — 0 iff all cases pass Robustness:
```powershell
$robustFails = @($rawScores | Where-Object {
    ($_.status -eq 'fail') -or
    ($_.scores -and ($_.scores.robustness -eq 'FAIL'))
}).Count
if ($robustFails -gt 0) { exit 1 } else { exit 0 }
```

Bash port:
```bash
robust_fails=$(jq -r '[.[] | select(.status=="fail" or .scores.robustness=="FAIL")] | length' "$raw_scores_path")
if (( robust_fails > 0 )); then exit 1; fi
exit 0
```

---

### `evals/compare-reports.sh` (diff utility — plan 02-03)

**Bash analog for JSON delta:** `lib/co-evolution.sh::compute_execute_delta` lines 782-803
**PS source (spec):** `runners/codex-ps/evals/compare-reports.ps1` (110 LOC — shortest of the three ports)

**Core diff pattern** — copy the jq --slurpfile two-file pattern from `lib/co-evolution.sh:787-798`:

```bash
compute_execute_delta() {
  local baseline="${1:?baseline required}"
  local current="${2:?current required}"
  local output="${3:?output required}"

  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --slurpfile b "$baseline" \
      --slurpfile c "$current" \
      '
      ($b[0] // {}) as $B |
      ($c[0] // {}) as $C |
      {
        modified: [ ($B | keys[]) | select(($C[.] // null) != null and $C[.] != $B[.]) ] | sort,
        added:    [ ($C | keys[]) | select(($B[.] // null) == null) ] | sort,
        deleted:  [ ($B | keys[]) | select(($C[.] // null) == null) ] | sort
      }' > "$output"
  ...
}
```

This is the EXACT pattern to adapt for `compare-reports.sh` — two `raw-scores.json` files, build per-case regression/improvement/unchanged lists with jq.

**PS score-ordering map** (compare-reports.ps1:47) — port 1:1:
```bash
# In jq: {PASS:3, PARTIAL:2, FAIL:1, "N/A":null, "?":0}
# Per-dimension comparison: if after < before → regression; after > before → improvement
```

PS arrows `↓` / `↑` (compare-reports.ps1:68-72) — Bash port should emit same UTF-8 characters for PS-compat, OR use ASCII fallback (`v` / `^`) if CONTEXT.md's "line endings on Windows" risk materializes. Plan 02-03 tests both on Git Bash.

**Markdown assembly** (compare-reports.ps1:79-96) — straightforward string concatenation. Bash can use heredoc or `cat > $output <<EOF`.

**Exit code** (compare-reports.ps1:105-110) — 0 iff no Robustness regressions; 1 otherwise. Same shape as `run-evals.sh` exit-code logic.

---

### `evals/tests/scorer-verification.sh` (regression test — plan 02-03)

**Bash analog:** `tests/worktree-management-simulation.sh` (160 LOC — closest match by complexity + scenario-loop shape); `tests/live-mode-simulation.sh` (102 LOC — simpler scenario pattern); `tests/revise-loop-simulation.sh` (171 LOC — mocking-heavy pattern)
**PS source:** NONE (D-05 — PS test harness NOT ported). Test corpus inherited via `runners/codex-ps/evals/tests/fixtures/**/EXPECTED.json`.

**Header + mktemp + trap cleanup** — copy from `tests/worktree-management-simulation.sh:16-24`:

```bash
#!/usr/bin/env bash
# tests/scorer-verification.sh
# Tier 1: Golden-fixture regression. Runs Bash scorer against
# runners/codex-ps/evals/tests/fixtures/**/EXPECTED.json and asserts
# output matches within semantic epsilon (0.001 for float fields).

set -euo pipefail

TEST_DIR=$(mktemp -d -t scorer-verify-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export REPO_ROOT

FAILURES=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
```

(REPO_ROOT needs TWO `..` because this test lives at `evals/tests/` not `tests/`.)

**Scenario-loop over fixtures** — ADAPT the `worktree-management-simulation.sh` per-scenario subshell pattern (`:42-55`):

```bash
# Iterate every fixture suite under runners/codex-ps/evals/tests/fixtures/
for fixture_dir in "$REPO_ROOT/runners/codex-ps/evals/tests/fixtures/"*/; do
  suite_name=$(basename "$fixture_dir")
  (
    case_file="$fixture_dir/case.yaml"
    run_dir="$fixture_dir/run"
    expected_file="$fixture_dir/EXPECTED.json"
    actual_scores="$TEST_DIR/$suite_name-actual.json"

    bash "$REPO_ROOT/evals/score-run.sh" \
      --case-file "$case_file" \
      --run-dir "$run_dir" \
      --output-dir "$TEST_DIR/$suite_name" > /dev/null

    # Tier 1 comparison: jq -S sort keys, extract .scores, diff
    actual=$(jq -S '.scores' "$TEST_DIR/$suite_name/scores.json")
    expected=$(jq -S '.scores' "$expected_file")
    [[ "$actual" == "$expected" ]] || {
      echo "Suite $suite_name: scores mismatch" >&2
      diff <(echo "$expected") <(echo "$actual") >&2
      exit 1
    }
  ) || fail "Suite $suite_name"
done
```

**Tier 3 determinism check** — run scorer twice on same fixture, assert byte-identical (with `scored_at` stripped):

```bash
# Scenario: determinism sanity
(
  fixture="$REPO_ROOT/runners/codex-ps/evals/tests/fixtures/01-all-pass"
  for i in 1 2; do
    bash "$REPO_ROOT/evals/score-run.sh" \
      --case-file "$fixture/case.yaml" \
      --run-dir "$fixture/run" \
      --output-dir "$TEST_DIR/det-$i" > /dev/null
    jq -S 'del(.scored_at)' "$TEST_DIR/det-$i/scores.json" > "$TEST_DIR/det-$i.norm.json"
  done
  diff "$TEST_DIR/det-1.norm.json" "$TEST_DIR/det-2.norm.json" \
    || { echo "Determinism regression: two runs produced different output" >&2; exit 1; }
) || fail "Scenario: determinism sanity"
```

**Summary footer** — copy from `tests/worktree-management-simulation.sh:154-160`:

```bash
if (( FAILURES == 0 )); then
  echo "ALL SCENARIOS PASSED"
  exit 0
else
  echo "FAILED: $FAILURES scenario(s)" >&2
  exit 1
fi
```

**Float-epsilon comparison** (per CONTEXT.md D-01, 0.001 tolerance on float fields) — the Tier 1 comparison above uses string equality via `jq -S`, which is fine for the `scores` dict (strings: PASS/PARTIAL/FAIL/N/A). For `composite` float comparison, use jq:

```bash
# Epsilon float diff
jq --slurpfile a "$actual_scores" --slurpfile e "$expected_file" -n '
  ($a[0].composite // 0) as $ac |
  ($e[0].composite // 0) as $ec |
  (($ac - $ec) | if . < 0 then -. else . end) as $delta |
  if $delta > 0.001 then "FAIL: composite diff $delta > 0.001" else "ok" end
'
```

But note: existing `EXPECTED.json` files DO NOT contain `composite` — they're `{scores: {...}}` only (verified against `01-all-pass/EXPECTED.json:1-11`, `02-robustness-fail/EXPECTED.json`, `08-unparseable-verdict/EXPECTED.json`). So Tier 1 Bash test only needs scores-dict string match, not float epsilon. Tier 3 determinism test covers the float-stability invariant.

---

### `evals/README.md` (doc update — plan 02-03)

**Existing file:** `C:/Users/alan/Project/co-evolution-v12/evals/README.md` (103 lines, already documents the PS harness as canonical)

**Update scope** — minimal, per CONTEXT.md "Claude's Discretion":
1. Replace "A Bash port of the harness is **deferred to post-milestone work**" (`README.md:45-47`) with an Invocation section pointing at `evals/run-evals.sh`, `evals/score-run.sh`, `evals/compare-reports.sh` as defaults.
2. Update the pwsh-dependency table (`README.md:57-64`) — flip the pwsh column for eval harness lines from "Yes" to "No (Bash default; PS legacy)".
3. Add a Dependencies subsection: `jq` (already required) + `yq` (new) with install instructions per CONTEXT.md specifics (`scoop install yq` / `brew install yq` / `apt install yq`).
4. Keep the "Running Evals Today" PS block (`README.md:30-38`) as a "legacy reference" — CONTEXT.md D-04 explicitly says "point at `runners/codex-ps/evals/` for PS legacy reference."

---

## Shared Patterns

### Logging
**Source:** `lib/co-evolution.sh:3-11` (`log()` function)
**Apply to:** Every new Bash file (library + 3 scripts + test)
```bash
log() {
  local message="${1:-}"
  if [[ -n "${LOG_FILE:-}" ]]; then
    echo "$message" | tee -a "$LOG_FILE"
  else
    echo "$message"
  fi
}
```
Mechanism: scripts optionally export `$LOG_FILE`; helper tee-writes to it when set. Matches existing runner logging contract.

### Fatal Errors
**Source:** `lib/co-evolution.sh:13-17` (`die()` function)
**Apply to:** Every new Bash file
```bash
die() {
  local message="${1:-Fatal error}"
  log "ERROR: $message"
  exit 1
}
```
Every `[[ condition ]] || die "message"` or `command || die "message"` gates a precondition. CONTEXT.md explicitly says "Error-handling granularity for malformed YAML — fail fast with a clear error is the floor."

### Mandatory Argument Guards
**Source:** `lib/co-evolution.sh:742-744, 807-813, 862-868` (`${N:?message}` idiom)
**Apply to:** Every new library function with required args
```bash
local workdir="${1:?some_helper requires a workdir}"
local output_path="${2:?some_helper requires an output path}"
```

### jq Atomic Writes
**Source:** `lib/co-evolution.sh:870-895` (write_state_phase mktemp → jq → mv pattern)
**Apply to:** Every scorer output (scores.json, report.md, raw-scores.json, comparison markdown)
```bash
local tmp
tmp=$(mktemp)
if jq '...' "$input" > "$tmp"; then
  mv "$tmp" "$output"
else
  rm -f "$tmp"
  die "jq failed in <context>"
fi
```
Per CONTEXT.md D-03, drop the `command -v jq` guard (jq IS required). Keep the mktemp → mv atomicity.

### Trap Cleanup for Scripts with Tmp Dirs
**Source:** `tests/worktree-management-simulation.sh:18-20`, `tests/live-mode-simulation.sh:15-17`, `tests/revise-loop-simulation.sh:26-28`
**Apply to:** `evals/run-evals.sh` (fixture tmp dirs), `evals/tests/scorer-verification.sh` (test tmp dir). NOT in `evals/lib/co-evolution-evals.sh` (sourced library, not a script).
```bash
TEST_DIR=$(mktemp -d -t <name>-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
```

### REPO_ROOT Derivation
**Source:** `dev-review/codex/dev-review.sh:5-6`, `tests/worktree-management-simulation.sh:22-23`
**Apply to:** All new scripts
```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"     # or "/.." twice for nested dirs
```
`evals/tests/scorer-verification.sh` lives 2 levels deep from repo root, so needs `$SCRIPT_DIR/../..`. `evals/score-run.sh` / `run-evals.sh` / `compare-reports.sh` live 1 level deep, so `$SCRIPT_DIR/..`.

### CLI Flag Parsing (while/case/shift)
**Source:** `dev-review/codex/dev-review.sh:926-1028`
**Apply to:** `evals/score-run.sh`, `evals/run-evals.sh`, `evals/compare-reports.sh`
Copy the full `while [[ $# -gt 0 ]]; do case "$1" in ...` block, adapt per-flag.

### JSON Schema Validation
**Source:** `lib/co-evolution.sh::validate_review_verdict` lines 453-571 (jq-heavy structural validation with explicit fallback + per-field error messages)
**Apply to:** Scorer's verdict.json parsing (`evals/score-run.sh` emulates `score-run.ps1:89-97` `$verdict = '__unparseable__'` sentinel)

Key excerpt — jq structural guard pattern (`lib/co-evolution.sh:462-476`):
```bash
jq -e 'type == "object"' "$json_file" >/dev/null 2>&1 || {
  printf '%s' "verdict was not a JSON object"
  return 1
}
jq -e 'has("verdict") and has("confidence") and has("summary") and has("issues")' "$json_file" >/dev/null 2>&1 || {
  printf '%s' "verdict was missing one or more required fields"
  return 1
}
```
For scorer's verdict handling, the parse failure doesn't abort the run — it sets a sentinel (`__unparseable__` in PS; use `unparseable="true"` shell var in Bash) and the scorer continues to emit `scores.verify_accuracy = FAIL`. Use `jq -e . "$verdict_path" >/dev/null 2>&1 || unparseable=true` as the guard.

---

## Non-Obvious Risks Per File

### `evals/lib/co-evolution-evals.sh`
- **YAML merge semantics divergence** (CONTEXT.md `<code_context>` non-obvious risks): PS's `Merge-HashtablesDeep` (Yaml.ps1:48-75) does recursive deep-merge with override-wins semantics, lists replaced wholesale. yq's `*` operator and jq's `*` both do the same — but they differ on null handling. Plan 02-01 must test on `cases/defaults.yaml` + `cases/01-trivial-task.yaml` as a first-class acceptance test; failure here breaks every downstream scorer pass.
- **Trap-cleanup red herring**: CONTEXT.md hinted that `lib/co-evolution.sh` "uses trap-based cleanup" — it does NOT (verified: no `trap` in lib). Only the test scripts do. Don't try to port a non-existent pattern; the library stays trap-free.

### `evals/score-run.sh`
- **jq float determinism** (CONTEXT.md non-obvious risk): jq handles doubles via IEEE 754 but differs from .NET in rounding edge cases. Plan 02-02 should probe early with `details.execution_fidelity.jaccard` (rounded to 3 decimals in PS via `[Math]::Round($jac, 3)`) — run on `01-all-pass/run/` and compare to EXPECTED. If divergence > 0.001 emerges, tighten epsilon only if all fixtures still pass.
- **Levenshtein in awk** — awk's 2D arrays work, but performance on 4000x4000 matrices may be slow on Git Bash for Windows. Keep the 4000-char cap from PS; measure runtime on worst-case fixture before committing to awk vs a jq-only approach.
- **grep behavior on .log files** — PS uses case-insensitive regex across all `*.log` files in `outputs/`. Bash `grep -iE` matches (tested above in Robustness port). Watch for `grep`'s exit 1 on no-match — use `|| true` or `grep -c` + int compare.

### `evals/run-evals.sh`
- **-Reviewer divergence**: PS case YAML has a `runner.reviewer` field that Bash dev-review has no equivalent for. Either punt (drop silently — v1 posture) or add `--reviewer` flag to dev-review (scope creep). See Plan 02-03 decision note above.
- **Start-Process vs bash piping**: PS redirects stdout/stderr via `Start-Process -RedirectStandardOutput/Error`. Bash `> "$out" 2> "$err"` is equivalent — but `dev-review.sh` itself internally uses `tee "$LOG_FILE"`, so setting `LOG_FILE="$stdout_path"` plus piping stdout may double-log. Pick one: either set LOG_FILE OR redirect, not both.
- **Fixture git init** (Fixture.ps1:46-55): PS wraps `git init` in `$ErrorActionPreference = 'Continue'` because git prints advisory lines to stderr that PS 5.1 strict mode treats as errors. Bash doesn't have this problem — `git -c core.autocrlf=false init -q` should Just Work. But keep the `-q` to silence CRLF warnings on Git Bash for Windows.

### `evals/compare-reports.sh`
- **UTF-8 arrows on Git Bash Windows** — `↓` / `↑` may render as mojibake if stdout isn't UTF-8. PS uses them fine in Windows Terminal. Test on Git Bash explicitly in plan 02-03 — if mojibake appears, fall back to `v` / `^` ASCII (but this diverges visually from PS output, acceptable per CONTEXT.md D-01 "Semantic equivalence" bar).

### `evals/tests/scorer-verification.sh`
- **REPO_ROOT depth**: 2 levels deep from repo root (`../..`), not 1. Miscount breaks every path in the test.
- **Fixture drift**: If the PS scorer is updated without re-generating EXPECTED.json, the Bash port will mismatch EXPECTED even when it's correct. The EXPECTED.json files are the STATIC spec; they must match the current PS scorer. v1 posture: assume EXPECTED files are current as of 2026-04-17. If drift is suspected during plan 02-02, re-run PS scorer against the fixtures and commit updated EXPECTED.json as a pre-port step.
- **10 fixtures, not 2** — CONTEXT.md said "2+ suites"; actual is 10. Plan 02-03 should verify all 10 succeed, not just 2. This expands Tier 1 coverage significantly.

### `evals/README.md`
- **Keep PS block as legacy reference** — don't delete the `pwsh runners/codex-ps/evals/run-evals.ps1` commands; CONTEXT.md D-04 explicitly preserves them. Flip the framing, not the content.

---

## Dependency Contract (for planner)

Every new file depends on these already-in-place assets:

| Dependency | Source | Status |
|------------|--------|--------|
| `jq` binary | system PATH | already required by `dev-review.sh` |
| `yq` binary (mikefarah) | system PATH | **NEW dep** — install docs go in README |
| `bash` ≥ 4 | system | standard |
| `lib/co-evolution.sh::log` | sourced | existing |
| `lib/co-evolution.sh::die` | sourced | existing |
| `evals/cases/*.yaml` | repo | 10 files in place (v1.0 Phase 8) |
| `schemas/review-verdict.json` | repo | in place (v1.0 Phase 8) |
| `runners/codex-ps/evals/report-template.md` | repo | in place (port COPY to `evals/report-template.md` in plan 02-01) |
| `runners/codex-ps/evals/tests/fixtures/**/` | repo | **10 suites** available (not 2 as CONTEXT.md estimated) |

Cross-plan dependency graph:
- Plan 02-01 (lib) → NO runtime deps on 02-02/02-03 (but `lib/co-evolution-evals.sh` should be importable standalone so 02-02 and 02-03 can source it)
- Plan 02-02 (scorer) → sources 02-01's library
- Plan 02-03 (runner + comparator + test) → sources 02-01's library AND invokes 02-02's scorer binary

---

## Metadata

**Analog search scope:**
- `C:/Users/alan/Project/co-evolution-v12/lib/` — shared bash library
- `C:/Users/alan/Project/co-evolution-v12/dev-review/codex/` — primary Bash orchestrator (1326 LOC)
- `C:/Users/alan/Project/co-evolution-v12/tests/` — simulation test scripts (3 files, 433 LOC)
- `C:/Users/alan/Project/co-evolution-v12/evals/` — portable assets (cases, fixtures, schemas, README)
- `C:/Users/alan/Project/co-evolution-v12/runners/codex-ps/evals/` — PS source specs (1226 LOC across 6 files)
- `C:/Users/alan/Project/co-evolution-v12/schemas/` — JSON schemas

**Files scanned:** 20+ (full bodies of `lib/co-evolution.sh`, all 6 PS sources, 3 simulation tests, existing `evals/README.md`, all 10 EXPECTED.json fixtures spot-checked for schema)

**Pattern extraction date:** 2026-04-17

---

*Phase: 02-bash-eval-harness-port*
