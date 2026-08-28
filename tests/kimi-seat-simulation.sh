#!/usr/bin/env bash
# Hermetic coverage for the Kimi Code v0.39.1 document seat.
#
# The real contract discovered on Windows is:
#   kimi -m kimi-code/k3 -p <prompt> --output-format stream-json
# The adapter runs in a disposable no-tools project and extracts the last raw
# assistant content with jq; transcript-formatted text output is never accepted.
# Authentication is file-backed. The bouncer must reject a missing CLI, config,
# or login before creating a run or invoking an agent. No scenario in this file
# contacts kimi.com or any model API.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOUNCER="$REPO_ROOT/co-evolve-bouncer.sh"

TEST_DIR="$(mktemp -d -t kimi-seat-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
FAILURES=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

mkdir -p "$TEST_DIR/bin"
KIMI_CALL_LOG="$TEST_DIR/kimi-call.log"
: > "$KIMI_CALL_LOG"

cat > "$TEST_DIR/bin/kimi" <<'STUB'
#!/usr/bin/env bash
status=BAD
if [[ "$#" -eq 6 && "$1" == "-m" && "$2" == "kimi-code/k3" \
   && "$3" == "-p" && -n "$4" \
   && "$5" == "--output-format" && "$6" == "stream-json" \
   && -f ".kimi-code/local.toml" ]]; then
  if grep -Fq 'enabled = ["*"]' ".kimi-code/local.toml"; then
    case "$4" in
      *"## DOCUMENT TO REVIEW"*"Kimi seat contract fixture"*) status=OK ;;
    esac
  fi
fi
printf 'CONTRACT_%s\n' "$status" >> "$KIMI_CALL_LOG"
if [[ "${KIMI_STUB_PARTIAL_FAILURE:-}" == "1" ]]; then
  printf '%s\n' '{"role":"assistant","content":"Kimi partial response that must never replace the document."}'
  exit 23
fi
printf '%s\n' '{"role":"assistant","content":"# Kimi raw Markdown\n\nKimi returns a clean document with enough ordinary words to pass artifact validation without transcript bullets, tool calls, protocol markers, or another bounce pass."}'
printf '%s\n' '{"role":"meta","type":"session.resume_hint","session_id":"hermetic"}'
STUB
chmod +x "$TEST_DIR/bin/kimi"

cat > "$TEST_DIR/doc.md" <<'DOC'
# Kimi seat contract fixture

This hermetic document has enough words and structure for the bouncer to treat
it as a real input while the PATH-injected Kimi executable validates its argv.
DOC

run_kimi() {
  local home_dir="$1" path_value="$2" runs_dir="$3" out_file="$4"
  local document="${KIMI_TEST_DOC:-$TEST_DIR/doc.md}"
  shift 4
  HOME="$home_dir" PATH="$path_value" KIMI_CALL_LOG="$KIMI_CALL_LOG" \
    KIMI_STUB_PARTIAL_FAILURE="${KIMI_STUB_PARTIAL_FAILURE:-}" \
    CO_EVOLVE_RUNS_DIR="$runs_dir" \
    bash "$BOUNCER" --vanilla --no-report --bounce-only --bounces 1 \
      --agents kimi,claude "$document" "$@" > "$out_file" 2>&1
}

# Scenario 1: no executable on PATH and no per-user fallback fails immediately.
TOTAL=$((TOTAL + 1))
s1_rc=0
run_kimi "$TEST_DIR/home-no-cli" "/usr/bin:/bin" "$TEST_DIR/runs1" \
  "$TEST_DIR/s1.out" || s1_rc=$?
if [[ "$s1_rc" -ne 0 ]] \
   && grep -Fq 'ERROR: kimi seat requires the kimi CLI on PATH (or under ~/.kimi-code/bin)' "$TEST_DIR/s1.out" \
   && [[ ! -s "$KIMI_CALL_LOG" ]]; then
  pass "Kimi prereq: missing CLI fails before agent invocation"
else
  fail "Kimi missing-CLI prereq did not fail early"
  cat "$TEST_DIR/s1.out" >&2
fi

# Scenario 2: executable present but config absent fails before invocation.
TOTAL=$((TOTAL + 1))
s2_rc=0
run_kimi "$TEST_DIR/home-no-config" "$TEST_DIR/bin:$PATH" "$TEST_DIR/runs2" \
  "$TEST_DIR/s2.out" || s2_rc=$?
if [[ "$s2_rc" -ne 0 ]] \
   && grep -Fq 'ERROR: kimi seat requires readable Kimi config at ~/.kimi-code/config.toml' "$TEST_DIR/s2.out" \
   && [[ ! -s "$KIMI_CALL_LOG" ]]; then
  pass "Kimi prereq: missing config fails before agent invocation"
else
  fail "Kimi missing-config prereq did not fail early"
  cat "$TEST_DIR/s2.out" >&2
fi

# Scenario 3: config present but login credential absent fails before invocation.
TOTAL=$((TOTAL + 1))
mkdir -p "$TEST_DIR/home-no-login/.kimi-code"
printf '%s\n' '[default]' > "$TEST_DIR/home-no-login/.kimi-code/config.toml"
s3_rc=0
run_kimi "$TEST_DIR/home-no-login" "$TEST_DIR/bin:$PATH" "$TEST_DIR/runs3" \
  "$TEST_DIR/s3.out" || s3_rc=$?
if [[ "$s3_rc" -ne 0 ]] \
   && grep -Fq "ERROR: kimi seat is not logged in; run 'kimi login --region mainland-cn'" "$TEST_DIR/s3.out" \
   && [[ ! -s "$KIMI_CALL_LOG" ]]; then
  pass "Kimi prereq: missing login fails before agent invocation"
else
  fail "Kimi missing-login prereq did not fail early"
  cat "$TEST_DIR/s3.out" >&2
fi

# Scenario 4: valid config/login reaches the hardened v0.39.1 stream contract.
TOTAL=$((TOTAL + 1))
mkdir -p "$TEST_DIR/home-ready/.kimi-code/credentials"
printf '%s\n' '[default]' > "$TEST_DIR/home-ready/.kimi-code/config.toml"
printf '%s\n' '{}' > "$TEST_DIR/home-ready/.kimi-code/credentials/kimi-code.json"
s4_rc=0
run_kimi "$TEST_DIR/home-ready" "$TEST_DIR/bin:$PATH" "$TEST_DIR/runs4" \
  "$TEST_DIR/s4.out" || s4_rc=$?
s4_calls=$(wc -l < "$KIMI_CALL_LOG" | tr -d '\r\n ')
working_file=$(ls -dt "$TEST_DIR"/runs4/co-evolve-*/working.md 2>/dev/null | head -1)
if [[ "$s4_rc" -eq 0 && "$s4_calls" == "1" ]] \
   && grep -Fxq 'CONTRACT_OK' "$KIMI_CALL_LOG" \
   && [[ -n "$working_file" ]] \
   && grep -Fq '# Kimi raw Markdown' "$working_file" \
   && ! grep -Fq '• ' "$working_file"; then
  pass "Kimi invocation: no-tools stream-json yields raw assistant Markdown"
else
  fail "Kimi no-tools stream-json contract mismatch"
  {
    cat "$TEST_DIR/s4.out"
    cat "$KIMI_CALL_LOG"
    find "$TEST_DIR/runs4" -name 'pass-1-stderr.log' -type f -exec cat {} \;
  } >&2
fi

# Scenario 5: Kimi has no effort flag. Reject an override instead of reporting
# an effort the CLI cannot apply.
TOTAL=$((TOTAL + 1))
s5_rc=0
run_kimi "$TEST_DIR/home-ready" "$TEST_DIR/bin:$PATH" "$TEST_DIR/runs5" \
  "$TEST_DIR/s5.out" --reviewer-effort high || s5_rc=$?
s5_calls=$(wc -l < "$KIMI_CALL_LOG" | tr -d '\r\n ')
if [[ "$s5_rc" -ne 0 && "$s5_calls" == "1" ]] \
   && grep -Fq 'ERROR: kimi seat does not support reviewer effort overrides' "$TEST_DIR/s5.out"; then
  pass "Kimi effort: unsupported override fails before invocation"
else
  fail "Kimi effort override was accepted or reached the CLI"
  cat "$TEST_DIR/s5.out" >&2
fi

# Scenario 6: a composer effort can still target the second (Claude) seat in a
# bounce-only kimi,claude pair. Do not reject it merely because Kimi is present.
TOTAL=$((TOTAL + 1))
s6_rc=0
run_kimi "$TEST_DIR/home-ready" "$TEST_DIR/bin:$PATH" "$TEST_DIR/runs6" \
  "$TEST_DIR/s6.out" --composer-effort high || s6_rc=$?
s6_calls=$(wc -l < "$KIMI_CALL_LOG" | tr -d '\r\n ')
if [[ "$s6_rc" -eq 0 && "$s6_calls" == "2" ]]; then
  pass "Kimi effort: override for the other seat remains valid"
else
  fail "Kimi presence incorrectly rejected the other seat's effort override"
  cat "$TEST_DIR/s6.out" >&2
fi

# Scenario 7: native Windows transports -p through CreateProcess. Fail clearly
# before the 32,767 UTF-16 command-line ceiling instead of truncating a document
# or surfacing an opaque launcher error. Non-Windows hosts record an honest skip
# while keeping the cross-platform scenario count stable.
TOTAL=$((TOTAL + 1))
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    long_doc="$TEST_DIR/long-doc.md"
    awk 'BEGIN { print "# Long Kimi prompt"; for (i = 0; i < 13000; i++) printf "x"; print "" }' > "$long_doc"
    s7_rc=0
    KIMI_TEST_DOC="$long_doc" run_kimi \
      "$TEST_DIR/home-ready" "$TEST_DIR/bin:$PATH" "$TEST_DIR/runs7" \
      "$TEST_DIR/s7.out" || s7_rc=$?
    s7_calls=$(wc -l < "$KIMI_CALL_LOG" | tr -d '\r\n ')
    if [[ "$s7_rc" -ne 0 && "$s7_calls" == "2" ]] \
       && grep -Fq 'ERROR: kimi seat prompt exceeds the safe Windows command-line limit (12000 bytes)' "$TEST_DIR/s7.out"; then
      pass "Kimi Windows argv: oversized prompt fails clearly before invocation"
    else
      fail "Kimi Windows argv guard did not fail before invocation"
      cat "$TEST_DIR/s7.out" >&2
    fi
    ;;
  *)
    pass "Kimi Windows argv: guard is platform-specific (not exercised on this host)"
    ;;
esac

# Scenario 8: a nonzero Kimi exit may still flush partial assistant NDJSON.
# Discard it so the bouncer retries and aborts instead of installing a truncated
# document as a successful pass.
TOTAL=$((TOTAL + 1))
s8_rc=0
KIMI_STUB_PARTIAL_FAILURE=1 run_kimi \
  "$TEST_DIR/home-ready" "$TEST_DIR/bin:$PATH" "$TEST_DIR/runs8" \
  "$TEST_DIR/s8.out" || s8_rc=$?
s8_calls=$(wc -l < "$KIMI_CALL_LOG" | tr -d '\r\n ')
s8_working=$(ls -dt "$TEST_DIR"/runs8/co-evolve-*/working.md 2>/dev/null | head -1)
if [[ "$s8_rc" -ne 0 && "$s8_calls" == "4" && -n "$s8_working" ]] \
   && ! grep -Fq 'Kimi partial response' "$s8_working" \
   && grep -Fq 'returned empty output on call and retry' "$TEST_DIR/s8.out"; then
  pass "Kimi partial failure: nonzero CLI output is discarded"
else
  fail "Kimi partial failure output was accepted or not retried"
  {
    cat "$TEST_DIR/s8.out"
    [[ -n "$s8_working" ]] && cat "$s8_working"
  } >&2
fi

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
fi

echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
exit 1
