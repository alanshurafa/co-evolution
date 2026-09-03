#!/usr/bin/env bash

CODE_BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODE_BENCH_REPO_ROOT="$(cd "$CODE_BENCH_DIR/../.." && pwd)"
CODE_BENCH_RESULTS_ROOT="${CODE_BENCH_RESULTS_ROOT:-$CODE_BENCH_REPO_ROOT/benchmarks/results/code}"

code_die() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}

code_require() {
  command -v "$1" >/dev/null 2>&1 || code_die "$1 is required"
}

# Which suite the commands operate on. The canary stays the default so every
# existing invocation keeps working; a larger suite is opt-in per command.
code_suite_id() {
  printf '%s' "${CODE_BENCH_SUITE:-swebench-verified-canary}"
}

# A model tier is a complete, named configuration of the primary seats, not a
# single knob. Changing a model without changing the label it runs under is how
# two incomparable runs end up in one table, so the tier is validated here,
# recorded in every cell manifest, and rendered on the page.
#
# GLM and Kimi are deliberately held constant across tiers. They are the same
# model in every tier, which makes the critic seats a fixed reference point and
# leaves the tier to vary only the two seats that have a cheaper sibling.
code_model_tier() {
  printf '%s' "${CODE_BENCH_MODEL_TIER:-frontier}"
}

code_tier_is_valid() {
  case "$1" in frontier|max|light) return 0 ;; *) return 1 ;; esac
}

# Sets CODE_BENCH_CLAUDE_MODEL/EFFORT and CODE_BENCH_CODEX_MODEL/EFFORT for the
# named tier, leaving any value the caller set explicitly alone: a deliberate
# one-off override must survive a tier selection.
code_apply_model_tier() {
  local tier="$1" claude_model claude_effort codex_model codex_effort
  case "$tier" in
    frontier)
      claude_model=fable;  claude_effort=medium
      codex_model=gpt-5.6-sol;   codex_effort=medium ;;
    max)
      claude_model=fable;  claude_effort=high
      codex_model=gpt-5.6-sol;   codex_effort=xhigh ;;
    light)
      # Sonnet's own default effort; the CLI picks it when none is passed.
      claude_model=sonnet; claude_effort=""
      codex_model=gpt-5.6-terra; codex_effort=medium ;;
    *) code_die "unknown model tier: $tier"; return 1 ;;
  esac
  export CODE_BENCH_MODEL_TIER="$tier"
  export CODE_BENCH_CLAUDE_MODEL="${CODE_BENCH_CLAUDE_MODEL:-$claude_model}"
  export CODE_BENCH_CODEX_MODEL="${CODE_BENCH_CODEX_MODEL:-$codex_model}"
  export CODE_BENCH_CODEX_EFFORT="${CODE_BENCH_CODEX_EFFORT:-$codex_effort}"
  # Assigned with "-" rather than ":-" so a tier can select an empty effort and
  # have it stick. An empty value is the instruction to omit --effort entirely
  # and let the model use its own default; ":-" would silently fall back to the
  # driver's medium and the manifest would then record an effort never asked for.
  export CODE_BENCH_CLAUDE_EFFORT="${CODE_BENCH_CLAUDE_EFFORT-$claude_effort}"
}

code_metadata_path() {
  printf '%s/metadata/%s.json' "$CODE_BENCH_RESULTS_ROOT" "$(code_suite_id)"
}

code_suite_json() {
  local suite="$1"
  jq -ce --arg id "$suite" '.suites[] | select(.id == $id)' "$CODE_BENCH_DIR/suites.json"
}

code_subset_path() {
  local suite_json="$1" rel
  rel=$(printf '%s' "$suite_json" | jq -r '.subset_file' | tr -d '\r')
  printf '%s/%s' "$CODE_BENCH_DIR" "$rel"
}

code_check_manifests() {
  local failures=0 suite_json subset count declared
  code_require jq || return 1

  jq -e '.schema == "code-bench-conditions/1.0" and
         (.conditions | length > 0) and
         ([.conditions[].id] | length == (unique | length)) and
         (all(.conditions[]; (.dispatches | keys) == ["claude","codex","glm","kimi"])) and
         (all(.conditions[]; (.label | type == "string" and length > 0))) and
         (all(.conditions[]; .tier == "agentic" or .tier == "single-shot")) and
         ([.conditions[].dispatches[] | type == "number" and . >= 0 and floor == .] | all)' \
    "$CODE_BENCH_DIR/conditions.json" >/dev/null || {
      printf 'CHECK FAIL: conditions.json\n' >&2; failures=$((failures + 1));
    }
  jq -e '.schema == "code-bench-suites/1.0" and
         (.suites | length > 0) and
         ([.suites[].id] | length == (unique | length))' \
    "$CODE_BENCH_DIR/suites.json" >/dev/null || {
      printf 'CHECK FAIL: suites.json\n' >&2; failures=$((failures + 1));
    }
  jq -e '.schema == "code-bench-external-lock/1.0" and
         (.swebench.commit | test("^[0-9a-f]{40}$")) and
         (.dataset.revision | test("^[0-9a-f]{40}$")) and
         (.compatibility_patches | type == "array" and length > 0) and
         (all(.compatibility_patches[]; test("^patches/[A-Za-z0-9._-]+[.]patch$")))' \
    "$CODE_BENCH_DIR/external-sources.lock.json" >/dev/null || {
      printf 'CHECK FAIL: external-sources.lock.json\n' >&2; failures=$((failures + 1));
    }
  while IFS= read -r patch_rel; do
    [[ -f "$CODE_BENCH_DIR/$patch_rel" ]] || {
      printf 'CHECK FAIL: compatibility patch missing: %s\n' "$patch_rel" >&2
      failures=$((failures + 1))
    }
  done < <(jq -r '.compatibility_patches[]' "$CODE_BENCH_DIR/external-sources.lock.json" | tr -d '\r')

  while IFS= read -r suite_json; do
    subset=$(code_subset_path "$suite_json")
    declared=$(printf '%s' "$suite_json" | jq -r '.task_count' | tr -d '\r')
    if [[ ! -f "$subset" ]]; then
      printf 'CHECK FAIL: subset missing: %s\n' "$subset" >&2
      failures=$((failures + 1)); continue
    fi
    if ! jq -e '.schema == "code-bench-subset/1.0" and
                (.instances | length > 0) and
                ([.instances[].instance_id] | length == (unique | length))' "$subset" >/dev/null; then
      printf 'CHECK FAIL: malformed or duplicate subset entries: %s\n' "$subset" >&2
      failures=$((failures + 1)); continue
    fi
    if printf '%s' "$suite_json" | jq -e '.require_unique_repos == true' >/dev/null 2>&1; then
      if ! jq -e '[.instances[].repo] | length == (unique | length)' "$subset" >/dev/null; then
        printf 'CHECK FAIL: suite requires one task per repository: %s\n' "$subset" >&2
        failures=$((failures + 1)); continue
      fi
    fi
    count=$(jq '.instances | length' "$subset" | tr -d '\r')
    if [[ "$count" != "$declared" ]]; then
      printf 'CHECK FAIL: suite declares %s tasks but subset contains %s: %s\n' "$declared" "$count" "$subset" >&2
      failures=$((failures + 1))
    fi
    while IFS= read -r condition; do
      jq -e --arg id "$condition" 'any(.conditions[]; .id == $id)' \
        "$CODE_BENCH_DIR/conditions.json" >/dev/null || {
          printf 'CHECK FAIL: suite references unknown condition %s\n' "$condition" >&2
          failures=$((failures + 1))
        }
    done < <(printf '%s' "$suite_json" | jq -r '.default_conditions[]' | tr -d '\r')
  done < <(jq -c '.suites[]' "$CODE_BENCH_DIR/suites.json")

  (( failures == 0 )) || return 1
  printf 'CHECK: code benchmark manifests PASS\n'
}

# Codex 0.144.5 on Windows degrades `--sandbox workspace-write` to read-only,
# so the write phases refuse every edit and a repair arm silently goes inert.
# The mode is a treatment-relevant fact, so it is a gated variable rather than
# a constant: elevated access is acceptable only because benchmark workspaces
# are disposable clones under the ignored results tree.
code_codex_sandbox() {
  local mode="${CODE_BENCH_CODEX_SANDBOX:-workspace-write}"
  case "$mode" in
    read-only|workspace-write|danger-full-access) ;;
    *) code_die "CODE_BENCH_CODEX_SANDBOX must be read-only, workspace-write, or danger-full-access"; return 1 ;;
  esac
  printf '%s' "$mode"
}

# Reads one key from the seat env file without ever echoing its value. Honours
# CO_EVOLVE_ENV_FILE so a test can point at a fixture instead of the real file.
code_load_env_key() {
  local name="$1" env_file line value
  env_file="${CO_EVOLVE_ENV_FILE:-$CODE_BENCH_REPO_ROOT/.env.local}"
  [[ -z "${!name:-}" && -r "$env_file" ]] || return 0
  line=$(grep -m 1 -E "^[[:space:]]*(export[[:space:]]+)?${name}[[:space:]]*=" "$env_file" 2>/dev/null || true)
  [[ -n "$line" ]] || return 0
  value=$(printf '%s' "$line" | sed -e 's/^[^=]*=//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  case "$value" in
    \"*\") value="${value#\"}"; value="${value%\"}" ;;
    \'*\') value="${value#\'}"; value="${value%\'}" ;;
  esac
  [[ -n "$value" ]] && printf -v "$name" '%s' "$value"
}

# The bounce conditions differ only in how many critics they run, so the repair
# prompt takes however many reviews were produced: three for the full panel, one
# for a single-critic bounce. Reviews stay anonymous and numbered so the
# repairing agent weighs each finding on merit rather than on its author.
code_write_repair_prompt() {
  local out="$1" task_file="$2"
  shift 2
  local review number=0
  (( $# > 0 )) || { code_die "code_write_repair_prompt needs at least one review"; return 1; }
  {
    if (( $# == 1 )); then
      printf '%s\n' "Re-open the current implementation and evaluate the anonymous review below. Decide every finding on its merits, repair accepted issues, and run relevant tests. Do not commit."
    else
      printf 'Re-open the current implementation and evaluate the %s anonymous reviews below. Decide every finding on its merits, repair accepted issues, and run relevant tests. Do not commit.\n' "$#"
    fi
    printf '\n## ISSUE\n\n'
    cat "$task_file"
    for review in "$@"; do
      number=$((number + 1))
      printf '\n## REVIEWER %s\n\n' "$number"
      head -c 40000 "$review"
      printf '\n'
    done
  } > "$out"
}

# Two orchestrators once appended to the same status file and the resulting
# timeline described neither run. A status file now belongs to exactly one
# writer: the owner is recorded on creation, every line carries writer=, and a
# second writer is refused instead of interleaving.
code_status_init() {
  local file="$1" writer="$2"
  [[ -n "$file" && -n "$writer" ]] || { code_die "code_status_init needs FILE WRITER"; return 1; }
  [[ "$writer" =~ ^[A-Za-z0-9._-]+$ ]] || { code_die "writer id must be filesystem-safe: $writer"; return 1; }
  mkdir -p "$(dirname "$file")"
  if [[ -f "$file.writer" ]] && [[ "$(cat "$file.writer")" != "$writer" ]]; then
    code_die "status file $file already belongs to writer $(cat "$file.writer"); use your own file"
    return 1
  fi
  printf '%s' "$writer" > "$file.writer"
  printf 'writer=%s state=running started=%s\n' "$writer" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$file"
}

code_status_append() {
  local file="$1" writer="$2"; shift 2
  [[ -f "$file.writer" ]] || { code_die "status file $file has no owner; call code_status_init first"; return 1; }
  [[ "$(cat "$file.writer")" == "$writer" ]] \
    || { code_die "writer $writer may not append to $file (owner $(cat "$file.writer"))"; return 1; }
  printf 'writer=%s at=%s %s\n' "$writer" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$file"
}
