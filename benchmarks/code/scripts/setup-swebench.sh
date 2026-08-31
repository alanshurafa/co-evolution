#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/code-bench-lib.sh
source "$CODE_DIR/lib/code-bench-lib.sh"

MODE="${1:---check}"
CACHE="$CODE_BENCH_RESULTS_ROOT/.cache"
REPO="$CACHE/SWE-bench"
VENV="$CACHE/venv"
LOCK="$CODE_DIR/external-sources.lock.json"
SHA=$(jq -r '.swebench.commit' "$LOCK" | tr -d '\r')
URL=$(jq -r '.swebench.repository' "$LOCK" | tr -d '\r')

python_path() {
  if [[ -x "$VENV/Scripts/python.exe" ]]; then printf '%s' "$VENV/Scripts/python.exe"; else printf '%s' "$VENV/bin/python"; fi
}

cli_path() {
  if [[ -x "$VENV/Scripts/swebench.exe" ]]; then printf '%s' "$VENV/Scripts/swebench.exe"; else printf '%s' "$VENV/bin/swebench"; fi
}

check_state() {
  local failed=0
  for tool in git uv docker jq; do
    if command -v "$tool" >/dev/null 2>&1; then printf '%s=present\n' "$tool"; else printf '%s=missing\n' "$tool"; failed=1; fi
  done
  if command -v timeout >/dev/null 2>&1; then
    timeout 10 docker info >/dev/null 2>&1 && engine_ready=true || engine_ready=false
  else
    docker info >/dev/null 2>&1 && engine_ready=true || engine_ready=false
  fi
  if [[ "$engine_ready" == true ]]; then printf 'docker_engine=ready\n'; else printf 'docker_engine=unavailable\n'; failed=1; fi
  if [[ -d "$REPO/.git" && "$(git -C "$REPO" rev-parse HEAD 2>/dev/null)" == "$SHA" ]]; then
    printf 'swebench_source=pinned\n'
  else
    printf 'swebench_source=not-installed\n'; failed=1
  fi
  if [[ -x "$(cli_path)" ]]; then printf 'swebench_cli=ready\n'; else printf 'swebench_cli=not-installed\n'; failed=1; fi
  return "$failed"
}

case "$MODE" in
  --check)
    check_state
    ;;
  --install)
    code_require git; code_require uv; code_require jq
    mkdir -p "$CACHE"
    if [[ ! -d "$REPO/.git" ]]; then
      git clone --filter=blob:none --no-checkout "$URL" "$REPO"
    fi
    git -C "$REPO" fetch --depth 1 origin "$SHA"
    git -C "$REPO" checkout --detach "$SHA"
    if [[ ! -x "$(python_path)" ]]; then
      uv venv --python 3.11 "$VENV"
    fi
    uv pip install --python "$(python_path)" -e "$REPO"
    printf 'INSTALLED: SWE-bench %s\n' "$SHA"
    check_state || true
    ;;
  *)
    code_die "usage: setup-swebench.sh --check|--install"; exit 2
    ;;
esac
