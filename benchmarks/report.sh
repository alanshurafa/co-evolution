#!/usr/bin/env bash

# benchmarks/report.sh — aggregate a judged batch into REPORT.md
# (plan section "Report").
#
#   bash benchmarks/report.sh --batch-dir benchmarks/results/b1 [--out FILE]
#                             [--judges fable,codex,glm] [--primary-judge fable]
#                             [--corpus benchmarks/corpus] [--no-copy]
#
# Section order is the plan's, and it is deliberate: the PRE-REGISTERED
# outcomes come first, everything else is labeled secondary or exploratory, and
# missing data is surfaced above the results rather than buried under them.
#
# Reads only `bench-pair/1.0` verdict files written by judge-matrix.sh and the
# `bench-cell/1.0` meta.json files written by run-benchmark.sh. It never calls a
# model and never mutates the batch.
#
# Verdict accounting, applied identically to every judge (PREREGISTRATION.md §4):
#   x / y              -> one win for that condition
#   tie                -> half a win each
#   position_biased    -> half a win each (the swap disagreed: no quality claim)
#   invalid-evidence   -> EXCLUDED from win counts (majority of quotes fabricated)
#   sanitize-leak      -> EXCLUDED from win counts (never judged)
#
# Output: <batch>/REPORT.md (or --out) plus a copy at benchmarks/reports/<batch>.md.
# Exit: 0 report written, 1 hard error (missing batch dir, no verdicts at all).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/co-evolution.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/benchmark-lib.sh"

command -v jq >/dev/null 2>&1 || die "jq is required for report.sh"

BATCH_DIR=""
OUT_FILE=""
JUDGES_CSV="fable,codex,glm"
PRIMARY_JUDGE="fable"
CORPUS_DIR="$SCRIPT_DIR/corpus"
COPY_TO_REPORTS=true

# Sign-test thresholds, frozen in benchmarks/PREREGISTRATION.md §1 for N=8.
PREREG_N=8
PREREG_HELPS=7
PREREG_DIRECTIONAL=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --batch-dir)     BATCH_DIR="${2:?--batch-dir needs a value}"; shift 2 ;;
    --out)           OUT_FILE="${2:?--out needs a value}"; shift 2 ;;
    --judges)        JUDGES_CSV="${2:?--judges needs a value}"; shift 2 ;;
    --primary-judge) PRIMARY_JUDGE="${2:?--primary-judge needs a value}"; shift 2 ;;
    --corpus)        CORPUS_DIR="${2:?--corpus needs a value}"; shift 2 ;;
    --no-copy)       COPY_TO_REPORTS=false; shift ;;
    -h|--help)       sed -n '3,30p' "$0"; exit 0 ;;
    *) die "unknown flag: $1" ;;
  esac
done

[[ -n "$BATCH_DIR" && -d "$BATCH_DIR" ]] || die "--batch-dir <existing dir> is required"
BATCH_DIR="$(cd "$BATCH_DIR" && pwd)"
BATCH_ID="$(basename "$BATCH_DIR")"
[[ -n "$OUT_FILE" ]] || OUT_FILE="$BATCH_DIR/REPORT.md"

WORK=$(mktemp -d -t bench-report-XXXXXX) || die "could not create a work dir"
trap 'rm -rf -- "$WORK"' EXIT

JUDGES=()
while IFS= read -r seat; do [[ -n "$seat" ]] && JUDGES+=("$seat"); done \
  < <(printf '%s\n' "$JUDGES_CSV" | tr ',' '\n' | tr -d '\r' | sed 's/^ *//; s/ *$//')
(( ${#JUDGES[@]} > 0 )) || die "--judges resolved to an empty list"

# --- Collection ---------------------------------------------------------------

list_subdirs() {
  local dir="$1" exclude="${2:-}" path base
  [[ -d "$dir" ]] || return 0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    base="$(basename "$path")"
    [[ -n "$exclude" && "$base" == "$exclude" ]] && continue
    printf '%s\n' "$base"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort)
}

TASKS=()
while IFS= read -r t; do TASKS+=("$t"); done < <(list_subdirs "$BATCH_DIR" judging)
(( ${#TASKS[@]} > 0 )) || die "no task directories under $BATCH_DIR"

# rows.tsv per judge: task \t x \t y \t verdict \t words_x \t words_y
#
# `tr -d '\r'` is not cosmetic: jq.exe under Git Bash emits CRLF, which would
# leave the last TSV field carrying a trailing CR for every awk pass below.
collect_rows() {
  local seat="$1" out="$2" task dir f
  : > "$out"
  for task in "${TASKS[@]}"; do
    dir="$BATCH_DIR/$task/judging/$seat"
    [[ -d "$dir" ]] || continue
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      jq -r 'select(.schema == "bench-pair/1.0")
             | [.task_id, .cond_x, .cond_y, .verdict,
                (.doc_words.x // 0), (.doc_words.y // 0)] | @tsv' "$f" 2>/dev/null \
        | tr -d '\r' >> "$out" || true
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -name '*.json' -type f 2>/dev/null | LC_ALL=C sort)
  done
}

ACTIVE_JUDGES=()
TOTAL_ROWS=0
for seat in "${JUDGES[@]}"; do
  collect_rows "$seat" "$WORK/rows-$seat.tsv"
  n=$(wc -l < "$WORK/rows-$seat.tsv" | tr -d '[:space:]')
  TOTAL_ROWS=$((TOTAL_ROWS + n))
  (( n > 0 )) && ACTIVE_JUDGES+=("$seat")
done
(( TOTAL_ROWS > 0 )) || die "no bench-pair/1.0 verdict files found under $BATCH_DIR — run benchmarks/judge-matrix.sh first"

# Conditions actually present in the batch tree (not in the verdicts — a
# condition that generated but never got judged must still show up as missing).
CONDS=()
for task in "${TASKS[@]}"; do
  while IFS= read -r c; do
    for seen in ${CONDS[@]+"${CONDS[@]}"}; do [[ "$seen" == "$c" ]] && continue 2; done
    CONDS+=("$c")
  done < <(list_subdirs "$BATCH_DIR/$task" judging)
done
mapfile -t CONDS < <(printf '%s\n' ${CONDS[@]+"${CONDS[@]}"} | LC_ALL=C sort -u | sed '/^$/d')

# --- Verdict lookup -----------------------------------------------------------

# pair_verdict SEAT TASK P Q → the verdict oriented so that P is the first
# named condition: prints "P" when P won, "Q" when Q won, or the raw
# non-decisive verdict (tie / position_biased / invalid-evidence /
# sanitize-leak), or "missing".
pair_verdict() {
  local seat="$1" task="$2" p="$3" q="$4" x y v
  local row
  row=$(awk -F'\t' -v t="$task" -v a="$p" -v b="$q" \
    '$1 == t && (($2 == a && $3 == b) || ($2 == b && $3 == a)) { print; exit }' \
    "$WORK/rows-$seat.tsv")
  [[ -n "$row" ]] || { printf 'missing'; return 0; }
  x=$(printf '%s' "$row" | cut -f2)
  y=$(printf '%s' "$row" | cut -f3)
  v=$(printf '%s' "$row" | cut -f4)
  case "$v" in
    x) printf '%s' "$x" ;;
    y) printf '%s' "$y" ;;
    *) printf '%s' "$v" ;;
  esac
}

# comparison_counts SEAT P Q → "pwins qwins nondecisive missing n_tasks"
comparison_counts() {
  local seat="$1" p="$2" q="$3"
  local pw=0 qw=0 nd=0 ms=0 task v
  for task in "${TASKS[@]}"; do
    v="$(pair_verdict "$seat" "$task" "$p" "$q")"
    case "$v" in
      "$p")    pw=$((pw + 1)) ;;
      "$q")    qw=$((qw + 1)) ;;
      missing) ms=$((ms + 1)) ;;
      *)       nd=$((nd + 1)) ;;
    esac
  done
  printf '%s %s %s %s %s' "$pw" "$qw" "$nd" "$ms" "${#TASKS[@]}"
}

# --- Bradley-Terry + win matrix ----------------------------------------------
# MM fixed point, 20 iterations (plan: "awk fixed-point ~20 iterations, ties =
# half-win"). Secondary metric only: N=8 tasks gives no meaningful confidence
# intervals, and none are computed or implied.
matrix_and_bt() { # $1 = rows.tsv
  awk -F'\t' '
    function add(a, b, wa, wb) {
      W[a SUBSEP b] += wa; W[b SUBSEP a] += wb
      N[a SUBSEP b] += 1;  N[b SUBSEP a] += 1
      TW[a] += wa; TW[b] += wb
      seen[a] = 1; seen[b] = 1
    }
    {
      x = $2; y = $3; v = $4
      if (v == "x")                                add(x, y, 1, 0)
      else if (v == "y")                           add(x, y, 0, 1)
      else if (v == "tie" || v == "position_biased") add(x, y, 0.5, 0.5)
      else { seen[x] = 1; seen[y] = 1 }   # invalid-evidence / sanitize-leak
    }
    END {
      n = 0
      for (c in seen) ids[++n] = c
      for (i = 1; i < n; i++)
        for (j = i + 1; j <= n; j++)
          if (ids[i] > ids[j]) { tmp = ids[i]; ids[i] = ids[j]; ids[j] = tmp }

      for (i = 1; i <= n; i++)
        for (j = 1; j <= n; j++)
          if (i != j)
            printf "MATRIX\t%s\t%s\t%.1f\t%d\n", ids[i], ids[j], W[ids[i] SUBSEP ids[j]] + 0, N[ids[i] SUBSEP ids[j]] + 0

      for (i = 1; i <= n; i++) p[ids[i]] = 1.0
      for (it = 0; it < 20; it++) {
        total = 0
        for (i = 1; i <= n; i++) {
          a = ids[i]; den = 0
          for (j = 1; j <= n; j++) {
            b = ids[j]
            if (a == b) continue
            if (N[a SUBSEP b] > 0 && (p[a] + p[b]) > 0)
              den += N[a SUBSEP b] / (p[a] + p[b])
          }
          np[a] = (den > 0) ? (TW[a] + 0) / den : 0
          total += np[a]
        }
        if (total <= 0) break
        for (i = 1; i <= n; i++) p[ids[i]] = np[ids[i]] / total
      }
      for (i = 1; i <= n; i++) printf "BT\t%s\t%.4f\t%.1f\n", ids[i], p[ids[i]], TW[ids[i]] + 0
    }
  ' "$1"
}

# --- Integrity / length / words ----------------------------------------------

integrity_counts() { # $1 = rows.tsv → "total decisive tie posbias invalid leak"
  awk -F'\t' '
    { t++
      if ($4 == "x" || $4 == "y") d++
      else if ($4 == "tie") ti++
      else if ($4 == "position_biased") pb++
      else if ($4 == "invalid-evidence") iv++
      else if ($4 == "sanitize-leak") lk++
    }
    END { printf "%d %d %d %d %d %d", t+0, d+0, ti+0, pb+0, iv+0, lk+0 }
  ' "$1"
}

length_bias() { # $1 = rows.tsv → "longer_wins comparable_pairs"
  awk -F'\t' '
    ($4 == "x" || $4 == "y") && ($5 + 0) > 0 && ($6 + 0) > 0 && ($5 + 0) != ($6 + 0) {
      n++
      if (($4 == "x" && ($5 + 0) > ($6 + 0)) || ($4 == "y" && ($6 + 0) > ($5 + 0))) w++
    }
    END { printf "%d %d", w+0, n+0 }
  ' "$1"
}

condition_words() { # all rows across judges → "cond mean_words n"
  cat "$WORK"/rows-*.tsv 2>/dev/null | awk -F'\t' '
    { if (($5 + 0) > 0) words[$1 SUBSEP $2] = $5 + 0
      if (($6 + 0) > 0) words[$1 SUBSEP $3] = $6 + 0 }
    END {
      for (k in words) { split(k, parts, SUBSEP); sum[parts[2]] += words[k]; cnt[parts[2]]++ }
      n = 0
      for (c in sum) ids[++n] = c
      for (i = 1; i < n; i++) for (j = i + 1; j <= n; j++)
        if (ids[i] > ids[j]) { tmp = ids[i]; ids[i] = ids[j]; ids[j] = tmp }
      for (i = 1; i <= n; i++)
        printf "%s %d %d\n", ids[i], sum[ids[i]] / cnt[ids[i]], cnt[ids[i]]
    }'
}

pct() { # $1 = numerator, $2 = denominator
  awk -v a="$1" -v b="$2" 'BEGIN { if (b + 0 == 0) print "n/a"; else printf "%.0f%%", 100 * a / b }'
}

ratio() { # $1 = numerator, $2 = denominator
  awk -v a="$1" -v b="$2" 'BEGIN { if (b + 0 == 0) print "n/a"; else printf "%.2f", a / b }'
}

# meta_num META JQ_PATH → an integer, 0 for anything unreadable. Keeps the
# arithmetic below from blowing up on a malformed or partial meta.json.
meta_num() {
  local v
  v=$(jq -r "${2} // 0 | floor" "$1" 2>/dev/null | tr -d '\r') || v=0
  [[ "$v" =~ ^-?[0-9]+$ ]] || v=0
  printf '%s' "$v"
}

task_difficulty() {
  local task="$1" f="$CORPUS_DIR/$1.md"
  [[ -f "$f" ]] || { printf 'unknown'; return 0; }
  command -v yq >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  yq --version 2>&1 | grep -qi mikefarah || { printf 'unknown'; return 0; }
  local d; d=$(bench_fm_get "$f" difficulty 2>/dev/null) || d=""
  printf '%s' "${d:-unknown}"
}

# --- Report body --------------------------------------------------------------

mkdir -p "$(dirname "$OUT_FILE")"
exec 3>"$OUT_FILE"
emit() { printf '%s\n' "$*" >&3; }

emit "# Co-Evolution Benchmark — Batch \`$BATCH_ID\`"
emit ""
emit "Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) by \`benchmarks/report.sh\`."
emit "Judges reported separately and never adjudicated into one score."
emit ""

# --- Data completeness (before any result) ------------------------------------
emit "## 0. Data completeness"
emit ""
emit "Read this before any number below it."
emit ""
INCOMPLETE_CELLS=()
for task in "${TASKS[@]}"; do
  for cond in ${CONDS[@]+"${CONDS[@]}"}; do
    cell="$(bench_cell_dir "$BATCH_DIR" "$task" "$cond")"
    status="$(bench_meta_status "$cell")"
    [[ "$status" == "complete" ]] || INCOMPLETE_CELLS+=("$task/$cond: $status")
  done
done
DEGRADED_LIST=()
for task in "${TASKS[@]}"; do
  for cond in ${CONDS[@]+"${CONDS[@]}"}; do
    cell="$(bench_cell_dir "$BATCH_DIR" "$task" "$cond")"
    if jq -e '.degraded == true' "$cell/meta.json" >/dev/null 2>&1; then
      DEGRADED_LIST+=("$task/$cond")
    fi
  done
done

emit "- Tasks: ${#TASKS[@]} (\`$(printf '%s ' "${TASKS[@]}" | sed 's/ $//')\`)"
emit "- Conditions: ${#CONDS[@]} (\`$(printf '%s ' ${CONDS[@]+"${CONDS[@]}"} | sed 's/ $//')\`)"
emit "- Judges requested: \`${JUDGES[*]}\`; judges with verdicts on disk: \`${ACTIVE_JUDGES[*]:-none}\`"
if (( ${#INCOMPLETE_CELLS[@]} > 0 )); then
  emit "- **Generation cells not complete (${#INCOMPLETE_CELLS[@]}):**"
  for c in "${INCOMPLETE_CELLS[@]}"; do emit "  - \`$c\`"; done
else
  emit "- Generation cells: all ${#TASKS[@]}x${#CONDS[@]} complete"
fi
if (( ${#DEGRADED_LIST[@]} > 0 )); then
  emit "- **Degraded cells excluded from all pairing (${#DEGRADED_LIST[@]}):** \`${DEGRADED_LIST[*]}\`"
else
  emit "- Degraded cells: none"
fi

EXPECTED_PAIRS=$(( ${#TASKS[@]} * ${#CONDS[@]} * (${#CONDS[@]} - 1) / 2 ))
emit ""
emit "| Judge | Verdict files | Expected pairs | Unjudged |"
emit "|---|---|---|---|"
for seat in "${JUDGES[@]}"; do
  n=$(wc -l < "$WORK/rows-$seat.tsv" | tr -d '[:space:]')
  emit "| \`$seat\` | $n | $EXPECTED_PAIRS | $(( EXPECTED_PAIRS - n )) |"
done
emit ""
emit "\"Expected pairs\" assumes every condition survives sanitization and no cell"
emit "is degraded; a nonzero \"Unjudged\" column means pairs are still missing and"
emit "every rate below is computed over what exists, not over what was planned."
emit ""

# --- 1. Pre-registered outcomes ----------------------------------------------
emit "## 1. Pre-registered outcomes"
emit ""
emit "Decision rules frozen in \`benchmarks/PREREGISTRATION.md\` before generation."
emit "Primary judge: \`$PRIMARY_JUDGE\`."
emit ""

has_cond() { local c; for c in ${CONDS[@]+"${CONDS[@]}"}; do [[ "$c" == "$1" ]] && return 0; done; return 1; }

report_comparison() { # $1 = P (treatment), $2 = Q (baseline), $3 = label, $4 = primary(true/false)
  local p="$1" q="$2" label="$3" is_primary="$4"
  local seat counts pw qw nd ms nt outcome

  if ! has_cond "$p" || ! has_cond "$q"; then
    emit "### $label"
    emit ""
    emit "**Not computable** — condition \`$p\` or \`$q\` is absent from this batch."
    emit ""
    return 0
  fi

  emit "### $label"
  emit ""
  emit "| Judge | $p wins | $q wins | Non-decisive | Missing |"
  emit "|---|---|---|---|---|"
  for seat in "${JUDGES[@]}"; do
    read -r pw qw nd ms nt <<<"$(comparison_counts "$seat" "$p" "$q")"
    emit "| \`$seat\` | $pw | $qw | $nd | $ms |"
  done
  emit ""

  if [[ "$is_primary" == true ]]; then
    read -r pw qw nd ms nt <<<"$(comparison_counts "$PRIMARY_JUDGE" "$p" "$q")"
    if (( pw >= PREREG_HELPS )); then
      outcome="**$p helps** — $pw/$nt decisive wins meets the pre-registered >=${PREREG_HELPS}/${PREREG_N} sign-test threshold (p<0.05, two-sided)."
    elif (( pw >= PREREG_DIRECTIONAL )); then
      outcome="**Directionally positive, underpowered** — $pw/$nt decisive wins falls in the pre-registered ${PREREG_DIRECTIONAL}-$((PREREG_HELPS - 1))/${PREREG_N} band."
    else
      outcome="**No evidence** — $pw/$nt decisive wins is below the pre-registered ${PREREG_DIRECTIONAL}/${PREREG_N} band."
    fi
    emit "Primary-judge sign test (\`$PRIMARY_JUDGE\`): $outcome"
    if (( nt != PREREG_N )); then
      emit ""
      emit "**Caveat:** the frozen rule was written for N=$PREREG_N tasks; this batch has $nt."
      emit "The thresholds are applied as absolute win counts, so read the outcome above as"
      emit "indicative only."
    fi
    if (( ms > 0 )); then
      emit ""
      emit "**Caveat:** $ms task(s) have no verdict for this pair. Missing verdicts are counted"
      emit "as neither wins nor losses, which makes the sign test conservative, not neutral."
    fi
    emit ""
  fi

  emit "Per-task detail (primary judge \`$PRIMARY_JUDGE\`):"
  emit ""
  emit "| Task | Difficulty | Verdict |"
  emit "|---|---|---|"
  local task v
  for task in "${TASKS[@]}"; do
    v="$(pair_verdict "$PRIMARY_JUDGE" "$task" "$p" "$q")"
    emit "| \`$task\` | $(task_difficulty "$task") | $v |"
  done
  emit ""
}

report_comparison B A "Primary comparison: B (cross-vendor bounce) vs A (solo)" true
report_comparison B D "Secondary confirmatory: B (cross-vendor bounce) vs D (self-bounce)" false

# --- 2. Per-judge matrices + BT ----------------------------------------------
emit "## 2. Per-judge win matrices and Bradley-Terry ranking (secondary)"
emit ""
emit "Ties and position-biased pairs count as half a win each"
emit "(\`PREREGISTRATION.md\` §4); invalid-evidence and sanitize-leak pairs are"
emit "excluded from win counts entirely."
emit ""

for seat in "${JUDGES[@]}"; do
  emit "### Judge \`$seat\`"
  emit ""
  rows="$WORK/rows-$seat.tsv"
  if [[ ! -s "$rows" ]]; then
    emit "No verdicts on disk for this judge."
    emit ""
    continue
  fi
  matrix_and_bt "$rows" > "$WORK/bt-$seat.tsv"

  emit "Win rate of the row condition against the column condition (wins / comparisons):"
  emit ""
  header="| vs |"; sep="|---|"
  for c in ${CONDS[@]+"${CONDS[@]}"}; do header="$header $c |"; sep="$sep---|"; done
  emit "$header"
  emit "$sep"
  for a in ${CONDS[@]+"${CONDS[@]}"}; do
    line="| **$a** |"
    for b in ${CONDS[@]+"${CONDS[@]}"}; do
      if [[ "$a" == "$b" ]]; then line="$line — |"; continue; fi
      cell=$(awk -F'\t' -v a="$a" -v b="$b" '$1 == "MATRIX" && $2 == a && $3 == b { print $4 " " $5; exit }' "$WORK/bt-$seat.tsv")
      if [[ -z "$cell" ]]; then line="$line n/a |"; continue; fi
      w=${cell% *}; nn=${cell#* }
      if [[ "$nn" == "0" ]]; then line="$line n/a |"; else line="$line $(ratio "$w" "$nn") ($w/$nn) |"; fi
    done
    emit "$line"
  done
  emit ""
  emit "Bradley-Terry strengths (normalized to sum 1; **no confidence intervals** —"
  emit "with ${#TASKS[@]} tasks none would be meaningful):"
  emit ""
  emit "| Rank | Condition | BT strength | Total wins |"
  emit "|---|---|---|---|"
  rank=0
  while IFS=$'\t' read -r tag cid score wins; do
    [[ "$tag" == "BT" ]] || continue
    rank=$((rank + 1))
    emit "| $rank | \`$cid\` | $score | $wins |"
  done < <(awk -F'\t' '$1 == "BT"' "$WORK/bt-$seat.tsv" | LC_ALL=C sort -t$'\t' -k3,3gr)
  emit ""
done

# --- 3. Judge integrity -------------------------------------------------------
emit "## 3. Judge integrity"
emit ""
emit "| Judge | Pairs | Decisive | Ties | Position-biased | Invalid evidence | Sanitize-leak |"
emit "|---|---|---|---|---|---|---|"
for seat in "${JUDGES[@]}"; do
  read -r tot dec ti pb iv lk <<<"$(integrity_counts "$WORK/rows-$seat.tsv")"
  emit "| \`$seat\` | $tot | $dec | $ti | $pb ($(pct "$pb" "$tot")) | $iv ($(pct "$iv" "$tot")) | $lk |"
done
emit ""

# Three-way agreement over pairs all requested judges scored.
if (( ${#JUDGES[@]} >= 2 )); then
  agree_total=0; agree_all=0; agree_dir=0
  for task in "${TASKS[@]}"; do
    for (( ci = 0; ci < ${#CONDS[@]}; ci++ )); do
      for (( cj = ci + 1; cj < ${#CONDS[@]}; cj++ )); do
        p="${CONDS[$ci]}"; q="${CONDS[$cj]}"
        allsame=true; first=""; complete=true; decisive=true
        for seat in "${JUDGES[@]}"; do
          v="$(pair_verdict "$seat" "$task" "$p" "$q")"
          [[ "$v" == "missing" ]] && { complete=false; break; }
          [[ "$v" == "$p" || "$v" == "$q" ]] || decisive=false
          [[ -z "$first" ]] && first="$v"
          [[ "$v" == "$first" ]] || allsame=false
        done
        [[ "$complete" == true ]] || continue
        agree_total=$((agree_total + 1))
        [[ "$allsame" == true ]] && agree_all=$((agree_all + 1))
        [[ "$allsame" == true && "$decisive" == true ]] && agree_dir=$((agree_dir + 1))
      done
    done
  done
  emit "**Cross-judge agreement.** Of $agree_total pair(s) scored by all ${#JUDGES[@]} requested judges,"
  emit "$agree_all agreed exactly ($(pct "$agree_all" "$agree_total")), and $agree_dir of those were unanimous *and* decisive"
  emit "($(pct "$agree_dir" "$agree_total") of comparable pairs). Unanimous decisive agreement across vendors is the"
  emit "strongest signal this batch can produce; systematic divergence along the"
  emit "conflict map below is reported as exactly that, not averaged away."
  emit ""
fi

emit "**Conflict map.** Conditions A, C, and D emit a Fable-authored final"
emit "document; condition B's final is Codex-revised (bouncer seat semantics: odd"
emit "passes review, even passes compose, so \`--agents claude,codex\` at two"
emit "bounces ends on Codex). Neither of the two strongest judges is neutral: the"
emit "fable-5 judge may favor A/C/D on style, and the gpt-5.5 judge may favor B for"
emit "the same reason in the opposite direction. That is why the glm-5.3-flash"
emit "judge is here — GLM enters generation only as one of three panel critics in"
emit "condition C and never composes or revises, so it carries no side in the"
emit "A/B/D comparisons. Per-judge results are presented side by side and never"
emit "adjudicated into a single score."
emit ""

# --- 4. Length bias -----------------------------------------------------------
emit "## 4. Length-bias check"
emit ""
emit "| Judge | Longer doc won | Comparable decisive pairs | Rate |"
emit "|---|---|---|---|"
for seat in "${JUDGES[@]}"; do
  read -r lw ln <<<"$(length_bias "$WORK/rows-$seat.tsv")"
  emit "| \`$seat\` | $lw | $ln | $(pct "$lw" "$ln") |"
done
emit ""
emit "A rate near 50% is what an unbiased judge looks like; a rate well above it"
emit "means length, not quality, is doing the work. Pairs where the two documents"
emit "have identical word counts are excluded from the denominator."
emit ""
emit "Word counts of the sanitized documents, by condition:"
emit ""
emit "| Condition | Mean words | Documents |"
emit "|---|---|---|"
while read -r cid mw cn; do
  [[ -n "$cid" ]] && emit "| \`$cid\` | $mw | $cn |"
done < <(condition_words)
emit ""

# --- 5. Exploratory -----------------------------------------------------------
emit "## 5. Exploratory (labeled non-evidence)"
emit ""
emit "Nothing in this section was pre-registered. It is descriptive only and must"
emit "not be quoted as a result."
emit ""
if has_cond C; then
  emit "**Condition C (panel) standing.** Total wins across all its pairs, per judge:"
  emit ""
  emit "| Judge | C wins | C comparisons |"
  emit "|---|---|---|"
  for seat in "${JUDGES[@]}"; do
    read -r cw cn <<<"$(awk -F'\t' '
      $2 == "C" || $3 == "C" {
        n++
        if (($4 == "x" && $2 == "C") || ($4 == "y" && $3 == "C")) w++
        else if ($4 == "tie" || $4 == "position_biased") w += 0.5
      }
      END { printf "%.1f %d", w+0, n+0 }' "$WORK/rows-$seat.tsv")"
    emit "| \`$seat\` | $cw | $cn |"
  done
  emit ""
else
  emit "Condition C is absent from this batch."
  emit ""
fi

emit "**Difficulty cuts** (primary judge \`$PRIMARY_JUDGE\`, B-vs-A). With at most a"
emit "couple of tasks per difficulty band these are anecdotes, not cuts:"
emit ""
emit "| Difficulty | Tasks | B wins | A wins | Other |"
emit "|---|---|---|---|---|"
: > "$WORK/difficulty.tsv"
for task in "${TASKS[@]}"; do
  printf '%s\t%s\t%s\n' "$(task_difficulty "$task")" "$task" "$(pair_verdict "$PRIMARY_JUDGE" "$task" B A)" >> "$WORK/difficulty.tsv"
done
while IFS=$'\t' read -r diff cnt bw aw ot; do
  [[ -n "$diff" ]] && emit "| $diff | $cnt | $bw | $aw | $ot |"
done < <(awk -F'\t' '
  { n[$1]++; if ($3 == "B") b[$1]++; else if ($3 == "A") a[$1]++; else o[$1]++ }
  END { for (d in n) printf "%s\t%d\t%d\t%d\t%d\n", d, n[d], b[d]+0, a[d]+0, o[d]+0 }
' "$WORK/difficulty.tsv" | LC_ALL=C sort)
emit ""

# --- 6. Process stats + cost --------------------------------------------------
emit "## 6. Process stats and cost"
emit ""
emit "| Condition | Cells | Mean words | Mean wall s | Converged | Adjudicated | Stuck | GLM calls | Captured cost USD |"
emit "|---|---|---|---|---|---|---|---|---|"
for cond in ${CONDS[@]+"${CONDS[@]}"}; do
  cells=0; words=0; wall=0; conv=0; adj=0; stuck=0; glm=0
  costs_file="$WORK/costs-$cond.txt"; : > "$costs_file"
  for task in "${TASKS[@]}"; do
    meta="$(bench_cell_dir "$BATCH_DIR" "$task" "$cond")/meta.json"
    [[ -f "$meta" ]] || continue
    cells=$((cells + 1))
    words=$(( words + $(meta_num "$meta" .word_count) ))
    wall=$(( wall + $(meta_num "$meta" .wall_secs) ))
    glm=$(( glm + $(meta_num "$meta" .glm_calls) ))
    case "$(jq -r '.convergence_status // ""' "$meta" 2>/dev/null)" in
      converged)   conv=$((conv + 1)) ;;
      adjudicated) adj=$((adj + 1)) ;;
      stuck)       stuck=$((stuck + 1)) ;;
    esac
    # Costs live under per-phase `tokens`; sum every total_cost_usd beneath it
    # rather than assuming one shape, since phase names vary by condition kind.
    jq -r '[(.tokens // {}) | .. | objects | select(has("total_cost_usd"))
            | .total_cost_usd | numbers] | add // 0' "$meta" 2>/dev/null \
      | tr -d '\r' >> "$costs_file" || true
  done
  cost=$(awk '{ s += $1 } END { printf "%.4f", s + 0 }' "$costs_file")
  emit "| \`$cond\` | $cells | $(( cells > 0 ? words / cells : 0 )) | $(( cells > 0 ? wall / cells : 0 )) | $conv | $adj | $stuck | $glm | $cost |"
done
emit ""
emit "Costs sum any token sidecar \`total_cost_usd\` values. Claude reports that"
emit "field; the direct GLM and Kimi sidecars report tokens but no dollar price,"
emit "and Codex has no sidecar. The cost column is therefore a floor, not a total."
emit ""
emit "Judging cost is not itemized here: the judge CLIs are invoked in text/schema"
emit "mode without token capture. Judging volume is $EXPECTED_PAIRS pairs x 2 trials x"
emit "${#JUDGES[@]} judge(s) at full coverage."
emit ""

# --- 7. Limitations -----------------------------------------------------------
emit "## 7. Honest limitations"
emit ""
emit "- ${#TASKS[@]} selected tasks with automated judges produce **exploratory"
emit "  directional evidence**. This is not hard evidence and not proof. General"
emit "  claims about cross-AI bouncing need a larger held-out replication."
emit "- Only the B-vs-A and B-vs-D comparisons were pre-registered. Everything in"
emit "  sections 2, 4, and 5 is secondary or exploratory and is labeled as such."
emit "- No judge is condition-neutral on style. Two of the three share a vendor"
emit "  with a condition under test, in opposite directions (see the conflict map)."
emit "- Bradley-Terry strengths have no confidence intervals and should not be read"
emit "  as a ranking with a margin."
emit "- The GLM quota ledger cannot see Z.AI's server-side window or GLM usage"
emit "  outside this benchmark, so a batch spread across days may have generation"
emit "  and judging runs with different effective rate limits."
emit "- Sanitization is fail-closed but not omniscient: it removes the process"
emit "  artifacts and vendor names on the frozen banned-token list, and a novel"
emit "  tell would pass. The list is frozen per batch."

exec 3>&-

REPORT_COPY=""
if [[ "$COPY_TO_REPORTS" == true ]]; then
  mkdir -p "$SCRIPT_DIR/reports"
  REPORT_COPY="$SCRIPT_DIR/reports/$BATCH_ID.md"
  cp -f "$OUT_FILE" "$REPORT_COPY"
fi

log "INFO: report written -> $OUT_FILE"
[[ -n "$REPORT_COPY" ]] && log "INFO: committed copy   -> $REPORT_COPY"
exit 0
