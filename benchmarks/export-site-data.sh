#!/usr/bin/env bash

# benchmarks/export-site-data.sh — turn a judged batch into the static site's
# data files.
#
#   bash benchmarks/export-site-data.sh --batch b1
#   bash benchmarks/export-site-data.sh --batch-dir /path/to/results/b1 --docs-dir docs
#
# Writes docs/data/<batch>.json (per-condition aggregates, per-task rows,
# per-judge tallies) and regenerates docs/data/index.json from every
# bench-site/1.0 file already in that directory.
#
# The site renders this JSON and nothing else, so anything not traceable to a
# run artifact cannot reach the page. Publishable fields only: scores, costs,
# model and condition names, judge tallies, task ids and difficulty. Prompt
# text, plan text, judge reasons and evidence quotes are never read into the
# output, and a guard at the end fails the export if they somehow appear.
#
# Every number is computed with the accounting benchmarks/report.sh uses
# (PREREGISTRATION.md section 4): a win is 1, a tie or a position-biased pair
# is 0.5 for each side, and invalid-evidence / sanitize-leak pairs leave both
# the numerator and the denominator. Judges stay separate and are never
# adjudicated into one score.
#
# Exit: 0 data written, 1 hard error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log() { printf '%s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required for export-site-data.sh"

BATCH_ID=""
BATCH_DIR=""
RESULTS_ROOT="$SCRIPT_DIR/results"
# The plan-composition suite scores Co-Evolution against itself: every condition
# is composed by Fable and the primary judge is Fable. That is a legitimate
# internal signal and not a publishable result, so the export lands in the
# ignored results tree rather than in a directory staged for the public site.
# Point --docs-dir somewhere else deliberately if you have a reason to.
DOCS_DIR="${CODE_BENCH_SITE_EXPORT_DIR:-$REPO_ROOT/benchmarks/results/site-export}"
CORPUS_DIR="$SCRIPT_DIR/corpus"
CONDITIONS_FILE="$SCRIPT_DIR/conditions.yaml"
JUDGES_CSV="fable,codex,glm"
PRIMARY_JUDGE="fable"
OUT_FILE=""
WRITE_INDEX=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --batch)         BATCH_ID="${2:?--batch needs a value}"; shift 2 ;;
    --batch-dir)     BATCH_DIR="${2:?--batch-dir needs a value}"; shift 2 ;;
    --results-root)  RESULTS_ROOT="${2:?--results-root needs a value}"; shift 2 ;;
    --docs-dir)      DOCS_DIR="${2:?--docs-dir needs a value}"; shift 2 ;;
    --corpus)        CORPUS_DIR="${2:?--corpus needs a value}"; shift 2 ;;
    --conditions)    CONDITIONS_FILE="${2:?--conditions needs a value}"; shift 2 ;;
    --judges)        JUDGES_CSV="${2:?--judges needs a value}"; shift 2 ;;
    --primary-judge) PRIMARY_JUDGE="${2:?--primary-judge needs a value}"; shift 2 ;;
    --out)           OUT_FILE="${2:?--out needs a value}"; shift 2 ;;
    --no-index)      WRITE_INDEX=false; shift ;;
    -h|--help)       sed -n '3,26p' "$0"; exit 0 ;;
    *) die "unknown flag: $1" ;;
  esac
done

if [[ -z "$BATCH_DIR" ]]; then
  [[ -n "$BATCH_ID" ]] || die "--batch <id> or --batch-dir <dir> is required"
  BATCH_DIR="$RESULTS_ROOT/$BATCH_ID"
fi
[[ -d "$BATCH_DIR" ]] || die "batch dir does not exist: $BATCH_DIR"
BATCH_DIR="$(cd "$BATCH_DIR" && pwd)"
[[ -n "$BATCH_ID" ]] || BATCH_ID="$(basename "$BATCH_DIR")"
[[ -n "$OUT_FILE" ]] || OUT_FILE="$DOCS_DIR/data/$BATCH_ID.json"

WORK=$(mktemp -d -t bench-site-XXXXXX) || die "could not create a work dir"
trap 'rm -rf -- "$WORK"' EXIT

JUDGES=()
while IFS= read -r seat; do [[ -n "$seat" ]] && JUDGES+=("$seat"); done \
  < <(printf '%s\n' "$JUDGES_CSV" | tr ',' '\n' | tr -d '\r' | sed 's/^ *//; s/ *$//')
(( ${#JUDGES[@]} > 0 )) || die "--judges resolved to an empty list"

# --- Discovery ----------------------------------------------------------------

list_subdirs() { # DIR [EXCLUDE]
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

CONDS=()
for task in "${TASKS[@]}"; do
  while IFS= read -r c; do
    for seen in ${CONDS[@]+"${CONDS[@]}"}; do [[ "$seen" == "$c" ]] && continue 2; done
    CONDS+=("$c")
  done < <(list_subdirs "$BATCH_DIR/$task" judging)
done
SORTED=()
while IFS= read -r c; do [[ -n "$c" ]] && SORTED+=("$c"); done \
  < <(printf '%s\n' ${CONDS[@]+"${CONDS[@]}"} | LC_ALL=C sort -u | sed '/^$/d')
CONDS=("${SORTED[@]}")
(( ${#CONDS[@]} > 0 )) || die "no condition directories under $BATCH_DIR/${TASKS[0]}"

# --- Corpus difficulty --------------------------------------------------------
# Read straight out of the frontmatter rather than through yq: the site export
# has to run anywhere jq runs, and difficulty is a single flat scalar.

task_difficulty() {
  local f="$CORPUS_DIR/$1.md" d
  [[ -f "$f" ]] || { printf 'unknown'; return 0; }
  d=$(awk '
    /^---[[:space:]]*$/ { fence++; if (fence == 2) exit; next }
    fence == 1 && /^difficulty:[[:space:]]*/ {
      sub(/^difficulty:[[:space:]]*/, ""); gsub(/[",\r]/, ""); print; exit
    }' "$f")
  printf '%s' "${d:-unknown}"
}

: > "$WORK/tasks.tsv"
for task in "${TASKS[@]}"; do
  printf '%s\t%s\n' "$task" "$(task_difficulty "$task")" >> "$WORK/tasks.tsv"
done

# --- Condition manifest -------------------------------------------------------
# conditions.yaml is a flat list of scalars plus one folded description and two
# short inline sequences. Parsing it here with awk keeps the export free of a
# yq dependency; run-benchmark.sh stays the validating reader.
#
# Pass 1 pulls the raw fields, pass 2 resolves seats to model names — split in
# two so `args:` appearing after `kind:` inside an entry cannot change the
# answer.

awk '
  function flush(  seats, models) {
    if (id == "") return
    if (kind == "solo")         { seats = "composer";              models = model }
    else if (kind == "bouncer") { seats = agents;                  models = "" }
    else if (kind == "panel")   { seats = "composer|" reviewers;   models = "" }
    else                        { seats = "";                      models = model }
    gsub(/\t/, " ", desc)
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", id, label, kind, glm, seats, models, desc, cm
    reset()
  }
  function reset() {
    id = ""; label = ""; kind = ""; model = ""; glm = "0"; desc = ""
    agents = ""; reviewers = ""; cm = "best"; infold = 0
  }
  BEGIN { reset() }
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/ {
    flush()
    line = $0; sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", line)
    gsub(/[",\r]/, "", line); id = line; next
  }
  id == "" { next }
  /^[[:space:]]+label:/ { infold = 0; line = $0; sub(/^[[:space:]]*label:[[:space:]]*/, "", line); gsub(/[",\r]/, "", line); label = line; next }
  /^[[:space:]]+kind:/  { infold = 0; line = $0; sub(/^[[:space:]]*kind:[[:space:]]*/,  "", line); gsub(/[",\r]/, "", line); kind  = line; next }
  /^[[:space:]]+model:/ { infold = 0; line = $0; sub(/^[[:space:]]*model:[[:space:]]*/, "", line); gsub(/[",\r]/, "", line); model = line; next }
  /^[[:space:]]+glm_calls_per_run:/ { infold = 0; line = $0; gsub(/[^0-9]/, "", line); glm = (line == "" ? "0" : line); next }
  /^[[:space:]]+description:/ { infold = 1; desc = ""; next }
  /^[[:space:]]+args:/ {
    # Pull the quoted elements out one at a time. Splitting the inline list on
    # commas would break "claude,codex", which is a single argument whose value
    # happens to contain the list separator.
    infold = 0; line = $0; sub(/^[[:space:]]*args:[[:space:]]*/, "", line)
    n = 0
    while (match(line, /"[^"]*"/)) {
      a[++n] = substr(line, RSTART + 1, RLENGTH - 2)
      line = substr(line, RSTART + RLENGTH)
    }
    for (i = 1; i <= n; i++) {
      if (a[i] == "--agents"       && i < n) { agents = a[i + 1]; gsub(/,/, "|", agents) }
      if (a[i] == "--claude-model" && i < n) { cm = a[i + 1] }
    }
    next
  }
  /^[[:space:]]+reviewers:/ {
    # Inline sequence, elements unquoted: drop the brackets, quotes and spaces,
    # then the commas are the only separators left.
    infold = 0; line = $0; sub(/^[[:space:]]*reviewers:[[:space:]]*/, "", line)
    gsub(/[]["\r]/, "", line); gsub(/[[:space:]]/, "", line)
    reviewers = line; gsub(/,/, "|", reviewers)
    next
  }
  /^[[:space:]]+[a-z_]+:/ { infold = 0; next }
  infold == 1 {
    line = $0; sub(/^[[:space:]]+/, "", line); gsub(/\r/, "", line)
    if (line == "") next
    desc = (desc == "") ? line : desc " " line
    next
  }
  END { flush() }
' "$CONDITIONS_FILE" > "$WORK/conds-raw.tsv" 2>/dev/null || : > "$WORK/conds-raw.tsv"

# Pass 2: seat -> concrete model id, mirroring lib/co-evolution.sh's alias table
# and run-panel.sh's panel_reviewer_model. Codex takes its model from the Codex
# CLI config unless CODEX_MODEL is set, so it is named as exactly that rather
# than guessed at.
awk -F'\t' -v OFS='\t' '
  function claude_model(a) {
    if (a == "fable") return "claude-fable-5"
    if (a == "opus" || a == "best") return "claude-opus-4-8"
    return a
  }
  function seat_model(s, cm) {
    if (s == "codex")     return "codex CLI default"
    if (s == "glm")       return "glm-5.3-flash"
    if (s == "kimi")      return "kimi-k3"
    if (s == "claude")    return claude_model(cm)
    if (s == "composer")  return claude_model("fable")
    return s
  }
  {
    id = $1; label = $2; kind = $3; glm = $4; seats = $5; models = $6; desc = $7; cm = $8
    if (kind == "solo") { out = models }
    else {
      n = split(seats, s, /\|/); out = ""
      for (i = 1; i <= n; i++) out = (out == "") ? seat_model(s[i], cm) : out "|" seat_model(s[i], cm)
    }
    print id, label, kind, glm, seats, out, desc
  }
' "$WORK/conds-raw.tsv" > "$WORK/conds.tsv"

# Keep only the conditions this batch actually ran, in the batch tree's order.
: > "$WORK/conds-batch.tsv"
for cond in "${CONDS[@]}"; do
  row=$(awk -F'\t' -v c="$cond" '$1 == c { print; exit }' "$WORK/conds.tsv")
  if [[ -n "$row" ]]; then
    printf '%s\n' "$row" >> "$WORK/conds-batch.tsv"
  else
    printf '%s\t%s\t\t0\t\t\t%s\n' "$cond" "$cond" "Not described in $(basename "$CONDITIONS_FILE")." >> "$WORK/conds-batch.tsv"
  fi
done
mv "$WORK/conds-batch.tsv" "$WORK/conds.tsv"

# --- Judge roster from the judging preflight ---------------------------------

: > "$WORK/judges.tsv"
PREFLIGHT="$BATCH_DIR/judging/preflight.json"
for seat in "${JUDGES[@]}"; do
  model=""; cli=""; effort=""; assert=""
  if [[ -f "$PREFLIGHT" ]]; then
    # One field per line, not a TSV row: tab is IFS whitespace, so `read` would
    # collapse the empty `effort` a curl-driven judge seat reports and shift
    # every later field up by one.
    fields=()
    while IFS= read -r v; do fields+=("$v"); done < <(
      jq -r --arg j "$seat" '
        (.judges // []) | map(select(.judge == $j)) | .[0] // {}
        | [ (.model // ""), (.cli_version // ""), (.effort // ""), (.model_assert // "") ] | .[]' \
        "$PREFLIGHT" 2>/dev/null | tr -d '\r'
    ) || true
    model="${fields[0]:-}"; cli="${fields[1]:-}"; effort="${fields[2]:-}"; assert="${fields[3]:-}"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$seat" "$model" "$cli" "$effort" "$assert" >> "$WORK/judges.tsv"
done

# --- Verdict rows -------------------------------------------------------------
# judge \t task \t x \t y \t verdict \t words_x \t words_y \t confidence_pair \t evidence_verified
#
# `tr -d '\r'` is not cosmetic: jq.exe under Git Bash emits CRLF, which would
# leave the last field of every row carrying a trailing CR.
#
# Only these eight fields are read. The verdict files also carry the judge's
# reasons and verbatim evidence quotes from the plans; those are plan text and
# stay out of the export by construction.

: > "$WORK/rows.tsv"
for seat in "${JUDGES[@]}"; do
  : > "$WORK/rows-$seat.tsv"
  for task in "${TASKS[@]}"; do
    dir="$BATCH_DIR/$task/judging/$seat"
    [[ -d "$dir" ]] || continue
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      jq -r 'select(.schema == "bench-pair/1.0")
             | [.task_id, .cond_x, .cond_y, .verdict,
                (.doc_words.x // 0), (.doc_words.y // 0),
                (.confidence_pair // ""), ((.evidence_verified // false) | tostring)] | @tsv' "$f" 2>/dev/null \
        | tr -d '\r' >> "$WORK/rows-$seat.tsv" || true
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -name '*.json' -type f 2>/dev/null | LC_ALL=C sort)
  done
  awk -F'\t' -v OFS='\t' -v j="$seat" 'NF > 0 { print j, $0 }' "$WORK/rows-$seat.tsv" >> "$WORK/rows.tsv"
done

TOTAL_ROWS=$(wc -l < "$WORK/rows.tsv" | tr -d '[:space:]')
(( TOTAL_ROWS > 0 )) || die "no bench-pair/1.0 verdict files under $BATCH_DIR — run benchmarks/judge-matrix.sh first"

# --- Win matrix + Bradley-Terry ----------------------------------------------
# The accounting in report.sh's matrix_and_bt, unchanged: MM fixed point over
# 20 iterations, ties and position-biased pairs at half a win each,
# invalid-evidence and sanitize-leak excluded from both wins and comparisons.
# Keeping the two implementations identical is what makes the site's numbers
# and the report's numbers the same numbers.

matrix_and_bt() { # $1 = rows tsv for one judge
  awk -F'\t' '
    function add(a, b, wa, wb) {
      W[a SUBSEP b] += wa; W[b SUBSEP a] += wb
      N[a SUBSEP b] += 1;  N[b SUBSEP a] += 1
      TW[a] += wa; TW[b] += wb
      seen[a] = 1; seen[b] = 1
    }
    {
      x = $2; y = $3; v = $4
      if (v == "x")                                  add(x, y, 1, 0)
      else if (v == "y")                             add(x, y, 0, 1)
      else if (v == "tie" || v == "position_biased") add(x, y, 0.5, 0.5)
      else { seen[x] = 1; seen[y] = 1 }
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

: > "$WORK/matrix.tsv"
: > "$WORK/bt.tsv"
for seat in "${JUDGES[@]}"; do
  [[ -s "$WORK/rows-$seat.tsv" ]] || continue
  matrix_and_bt "$WORK/rows-$seat.tsv" > "$WORK/bt-$seat.tsv"
  awk -F'\t' -v OFS='\t' -v j="$seat" '$1 == "MATRIX" { print j, $2, $3, $4, $5 }' "$WORK/bt-$seat.tsv" >> "$WORK/matrix.tsv"
  awk -F'\t' -v OFS='\t' -v j="$seat" '$1 == "BT"     { print j, $2, $3, $4 }'     "$WORK/bt-$seat.tsv" >> "$WORK/bt.tsv"
done

# --- Cell stats ---------------------------------------------------------------
# task \t cond \t status \t degraded \t words \t wall_secs \t glm_calls \t convergence \t cost_usd
#
# Costs live under per-phase `tokens`; sum every total_cost_usd beneath it
# rather than assuming one shape, since phase names vary by condition kind.
# Same expression as report.sh section 6.

: > "$WORK/cells.tsv"
for task in "${TASKS[@]}"; do
  for cond in "${CONDS[@]}"; do
    meta="$BATCH_DIR/$task/$cond/meta.json"
    if [[ ! -f "$meta" ]]; then
      printf '%s\t%s\tabsent\tfalse\t0\t0\t0\t\t0\n' "$task" "$cond" >> "$WORK/cells.tsv"
      continue
    fi
    jq -r --arg t "$task" --arg c "$cond" '
      [ $t, $c,
        (if (has("status") and (.status | type == "string")) then .status else "absent" end),
        ((.degraded // false) | tostring),
        ((.word_count // 0) | floor),
        ((.wall_secs // 0) | floor),
        ((.glm_calls // 0) | floor),
        (.convergence_status // ""),
        ([(.tokens // {}) | .. | objects | select(has("total_cost_usd")) | .total_cost_usd | numbers] | add // 0)
      ] | @tsv' "$meta" 2>/dev/null | tr -d '\r' >> "$WORK/cells.tsv" \
      || printf '%s\t%s\tabsent\tfalse\t0\t0\t0\t\t0\n' "$task" "$cond" >> "$WORK/cells.tsv"
  done
done

# --- Sanitization exclusions --------------------------------------------------
# task \t cond \t reason. The leak-file path in excluded.json is a local
# absolute path and is deliberately not carried into the export.

: > "$WORK/excluded.tsv"
for task in "${TASKS[@]}"; do
  f="$BATCH_DIR/$task/judging/excluded.json"
  [[ -f "$f" ]] || continue
  jq -r --arg t "$task" '(.excluded // [])[] | [$t, (.condition // ""), (.reason // "")] | @tsv' \
    "$f" 2>/dev/null | tr -d '\r' >> "$WORK/excluded.tsv" || true
done

# --- Assemble -----------------------------------------------------------------

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$(dirname "$OUT_FILE")"

jq -n \
  --arg batch "$BATCH_ID" \
  --arg generated_at "$GENERATED_AT" \
  --arg primary "$PRIMARY_JUDGE" \
  --argjson prereg_n 8 --argjson prereg_helps 7 --argjson prereg_dir 5 \
  --rawfile tasks_tsv    "$WORK/tasks.tsv" \
  --rawfile conds_tsv    "$WORK/conds.tsv" \
  --rawfile judges_tsv   "$WORK/judges.tsv" \
  --rawfile rows_tsv     "$WORK/rows.tsv" \
  --rawfile matrix_tsv   "$WORK/matrix.tsv" \
  --rawfile bt_tsv       "$WORK/bt.tsv" \
  --rawfile cells_tsv    "$WORK/cells.tsv" \
  --rawfile excluded_tsv "$WORK/excluded.tsv" \
  -f "$SCRIPT_DIR/lib/site-export.jq" > "$WORK/out.json" \
  || die "failed to assemble site data for $BATCH_ID"

# --- Publishability guard -----------------------------------------------------
# The export never reads a prompt, plan, transcript, judge reason or evidence
# quote. Assert it rather than trust it: a field added upstream must not ride
# into docs/ unnoticed.

LEAKED=$(jq -r '
  [ paths(scalars) | map(tostring) | .[] ]
  | map(ascii_downcase)
  | map(select(. == "reason" or . == "reasons" or . == "quote" or . == "quotes"
               or . == "evidence" or . == "raw" or . == "trials" or . == "trial"
               or . == "prompt" or . == "final" or . == "body" or . == "plan"
               or . == "transcript" or . == "detail" or . == "text"))
  | unique | join(", ")' "$WORK/out.json")
[[ -z "$LEAKED" ]] || die "publishability guard: unexpected field(s) in export output: $LEAKED"

jq . "$WORK/out.json" > "$OUT_FILE" || die "could not write $OUT_FILE"
log "INFO: site data written -> $OUT_FILE"

# --- Index --------------------------------------------------------------------

if [[ "$WRITE_INDEX" == true ]]; then
  INDEX="$DOCS_DIR/data/index.json"
  : > "$WORK/batches.jsonl"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    case "$(basename "$f")" in index.json|schema.json) continue ;; esac
    jq -c 'select(.schema == "bench-site/1.0")
           | { batch: .batch, title: .suite.title, suite: .suite.id,
               generated_at: .generated_at,
               metric: .metric.label, metric_unit: .metric.unit,
               tasks: .completeness.tasks, conditions: .completeness.conditions,
               judges: (.completeness.judges_with_verdicts | length),
               complete: .completeness.generation_cells_complete,
               file: ("data/" + .batch + ".json") }' "$f" 2>/dev/null >> "$WORK/batches.jsonl" || true
  done < <(find "$DOCS_DIR/data" -maxdepth 1 -name '*.json' -type f 2>/dev/null | LC_ALL=C sort)

  jq -s --arg generated_at "$GENERATED_AT" --arg default "$BATCH_ID" \
    '{ schema: "bench-site-index/1.0", generated_at: $generated_at,
       default_batch: $default,
       batches: (sort_by(.generated_at) | reverse) }' \
    "$WORK/batches.jsonl" > "$INDEX" || die "could not write $INDEX"
  log "INFO: index written     -> $INDEX"
fi

exit 0
