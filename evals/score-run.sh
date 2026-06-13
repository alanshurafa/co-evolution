#!/usr/bin/env bash
# evals/score-run.sh
# Port of runners/codex-ps/evals/score-run.ps1 (BASH-EVAL-01 Plan 02-02).
# Scores a single co-evolution run against a case spec across 7 dimensions.
# Emits scores.json to --output-dir (default: --run-dir).
#
# Dimensions (PS analog lines in score-run.ps1):
#   robustness         (234-251)  — state.status + UnhandledException grep in outputs/*.log
#   convergence        (253-301)  — marker_counts.total + bounce structural check
#   plan_quality       (303-320)  — plan.md word count + heading group match
#   execution_fidelity (322-337)  — Jaccard of plan-declared paths vs state.changed_files
#   verify_accuracy    (339-378)  — verdict.json presence + allow_verdict / must_catch_issue
#   cost               (380-402)  — wall-clock state.started_at -> .updated_at vs max
#   cross_ai_diversity (404-426)  — Levenshtein(compose.txt, bounce-01.txt) when composer != reviewer
#
# Dependencies: bash, jq, yq, awk, grep, find, wc, date. Per D-03 all mandatory.
#
# Determinism contract (D-02): byte-identical output across repeated invocations on
# the same input, stripping .scored_at. Must NOT use environment-random or sub-second
# clock sources (per plan_02-02 acceptance criteria).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/co-evolution.sh
source "${REPO_ROOT}/lib/co-evolution.sh"
# shellcheck source=./lib/co-evolution-evals.sh
source "${SCRIPT_DIR}/lib/co-evolution-evals.sh"

# ---------------------------------------------------------------------------
# Helpers — Jaccard + Levenshtein (ported from score-run.ps1:102-169)
# ---------------------------------------------------------------------------

# jaccard <a_json_file> <b_json_file>
# Each input file must contain a JSON array of strings. Emits a float in [0.0, 1.0].
# Semantics match score-run.ps1:122-133:
#   both-empty  -> 1.0
#   one-empty   -> 0.0 (union is non-empty from the other side -> empty intersection)
#   otherwise   -> |A ∩ B| / |A ∪ B|
jaccard() {
  local a_file="${1:?jaccard requires path a}"
  local b_file="${2:?jaccard requires path b}"
  jq -n --slurpfile a "$a_file" --slurpfile b "$b_file" '
    ($a[0] // []) as $A | ($b[0] // []) as $B |
    if ($A|length)==0 and ($B|length)==0 then 1.0
    else
      (($A + $B) | unique) as $union |
      if ($union|length)==0 then 0.0
      else
        ($A - ($A - $B)) as $inter |
        (($inter|length) / ($union|length))
      end
    end
  '
}

# levenshtein <a_file> <b_file>
# Emits the integer edit distance on stdout using Wagner-Fischer 2-row DP.
# 4000-character cap per PS (prevents O(n*m) blowup on multi-MB bounces).
# awk's 2D-via-two-1D-arrays pattern is portable across BSD and GNU awk.
# The function reads the raw file bytes and strips a UTF-8 BOM on either side
# so PS-produced compose.txt / bounce-*.txt (BOM-prefixed) compare cleanly.
levenshtein() {
  local a_file="${1:?levenshtein requires path a}"
  local b_file="${2:?levenshtein requires path b}"
  awk -v a_file="$a_file" -v b_file="$b_file" '
    BEGIN {
      # Read both files into single strings, preserving newlines.
      a = ""
      while ((getline l < a_file) > 0) {
        if (a == "") a = l; else a = a "\n" l
      }
      close(a_file)
      b = ""
      while ((getline l < b_file) > 0) {
        if (b == "") b = l; else b = b "\n" l
      }
      close(b_file)

      # Strip UTF-8 BOM (0xEF 0xBB 0xBF) if present.
      bom = sprintf("%c%c%c", 0xef, 0xbb, 0xbf)
      if (substr(a, 1, 3) == bom) a = substr(a, 4)
      if (substr(b, 1, 3) == bom) b = substr(b, 4)

      la = length(a); lb = length(b)
      cap = 4000
      if (la > cap) { la = cap; a = substr(a, 1, cap) }
      if (lb > cap) { lb = cap; b = substr(b, 1, cap) }
      if (la == 0) { print lb; exit }
      if (lb == 0) { print la; exit }

      for (j = 0; j <= lb; j++) prev[j] = j
      for (i = 1; i <= la; i++) {
        curr[0] = i
        ca = substr(a, i, 1)
        for (j = 1; j <= lb; j++) {
          cb = substr(b, j, 1)
          cost = (ca == cb) ? 0 : 1
          del_ = prev[j]   + 1
          ins  = curr[j-1] + 1
          sub_ = prev[j-1] + cost
          m = del_; if (ins < m) m = ins; if (sub_ < m) m = sub_
          curr[j] = m
        }
        for (j = 0; j <= lb; j++) prev[j] = curr[j]
      }
      print prev[lb]
    }
  '
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: evals/score-run.sh --case-file PATH --run-dir PATH [OPTIONS]

Score a single co-evolution run across 7 dimensions and emit scores.json.

Required:
  --case-file PATH      Case YAML spec (merged with --defaults-file if given).
  --run-dir PATH        Captured run dir containing state.json, plan.md,
                        verdict.json, outputs/.

Optional:
  --defaults-file PATH  Defaults YAML merged under the case (default: none).
  --output-dir PATH     Where to write scores.json (default: --run-dir).
  --help                Show this help and exit 0.

Exit codes:
  0 on successful score emission
  1 on any fatal error (missing state.json, invalid JSON, jq failure, etc.)
EOF
}

# ---------------------------------------------------------------------------
# CLI parsing (ports score-run.ps1 param block 1:1)
# ---------------------------------------------------------------------------

CASE_FILE=""
RUN_DIR=""
DEFAULTS_FILE=""
OUTPUT_DIR=""

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
    --help|-h)
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

[[ -n "$CASE_FILE" ]] || { usage >&2; die "--case-file is required"; }
[[ -n "$RUN_DIR" ]]   || { usage >&2; die "--run-dir is required"; }
[[ -f "$CASE_FILE" ]] || die "case file not found: $CASE_FILE"
[[ -d "$RUN_DIR" ]]   || die "run-dir not found: $RUN_DIR"
[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="$RUN_DIR"
mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Load merged case spec (ports score-run.ps1:52-57)
# ---------------------------------------------------------------------------

if [[ -n "$DEFAULTS_FILE" && -f "$DEFAULTS_FILE" ]]; then
  case_json=$(merge_yaml_defaults "$DEFAULTS_FILE" "$CASE_FILE")
else
  case_json=$(read_yaml_file "$CASE_FILE")
fi

case_id=$(jq -r '.id // "unknown"' <<<"$case_json")
case_title=$(jq -r '.title // ""' <<<"$case_json")
composer=$(jq -r '(.runner.composer // "codex") | tostring' <<<"$case_json")
reviewer=$(jq -r '(.runner.reviewer // "codex") | tostring' <<<"$case_json")
executor=$(jq -r '(.runner.executor // "codex") | tostring' <<<"$case_json")

# ---------------------------------------------------------------------------
# Load run artifacts (ports score-run.ps1:79-100)
# ---------------------------------------------------------------------------

state_json_path="$RUN_DIR/state.json"
[[ -f "$state_json_path" ]] || die "state.json not found at: $state_json_path"
jq -e . "$state_json_path" >/dev/null 2>&1 || die "state.json is not valid JSON: $state_json_path"

plan_path="$RUN_DIR/plan.md"
plan_text=""
if [[ -f "$plan_path" ]]; then
  plan_text=$(<"$plan_path")
  # Strip UTF-8 BOM if present (PS-produced fixtures are BOM-prefixed; PS reads
  # them transparently, but Bash grep on ^# would miss "# Plan" after a BOM.
  # \xef\xbb\xbf is the 3-byte UTF-8 BOM).
  plan_text="${plan_text#$'\xef\xbb\xbf'}"
fi

verdict_path="$RUN_DIR/verdict.json"
verdict_state=''
load_json_or_sentinel "$verdict_path" verdict_state
# verdict_state is: "" (OK), "missing" (file absent), or "unparseable" (bad JSON)

outputs_dir="$RUN_DIR/outputs"

run_id=$(jq -r '.run_id // "unknown"' "$state_json_path")

# ---------------------------------------------------------------------------
# Dimension: Robustness (port score-run.ps1:234-251)
# state.status != "completed" -> FAIL. Exception regex in outputs/*.log -> PARTIAL.
# ---------------------------------------------------------------------------

status=$(jq -r '.status // "unknown"' "$state_json_path")
robust="PASS"
[[ "$status" != "completed" ]] && robust="FAIL"
had_exception=false
if [[ -d "$outputs_dir" ]]; then
  # Guard: the glob expands to nothing if no *.log files; redirect stderr to /dev/null
  # and explicitly handle grep's exit 1 on no-match via `|| true` pattern (avoid set -e).
  if grep -qiE '\bUnhandledException\b|\bFullyQualifiedErrorId\b.*\bRuntimeException\b' "$outputs_dir/"*.log 2>/dev/null; then
    had_exception=true
  fi
fi
if [[ "$had_exception" == "true" && "$robust" == "PASS" ]]; then
  robust="PARTIAL"
fi

# ---------------------------------------------------------------------------
# Dimension: Cost (port score-run.ps1:380-402)
# wall = updated_at - started_at. > max -> PARTIAL. > max*1.5 -> FAIL.
# ---------------------------------------------------------------------------

max_wall=$(jq -r '(.expectations.cost.max_wall_clock_seconds // 900) | tostring' <<<"$case_json")
started_at=$(jq -r '.started_at // ""' "$state_json_path")
updated_at=$(jq -r '.updated_at // ""' "$state_json_path")

wall_secs=0
if [[ -n "$started_at" && -n "$updated_at" && "$started_at" != "null" && "$updated_at" != "null" ]]; then
  # jq's fromdateiso8601 requires "%Y-%m-%dT%H:%M:%SZ" form; PS emits
  # fractional seconds + numeric timezone offsets (e.g. "2026-04-17T09:00:00.0000000-04:00").
  # parseiso trims the fractional part then splits the numeric offset, parses the
  # base with a Z suffix, and subtracts the offset in seconds to recover UTC epoch.
  # Character-class "[.]" avoids shell/jq escape collisions for the literal dot.
  wall_secs=$(jq -rn --arg s "$started_at" --arg e "$updated_at" '
    def trimfrac: sub("[.][0-9]+"; "");
    def parseiso:
      trimfrac as $t |
      if ($t | test("Z$")) then ($t | fromdateiso8601?)
      else
        (($t | capture("^(?<base>.+T[0-9:]+)(?<sign>[+-])(?<h>[0-9]{2}):(?<m>[0-9]{2})$")?) // null) as $m |
        if $m == null then null
        else
          (($m.h | tonumber) * 3600 + ($m.m | tonumber) * 60) as $offs |
          (if $m.sign == "-" then -$offs else $offs end) as $tzsec |
          (($m.base + "Z") | fromdateiso8601?) as $epoch |
          if $epoch == null then null else ($epoch - $tzsec) end
        end
      end;
    (($s | parseiso) // null) as $se |
    (($e | parseiso) // null) as $ee |
    if ($se != null and $ee != null) then ($ee - $se) else 0 end
  ')
fi

cost="PASS"
# Integer compare; ensure numeric. If either side non-numeric, default to 0 (PASS)
if [[ "$wall_secs" =~ ^[0-9]+$ && "$max_wall" =~ ^[0-9]+$ ]]; then
  if (( wall_secs > max_wall )); then
    cost="PARTIAL"
  fi
  threshold_hard=$(( max_wall * 3 / 2 ))  # max * 1.5
  if (( wall_secs > threshold_hard )); then
    cost="FAIL"
  fi
fi

# ---------------------------------------------------------------------------
# Dimension: Convergence (port score-run.ps1:253-301)
# Checks: (1) marker_counts.total -> PASS=0 / PARTIAL<=2 / FAIL>2;
#         (2) if expects_bounces, outputs/bounce-*.txt OR state.history has a
#             "bounce-NN" phase -> structural_ok (Tier 4 regression A axiom).
# ---------------------------------------------------------------------------

final_markers=$(jq -r '.marker_counts.total // 0' "$state_json_path")
convergence="FAIL"
if [[ "$final_markers" =~ ^[0-9]+$ ]]; then
  if   (( final_markers == 0 )); then convergence="PASS"
  elif (( final_markers <= 2 )); then convergence="PARTIAL"
  fi
fi

# Bounces expected iff runner.bounces is a positive integer (default "auto" -> expected).
requested_bounces=$(jq -r '.runner.bounces // "auto"' <<<"$case_json")
expects_bounces=true
if [[ "$requested_bounces" =~ ^[0-9]+$ ]] && (( requested_bounces <= 0 )); then
  expects_bounces=false
fi

# Structural bounce-check (PS Tier 4 regression A): require either a real
# outputs/bounce-NN.txt artifact OR a state.history entry matching "^bounce-[0-9]+$".
# The plain "bounce" wrapper phase is insufficient — it is written BEFORE the
# loop body runs and doesn't prove any iteration executed.
bounce_phases_ran=false
if [[ -d "$outputs_dir" ]]; then
  # find | sort for deterministic iteration; wc -l gives count.
  bounce_files_count=$(find "$outputs_dir" -maxdepth 1 -type f -name 'bounce-*.txt' 2>/dev/null | wc -l | tr -d ' ')
  if (( bounce_files_count > 0 )); then
    bounce_phases_ran=true
  fi
fi
if [[ "$bounce_phases_ran" != "true" ]]; then
  bounce_hist=$(jq -r '[.history[]? | select((.phase // "") | test("^bounce-[0-9]+$"))] | length' "$state_json_path" 2>/dev/null || echo 0)
  if [[ "$bounce_hist" =~ ^[0-9]+$ ]] && (( bounce_hist > 0 )); then
    bounce_phases_ran=true
  fi
fi

bounce_structural_ok=true
if [[ "$expects_bounces" == "true" && "$bounce_phases_ran" != "true" ]]; then
  convergence="FAIL"
  bounce_structural_ok=false
fi

# ---------------------------------------------------------------------------
# Dimension: Plan Quality (port score-run.ps1:303-320)
# Checks: (1) words >= min_word_count; (2) every heading group has >=1 match;
#         PASS = both OK; PARTIAL = PASS + has TODO/TBD/FIXME; FAIL otherwise.
# Default heading groups match PS hardcoded fallback: (Plan|Approach|Strategy) + (Risks|Concerns|Caveats).
# ---------------------------------------------------------------------------

min_words=$(jq -r '.expectations.plan_quality.min_word_count // 120' <<<"$case_json")
# must_contain_any is a list of lists: each inner list is an OR group; ALL groups
# must have ≥1 hit. Default to PS hardcoded fallback when case and defaults omit it.
has_mca=$(jq -r 'has("expectations") and (.expectations | has("plan_quality")) and (.expectations.plan_quality | has("must_contain_any"))' <<<"$case_json")
if [[ "$has_mca" == "true" ]]; then
  heading_groups_json=$(jq -c '.expectations.plan_quality.must_contain_any' <<<"$case_json")
else
  heading_groups_json='[["Plan","Approach","Strategy"],["Risks","Concerns","Caveats"]]'
fi

# Word count: split on whitespace, drop empties. Use awk for deterministic behavior.
plan_word_count=$(printf '%s' "$plan_text" | awk 'BEGIN{n=0} {for(i=1;i<=NF;i++) if(length($i)>0) n++} END{print n}')

# Heading check: each group must have ≥1 heading of form ^#+\s+<token>.
# Iterate with jq to enumerate groups/tokens deterministically; grep each token
# against plan_text via process substitution (stream through bash here-string
# would require echo -n semantics that differ across shells).
headings_ok=true
groups_count=$(jq -r 'length' <<<"$heading_groups_json")
for ((gi = 0; gi < groups_count; gi++)); do
  group_size=$(jq -r --argjson i "$gi" '.[$i] | length' <<<"$heading_groups_json")
  group_matched=false
  for ((ti = 0; ti < group_size; ti++)); do
    token=$(jq -r --argjson i "$gi" --argjson t "$ti" '.[$i][$t]' <<<"$heading_groups_json")
    # Build extended regex; grep -E. Case-SENSITIVE to match PS default.
    # Use fixed-string in token portion defused via grep's -P escape-like handling;
    # PS uses [regex]::Escape($h). Since fixture tokens are plain words (Plan,
    # Risks, etc.) no escape issues arise; but guard anyway by rejecting anything
    # that isn't alphanumeric/space for the security posture T-02-02-03.
    if [[ "$token" =~ ^[[:alnum:][:space:]_-]+$ ]]; then
      if printf '%s\n' "$plan_text" | grep -qE "^#+[[:space:]]+${token}\\b"; then
        group_matched=true
        break
      fi
    fi
  done
  if [[ "$group_matched" != "true" ]]; then
    headings_ok=false
    break
  fi
done

has_todo_stub=false
if printf '%s\n' "$plan_text" | grep -qE '\b(TODO|TBD|FIXME)\b'; then
  has_todo_stub=true
fi

plan_quality="PASS"
if ! [[ "$plan_word_count" =~ ^[0-9]+$ ]] || (( plan_word_count < min_words )) || [[ "$headings_ok" != "true" ]]; then
  plan_quality="FAIL"
elif [[ "$has_todo_stub" == "true" ]]; then
  plan_quality="PARTIAL"
fi

# ---------------------------------------------------------------------------
# Dimension: Execution Fidelity (port score-run.ps1:102-133 Jaccard + 322-337)
# Jaccard(plan-declared files, state.changed_files). PASS if >= min_jaccard;
# PARTIAL if >= min_jaccard * 0.6; FAIL otherwise.
# Special case: no-op plan AND no changes -> PASS.
# ---------------------------------------------------------------------------

min_jaccard=$(jq -r '.expectations.execution_fidelity.min_jaccard // 0.5' <<<"$case_json")

# Extract "Files to Change" section from plan.md, then per-line match
# ^- `path` (preferred) OR ^- word (fallback). Sort -u for determinism.
# Use awk to scan only the "## Files to Change" section up to the next "##".
plan_files_file=$(mktemp)
printf '%s\n' "$plan_text" | awk '
  BEGIN { in_section = 0 }
  /^##[[:space:]]+Files to Change[[:space:]]*$/ { in_section = 1; next }
  /^##[[:space:]]/ { if (in_section) exit }
  in_section { print }
' | awk '
  # Extract path from either: `- \`path\` ...` or `- path ...` (no backticks).
  {
    line = $0
    sub(/^[[:space:]]+/, "", line)
    if (line !~ /^-[[:space:]]+/) next
    sub(/^-[[:space:]]+/, "", line)
    # Backtick-delimited path preferred.
    if (match(line, /`[^`]+`/)) {
      p = substr(line, RSTART + 1, RLENGTH - 2)
      print p
    } else {
      # First token up to whitespace or (/).
      n = split(line, parts, /[[:space:]()]+/)
      if (n >= 1 && parts[1] != "" && parts[1] != "(no") print parts[1]
    }
  }
' | sort -u | jq -Rn '[inputs | select(length > 0)]' > "$plan_files_file"

# Normalize state.changed_files to a JSON array (could be string or array).
state_files_file=$(mktemp)
jq '
  .changed_files as $cf |
  if $cf == null then []
  elif ($cf | type) == "string" then [$cf]
  elif ($cf | type) == "array" then [$cf[] | select(. != null and . != "")]
  else []
  end
' "$state_json_path" > "$state_files_file"

plan_files_count=$(jq -r 'length' "$plan_files_file")
state_files_count=$(jq -r 'length' "$state_files_file")

if (( plan_files_count == 0 && state_files_count == 0 )); then
  # No-op plan + no changes: PASS
  jac="1.0"
  execution_fidelity="PASS"
else
  jac=$(jaccard "$plan_files_file" "$state_files_file")
  execution_fidelity=$(jq -nr --argjson j "$jac" --argjson m "$min_jaccard" '
    if   $j >= $m        then "PASS"
    elif $j >= ($m * 0.6) then "PARTIAL"
    else                       "FAIL"
    end
  ')
fi
rm -f "$plan_files_file" "$state_files_file"

# ---------------------------------------------------------------------------
# Dimension: Verify Accuracy (port score-run.ps1:339-378)
# Scored only when case.expectations.verify_accuracy is set; else N/A.
# missing/unparseable verdict.json -> FAIL.
# must_catch_issue branch: verdict=REVISE + keyword hit -> PASS;
#                           verdict=REVISE only -> PARTIAL;
#                           else -> FAIL.
# non-catch branch: verdict in allow_verdict -> PASS; else -> FAIL.
# ---------------------------------------------------------------------------

has_va_expect=$(jq -r 'has("expectations") and (.expectations | has("verify_accuracy"))' <<<"$case_json")
verify_accuracy="N/A"
if [[ "$has_va_expect" == "true" ]]; then
  if [[ "$verdict_state" == "unparseable" || "$verdict_state" == "missing" ]]; then
    verify_accuracy="FAIL"
  else
    must_catch=$(jq -r '(.expectations.verify_accuracy.must_catch_issue // false) | tostring' <<<"$case_json")
    # allow_verdict default matches PS: ['APPROVED','REVISE']
    allow_verdict_json=$(jq -c '.expectations.verify_accuracy.allow_verdict // ["APPROVED","REVISE"]' <<<"$case_json")
    keywords_json=$(jq -c '.expectations.verify_accuracy.issue_keywords // []' <<<"$case_json")

    actual_verdict=$(jq -r '.verdict // ""' "$verdict_path")

    # keyword_hit: any keyword appears (as a literal substring) in the
    # issues-as-JSON text. PS iterates $verdict.issues, compresses each to JSON,
    # joins with newline, then tests -match (regex, case-insensitive by default
    # in PS with [regex]::Escape wrapping the keyword — i.e. literal substring,
    # case-insensitive). We use awk's case-folded `index()` because MINGW/MSYS
    # grep has a known abort when `-i` is combined with `-F`; see
    # notes/grep-windows-iF-abort for the workaround rationale.
    issues_text=$(jq -r '(.issues // []) | map(tostring) | join("\n")' "$verdict_path")
    kw_count=$(jq -r 'length' <<<"$keywords_json")
    keyword_hit=true
    if (( kw_count > 0 )); then
      keyword_hit=false
      for ((ki = 0; ki < kw_count; ki++)); do
        kw=$(jq -r --argjson i "$ki" '.[$i]' <<<"$keywords_json")
        if [[ -z "$kw" ]]; then
          continue
        fi
        # awk tolower + index: fixed-string case-insensitive substring test.
        if awk -v text="$issues_text" -v kw="$kw" \
              'BEGIN { exit (index(tolower(text), tolower(kw)) > 0) ? 0 : 1 }'; then
          keyword_hit=true
          break
        fi
      done
    fi

    verdict_ok=$(jq -r --argjson av "$allow_verdict_json" --arg v "$actual_verdict" '$av | index($v) != null' <<<'null')

    if [[ "$must_catch" == "true" ]]; then
      if [[ "$actual_verdict" == "REVISE" && "$keyword_hit" == "true" ]]; then
        verify_accuracy="PASS"
      elif [[ "$actual_verdict" == "REVISE" ]]; then
        verify_accuracy="PARTIAL"
      else
        verify_accuracy="FAIL"
      fi
    else
      if [[ "$verdict_ok" == "true" ]]; then
        verify_accuracy="PASS"
      else
        verify_accuracy="FAIL"
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Dimension: Cross-AI diversity (port score-run.ps1:404-426, full impl)
# composer==reviewer -> N/A.
# Else: Levenshtein(compose.txt, bounce-01.txt). similarity = 1 - dist/max(len).
# change_ratio = 1 - similarity. >= min_edit -> PASS; >= min_edit*0.5 -> PARTIAL; else FAIL.
# Missing compose.txt or bounce-01.txt -> FAIL.
# ---------------------------------------------------------------------------

cross_ai_diversity="N/A"
cross_ai_reason=""
cross_ai_similarity=""
cross_ai_change_ratio=""
if [[ "$composer" != "$reviewer" ]]; then
  compose_file="$outputs_dir/compose.txt"
  # First bounce-*.txt file in sort order (PS Sort-Object Name | Select -First 1).
  first_bounce=""
  if [[ -d "$outputs_dir" ]]; then
    first_bounce=$(find "$outputs_dir" -maxdepth 1 -type f -name 'bounce-*.txt' 2>/dev/null | sort | head -1)
  fi
  min_edit=$(jq -r '.expectations.cross_ai_diversity.min_edit_distance // 0.15' <<<"$case_json")

  if [[ ! -f "$compose_file" || -z "$first_bounce" || ! -f "$first_bounce" ]]; then
    cross_ai_diversity="FAIL"
    cross_ai_reason="missing compose or first bounce output"
  else
    # Compute max length (BOM-stripped char count) matching the awk Levenshtein's
    # view of the files. wc -c counts bytes; for BOM-prefixed ASCII that's the
    # same as chars + 3. Subtract 3 if BOM detected. Cap at 4000.
    compose_bytes=$(wc -c < "$compose_file" | tr -d ' ')
    bounce_bytes=$(wc -c < "$first_bounce" | tr -d ' ')
    compose_has_bom=0; bounce_has_bom=0
    if [[ $(head -c 3 "$compose_file" 2>/dev/null | xxd -p 2>/dev/null) == "efbbbf" ]]; then
      compose_has_bom=1
    fi
    if [[ $(head -c 3 "$first_bounce" 2>/dev/null | xxd -p 2>/dev/null) == "efbbbf" ]]; then
      bounce_has_bom=1
    fi
    compose_len=$(( compose_bytes - (compose_has_bom * 3) ))
    bounce_len=$(( bounce_bytes - (bounce_has_bom * 3) ))
    (( compose_len < 0 )) && compose_len=0
    (( bounce_len < 0 )) && bounce_len=0
    (( compose_len > 4000 )) && compose_len=4000
    (( bounce_len > 4000 )) && bounce_len=4000
    max_len=$(( compose_len > bounce_len ? compose_len : bounce_len ))

    if (( max_len == 0 )); then
      # Both empty -> PS returns similarity=1.0 -> change_ratio=0.0 -> FAIL (below 0.075)
      cross_ai_similarity="1.0"
      cross_ai_change_ratio="0.0"
      cross_ai_diversity="FAIL"
    else
      edit_dist=$(levenshtein "$compose_file" "$first_bounce")
      cross_ai_similarity=$(jq -n --argjson d "$edit_dist" --argjson m "$max_len" '(1.0 - ($d / $m)) * 1000 | round / 1000')
      cross_ai_change_ratio=$(jq -n --argjson d "$edit_dist" --argjson m "$max_len" '($d / $m) * 1000 | round / 1000')
      cross_ai_diversity=$(jq -nr --argjson cr "$cross_ai_change_ratio" --argjson me "$min_edit" '
        if   $cr >= $me         then "PASS"
        elif $cr >= ($me * 0.5) then "PARTIAL"
        else                         "FAIL"
        end
      ')
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Scores object (fixed key order for determinism; jq -S re-sorts at final write)
# ---------------------------------------------------------------------------

scores_json=$(jq -n \
  --arg ca "$cross_ai_diversity" \
  --arg co "$convergence" \
  --arg pq "$plan_quality" \
  --arg ef "$execution_fidelity" \
  --arg va "$verify_accuracy" \
  --arg cs "$cost" \
  --arg rb "$robust" \
  '{cross_ai_diversity:$ca, convergence:$co, plan_quality:$pq, execution_fidelity:$ef, verify_accuracy:$va, cost:$cs, robustness:$rb}')

# ---------------------------------------------------------------------------
# Composite weighted mean (port score-run.ps1:428-446)
# Weights: robustness=2, all others=1. Values: PASS=1.0, PARTIAL=0.5, FAIL=0.0, N/A=excluded.
# Result rounded to 3 decimals via jq '*1000 | round / 1000'.
# ---------------------------------------------------------------------------

composite=$(jq -n --argjson scores "$scores_json" '
  {cross_ai_diversity:1, convergence:1, plan_quality:1, execution_fidelity:1, verify_accuracy:1, cost:1, robustness:2} as $W |
  {PASS:1.0, PARTIAL:0.5, FAIL:0.0, "N/A":null} as $V |
  ($scores | to_entries | map(
    ($W[.key]) as $w |
    ($V[.value]) as $v |
    if $v == null then null else {sum_w:$w, sum_s:($w * $v)} end
  ) | map(select(. != null))) as $rows |
  if ($rows | length) == 0 then 0
  else (($rows | map(.sum_s) | add) / ($rows | map(.sum_w) | add) * 1000 | round / 1000)
  end
')

# ---------------------------------------------------------------------------
# Details (sparse for Task 1; Task 2 expands per-dimension metadata)
# ---------------------------------------------------------------------------

# v1.5 Phase 4: token economics (informational only). When the runner ran with
# CO_EVOLVE_TOKEN_CAPTURE=1, state.json carries a .tokens.totals block; surface
# it under details.cost.tokens so the report can speak to the ~50% Claude-token
# savings claim. The `// empty` guard means: when there is no tokens block (every
# existing fixture, and any run with capture off), the key is simply absent and
# details stays byte-identical — this MUST NOT touch any PASS/FAIL dimension.
tokens_totals_json=$(jq -c '.tokens.totals // empty' "$state_json_path" 2>/dev/null)

details_json=$(jq -n \
  --arg status "$status" \
  --argjson had_exception "$had_exception" \
  --argjson wall_secs "$wall_secs" \
  --argjson max_wall "$max_wall" \
  --arg composer "$composer" \
  --arg reviewer "$reviewer" \
  --argjson tokens "${tokens_totals_json:-null}" \
  '{
    robustness: {status: $status, had_exception: $had_exception},
    cost: ({wall_clock_seconds: $wall_secs, max: $max_wall}
           + (if $tokens == null then {} else {tokens: $tokens} end)),
    cross_ai_diversity: {composer: $composer, reviewer: $reviewer}
  }')

scored_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build final JSON with fixed key order; jq -S sort keys for determinism.
jq -nS \
  --arg case_id "$case_id" \
  --arg title "$case_title" \
  --arg run_id "$run_id" \
  --argjson scores "$scores_json" \
  --argjson composite "$composite" \
  --argjson details "$details_json" \
  --arg scored_at "$scored_at" \
  '{case_id:$case_id, title:$title, run_id:$run_id, scores:$scores, composite:$composite, details:$details, scored_at:$scored_at}' \
  | atomic_json_write_stdin '.' "$OUTPUT_DIR/scores.json"

# Echo scores dict on stdout for CLI convenience (matches PS Write-Host line).
jq -S '.scores' "$OUTPUT_DIR/scores.json"
