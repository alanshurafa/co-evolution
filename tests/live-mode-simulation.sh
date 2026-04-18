#!/usr/bin/env bash
# tests/live-mode-simulation.sh
# RTUX-01: Smoke test for --live / LIVE_MODE. Runs without network, without
# codex/claude CLIs, and without a real Windows host — is_windows_host is
# overridden per-scenario and wt.exe is stubbed via PATH shadowing.
#
# Scenarios:
#   A: LIVE_MODE=false — helper is a true no-op (no file touched, no log).
#   B: LIVE_MODE=true on non-Windows — one warning, never blocks, idempotent.
#   C: LIVE_MODE=true on simulated Windows — wt.exe stub invoked with
#      "phase:execute" title, stderr file pre-touched, state.json untouched.

set -euo pipefail

TEST_DIR=$(mktemp -d -t live-sim-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

FAILURES=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }

# --- Scenario A: --live absent (byte-parity invariant) ---
(
  export LOG_FILE="$TEST_DIR/a.log"
  : > "$LOG_FILE"
  unset LIVE_MODE
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/co-evolution.sh"
  maybe_launch_live_window "test-phase" "$TEST_DIR/a-stderr.log"
  [[ ! -e "$TEST_DIR/a-stderr.log" ]] || { echo "A: stderr file unexpectedly created" >&2; exit 1; }
  ! grep -q "WARNING" "$LOG_FILE" || { echo "A: unexpected warning in log" >&2; exit 1; }
) || fail "Scenario A (LIVE_MODE=false no-op)"

# --- Scenario B: --live on non-Windows (one warning, inline fallback) ---
(
  export LOG_FILE="$TEST_DIR/b.log"
  : > "$LOG_FILE"
  export LIVE_MODE=true
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/co-evolution.sh"
  # Stub is_windows_host to force the non-Windows branch regardless of host.
  is_windows_host() { printf '%s' "false"; }
  maybe_launch_live_window "p1" "$TEST_DIR/b-stderr.log"
  maybe_launch_live_window "p2" "$TEST_DIR/b-stderr.log"
  maybe_launch_live_window "p3" "$TEST_DIR/b-stderr.log"
  warn_count=$(grep -c "WARNING: --live is Windows-only" "$LOG_FILE" || true)
  [[ "$warn_count" == "1" ]] || { echo "B: expected 1 warning, got $warn_count" >&2; exit 1; }
  [[ ! -e "$TEST_DIR/b-stderr.log" ]] || { echo "B: stderr file unexpectedly created" >&2; exit 1; }
) || fail "Scenario B (LIVE_MODE=true non-Windows)"

# --- Scenario C: --live on simulated Windows with stubbed wt.exe ---
(
  export LOG_FILE="$TEST_DIR/c.log"
  : > "$LOG_FILE"
  export LIVE_MODE=true
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/wt.exe" <<'STUB'
#!/usr/bin/env bash
# Stubbed wt.exe — records its args and exits 0.
printf '%s\n' "$*" >> "$WT_STUB_LOG"
STUB
  chmod +x "$TEST_DIR/bin/wt.exe"
  export WT_STUB_LOG="$TEST_DIR/wt-calls.log"
  : > "$WT_STUB_LOG"
  export PATH="$TEST_DIR/bin:$PATH"

  # Seed a minimal state.json to assert it remains untouched/valid.
  printf '%s\n' '{"phases":[]}' > "$TEST_DIR/state.json"

  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/co-evolution.sh"
  is_windows_host() { printf '%s' "true"; }

  maybe_launch_live_window "execute" "$TEST_DIR/execute-stderr.log"
  rc=$?
  [[ "$rc" == "0" ]] || { echo "C: helper returned $rc, expected 0" >&2; exit 1; }
  [[ -e "$TEST_DIR/execute-stderr.log" ]] || { echo "C: stderr file was not pre-touched" >&2; exit 1; }

  # Give the backgrounded subshell up to 2s to exec the stub.
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if grep -q "phase:execute" "$WT_STUB_LOG" 2>/dev/null; then break; fi
    sleep 0.1
  done
  grep -q "phase:execute" "$WT_STUB_LOG" \
    || { echo "C: wt.exe stub was not invoked with 'phase:execute'" >&2; cat "$WT_STUB_LOG" >&2; exit 1; }

  # state.json must be byte-identical to the seed.
  [[ "$(cat "$TEST_DIR/state.json")" == '{"phases":[]}' ]] \
    || { echo "C: state.json was mutated" >&2; exit 1; }
) || fail "Scenario C (LIVE_MODE=true simulated Windows)"

if (( FAILURES == 0 )); then
  echo "ALL SCENARIOS PASSED"
  exit 0
else
  echo "FAILED: $FAILURES scenario(s)" >&2
  exit 1
fi
