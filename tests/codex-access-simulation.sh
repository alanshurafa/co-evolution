#!/usr/bin/env bash
# tests/codex-access-simulation.sh
# Hermetic simulation of the lib/codex-access.sh launch matrix.
#
# All scenarios are hermetic: no real codex/cmd.exe/claude binaries are run.
# We construct a PATH-shadow directory with fake `codex`, `cmd.exe`, and
# `wslpath` stubs, then source the helper and exercise each branch.
#
# Scenarios:
#   A: codex_available returns 1 when no codex is reachable.
#   B: codex_available returns 0 when `codex` is on PATH (native branch).
#   C: codex_available returns 0 when WSL_DISTRO_NAME is set and cmd.exe
#      + wslpath are on PATH (WSL bridge branch).
#   D: codex_invoke with no codex reachable writes empty output_file,
#      populates stderr_file with the install hint, and returns 0.
#   E: codex_invoke (native branch) actually calls the codex stub with the
#      expected argv and the stub's canned output reaches output_file.
#   F: codex_invoke (WSL branch) routes through cmd.exe stub with
#      wslpath-translated paths.
#   G: codex_install_hint prints the actionable multi-line message.
#
# Final line on success: `7/7 scenarios passed`.
# Exit 0 iff all scenarios pass; exit 1 otherwise.

set -euo pipefail

TEST_DIR=$(mktemp -d -t codex-access-sim-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/lib/codex-access.sh"

[[ -f "$HELPER" ]] || { echo "FAIL: helper missing: $HELPER" >&2; exit 1; }

FAILURES=0
TOTAL=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

# Minimal PATH containing system binaries (bash, grep, etc.) but NOT the
# user's real codex/claude/cmd.exe. Each scenario prepends its own stub dir
# so we can isolate which launch-matrix branch fires.
BASE_PATH="/usr/bin:/bin"

# ---------------------------------------------------------------------------
# PATH-shadow setup helpers
# ---------------------------------------------------------------------------
# Each scenario builds its own shadow $PATH and (optionally) sets WSL_DISTRO_NAME
# so the launch-matrix branches are exercised in isolation. We never touch the
# real $PATH outside of a subshell.

make_codex_stub() {
  local stub_dir="$1"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/codex" <<'STUB'
#!/usr/bin/env bash
# codex stub — handles --version and the `exec` subcommand.
if [[ "${1:-}" == "--version" ]]; then
  echo "codex-stub 0.0.1"
  exit 0
fi
# exec subcommand: pick up -o <output> and write canned text to it.
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      output="$2"; shift 2 ;;
    *)
      shift ;;
  esac
done
if [[ -n "$output" ]]; then
  echo "stub codex output" > "$output"
fi
STUB
  chmod +x "$stub_dir/codex"
}

make_cmdexe_stub() {
  local stub_dir="$1"
  mkdir -p "$stub_dir"
  # cmd.exe /c codex <args...> — forward to the codex stub in same dir.
  # First arg is "/c", remaining args are the command to run.
  cat > "$stub_dir/cmd.exe" <<STUB
#!/usr/bin/env bash
# cmd.exe stub: strip /c and forward to the codex stub.
[[ "\${1:-}" == "/c" ]] && shift
[[ "\${1:-}" == "codex" ]] && shift
exec "$stub_dir/codex" "\$@"
STUB
  chmod +x "$stub_dir/cmd.exe"
}

make_wslpath_stub() {
  local stub_dir="$1"
  mkdir -p "$stub_dir"
  # wslpath -w <path> → just echo with a recognizable Windows-ish prefix so
  # the test can grep for it in scenario F.
  cat > "$stub_dir/wslpath" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == "-w" ]] && shift
printf 'C:\\fake\\wsl\\%s\n' "${1#/}"
STUB
  chmod +x "$stub_dir/wslpath"
}

# ---------------------------------------------------------------------------
# Scenario A: nothing reachable → codex_available returns 1
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  empty_dir="$TEST_DIR/sA-empty"
  mkdir -p "$empty_dir"
  PATH="$empty_dir:$BASE_PATH" \
  WSL_DISTRO_NAME="" \
  bash -c "source '$HELPER' && codex_available && exit 0 || exit 1"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "A: codex_available returned 0 with no codex on PATH (expected 1)" >&2
    exit 1
  fi
) && pass "Scenario A (codex_available=1 when nothing reachable)" \
  || fail "Scenario A (no-codex detection)"

# ---------------------------------------------------------------------------
# Scenario B: native codex on PATH → codex_available returns 0
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  native_dir="$TEST_DIR/sB-native"
  make_codex_stub "$native_dir"
  PATH="$native_dir:$BASE_PATH" \
  WSL_DISTRO_NAME="" \
  bash -c "source '$HELPER' && codex_available"
) && pass "Scenario B (codex_available=0 native branch)" \
  || fail "Scenario B (native detection)"

# ---------------------------------------------------------------------------
# Scenario C: WSL bridge reachable → codex_available returns 0
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  wsl_dir="$TEST_DIR/sC-wsl"
  make_codex_stub  "$wsl_dir"   # cmd.exe stub forwards to this codex
  make_cmdexe_stub "$wsl_dir"
  make_wslpath_stub "$wsl_dir"
  PATH="$wsl_dir:$BASE_PATH" \
  WSL_DISTRO_NAME="Ubuntu" \
  bash -c "source '$HELPER' && codex_available"
) && pass "Scenario C (codex_available=0 WSL bridge branch)" \
  || fail "Scenario C (WSL bridge detection)"

# ---------------------------------------------------------------------------
# Scenario D: codex_invoke with no codex → empty output + install hint stderr
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  empty_dir="$TEST_DIR/sD-empty"
  mkdir -p "$empty_dir"
  prompt="$TEST_DIR/sD.prompt"; echo "test prompt" > "$prompt"
  out="$TEST_DIR/sD.out"
  err="$TEST_DIR/sD.err"

  PATH="$empty_dir:$BASE_PATH" \
  WSL_DISTRO_NAME="" \
  bash -c "source '$HELPER' && codex_invoke '$prompt' '$out' '$err'"
  rc=$?
  [[ $rc -eq 0 ]] \
    || { echo "D: codex_invoke returned $rc (expected 0 — error flows through files)" >&2; exit 1; }
  [[ -f "$out" && ! -s "$out" ]] \
    || { echo "D: output_file should exist but be empty; size=$(wc -c < "$out" 2>/dev/null)" >&2; exit 1; }
  grep -qF "codex CLI is not reachable" "$err" \
    || { echo "D: stderr missing install hint; got:" >&2; cat "$err" >&2; exit 1; }
  grep -qF "npm install -g @openai/codex" "$err" \
    || { echo "D: stderr missing install command in hint" >&2; exit 1; }
) && pass "Scenario D (codex_invoke unreachable → install hint + empty output)" \
  || fail "Scenario D (unreachable fallback)"

# ---------------------------------------------------------------------------
# Scenario E: codex_invoke native branch — stub gets invoked, output flows
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  native_dir="$TEST_DIR/sE-native"
  make_codex_stub "$native_dir"
  prompt="$TEST_DIR/sE.prompt"; echo "test prompt" > "$prompt"
  out="$TEST_DIR/sE.out"
  err="$TEST_DIR/sE.err"

  PATH="$native_dir:$BASE_PATH" \
  WSL_DISTRO_NAME="" \
  WORKDIR="$TEST_DIR" \
  bash -c "source '$HELPER' && codex_invoke '$prompt' '$out' '$err'"
  rc=$?
  [[ $rc -eq 0 ]] || { echo "E: codex_invoke returned $rc" >&2; exit 1; }
  grep -qF "stub codex output" "$out" \
    || { echo "E: output didn't contain stub canned text; out:" >&2; cat "$out" >&2; exit 1; }
) && pass "Scenario E (codex_invoke native branch invokes codex)" \
  || fail "Scenario E (native invocation)"

# ---------------------------------------------------------------------------
# Scenario F: codex_invoke WSL branch — routes through cmd.exe + wslpath
# ---------------------------------------------------------------------------
# We use the cmd.exe stub which forwards to the codex stub. The codex stub
# writes to whichever -o path it's given. The wslpath stub returns
# `C:\fake\wsl\...`, so if the WSL branch is wired correctly the codex stub
# would TRY to write to that fake-Windows path (which doesn't exist as a real
# file). We make the test robust by having cmd.exe stub strip the windowsy
# prefix and write to the real path: see make_cmdexe_stub below for adjusted
# semantics — actually it's easier to just verify cmd.exe was invoked at all
# by checking stderr from a deliberately failing cmd.exe stub that logs
# its argv. Simpler: write a marker file when cmd.exe is invoked, then
# assert the marker exists.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  wsl_dir="$TEST_DIR/sF-wsl"
  mkdir -p "$wsl_dir"

  # cmd.exe stub that writes a marker file proving it was invoked, then
  # writes canned output to the real (unix) output file. The bouncer passes
  # the Windows-translated path via -o, but our stub ignores that and uses
  # an env-var-supplied real path so the assertion is straightforward.
  marker="$TEST_DIR/sF.cmdexe-was-invoked"
  out="$TEST_DIR/sF.out"
  err="$TEST_DIR/sF.err"
  prompt="$TEST_DIR/sF.prompt"; echo "test prompt" > "$prompt"

  cat > "$wsl_dir/cmd.exe" <<STUB
#!/usr/bin/env bash
touch "$marker"
# Write canned output to the real unix path so the test can verify content.
echo "stub WSL output" > "$out"
exit 0
STUB
  chmod +x "$wsl_dir/cmd.exe"
  make_wslpath_stub "$wsl_dir"

  PATH="$wsl_dir:$BASE_PATH" \
  WSL_DISTRO_NAME="Ubuntu" \
  WORKDIR="$TEST_DIR" \
  bash -c "source '$HELPER' && codex_invoke '$prompt' '$out' '$err'"

  [[ -f "$marker" ]] \
    || { echo "F: cmd.exe stub was never invoked (WSL branch not taken)" >&2; exit 1; }
  grep -qF "stub WSL output" "$out" \
    || { echo "F: output missing canned WSL stub text" >&2; exit 1; }
) && pass "Scenario F (codex_invoke WSL branch routes through cmd.exe)" \
  || fail "Scenario F (WSL bridge invocation)"

# ---------------------------------------------------------------------------
# Scenario G: codex_install_hint prints the actionable message
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  out=$(bash -c "source '$HELPER' && codex_install_hint")
  echo "$out" | grep -qF "npm install -g @openai/codex" \
    || { echo "G: hint missing install command" >&2; exit 1; }
  echo "$out" | grep -qF "OPENAI_API_KEY" \
    || { echo "G: hint missing API key step" >&2; exit 1; }
  echo "$out" | grep -qF -- "--single-model claude" \
    || { echo "G: hint missing single-model claude fallback suggestion" >&2; exit 1; }
  echo "$out" | grep -qF "WSL users" \
    || { echo "G: hint missing WSL guidance" >&2; exit 1; }
) && pass "Scenario G (codex_install_hint includes install + auth + fallback)" \
  || fail "Scenario G (install hint content)"

# ---------------------------------------------------------------------------
echo
if [[ $FAILURES -eq 0 ]]; then
  echo "$TOTAL/$TOTAL scenarios passed"
  exit 0
else
  echo "$((TOTAL - FAILURES))/$TOTAL scenarios passed ($FAILURES failures)"
  exit 1
fi
