#!/usr/bin/env bash

# benchmarks/judge-matrix.sh — three-judge round-robin pairwise blind judging
# for the co-evolution benchmark suite (plan section "Judging").
#
#   bash benchmarks/judge-matrix.sh --batch-dir benchmarks/results/b1 \
#        [--tasks t1,t2] [--conditions A,B,D] [--judges fable,codex,glm] \
#        [--judge-effort high] [--corpus benchmarks/corpus] [--skip-probe]
#
# Per task, every unordered pair of surviving conditions is judged by each
# requested judge seat with two position-swapped blind trials. Agreement across
# the swap produces a winner or a tie; disagreement produces `position_biased`
# and no quality claim. Every evidence quote is grep-verified against the
# sanitized document it cites.
#
# Design notes, stated rather than implied:
# - Blinding, the claude-seat trial loop, and evidence verification are REUSED
#   from evals/lib/judge-lib.sh (judge_invoke_trial, judge_norm,
#   judge_check_trial_evidence). judge_build_trial_prompt is NOT reused: it is
#   bounce-specific ("two anonymous versions of the same document"), so this
#   script builds its own cross-condition prompt with the identical strict-JSON
#   contract. judge_invoke_trial hardcodes the claude CLI argv, so the codex and
#   glm seats use bench_invoke_{codex,glm}_trial — a documented parallel of its
#   2-attempt parse loop, sharing bench_parse_verdict and the same
#   file_contains_auth_failure gate. GLM uses the direct Z.AI HTTP adapter.
# - Blinding for the benchmark is benchmarks/lib/sanitize.sh's sanitize_doc,
#   not judge_blind: sanitize_doc is the frozen, wider rule set (benchmark
#   tells, H1 normalization, footer removal) and leak_check is the fail-closed
#   gate that judge_blind has no equivalent for.
# - Banned-token checks go through leak_check. NEVER `grep -iF` with a
#   multi-word pattern: GNU grep 3.0 as shipped with Git Bash SIGABRTs and a
#   fail-closed gate would become a silent pass.
#
# Output: <batch>/judging/preflight.json
#         <batch>/<task>/judging/sanitized/<cond>.md
#         <batch>/<task>/judging/excluded.json
#         <batch>/<task>/judging/leaks/<cond>.txt
#         <batch>/<task>/judging/<judge>/<X>__vs__<Y>.json  (schema bench-pair/1.0)
#
# Exit: 0 every requested pair has a verdict file,
#       75 (EX_TEMPFAIL) some pair is still unjudged — re-run to resume,
#       1 hard configuration error (incomplete batch, unresolvable judge model,
#         missing CLI, missing task prompt).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/co-evolution.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/evals/lib/judge-lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/benchmark-lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/sanitize.sh"

command -v jq >/dev/null 2>&1 || die "jq is required for judge-matrix.sh"

EXIT_RETRYABLE=75

BATCH_DIR=""
TASKS_CSV=""
CONDS_CSV=""
JUDGES_CSV="fable,codex,glm"
CORPUS_DIR="$SCRIPT_DIR/corpus"
BANNED_FILE="$SCRIPT_DIR/lib/banned-tokens.txt"
VERDICT_SCHEMA="$SCRIPT_DIR/schemas/judge-verdict.schema.json"
PREFLIGHT_SCHEMA="$SCRIPT_DIR/schemas/judge-preflight.schema.json"
SKIP_PROBE=false

# Judge seats. Model strings must be CONCRETE — an alias or an inherit marker is
# a configuration error, not a default (plan: "resolve and verify each judge's
# actual model id (a CLI default can drift); abort on mismatch").
JUDGE_MODEL_FABLE="${BENCH_JUDGE_FABLE_MODEL:-claude-fable-5}"
JUDGE_MODEL_CODEX="${BENCH_JUDGE_CODEX_MODEL:-gpt-5.5}"
JUDGE_MODEL_GLM="${BENCH_JUDGE_GLM_MODEL:-glm-5.3-flash}"
JUDGE_EFFORT="${BENCH_JUDGE_EFFORT:-high}"
CODEX_JUDGE_EFFORT="${BENCH_JUDGE_CODEX_EFFORT:-xhigh}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --batch-dir)    BATCH_DIR="${2:?--batch-dir needs a value}"; shift 2 ;;
    --tasks)        TASKS_CSV="${2:?--tasks needs a value}"; shift 2 ;;
    --conditions)   CONDS_CSV="${2:?--conditions needs a value}"; shift 2 ;;
    --judges)       JUDGES_CSV="${2:?--judges needs a value}"; shift 2 ;;
    --judge-effort) JUDGE_EFFORT="${2:?--judge-effort needs a value}"; shift 2 ;;
    --corpus)       CORPUS_DIR="${2:?--corpus needs a value}"; shift 2 ;;
    --skip-probe)   SKIP_PROBE=true; shift ;;
    -h|--help)      sed -n '3,40p' "$0"; exit 0 ;;
    *) die "unknown flag: $1" ;;
  esac
done

[[ -n "$BATCH_DIR" && -d "$BATCH_DIR" ]] || die "--batch-dir <existing dir> is required"
BATCH_DIR="$(cd "$BATCH_DIR" && pwd)"
BATCH_ID="$(basename "$BATCH_DIR")"
[[ -f "$BANNED_FILE" ]] || die "banned-token list not found: $BANNED_FILE"
[[ -f "$VERDICT_SCHEMA" ]] || die "judge verdict schema not found: $VERDICT_SCHEMA"

WORK=$(mktemp -d -t judge-matrix-XXXXXX) || die "could not create a work dir"
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/codex-cwd"

BANNED_SHA=""

# --- Small helpers ------------------------------------------------------------

lowercase() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Trailing newline is load-bearing: `while read` drops a final unterminated line.
csv_to_lines() { printf '%s\n' "$1" | tr ',' '\n' | tr -d '\r' | sed 's/^ *//; s/ *$//' | sed '/^$/d'; }

# list_subdirs DIR [EXCLUDE] → basenames of DIR's immediate subdirectories, sorted.
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

file_words() {
  local n
  n=$(wc -w < "$1" 2>/dev/null | tr -d '[:space:]') || n=0
  printf '%s' "${n:-0}"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf '%s' "unavailable"
  fi
}

judge_cli_for() {
  case "$1" in
    fable) printf '%s' "claude" ;;
    codex) printf '%s' "codex" ;;
    glm)   printf '%s' "curl" ;;
    *) die "unknown judge seat '$1' (expected fable, codex, or glm)" ;;
  esac
}

judge_model_for() {
  case "$1" in
    fable) printf '%s' "$JUDGE_MODEL_FABLE" ;;
    codex) printf '%s' "$JUDGE_MODEL_CODEX" ;;
    glm)   printf '%s' "$JUDGE_MODEL_GLM" ;;
    *) die "unknown judge seat '$1'" ;;
  esac
}

judge_effort_for() {
  case "$1" in
    codex) printf '%s' "$CODEX_JUDGE_EFFORT" ;;
    fable) printf '%s' "$JUDGE_EFFORT" ;;
    glm)   printf '%s' "${GLM_EFFORT:-}" ;;
  esac
}

# A judge seat whose model string is an alias, empty, or an inherit marker would
# put an unidentifiable model's opinion into a pre-registered result. Refuse.
assert_concrete_model() {
  local seat="$1" model="$2" lc
  [[ -n "$model" ]] || die "judge seat '$seat' has an empty model string — set BENCH_JUDGE_$(printf '%s' "$seat" | tr '[:lower:]' '[:upper:]')_MODEL to a concrete model id"
  lc=$(lowercase "$model")
  case "$lc" in
    *inherit*|default|best|opus|sonnet|haiku|fable|kimi|glm)
      die "judge seat '$seat' model '$model' is an alias or inherit marker, not a concrete model id — judging refuses to run on a model the report cannot name" ;;
  esac
}

# --- Judge selection ----------------------------------------------------------

JUDGES=()
while IFS= read -r seat; do JUDGES+=("$seat"); done < <(csv_to_lines "$JUDGES_CSV")
(( ${#JUDGES[@]} > 0 )) || die "--judges resolved to an empty list"
# Seat order is fixed: fable → codex → glm, regardless of the order given.
ORDERED_JUDGES=()
for seat in fable codex glm; do
  for requested in "${JUDGES[@]}"; do
    [[ "$requested" == "$seat" ]] && { ORDERED_JUDGES+=("$seat"); break; }
  done
done
for requested in "${JUDGES[@]}"; do
  case "$requested" in fable|codex|glm) ;; *) die "unknown judge seat '$requested' (expected fable, codex, or glm)" ;; esac
done
JUDGES=("${ORDERED_JUDGES[@]}")

# --- Task / condition selection ----------------------------------------------

TASKS=()
if [[ -n "$TASKS_CSV" ]]; then
  while IFS= read -r t; do TASKS+=("$t"); done < <(csv_to_lines "$TASKS_CSV")
else
  while IFS= read -r t; do TASKS+=("$t"); done < <(list_subdirs "$BATCH_DIR" judging)
fi
(( ${#TASKS[@]} > 0 )) || die "no task directories under $BATCH_DIR"

# Default conditions come from the frozen manifest when it is readable — that is
# the authoritative set, so a task missing a condition reads as "absent" (a gate
# failure) rather than silently shrinking the matrix. Falls back to the union of
# condition directories actually present.
conditions_from_manifest() {
  local manifest="$SCRIPT_DIR/conditions.yaml"
  [[ -f "$manifest" ]] || return 1
  command -v yq >/dev/null 2>&1 || return 1
  yq --version 2>&1 | grep -qi mikefarah || return 1
  yq -r '.conditions[].id' "$manifest" 2>/dev/null | tr -d '\r' | sed '/^$/d'
}

CONDS=()
if [[ -n "$CONDS_CSV" ]]; then
  while IFS= read -r c; do CONDS+=("$c"); done < <(csv_to_lines "$CONDS_CSV")
else
  while IFS= read -r c; do CONDS+=("$c"); done < <(conditions_from_manifest || true)
  if (( ${#CONDS[@]} == 0 )); then
    for task in "${TASKS[@]}"; do
      while IFS= read -r c; do
        for seen in ${CONDS[@]+"${CONDS[@]}"}; do [[ "$seen" == "$c" ]] && continue 2; done
        CONDS+=("$c")
      done < <(list_subdirs "$BATCH_DIR/$task" judging)
    done
  fi
fi
(( ${#CONDS[@]} > 0 )) || die "no conditions resolved (checked --conditions, conditions.yaml, and the batch tree)"
# Deterministic pair ordering everywhere downstream.
mapfile -t CONDS < <(printf '%s\n' "${CONDS[@]}" | LC_ALL=C sort -u)

# --- Generation-completeness gate --------------------------------------------
# Judging starts only after ALL generation cells are complete (single freeze
# point). A pending-quota or absent cell is a hard error listing every offender.

DEGRADED_CELLS=()

gate_generation_complete() {
  local task cond cell status
  local -a problems=()
  for task in "${TASKS[@]}"; do
    for cond in "${CONDS[@]}"; do
      cell="$(bench_cell_dir "$BATCH_DIR" "$task" "$cond")"
      status="$(bench_meta_status "$cell")"
      if [[ "$status" != "complete" ]]; then
        problems+=("$task/$cond: status=$status")
        continue
      fi
      if [[ ! -s "$cell/final.md" ]]; then
        problems+=("$task/$cond: status=complete but final.md is missing or empty")
        continue
      fi
      if jq -e '.degraded == true' "$cell/meta.json" >/dev/null 2>&1; then
        DEGRADED_CELLS+=("$task/$cond")
      fi
    done
  done

  if (( ${#problems[@]} > 0 )); then
    log "ERROR: judging starts only after ALL generation cells are complete; ${#problems[@]} cell(s) are not:"
    local p
    for p in "${problems[@]}"; do log "  - $p"; done
    log "ERROR: re-run benchmarks/run-benchmark.sh until the batch reports 0 pending cells, then judge."
    exit 1
  fi
}

is_degraded() {
  local key="$1/$2" c
  for c in ${DEGRADED_CELLS[@]+"${DEGRADED_CELLS[@]}"}; do
    [[ "$c" == "$key" ]] && return 0
  done
  return 1
}

# --- Preflight ----------------------------------------------------------------
# Records, per seat: the configured model string, the CLI version, and whether
# the model could be independently verified. Best-effort by design and labeled
# as such: the claude CLI's text-mode path echoes no model, so `configured-only`
# means "the --model argument the CLI was given", nothing stronger. The codex
# path CAN be verified (its run preamble names the model), so it is.

codex_probe_model() {
  local probe="$WORK/preflight-codex"
  local reported=""
  mkdir -p "$probe/cwd"
  cat > "$probe/prompt.md" <<'PROBE'
Preflight check. Respond with ONLY this JSON object and nothing else:
{"model": "<the exact model id you are running as>", "ok": true}
PROBE
  (
    CODEX_MODEL="$JUDGE_MODEL_CODEX"
    CODEX_REASONING_EFFORT="$CODEX_JUDGE_EFFORT"
    WORKDIR="$probe/cwd"
    invoke_codex_schema "$probe/prompt.md" "$probe/out.json" "$probe/stderr.log" "$PREFLIGHT_SCHEMA"
  ) || true

  # The CLI's own preamble is the trustworthy source; the model's self-report is
  # only a fallback. `grep -E` (never `-iF` with a multi-word pattern).
  if [[ -f "$probe/stderr.log" ]]; then
    reported=$(grep -aoE '[Mm]odel:?[[:space:]]+[A-Za-z0-9][A-Za-z0-9._/-]*' "$probe/stderr.log" 2>/dev/null \
      | head -1 | sed -E 's/^[Mm]odel:?[[:space:]]+//') || reported=""
  fi
  if [[ -z "$reported" && -f "$probe/out.json" ]]; then
    reported=$(jq -r '.model // ""' "$probe/out.json" 2>/dev/null) || reported=""
  fi
  printf '%s' "$reported"
}

preflight() {
  local jdir="$BATCH_DIR/judging"
  local pf="$jdir/preflight.json"
  local entries="[]"
  local seat cli model effort version assert reported lr lm
  mkdir -p "$jdir"

  for seat in "${JUDGES[@]}"; do
    cli="$(judge_cli_for "$seat")"
    command -v "$cli" >/dev/null 2>&1 \
      || die "judge seat '$seat' needs the '$cli' CLI on PATH"
    model="$(judge_model_for "$seat")"
    effort="$(judge_effort_for "$seat")"
    assert_concrete_model "$seat" "$model"
    [[ "$seat" != "glm" || -n "${ZAI_API_KEY:-}" ]] \
      || die "judge seat 'glm' requires ZAI_API_KEY (the seat calls the Z.AI API directly)"

    version=$("$cli" --version 2>/dev/null | head -1 | tr -d '\r') || version=""
    [[ -n "$version" ]] || version="unknown"

    assert="configured-only"
    if [[ "$seat" == "codex" ]]; then
      if [[ "$SKIP_PROBE" == true ]]; then
        assert="skipped"
      elif jq -e --arg m "$model" --arg v "$version" \
             '.judges // [] | any(.judge == "codex" and .model == $m and .cli_version == $v and .model_assert == "verified")' \
             "$pf" >/dev/null 2>&1; then
        assert="verified"
        log "INFO: preflight reusing the verified codex model probe from $pf"
      else
        reported="$(codex_probe_model)"
        if [[ -n "$reported" ]]; then
          lr="$(lowercase "$reported")"; lm="$(lowercase "$model")"
          if [[ "$lr" != *"$lm"* && "$lm" != *"$lr"* ]]; then
            die "codex judge preflight: configured model '$model' but the CLI reports '$reported' — refusing to judge with an unverified model"
          fi
          assert="verified"
        else
          assert="unavailable"
          log "WARNING: codex judge preflight could not read a model from the CLI; recording the configured model only."
        fi
      fi
    fi

    entries=$(printf '%s' "$entries" | jq \
      --arg judge "$seat" --arg cmd "$cli" --arg model "$model" \
      --arg effort "$effort" --arg version "$version" --arg assert "$assert" \
      '. += [{judge: $judge, cmd: $cmd, model: $model, effort: $effort,
              cli_version: $version, model_assert: $assert}]')
  done

  jq -S -n \
    --arg schema "bench-judge-preflight/1.0" \
    --arg batch "$BATCH_ID" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg banned_sha "$(sha256_of "$BANNED_FILE")" \
    --arg schema_sha "$(sha256_of "$VERDICT_SCHEMA")" \
    --argjson judges "$entries" \
    '{schema: $schema, batch: $batch, created_at: $created_at,
      banned_tokens_sha256: $banned_sha, verdict_schema_sha256: $schema_sha,
      judges: $judges}' > "$jdir/preflight.json.tmp"
  mv -f "$jdir/preflight.json.tmp" "$pf"

  PREFLIGHT_JSON="$pf"
}

preflight_field() { # $1 = seat, $2 = field
  jq -r --arg j "$1" --arg f "$2" '.judges[] | select(.judge == $j) | .[$f] // ""' "$PREFLIGHT_JSON"
}

# --- Task prompt --------------------------------------------------------------
# The judging prompt embeds the task. A missing task prompt would silently
# change the frozen prompt, so it is fatal rather than skipped.

task_prompt_file() {
  local task="$1" candidate
  local out="$WORK/task-$task.md"

  candidate="$CORPUS_DIR/$task.md"
  if [[ ! -f "$candidate" ]]; then
    # Fallback: the orchestrator writes a short-named copy per bouncer cell.
    candidate=$(find "$BATCH_DIR/$task" -mindepth 2 -maxdepth 2 -name in.md -type f 2>/dev/null | LC_ALL=C sort | head -1)
  fi
  [[ -n "$candidate" && -f "$candidate" ]] \
    || die "no task prompt for '$task' (looked for $CORPUS_DIR/$task.md and <cell>/in.md) — judging refuses to run without the task text"
  _bench_body "$candidate" > "$out"
  [[ -s "$out" ]] || die "task prompt for '$task' is empty after frontmatter stripping: $candidate"
  printf '%s' "$out"
}

# --- Sanitization -------------------------------------------------------------
# Per task: sanitize every eligible cell's final.md, then leak_check it. A hit
# excludes the condition and records a `sanitize-leak` verdict for every pair it
# is part of — never a silent pass, never a silent skip.

ELIGIBLE=()
LEAKY=()
EXCLUDED_JSON="[]"

prepare_task_docs() {
  local task="$1"
  local jdir="$BATCH_DIR/$task/judging"
  local cond cell out rc leak_out stamp want_stamp
  ELIGIBLE=()
  LEAKY=()
  EXCLUDED_JSON="[]"

  mkdir -p "$jdir/sanitized" "$jdir/leaks"

  for cond in "${CONDS[@]}"; do
    cell="$(bench_cell_dir "$BATCH_DIR" "$task" "$cond")"
    if is_degraded "$task" "$cond"; then
      log "INFO: $task/$cond is degraded — excluded from pairing."
      EXCLUDED_JSON=$(printf '%s' "$EXCLUDED_JSON" | jq --arg c "$cond" \
        '. += [{condition: $c, reason: "degraded"}]')
      continue
    fi

    out="$jdir/sanitized/$cond.md"

    # Sanitization + leak check is a pure function of (final.md, banned list),
    # so a stamp of both hashes makes a resume free. This is not an optimization
    # for its own sake: leak_check (benchmarks/lib/sanitize.sh) forks twice per
    # line per banned token, which on Git Bash costs roughly 1.8s per document
    # line — a 4x8 batch re-sanitized from scratch on every resume would spend
    # over an hour before the first judge call.
    stamp="$jdir/sanitized/$cond.stamp"
    want_stamp="$(sha256_of "$cell/final.md") $BANNED_SHA"
    if [[ -s "$out" && -f "$stamp" ]] && [[ "$(head -1 "$stamp")" == "$want_stamp clean" ]]; then
      log "INFO: $task/$cond sanitization cached (clean)."
      ELIGIBLE+=("$cond")
      continue
    fi
    if [[ -s "$out" && -f "$stamp" ]] && [[ "$(head -1 "$stamp")" == "$want_stamp leak" ]]; then
      log "WARNING: $task/$cond sanitization cached (leak) — still excluded from judging."
      LEAKY+=("$cond")
      EXCLUDED_JSON=$(printf '%s' "$EXCLUDED_JSON" | jq --arg c "$cond" --arg d "$jdir/leaks/$cond.txt" \
        '. += [{condition: $c, reason: "sanitize-leak", detail: $d}]')
      continue
    fi

    rm -f "$stamp"
    sanitize_doc "$cell/final.md" "$out"

    rc=0
    leak_out=$(leak_check "$out" "$BANNED_FILE") || rc=$?
    if (( rc != 0 )); then
      printf '%s leak\n' "$want_stamp" > "$stamp"
      printf '%s\n' "$leak_out" > "$jdir/leaks/$cond.txt"
      log "WARNING: $task/$cond leaked banned tokens after sanitization — excluded from judging (see $jdir/leaks/$cond.txt)."
      LEAKY+=("$cond")
      EXCLUDED_JSON=$(printf '%s' "$EXCLUDED_JSON" | jq --arg c "$cond" --arg d "$jdir/leaks/$cond.txt" \
        '. += [{condition: $c, reason: "sanitize-leak", detail: $d}]')
      continue
    fi
    rm -f "$jdir/leaks/$cond.txt"
    printf '%s clean\n' "$want_stamp" > "$stamp"
    ELIGIBLE+=("$cond")
  done

  jq -S -n \
    --arg schema "bench-judge-excluded/1.0" \
    --arg task "$task" \
    --argjson excluded "$EXCLUDED_JSON" \
    '{schema: $schema, task_id: $task, excluded: $excluded}' > "$jdir/excluded.json.tmp"
  mv -f "$jdir/excluded.json.tmp" "$jdir/excluded.json"
}

is_leaky() {
  local c
  for c in ${LEAKY[@]+"${LEAKY[@]}"}; do [[ "$c" == "$1" ]] && return 0; done
  return 1
}

# --- Judging prompt -----------------------------------------------------------
# Adapted from evals/judge-bounce.sh's trial prompt (via judge-lib's
# judge_build_trial_prompt) to the cross-condition framing: two plans written
# INDEPENDENTLY for the same task, not two versions of one document. The
# strict-JSON contract, the 1-3 reasons / 1-3 evidence rule, and the
# verbatim-quote requirement are unchanged so the same decode and verification
# helpers apply.
bench_build_pair_prompt() {
  local task_file="$1" doc_a="$2" doc_b="$3" prompt_file="$4"

  cat > "$prompt_file" <<PROMPT
You are evaluating two anonymous plans written independently in response to the
same task. You do not know who wrote either plan or in what order they were
written. Judge which plan is BETTER as a plan for this task: clearer, more
complete, better-argued, more actionable — not merely longer or shorter.

Respond with ONLY a JSON object, no markdown fences, no commentary:
{
  "better": "A" | "B" | "tie",
  "confidence": "low" | "medium" | "high",
  "reasons": ["<short reason>", ...],
  "evidence": [
    {"doc": "A" | "B", "quote": "<verbatim quote of 5-25 words from that plan supporting your judgment>"}
  ]
}
Rules: 1-3 reasons; 1-3 evidence entries; every quote must be copied
verbatim from the named plan.

## Task

$(cat "$task_file")

## Plan A

$(cat "$doc_a")

## Plan B

$(cat "$doc_b")
PROMPT
}

# --- Verdict parsing ----------------------------------------------------------
# Parallel of judge_invoke_trial's accept-raw-or-fenced step (judge-lib.sh:94-101),
# factored out so the codex and glm seats — which cannot use judge_invoke_trial's
# hardcoded claude argv — behave identically to the fable seat.
bench_parse_verdict() {
  local raw="$1" out="$2"
  if jq -e '.better and .confidence' "$raw" >/dev/null 2>&1; then
    cp "$raw" "$out"; return 0
  fi
  sed -n '/^{/,/^}/p' "$raw" > "$WORK/trial-extract.json" || true
  if jq -e '.better and .confidence' "$WORK/trial-extract.json" >/dev/null 2>&1; then
    cp "$WORK/trial-extract.json" "$out"; return 0
  fi
  return 1
}

bench_invoke_codex_trial() {
  local prompt_file="$1" out="$2"
  local raw="$WORK/codex-raw.json" errf="$WORK/codex-stderr.log"
  local attempt
  for attempt in 1 2; do
    : > "$raw"; : > "$errf"
    (
      CODEX_MODEL="$JUDGE_MODEL_CODEX"
      CODEX_REASONING_EFFORT="$CODEX_JUDGE_EFFORT"
      WORKDIR="$WORK/codex-cwd"
      invoke_codex_schema "$prompt_file" "$raw" "$errf" "$VERDICT_SCHEMA"
    ) || true
    if file_contains_auth_failure "$raw" || file_contains_auth_failure "$errf"; then
      log "ERROR: codex judge CLI is not authenticated — run \`codex\` interactively to log in, then re-run."
      return 1
    fi
    bench_parse_verdict "$raw" "$out" && return 0
    log "WARNING: codex judge returned unparseable output (attempt $attempt)"
  done
  return 1
}

bench_invoke_glm_trial() {
  local prompt_file="$1" out="$2"
  local raw="$WORK/glm-raw.txt" errf="$WORK/glm-stderr.log"
  local attempt
  for attempt in 1 2; do
    : > "$raw"; : > "$errf"
    (
      GLM_MODEL="$JUDGE_MODEL_GLM"
      invoke_glm "$prompt_file" "$raw" "$errf" false
    ) || true
    if file_contains_auth_failure "$raw" || file_contains_auth_failure "$errf"; then
      log "ERROR: glm judge (direct Z.AI API) is not authenticated — check ZAI_API_KEY, then re-run."
      return 1
    fi
    bench_parse_verdict "$raw" "$out" && return 0
    log "WARNING: glm judge returned unparseable output (attempt $attempt)"
  done
  return 1
}

# bench_run_seat_trial SEAT PROMPT OUT → 0 verdict written, 1 seat failure.
bench_run_seat_trial() {
  local seat="$1" prompt_file="$2" out="$3"
  case "$seat" in
    fable)
      JUDGE_CMD="claude"
      JUDGE_ARGS=(--model "$JUDGE_MODEL_FABLE")
      [[ -n "$JUDGE_EFFORT" ]] && JUDGE_ARGS+=(--effort "$JUDGE_EFFORT")
      judge_invoke_trial "$prompt_file" "$out" ;;
    codex) bench_invoke_codex_trial "$prompt_file" "$out" ;;
    glm)   bench_invoke_glm_trial "$prompt_file" "$out" ;;
    *) die "unknown judge seat '$seat'" ;;
  esac
}

# --- Verdict files ------------------------------------------------------------

verdict_path() { printf '%s/%s/judging/%s/%s__vs__%s.json' "$BATCH_DIR" "$1" "$2" "$3" "$4"; }

verdict_is_valid() {
  jq -e '.schema == "bench-pair/1.0" and (.verdict | type == "string") and (.verdict | length > 0)' \
    "$1" >/dev/null 2>&1
}

write_verdict() { # $1=path $2=json
  local dir; dir="$(dirname "$1")"
  mkdir -p "$dir"
  printf '%s' "$2" | jq -S . > "$1.tmp" || die "could not render verdict $1"
  mv -f "$1.tmp" "$1"
}

write_leak_verdict() { # task seat x y
  local task="$1" seat="$2" x="$3" y="$4"
  local out; out="$(verdict_path "$task" "$seat" "$x" "$y")"
  local leaked="" json
  is_leaky "$x" && leaked="$x"
  is_leaky "$y" && leaked="${leaked:+$leaked }$y"

  json=$(jq -n \
    --arg schema "bench-pair/1.0" --arg task "$task" --arg x "$x" --arg y "$y" \
    --arg verdict "sanitize-leak" --arg judge "$seat" \
    --arg judge_model "$(preflight_field "$seat" model)" \
    --arg cli_version "$(preflight_field "$seat" cli_version)" \
    --arg judged_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg leaked "$leaked" \
    '{schema: $schema, task_id: $task, cond_x: $x, cond_y: $y, verdict: $verdict,
      confidence_pair: "none", evidence_verified: false, trials: [], evidence: [],
      judge: $judge, judge_model: $judge_model, cli_version: $cli_version,
      prompt_sha256: "", judged_at: $judged_at, doc_words: {x: null, y: null},
      leaked_conditions: $leaked}')
  write_verdict "$out" "$json"
  log "WARNING: $task $seat $x vs $y -> sanitize-leak (leaked: $leaked); the pair was never sent to a judge."
}

# --- One judged pair ----------------------------------------------------------
# Returns 0 when a verdict file exists afterwards (written or already present),
# 1 when the judge seat failed and nothing was recorded.
judge_pair() {
  local task="$1" seat="$2" x="$3" y="$4" task_file="$5"
  local jdir="$BATCH_DIR/$task/judging"
  local out; out="$(verdict_path "$task" "$seat" "$x" "$y")"
  local doc_x="$jdir/sanitized/$x.md" doc_y="$jdir/sanitized/$y.md"
  local t1 t2 verdict conf1 conf2 conf_pair prompt_sha
  local norm_x norm_y

  if [[ -f "$out" ]] && verdict_is_valid "$out"; then
    log "INFO: $task $seat $x vs $y — verdict already present, skipping."
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  log "INFO: $task $seat $x vs $y — trial 1/2 ($x=A)"
  bench_build_pair_prompt "$task_file" "$doc_x" "$doc_y" "$WORK/pair-prompt-1.md"
  prompt_sha="$(sha256_of "$WORK/pair-prompt-1.md")"
  if ! bench_run_seat_trial "$seat" "$WORK/pair-prompt-1.md" "$WORK/pair-t1.json"; then
    return 1
  fi

  log "INFO: $task $seat $x vs $y — trial 2/2 ($y=A)"
  bench_build_pair_prompt "$task_file" "$doc_y" "$doc_x" "$WORK/pair-prompt-2.md"
  if ! bench_run_seat_trial "$seat" "$WORK/pair-prompt-2.md" "$WORK/pair-t2.json"; then
    return 1
  fi

  # Decode positions back to condition ids. Trial 1: A=x B=y. Trial 2: A=y B=x.
  decode_trial() { # $1=trial file $2=A-meaning $3=B-meaning
    local b; b=$(jq -r '.better // "tie"' "$1")
    case "$b" in A) printf '%s' "$2" ;; B) printf '%s' "$3" ;; *) printf 'tie' ;; esac
  }
  t1="$(decode_trial "$WORK/pair-t1.json" "$x" "$y")"
  t2="$(decode_trial "$WORK/pair-t2.json" "$y" "$x")"

  if [[ "$t1" == "$t2" ]]; then
    case "$t1" in
      "$x") verdict="x" ;;
      "$y") verdict="y" ;;
      *)    verdict="tie" ;;
    esac
  else
    verdict="position_biased"
  fi

  # Evidence verification against the SANITIZED documents the judge actually saw.
  norm_x="$(judge_norm "$doc_x")"
  norm_y="$(judge_norm "$doc_y")"
  judge_reset_evidence_state
  judge_check_trial_evidence "$WORK/pair-t1.json" "$norm_x" "$norm_y" 1
  judge_check_trial_evidence "$WORK/pair-t2.json" "$norm_y" "$norm_x" 2
  if (( EVIDENCE_TOTAL > 0 && EVIDENCE_FAILED * 2 > EVIDENCE_TOTAL )) && [[ "$verdict" != "position_biased" ]]; then
    verdict="invalid-evidence"
  fi

  conf1=$(jq -r '.confidence // "unknown"' "$WORK/pair-t1.json")
  conf2=$(jq -r '.confidence // "unknown"' "$WORK/pair-t2.json")
  conf_pair="mixed"
  [[ "$conf1" == "$conf2" ]] && conf_pair="$conf1"

  local json
  json=$(jq -n \
    --arg schema "bench-pair/1.0" --arg task "$task" --arg x "$x" --arg y "$y" \
    --arg verdict "$verdict" --arg conf "$conf_pair" --arg judge "$seat" \
    --arg judge_model "$(preflight_field "$seat" model)" \
    --arg cli_version "$(preflight_field "$seat" cli_version)" \
    --arg prompt_sha "$prompt_sha" \
    --arg judged_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson wx "$(file_words "$doc_x")" --argjson wy "$(file_words "$doc_y")" \
    --argjson evidence_verified "$([[ "$EVIDENCE_OK" == true ]] && echo true || echo false)" \
    --argjson t1raw "$(cat "$WORK/pair-t1.json")" \
    --argjson t2raw "$(cat "$WORK/pair-t2.json")" \
    --argjson evidence "$VERIFIED_EVIDENCE" \
    '{schema: $schema, task_id: $task, cond_x: $x, cond_y: $y, verdict: $verdict,
      confidence_pair: $conf, evidence_verified: $evidence_verified,
      trials: [{order: ($x + "=A " + $y + "=B"), raw: $t1raw},
               {order: ($y + "=A " + $x + "=B"), raw: $t2raw}],
      evidence: $evidence, judge: $judge, judge_model: $judge_model,
      cli_version: $cli_version, prompt_sha256: $prompt_sha, judged_at: $judged_at,
      doc_words: {x: $wx, y: $wy}}')
  write_verdict "$out" "$json"
  log "INFO: $task $seat $x vs $y -> $verdict"
  JUDGED=$((JUDGED + 1))
  return 0
}

# --- Main ---------------------------------------------------------------------

BANNED_SHA="$(sha256_of "$BANNED_FILE")"

log "INFO: judging batch $BATCH_ID — tasks: ${TASKS[*]} | conditions: ${CONDS[*]} | judges: ${JUDGES[*]}"

gate_generation_complete
preflight

JUDGED=0
SKIPPED=0
LEAK_PAIRS=0
UNJUDGED=0
FAILURES=()
for seat in "${JUDGES[@]}"; do FAILURES+=("0"); done

seat_index() {
  local i=0 s
  for s in "${JUDGES[@]}"; do
    [[ "$s" == "$1" ]] && { printf '%s' "$i"; return 0; }
    i=$((i + 1))
  done
  printf '%s' "0"
}

for task in "${TASKS[@]}"; do
  prepare_task_docs "$task"

  # Pair universe = every non-degraded condition (leaky ones included, so their
  # pairs are recorded as sanitize-leak rather than vanishing).
  PAIRABLE=()
  for cond in "${CONDS[@]}"; do
    is_degraded "$task" "$cond" && continue
    PAIRABLE+=("$cond")
  done
  if (( ${#PAIRABLE[@]} < 2 )); then
    log "WARNING: $task has ${#PAIRABLE[@]} non-degraded condition(s) — no pairs to judge."
    continue
  fi

  TASK_FILE="$(task_prompt_file "$task")"

  n=${#PAIRABLE[@]}
  for (( i = 0; i < n - 1; i++ )); do
    for (( j = i + 1; j < n; j++ )); do
      x="${PAIRABLE[$i]}"; y="${PAIRABLE[$j]}"
      if is_leaky "$x" || is_leaky "$y"; then
        for seat in "${JUDGES[@]}"; do
          out="$(verdict_path "$task" "$seat" "$x" "$y")"
          if [[ -f "$out" ]] && verdict_is_valid "$out"; then continue; fi
          write_leak_verdict "$task" "$seat" "$x" "$y"
          LEAK_PAIRS=$((LEAK_PAIRS + 1))
        done
        continue
      fi

      for seat in "${JUDGES[@]}"; do
        if ! judge_pair "$task" "$seat" "$x" "$y" "$TASK_FILE"; then
          idx="$(seat_index "$seat")"
          FAILURES[$idx]=$(( ${FAILURES[$idx]} + 1 ))
          # A seat failure abandons the whole pair and moves on; a later re-run
          # resumes it. Verdicts already written by earlier seats stay valid.
          UNJUDGED=$((UNJUDGED + 1))
          log "WARNING: $task $x vs $y — $seat failed; abandoning this pair for now."
          break
        fi
      done
    done
  done
done

# --- Summary ------------------------------------------------------------------

log ""
log "judge-matrix summary (batch $BATCH_ID)"
log "  pairs judged this run : $JUDGED"
log "  pairs already judged  : $SKIPPED"
log "  sanitize-leak pairs   : $LEAK_PAIRS"
log "  pairs left unjudged   : $UNJUDGED"
i=0
for seat in "${JUDGES[@]}"; do
  log "  $seat failures        : ${FAILURES[$i]}"
  i=$((i + 1))
done

if (( UNJUDGED > 0 )); then
  log "INFO: $UNJUDGED pair(s) still unjudged — re-run this command to resume (exit $EXIT_RETRYABLE)."
  exit "$EXIT_RETRYABLE"
fi
log "INFO: every requested pair has a verdict file."
