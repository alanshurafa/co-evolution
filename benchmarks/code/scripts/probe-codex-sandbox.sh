#!/usr/bin/env bash
# Can this host's Codex write inside a disposable workspace under the sandbox
# mode the harness defaults to?
#
# Codex 0.144.5 on Windows accepted `--sandbox workspace-write` and then ran
# read-only, so every repair arm went inert while still producing a review.
# The harness works around that with danger-full-access inside throwaway
# clones, and the workaround is a caveat on every published row. This probe
# is how the caveat gets removed: run it after a Codex upgrade, and if
# workspace-write writes, the default mode is safe again on this host.
#
# One tiny model call per mode probed (a one-line edit), so it is not free;
# it is never run by the test suite, which exercises it with a stub instead.
#
#   bash benchmarks/code/code-bench.sh probe-codex-sandbox            # workspace-write only
#   bash benchmarks/code/code-bench.sh probe-codex-sandbox --all      # then danger-full-access
#
# Writes probe-<mode>.json next to the logs under results/code/probes/ with
# the Codex version, the mode asked for, the mode Codex reported, and whether
# the file changed, so the manifest of a later run can cite it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/code-bench-lib.sh
source "$CODE_DIR/lib/code-bench-lib.sh"

PROBES="${CODE_BENCH_PROBE_DIR:-$CODE_BENCH_RESULTS_ROOT/probes}"
MODEL="${CODE_BENCH_CODEX_MODEL:-gpt-5.6-sol}"
EFFORT="${CODE_BENCH_CODEX_EFFORT:-medium}"
ALL=false
MODES=()
while (( $# > 0 )); do
  case "$1" in
    --all) ALL=true; shift ;;
    --mode) MODES+=("${2:?--mode needs a sandbox mode}"); shift 2 ;;
    *) code_die "unknown probe option: $1"; exit 2 ;;
  esac
done
if (( ${#MODES[@]} == 0 )); then
  MODES=(workspace-write)
  [[ "$ALL" == true ]] && MODES+=(danger-full-access)
fi
command -v codex >/dev/null 2>&1 || { code_die "codex CLI is required"; exit 1; }
mkdir -p "$PROBES"
version=$(codex --version 2>/dev/null </dev/null | head -1 | tr -d '\r')

probe_one() {
  local mode="$1"
  local ws="$PROBES/ws-$mode"
  rm -rf "$ws"; mkdir -p "$ws"
  git -C "$ws" init -q
  printf 'ORIGINAL\n' > "$ws/probe.txt"
  git -C "$ws" add probe.txt >/dev/null 2>&1
  git -C "$ws" -c user.email=b@e -c user.name=b commit -qm seed --no-gpg-sign >/dev/null 2>&1
  printf 'Edit probe.txt in the current working directory so its only line reads PATCHED. Use your file-write tool. Do not commit.\n' \
    > "$PROBES/prompt-$mode.md"
  local -a cmd=(codex exec -C "$ws" -m "$MODEL" --sandbox "$mode"
    --ephemeral --ignore-user-config -c approval_policy="never"
    -c model_reasoning_effort="$EFFORT" -)
  command -v timeout >/dev/null 2>&1 && cmd=(timeout --foreground 300s "${cmd[@]}")
  "${cmd[@]}" < "$PROBES/prompt-$mode.md" > "$PROBES/$mode.log" 2> "$PROBES/$mode.stderr.log"
  local rc=$?
  local content reported
  content=$(cat "$ws/probe.txt" 2>/dev/null || echo MISSING)
  # Codex prints the mode it actually runs under in its stderr banner; the
  # gap between the mode asked for and the mode reported is the whole bug.
  reported=$(grep -m1 -E '^sandbox:' "$PROBES/$mode.stderr.log" 2>/dev/null | sed 's/^sandbox:[[:space:]]*//' | tr -d '\r')
  local wrote=false
  [[ "$content" == "PATCHED" ]] && wrote=true
  jq -n --arg version "$version" --arg asked "$mode" --arg reported "${reported:-unknown}" \
    --argjson wrote "$wrote" --argjson rc "$rc" --arg host "$(uname -s 2>/dev/null || echo unknown)" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema:"code-bench-codex-probe/1.0",codex_version:$version,host:$host,probed_at:$at,
      sandbox_asked:$asked,sandbox_reported:$reported,wrote:$wrote,exit_code:$rc}' \
    > "$PROBES/probe-$mode.json"
  if [[ "$wrote" == true ]]; then
    printf 'PROBE %s: WRITE_OK codex=%s reported=%s\n' "$mode" "$version" "${reported:-unknown}"
    return 0
  fi
  printf 'PROBE %s: WRITE_FAILED codex=%s reported=%s content=%s rc=%s\n' \
    "$mode" "$version" "${reported:-unknown}" "$content" "$rc"
  return 1
}

status=1
for mode in "${MODES[@]}"; do
  code_codex_sandbox >/dev/null 2>&1 || true
  case "$mode" in read-only|workspace-write|danger-full-access) ;; *) code_die "unknown sandbox mode: $mode"; exit 2 ;; esac
  if probe_one "$mode"; then status=0; break; fi
done
exit "$status"
