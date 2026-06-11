#!/usr/bin/env bash
# evals/score-bounce.sh — deterministic bounce-quality scorer (v1.3 Phase 4).
#
# Scores a document-bounce run directory across the 4 automatable dimensions
# of evals/BOUNCE-RUBRIC.md and emits bounce-scores.json (+ the marker
# ledger). Reads state.json (bounce-state/1.0) when present; falls back to
# artifact parsing so historical (pre-v1.3) runs score on day one.
#
#   bash evals/score-bounce.sh --run-dir runs/co-evolve-foo-20260610-...
#   bash evals/score-bounce.sh --run-dir <dir> --output <file>
#
# Deterministic: same run dir -> byte-identical output modulo .scored_at.
# What it deliberately does NOT score: net quality lift (see the rubric).
# That is Layer 2's job (judge-bounce.sh) and Layer 3's (human sampling).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/co-evolution.sh"

require_mikefarah_yq
command -v jq >/dev/null 2>&1 || die "jq is required for score-bounce.sh"

RUN_DIR=""
OUTPUT_FILE=""
THRESHOLDS_FILE="$REPO_ROOT/evals/bounce-thresholds.yaml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)    RUN_DIR="${2:?--run-dir needs a value}"; shift 2 ;;
    --output)     OUTPUT_FILE="${2:?--output needs a value}"; shift 2 ;;
    --thresholds) THRESHOLDS_FILE="${2:?--thresholds needs a value}"; shift 2 ;;
    *) die "unknown flag: $1" ;;
  esac
done

[[ -n "$RUN_DIR" && -d "$RUN_DIR" ]] || die "--run-dir <existing dir> is required"
[[ -f "$THRESHOLDS_FILE" ]] || die "thresholds file not found: $THRESHOLDS_FILE"
[[ -z "$OUTPUT_FILE" ]] && OUTPUT_FILE="$RUN_DIR/bounce-scores.json"

T_JSON=$(yq -o=json '.' "$THRESHOLDS_FILE")
t() { printf '%s' "$T_JSON" | jq -r "$1"; }

# ---------------------------------------------------------------------------
# Run discovery: state.json first, artifact parsing as fallback.
# ---------------------------------------------------------------------------
STATE_FILE="$RUN_DIR/state.json"
SOURCE="artifacts"
MODE=""
BASELINE_REL=""
STATUS=""

if [[ -f "$STATE_FILE" ]] && jq -e '.schema == "bounce-state/1.0"' "$STATE_FILE" >/dev/null 2>&1; then
  SOURCE="state"
  MODE=$(jq -r '.mode' "$STATE_FILE")
  BASELINE_REL=$(jq -r '.baseline_file' "$STATE_FILE")
  STATUS=$(jq -r '.status' "$STATE_FILE")
else
  # Legacy run: infer mode from run.log, baseline from the artifact set.
  if [[ -f "$RUN_DIR/run.log" ]] && grep -q 'AGENT BOUNCER' "$RUN_DIR/run.log"; then
    MODE="agent-bouncer"
  elif [[ -f "$RUN_DIR/run.log" ]] && grep -q 'bounce-only' "$RUN_DIR/run.log"; then
    MODE="bounce-only"
  elif [[ -f "$RUN_DIR/run.log" ]] && grep -qiE 'chain' "$RUN_DIR/run.log"; then
    MODE="chain"
  elif [[ -f "$RUN_DIR/compose-output.md" ]]; then
    MODE="compose"
  else
    MODE="bounce-only"
  fi
  if [[ "$MODE" == "compose" && -f "$RUN_DIR/compose-output.md" ]]; then
    BASELINE_REL="compose-output.md"
  elif [[ -f "$RUN_DIR/original-input.md" ]]; then
    BASELINE_REL="original-input.md"
  elif [[ -f "$RUN_DIR/original.md" ]]; then
    BASELINE_REL="original.md"
  fi
  STATUS="unknown"
fi

BASELINE="$RUN_DIR/$BASELINE_REL"
[[ -f "$BASELINE" ]] || die "baseline artifact missing: $BASELINE"

# Final document: working.md, else the newest top-level .md that is not a
# pass/baseline artifact.
FINAL="$RUN_DIR/working.md"
if [[ ! -f "$FINAL" ]]; then
  FINAL=""
  for f in "$RUN_DIR"/*.md; do
    base=$(basename "$f")
    case "$base" in
      original*.md|compose-output.md|pass-*-clean.md|pass-*raw.md) continue ;;
      *) FINAL="$f" ;;
    esac
  done
fi
[[ -n "$FINAL" && -f "$FINAL" ]] || die "final document not found in $RUN_DIR"

# Ordered clean-pass files: plain contract name first, dotted legacy second.
PASS_FILES=()
i=1
while :; do
  if [[ -f "$RUN_DIR/pass-${i}-clean.md" ]]; then
    PASS_FILES+=("$RUN_DIR/pass-${i}-clean.md")
  elif [[ -f "$RUN_DIR/.bounce-pass-${i}-clean.md" ]]; then
    PASS_FILES+=("$RUN_DIR/.bounce-pass-${i}-clean.md")
  else
    break
  fi
  i=$((i + 1))
done
PASS_COUNT=${#PASS_FILES[@]}

# ---------------------------------------------------------------------------
# Text feature extractors (awk; all code-fence-aware where it matters)
# ---------------------------------------------------------------------------

# Headings (H1-H4): normalized "level|text" lines.
extract_headings() {
  awk '
    /^```/ { in_fence = !in_fence; next }
    !in_fence && /^#{1,4}[ \t]/ {
      level = 0
      while (substr($0, level + 1, 1) == "#") level++
      text = substr($0, level + 1)
      gsub(/^[ \t]+|[ \t\r]+$/, "", text)
      lower = tolower(text)
      gsub(/[^a-z0-9 ]/, "", lower)
      gsub(/  +/, " ", lower)
      if (length(lower) > 0) printf "%d|%s\n", level, lower
    }
  ' "$1"
}

# Anchors: numbers(+units), comparison operators, `code` tokens, "quoted
# terms", requirement modals. One anchor per line, normalized.
extract_anchors() {
  awk '
    /^```/ { in_fence = !in_fence; next }
    in_fence { next }
    {
      line = $0
      # `code` tokens
      tmp = line
      while (match(tmp, /`[^`]+`/)) {
        tok = substr(tmp, RSTART + 1, RLENGTH - 2)
        gsub(/[ \t\r]+$/, "", tok)
        if (length(tok) > 0 && length(tok) <= 60) printf "code|%s\n", tok
        tmp = substr(tmp, RSTART + RLENGTH)
      }
      # "quoted terms"
      tmp = line
      while (match(tmp, /"[^"]+"/)) {
        tok = substr(tmp, RSTART + 1, RLENGTH - 2)
        if (length(tok) > 0 && length(tok) <= 60) printf "quote|%s\n", tolower(tok)
        tmp = substr(tmp, RSTART + RLENGTH)
      }
      # numbers with optional unit suffix (5, 2.5, 90%, 10ms, 500K)
      tmp = line
      while (match(tmp, /[0-9]+(\.[0-9]+)?[a-zA-Z%]{0,8}/)) {
        tok = substr(tmp, RSTART, RLENGTH)
        printf "num|%s\n", tolower(tok)
        tmp = substr(tmp, RSTART + RLENGTH)
      }
      # comparison operators
      tmp = line
      while (match(tmp, /(>=|<=|==|!=)/)) {
        printf "op|%s\n", substr(tmp, RSTART, RLENGTH)
        tmp = substr(tmp, RSTART + RLENGTH)
      }
      # requirement modals
      lower = tolower(line)
      n = split(lower, words, /[^a-z]+/)
      for (w = 1; w <= n; w++) {
        if (words[w] == "must" || words[w] == "shall" || words[w] == "never" || words[w] == "always") {
          printf "modal|%s\n", words[w]
        }
      }
    }
  ' "$1"
}

# Markers with nearest-heading + normalized-text fingerprint.
# Output: type|heading_norm|text_norm
extract_markers() {
  awk '
    /^```/ { in_fence = !in_fence; next }
    in_fence { next }
    /^#{1,4}[ \t]/ {
      h = $0
      gsub(/^#+[ \t]+/, "", h)
      gsub(/[ \t\r]+$/, "", h)
      h = tolower(h)
      gsub(/[^a-z0-9 ]/, "", h)
      gsub(/  +/, " ", h)
      heading = h
    }
    {
      line = $0
      gsub(/`[^`]*`/, "", line)
      for (type_i = 1; type_i <= 2; type_i++) {
        marker = (type_i == 1) ? "[CONTESTED]" : "[CLARIFY]"
        type = (type_i == 1) ? "contested" : "clarify"
        idx = index(line, marker)
        if (idx > 0) {
          text = substr(line, idx + length(marker))
          text = tolower(text)
          gsub(/[^a-z0-9 ]/, "", text)
          gsub(/  +/, " ", text)
          gsub(/^ +| +$/, "", text)
          text = substr(text, 1, 80)
          printf "%s|%s|%s\n", type, (heading == "" ? "(no heading)" : heading), text
        }
      }
    }
  ' "$1"
}

count_words() { wc -w < "$1" | tr -d '\r\n '; }

# Multiset retention: fraction of lines in $1 also present in $2 (min-count).
retention_fraction() {
  local base_list="$1" final_list="$2"
  awk '
    NR == FNR { base[$0]++; total++; next }
    { if (base[$0] > 0) { base[$0]--; kept++ } }
    END {
      if (total == 0) { print "1.000"; exit }
      printf "%.3f", kept / total
    }
  ' "$base_list" "$final_list"
}

# Multiset Dice edit ratio between two token bags: 1 - 2*common/(a+b).
edit_ratio() {
  local a="$1" b="$2"
  awk '
    function tokenize(line,   n, parts, k) {
      n = split(tolower(line), parts, /[^a-z0-9]+/)
      for (k = 1; k <= n; k++) if (parts[k] != "") {
        if (FILENUM == 1) { abag[parts[k]]++; atot++ } else { bbag[parts[k]]++; btot++ }
      }
    }
    FNR == 1 { FILENUM++ }
    { tokenize($0) }
    END {
      common = 0
      for (tok in abag) {
        c = abag[tok] < bbag[tok] ? abag[tok] : bbag[tok]
        common += c
      }
      if (atot + btot == 0) { print "0.000"; exit }
      printf "%.3f", 1 - (2 * common) / (atot + btot)
    }
  ' "$a" "$b"
}

# ---------------------------------------------------------------------------
# Working scratch
# ---------------------------------------------------------------------------
WORK=$(mktemp -d -t score-bounce-XXXXXX)
trap 'rm -rf "$WORK"' EXIT

extract_headings "$BASELINE" | sort > "$WORK/base-headings"
extract_headings "$FINAL"    | sort > "$WORK/final-headings"
extract_anchors  "$BASELINE" | sort > "$WORK/base-anchors"
extract_anchors  "$FINAL"    | sort > "$WORK/final-anchors"

# ---------------------------------------------------------------------------
# Marker ledger
# ---------------------------------------------------------------------------
# Track each marker fingerprint across baseline + passes; classify its fate.
extract_markers "$BASELINE" | sort -u > "$WORK/markers-p0"
p=1
for pf in ${PASS_FILES[@]+"${PASS_FILES[@]}"}; do
  extract_markers "$pf" | sort -u > "$WORK/markers-p$p"
  extract_headings "$pf" | cut -d'|' -f2 | sort -u > "$WORK/headings-p$p"
  p=$((p + 1))
done
extract_markers "$FINAL" | sort -u > "$WORK/markers-final"

cat "$WORK"/markers-p* 2>/dev/null | sort -u > "$WORK/all-markers"

LEDGER="[]"
while IFS='|' read -r mtype mheading mtext; do
  [[ -z "$mtype" ]] && continue
  fp="${mtype}|${mheading}|${mtext}"
  first_pass=-1
  last_pass=-1
  for (( q=0; q<=PASS_COUNT; q++ )); do
    if grep -qxF "$fp" "$WORK/markers-p$q" 2>/dev/null; then
      (( first_pass < 0 )) && first_pass=$q
      last_pass=$q
    fi
  done
  fate="resolved"
  if grep -qxF "$fp" "$WORK/markers-final"; then
    fate="unresolved"
  else
    gone_at=$((last_pass + 1))
    heading_survives=true
    if [[ "$mheading" != "(no heading)" ]]; then
      if (( gone_at <= PASS_COUNT )); then
        grep -qxF "$mheading" "$WORK/headings-p$gone_at" 2>/dev/null || heading_survives=false
      else
        extract_headings "$FINAL" | cut -d'|' -f2 | sort -u | grep -qxF "$mheading" || heading_survives=false
      fi
    fi
    if [[ "$heading_survives" == false ]]; then
      fate="deleted-with-section"
    elif (( last_pass - first_pass >= 2 )); then
      fate="expired"
    else
      fate="resolved"
    fi
  fi
  carried=$(( last_pass - first_pass ))
  LEDGER=$(printf '%s' "$LEDGER" | jq \
    --arg type "$mtype" --arg heading "$mheading" --arg text "$mtext" \
    --argjson first "$first_pass" --argjson last "$last_pass" \
    --argjson carried "$carried" --arg fate "$fate" \
    '. += [{type: $type, heading: $heading, text: $text,
            first_pass: $first, last_pass: $last,
            passes_carried: $carried, fate: $fate}]')
done < "$WORK/all-markers"

DELETED_WITH_SECTION=$(printf '%s' "$LEDGER" | jq '[.[] | select(.fate == "deleted-with-section")] | length')
UNRESOLVED=$(printf '%s' "$LEDGER" | jq '[.[] | select(.fate == "unresolved")] | length')

# ---------------------------------------------------------------------------
# Dimension 1: loop execution + marker receipts
# ---------------------------------------------------------------------------
EXPECTED_PASSES=$(t ".loop_execution.expected_passes[\"$MODE\"] // 2")
FINAL_MARKERS=$(( $(count_markers "$FINAL" "[CONTESTED]") + $(count_markers "$FINAL" "[CLARIFY]") ))
FINAL_MARKERS_MAX=$(t '.loop_execution.final_markers_max')

D1_CHECKS="[]"
d1_add() { D1_CHECKS=$(printf '%s' "$D1_CHECKS" | jq --arg n "$1" --argjson ok "$2" --arg d "$3" '. += [{name: $n, ok: $ok, detail: $d}]'); }

if [[ "$STATUS" == "aborted" ]]; then
  d1_add "run_not_aborted" false "state.json status=aborted — no quality verdict possible"
else
  d1_add "run_not_aborted" true "status=$STATUS"
fi

if (( PASS_COUNT >= EXPECTED_PASSES )); then
  d1_add "expected_passes" true "$PASS_COUNT/$EXPECTED_PASSES passes present"
else
  d1_add "expected_passes" false "only $PASS_COUNT of $EXPECTED_PASSES expected passes have clean artifacts"
fi

empty_pass=""
p=1
for pf in ${PASS_FILES[@]+"${PASS_FILES[@]}"}; do
  [[ -s "$pf" ]] || empty_pass="$p"
  p=$((p + 1))
done
if [[ -z "$empty_pass" ]]; then
  d1_add "no_empty_pass" true "all clean passes non-empty"
else
  d1_add "no_empty_pass" false "pass $empty_pass clean artifact is empty"
fi

if (( FINAL_MARKERS <= FINAL_MARKERS_MAX )); then
  d1_add "final_markers" true "$FINAL_MARKERS live markers in final"
else
  d1_add "final_markers" false "$FINAL_MARKERS live markers remain in final (max $FINAL_MARKERS_MAX)"
fi

BASE_MARKERS=$(( $(count_markers "$BASELINE" "[CONTESTED]") + $(count_markers "$BASELINE" "[CLARIFY]") ))
if (( BASE_MARKERS == 0 && PASS_COUNT > 0 )); then
  ratio=$(edit_ratio "$BASELINE" "$FINAL")
  changed=$(awk -v r="$ratio" 'BEGIN { print (r > 0.001) ? "true" : "false" }')
  d1_add "zero_marker_input_changed" "$changed" "zero-marker input; baseline->final edit ratio $ratio"
fi

if (( DELETED_WITH_SECTION == 0 )); then
  d1_add "no_deletion_convergence" true "no marker vanished together with its section"
else
  d1_add "no_deletion_convergence" false "$DELETED_WITH_SECTION marker(s) resolved by deleting their section"
fi

D1_PASS=$(printf '%s' "$D1_CHECKS" | jq 'all(.[]; .ok)')

# ---------------------------------------------------------------------------
# Dimension 2: structural + anchor preservation
# ---------------------------------------------------------------------------
H23_BASE="$WORK/base-h23"
H23_FINAL="$WORK/final-h23"
grep -E '^(2|3)\|' "$WORK/base-headings"  > "$H23_BASE"  || true
grep -E '^(2|3)\|' "$WORK/final-headings" > "$H23_FINAL" || true
HEADING_RETENTION=$(retention_fraction "$H23_BASE" "$H23_FINAL")

# Marker-adjacent headings: every heading that ever hosted a marker must be
# in the final document.
printf '%s' "$LEDGER" | jq -r '.[].heading' | grep -vxF '(no heading)' | sort -u > "$WORK/marker-headings" || true
extract_headings "$FINAL" | cut -d'|' -f2 | sort -u > "$WORK/final-heading-texts"
MARKER_HEADING_RETENTION=$(retention_fraction "$WORK/marker-headings" "$WORK/final-heading-texts")

ANCHOR_RETENTION=$(retention_fraction "$WORK/base-anchors" "$WORK/final-anchors")

D2_CHECKS="[]"
d2_add() { D2_CHECKS=$(printf '%s' "$D2_CHECKS" | jq --arg n "$1" --argjson ok "$2" --arg d "$3" '. += [{name: $n, ok: $ok, detail: $d}]'); }

hr_min=$(t '.structural_preservation.heading_retention_min')
mh_min=$(t '.structural_preservation.marker_heading_retention_min')
an_min=$(t '.structural_preservation.anchor_retention_min')

d2_add "heading_retention" "$(awk -v v="$HEADING_RETENTION" -v m="$hr_min" 'BEGIN { print (v >= m) ? "true" : "false" }')" "H2/H3 retention $HEADING_RETENTION (min $hr_min)"
d2_add "marker_heading_retention" "$(awk -v v="$MARKER_HEADING_RETENTION" -v m="$mh_min" 'BEGIN { print (v >= m) ? "true" : "false" }')" "marker-hosting heading retention $MARKER_HEADING_RETENTION (min $mh_min)"
d2_add "anchor_retention" "$(awk -v v="$ANCHOR_RETENTION" -v m="$an_min" 'BEGIN { print (v >= m) ? "true" : "false" }')" "anchor retention $ANCHOR_RETENTION (min $an_min)"

D2_PASS=$(printf '%s' "$D2_CHECKS" | jq 'all(.[]; .ok)')

# ---------------------------------------------------------------------------
# Dimension 3: scope discipline
# ---------------------------------------------------------------------------
BASE_WORDS=$(count_words "$BASELINE")
FINAL_WORDS=$(count_words "$FINAL")
BASE_HEADING_COUNT=$(wc -l < "$WORK/base-headings" | tr -d ' ')
FINAL_HEADING_COUNT=$(wc -l < "$WORK/final-headings" | tr -d ' ')

WORD_RATIO=$(awk -v a="$FINAL_WORDS" -v b="$BASE_WORDS" 'BEGIN { printf "%.3f", (b == 0) ? 1 : a / b }')
HEADING_RATIO=$(awk -v a="$FINAL_HEADING_COUNT" -v b="$BASE_HEADING_COUNT" 'BEGIN { printf "%.3f", (b == 0) ? 1 : a / b }')

wr_min=$(t ".scope_discipline[\"$MODE\"].word_ratio_min // 0.55")
wr_max=$(t ".scope_discipline[\"$MODE\"].word_ratio_max // 1.15")
hr2_min=$(t ".scope_discipline[\"$MODE\"].heading_ratio_min // 0.75")
hr2_max=$(t ".scope_discipline[\"$MODE\"].heading_ratio_max // 1.25")

D3_CHECKS="[]"
d3_add() { D3_CHECKS=$(printf '%s' "$D3_CHECKS" | jq --arg n "$1" --argjson ok "$2" --arg d "$3" '. += [{name: $n, ok: $ok, detail: $d}]'); }

d3_add "word_ratio" "$(awk -v v="$WORD_RATIO" -v lo="$wr_min" -v hi="$wr_max" 'BEGIN { print (v >= lo && v <= hi) ? "true" : "false" }')" "word ratio $WORD_RATIO (band $wr_min-$wr_max, mode $MODE)"
d3_add "heading_ratio" "$(awk -v v="$HEADING_RATIO" -v lo="$hr2_min" -v hi="$hr2_max" 'BEGIN { print (v >= lo && v <= hi) ? "true" : "false" }')" "heading ratio $HEADING_RATIO (band $hr2_min-$hr2_max)"

D3_PASS=$(printf '%s' "$D3_CHECKS" | jq 'all(.[]; .ok)')

# ---------------------------------------------------------------------------
# Dimension 4: material engagement without churn
# ---------------------------------------------------------------------------
MIN_EDIT_RATIO=$(t '.material_engagement.min_edit_ratio')
MIN_EDIT_TOKENS=$(t '.material_engagement.min_edit_tokens')
MAX_REPLACEMENT=$(t '.material_engagement.max_replacement_ratio')

PASS_RATIOS="[]"
prev="$BASELINE"
max_ratio="0.000"
any_material=false
churn=false
p=1
for pf in ${PASS_FILES[@]+"${PASS_FILES[@]}"}; do
  r=$(edit_ratio "$prev" "$pf")
  prev_words=$(count_words "$prev")
  changed_tokens=$(awk -v r="$r" -v w="$prev_words" 'BEGIN { printf "%d", r * w }')
  PASS_RATIOS=$(printf '%s' "$PASS_RATIOS" | jq --argjson p "$p" --arg r "$r" --argjson tok "$changed_tokens" '. += [{pass: $p, edit_ratio: ($r | tonumber), changed_tokens: $tok}]')
  if awk -v r="$r" -v m="$MIN_EDIT_RATIO" 'BEGIN { exit !(r >= m) }' || (( changed_tokens >= MIN_EDIT_TOKENS )); then
    any_material=true
  fi
  if awk -v r="$r" -v m="$MAX_REPLACEMENT" 'BEGIN { exit !(r > m) }' && [[ "$D2_PASS" != "true" ]]; then
    churn=true
  fi
  if awk -v r="$r" -v m="$max_ratio" 'BEGIN { exit !(r > m) }'; then max_ratio="$r"; fi
  prev="$pf"
  p=$((p + 1))
done

D4_CHECKS="[]"
d4_add() { D4_CHECKS=$(printf '%s' "$D4_CHECKS" | jq --arg n "$1" --argjson ok "$2" --arg d "$3" '. += [{name: $n, ok: $ok, detail: $d}]'); }

if (( PASS_COUNT == 0 )); then
  d4_add "material_edit" false "no pass artifacts to measure"
else
  d4_add "material_edit" "$any_material" "max per-pass edit ratio $max_ratio (need >=$MIN_EDIT_RATIO or >=$MIN_EDIT_TOKENS tokens in some pass)"
  if [[ "$churn" == true ]]; then
    d4_add "no_destructive_churn" false "a pass replaced >$MAX_REPLACEMENT of tokens while structural preservation FAILED"
  else
    d4_add "no_destructive_churn" true "no high-replacement pass without preserved structure"
  fi
fi

D4_PASS=$(printf '%s' "$D4_CHECKS" | jq 'all(.[]; .ok)')

# ---------------------------------------------------------------------------
# Assemble output
# ---------------------------------------------------------------------------
OVERALL=$(jq -n --argjson a "$D1_PASS" --argjson b "$D2_PASS" --argjson c "$D3_PASS" --argjson d "$D4_PASS" '($a and $b and $c and $d)')

jq -S -n \
  --arg schema "bounce-scores/1.0" \
  --arg scored_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg run_dir "$(basename "$RUN_DIR")" \
  --arg mode "$MODE" \
  --arg source "$SOURCE" \
  --arg status "$STATUS" \
  --argjson pass_count "$PASS_COUNT" \
  --argjson d1 "{\"pass\": $D1_PASS, \"checks\": $D1_CHECKS}" \
  --argjson d2 "{\"pass\": $D2_PASS, \"checks\": $D2_CHECKS, \"heading_retention\": $HEADING_RETENTION, \"marker_heading_retention\": $MARKER_HEADING_RETENTION, \"anchor_retention\": $ANCHOR_RETENTION}" \
  --argjson d3 "{\"pass\": $D3_PASS, \"checks\": $D3_CHECKS, \"word_ratio\": $WORD_RATIO, \"heading_ratio\": $HEADING_RATIO}" \
  --argjson d4 "{\"pass\": $D4_PASS, \"checks\": $D4_CHECKS, \"pass_edit_ratios\": $PASS_RATIOS}" \
  --argjson ledger "$LEDGER" \
  --argjson overall "$OVERALL" \
  '{
    schema: $schema,
    scored_at: $scored_at,
    run_dir: $run_dir,
    mode: $mode,
    source: $source,
    run_status: $status,
    pass_count: $pass_count,
    dimensions: {
      loop_execution: $d1,
      structural_preservation: $d2,
      scope_discipline: $d3,
      material_engagement: $d4
    },
    marker_ledger: ($ledger | sort_by(.type, .heading, .text)),
    overall_pass: $overall
  }' > "$OUTPUT_FILE"

if [[ "$OVERALL" == "true" ]]; then
  printf 'PASS %s (mode=%s, passes=%s, source=%s)\n' "$(basename "$RUN_DIR")" "$MODE" "$PASS_COUNT" "$SOURCE"
else
  printf 'FAIL %s (mode=%s, passes=%s, source=%s) — see %s\n' "$(basename "$RUN_DIR")" "$MODE" "$PASS_COUNT" "$SOURCE" "$OUTPUT_FILE"
  exit 1
fi
