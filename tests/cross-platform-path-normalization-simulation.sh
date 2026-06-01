#!/usr/bin/env bash
# tests/cross-platform-path-normalization-simulation.sh
#
# Hermetic checks that normalize_path_for_bash (lib/co-evolution.sh) behaves
# correctly on every supported platform. Under WSL it converts Windows drive
# paths via wslpath; on macOS, Linux, and Git Bash it is a safe pass-through.
# Platform conditions are simulated via WSL_DISTRO_NAME and a stubbed wslpath on
# PATH, so no real WSL / macOS / Linux host is required to run these checks.
#
# Scenarios:
#   1: WSL + wslpath + Windows drive path   -> converted to /mnt/<drive>/...
#   2: WSL + wslpath + POSIX path           -> unchanged (regex no-match)
#   3: WSL + NO wslpath + Windows path      -> unchanged (command -v guard)
#   4: non-WSL (macOS/Linux/Git Bash) POSIX -> unchanged
#   5: non-WSL + wslpath present + Win path  -> unchanged (WSL flag gates it)
#   6: empty argument                       -> empty (no crash under set -u)
#   7: co-evolve-bouncer.sh accepts Windows-style args under WSL (integration)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$REPO_ROOT/runs"

TEST_DIR=$(mktemp -d "$REPO_ROOT/runs/xplat-path-sim-XXXXXX")
RUN_DIR_CREATED=""
cleanup() {
  rm -rf "$TEST_DIR"
  if [[ -n "$RUN_DIR_CREATED" && "$RUN_DIR_CREATED" == "$REPO_ROOT"/runs/co-evolve-* ]]; then
    rm -rf "$RUN_DIR_CREATED"
  fi
}
trap cleanup EXIT

FAILURES=0
TOTAL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
check() { # check <description> <actual> <expected>
  TOTAL=$((TOTAL + 1))
  if [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    fail "$1 (got '$2', expected '$3')"
  fi
}

# wslpath stub: mimics the real tool's C:/ and C:\ -> /mnt/<drive>/ conversion.
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/wslpath" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  [A-Za-z]:/*)
    drive=$(printf '%s' "${1%%:*}" | tr '[:upper:]' '[:lower:]')
    rest="${1#?:/}"
    printf '/mnt/%s/%s\n' "$drive" "$rest"
    ;;
  [A-Za-z]:\\*)
    drive=$(printf '%s' "${1%%:*}" | tr '[:upper:]' '[:lower:]')
    rest="${1#?:\\}"
    rest="${rest//\\//}"
    printf '/mnt/%s/%s\n' "$drive" "$rest"
    ;;
  *)
    printf '%s\n' "$1"
    ;;
esac
STUB
chmod +x "$TEST_DIR/bin/wslpath"

# normalize_path_for_bash is the shared, canonical helper from the lib.
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/co-evolution.sh"

WIN_PATH='C:/Users/alan/Project/co-evolution/co-evolve-bouncer.sh'
POSIX_PATH='/mnt/c/Users/alan/Project/co-evolution/co-evolve-bouncer.sh'

# 1: WSL + wslpath + Windows drive path -> converted. (Each call runs inside the
# command-substitution subshell, so the env prefixes do not leak between checks.)
check "WSL + wslpath: Windows drive path converted to /mnt" \
  "$(WSL_DISTRO_NAME=stub PATH="$TEST_DIR/bin:$PATH" normalize_path_for_bash "$WIN_PATH")" \
  "$POSIX_PATH"

# 2: WSL + wslpath + POSIX path -> unchanged (drive-letter regex does not match)
check "WSL + wslpath: POSIX path unchanged" \
  "$(WSL_DISTRO_NAME=stub PATH="$TEST_DIR/bin:$PATH" normalize_path_for_bash "$POSIX_PATH")" \
  "$POSIX_PATH"

# 3: WSL flag set but wslpath unavailable -> pass-through (command -v guard).
# Only meaningful when the host itself has no real wslpath (e.g. macOS/Linux/Git Bash).
if command -v wslpath >/dev/null 2>&1; then
  echo "SKIP: Scenario 3 (real wslpath present on host)"
else
  check "WSL without wslpath: Windows path passes through unchanged" \
    "$(WSL_DISTRO_NAME=stub normalize_path_for_bash "$WIN_PATH")" \
    "$WIN_PATH"
fi

# 4: non-WSL (macOS / Linux / Git Bash) + POSIX path -> unchanged
check "non-WSL: POSIX path unchanged" \
  "$(WSL_DISTRO_NAME= normalize_path_for_bash "$POSIX_PATH")" \
  "$POSIX_PATH"

# 5: non-WSL with wslpath available + Windows path -> unchanged. Proves the
# WSL_DISTRO_NAME guard (not merely wslpath's absence) is what gates conversion.
check "non-WSL with wslpath present: Windows path unchanged (WSL flag gates conversion)" \
  "$(WSL_DISTRO_NAME= PATH="$TEST_DIR/bin:$PATH" normalize_path_for_bash "$WIN_PATH")" \
  "$WIN_PATH"

# 6: empty argument -> empty (must not crash under set -u)
check "empty argument returns empty" \
  "$(WSL_DISTRO_NAME= normalize_path_for_bash "")" \
  ""

# 7: co-evolve-bouncer.sh accepts a Windows-style input file and output path
#    after the script has been launched through a valid Bash path. Requires a
#    real /mnt/<drive> WSL workspace; skipped elsewhere (macOS/Linux/Git Bash).
TOTAL=$((TOTAL + 1))
(
  case "$REPO_ROOT" in
    /mnt/[A-Za-z]/*) ;;
    *) echo "SKIP: Scenario 7 (not in a /mnt/<drive> WSL workspace)"; exit 0 ;;
  esac

  to_windows_path() {
    local path="$1" drive rest
    case "$path" in
      /mnt/[A-Za-z]/*)
        drive="${path#/mnt/}"; drive="${drive%%/*}"
        rest="${path#/mnt/$drive/}"
        drive=$(printf '%s' "$drive" | tr '[:lower:]' '[:upper:]')
        printf '%s:/%s' "$drive" "$rest" ;;
      *) return 1 ;;
    esac
  }

  cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
cat > /dev/null
printf '%s\n' 'Simulated refined output with no open markers and enough words for this smoke test.'
STUB
  cat > "$TEST_DIR/bin/cmd.exe" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == "/c" ]] && shift
exec "$@"
STUB
  cat > "$TEST_DIR/bin/codex" <<'STUB'
#!/usr/bin/env bash
cat > /dev/null
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude" "$TEST_DIR/bin/cmd.exe" "$TEST_DIR/bin/codex"

  doc_posix="$TEST_DIR/input.md"
  out_posix="$TEST_DIR/output.md"
  printf '%s\n' 'Original text to bounce in the cross-platform path normalization simulation.' > "$doc_posix"
  doc_win=$(to_windows_path "$doc_posix")
  out_win=$(to_windows_path "$out_posix")

  run_output=$(
    PATH="$TEST_DIR/bin:$PATH" \
    WSL_DISTRO_NAME="${WSL_DISTRO_NAME:-stub}" \
    bash "$REPO_ROOT/co-evolve-bouncer.sh" --vanilla --bounce-only "$doc_win" --output "$out_win" 2>&1
  )
  RUN_DIR_CREATED=$(printf '%s\n' "$run_output" | awk -F'Run dir:[[:space:]]*' '/Run dir:/ {print $2; exit}')

  [[ -s "$out_posix" ]] || { echo "Scenario 7: output file was not written: $out_posix" >&2; exit 1; }
  grep -qF 'Simulated refined output' "$out_posix" \
    || { echo "Scenario 7: output file did not contain stubbed agent output" >&2; exit 1; }
) && pass "co-evolve-bouncer accepts Windows-style file arguments (WSL integration)" \
  || fail "Scenario 7 (co-evolve-bouncer Windows-arg integration)"

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
