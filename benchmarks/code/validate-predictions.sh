#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/code-bench-lib.sh
source "$SCRIPT_DIR/lib/code-bench-lib.sh"

PREDICTIONS="${1:-}"
SUITE="${2:-swebench-verified-canary}"
[[ -n "$PREDICTIONS" && -f "$PREDICTIONS" ]] || { code_die "usage: validate-predictions.sh FILE [SUITE]"; exit 2; }

suite_json=$(code_suite_json "$SUITE") || { code_die "unknown suite: $SUITE"; exit 1; }
subset=$(code_subset_path "$suite_json")
seen=$(mktemp -t code-bench-seen-XXXXXX)
trap 'rm -f "$seen"' EXIT
line_no=0
records=0

while IFS= read -r line || [[ -n "$line" ]]; do
  line_no=$((line_no + 1))
  [[ -n "${line//[[:space:]]/}" ]] || continue
  if ! printf '%s' "$line" | jq -e '
      type == "object" and
      (.instance_id | type == "string" and length > 0) and
      (.model_name_or_path | type == "string" and length > 0) and
      (.model_patch | type == "string" and startswith("diff --git "))
    ' >/dev/null 2>&1; then
    code_die "invalid prediction record at line $line_no"; exit 1
  fi
  instance=$(printf '%s' "$line" | jq -r '.instance_id' | tr -d '\r')
  jq -e --arg id "$instance" '.instances[] | select(.instance_id == $id)' "$subset" >/dev/null \
    || { code_die "prediction line $line_no names an instance outside suite $SUITE: $instance"; exit 1; }
  if grep -qxF "$instance" "$seen"; then
    code_die "duplicate prediction for $instance"; exit 1
  fi
  printf '%s\n' "$instance" >> "$seen"
  records=$((records + 1))
done < "$PREDICTIONS"

(( records > 0 )) || { code_die "prediction file contains no records"; exit 1; }
printf 'VALID: %s prediction record(s) for %s\n' "$records" "$SUITE"
