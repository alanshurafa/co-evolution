#!/usr/bin/env bash
# Hermetic coverage for the direct Kimi K3 document seat. No network/model call.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOUNCER="$REPO_ROOT/co-evolve-bouncer.sh"
TEST_DIR="$(mktemp -d -t kimi-seat-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

# The bouncer also reads seat keys from the repo's .env.local, which on a
# developer machine holds a real KIMI_API_KEY and would defeat the missing-key
# scenario below. Point every scenario at a path that does not exist so the
# fixture, not the machine, decides which keys are present.
export CO_EVOLVE_ENV_FILE="$TEST_DIR/absent.env"

TOTAL=0
FAILURES=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

mkdir -p "$TEST_DIR/bin"
REAL_JQ=$(command -v jq)

# Direct-API curl stub. It reads the request from stdin and the bearer header
# from curl's mode-600 config, but logs only non-secret contract facts.
cat > "$TEST_DIR/bin/curl" <<STUB
#!/usr/bin/env bash
config=""; prev=""
for arg in "\$@"; do
  [[ "\$prev" == "--config" ]] && config="\$arg"
  prev="\$arg"
done
[[ -r "\$config" ]] || exit 2
request=\$(cat)
{
  printf 'MODEL=%s\n' "\$(printf '%s' "\$request" | "$REAL_JQ" -r '.model // empty')"
  printf 'TEMPERATURE=%s\n' "\$(printf '%s' "\$request" | "$REAL_JQ" -r '.temperature // empty')"
  grep -Fq 'header = "Authorization: Bearer ' "\$config" && printf '%s\n' 'AUTH_PRESENT=1'
  printf '%s' "\$request" | "$REAL_JQ" -e '.messages[0].content | contains("## DOCUMENT TO REVIEW")' >/dev/null \
    && printf '%s\n' 'PROMPT_PRESENT=1'
} >> "\$KIMI_CURL_LOG"
if [[ "\${KIMI_STUB_ERROR:-}" == "1" ]]; then
  printf '%s\n' '{"error":{"message":"Kimi quota unavailable"}}'
  exit 22
fi
content='Kimi returns a complete revised Markdown document with enough ordinary words to pass validation and no protocol markers.'
"$REAL_JQ" -n --arg content "\$content" '{model:"kimi-k3",choices:[{message:{content:\$content},finish_reason:"stop"}],usage:{prompt_tokens:10,completion_tokens:10}}'
STUB
chmod +x "$TEST_DIR/bin/curl"
cat > "$TEST_DIR/bin/jq" <<STUB
#!/usr/bin/env bash
exec "$REAL_JQ" "\$@"
STUB
chmod +x "$TEST_DIR/bin/jq"

DOC="$TEST_DIR/doc.md"
cat > "$DOC" <<'DOC'
# Kimi seat contract

This fixture contains enough ordinary words for a real document review while
remaining short enough to make the direct API contract easy to inspect.
DOC

run_kimi() {
  local runs_dir="$1" out_file="$2"
  shift 2
  PATH="$TEST_DIR/bin:$PATH" KIMI_CURL_LOG="$TEST_DIR/curl.log" \
    KIMI_STUB_ERROR="${KIMI_STUB_ERROR:-}" \
    CO_EVOLVE_RUNS_DIR="$runs_dir" \
    bash "$BOUNCER" --vanilla --no-report --bounce-only --bounces 1 \
      --agents kimi,claude "$DOC" "$@" > "$out_file" 2>&1
}

# 1. Missing key fails before a run or provider invocation.
TOTAL=$((TOTAL + 1))
: > "$TEST_DIR/curl.log"
s1_rc=0
(
  unset KIMI_API_KEY
  PATH="$TEST_DIR/bin:$PATH" CO_EVOLVE_RUNS_DIR="$TEST_DIR/runs1" \
    bash "$BOUNCER" --vanilla --no-report --bounce-only --bounces 1 \
      --agents kimi,claude "$DOC"
) > "$TEST_DIR/s1.out" 2>&1 || s1_rc=$?
if [[ "$s1_rc" -ne 0 ]] \
   && grep -Fq 'ERROR: kimi seat requires KIMI_API_KEY' "$TEST_DIR/s1.out" \
   && [[ ! -s "$TEST_DIR/curl.log" ]]; then
  pass "Kimi prereq: missing KIMI_API_KEY fails before invocation"
else
  fail "Kimi missing-key prerequisite did not fail early"
fi

# 2. Valid key reaches the direct K3 request with temperature=1 and raw Markdown.
TOTAL=$((TOTAL + 1))
: > "$TEST_DIR/curl.log"
s2_rc=0
KIMI_API_KEY='test-only-kimi-key' run_kimi "$TEST_DIR/runs2" "$TEST_DIR/s2.out" || s2_rc=$?
s2_working=$(find "$TEST_DIR/runs2" -name working.md -type f | head -1)
if [[ "$s2_rc" -eq 0 ]] \
   && grep -Fxq 'MODEL=kimi-k3' "$TEST_DIR/curl.log" \
   && grep -Fxq 'TEMPERATURE=1' "$TEST_DIR/curl.log" \
   && grep -Fxq 'AUTH_PRESENT=1' "$TEST_DIR/curl.log" \
   && grep -Fxq 'PROMPT_PRESENT=1' "$TEST_DIR/curl.log" \
   && grep -Fq 'complete revised Markdown document' "$s2_working"; then
  pass "Kimi direct API: K3 request yields raw Markdown with no agent tools"
else
  fail "Kimi direct API request/response contract mismatch"
fi

# 3. Kimi has no role-effort override in the current adapter contract.
TOTAL=$((TOTAL + 1))
: > "$TEST_DIR/curl.log"
s3_rc=0
KIMI_API_KEY='test-only-kimi-key' run_kimi "$TEST_DIR/runs3" "$TEST_DIR/s3.out" \
  --reviewer-effort high || s3_rc=$?
if [[ "$s3_rc" -ne 0 ]] \
   && grep -Fq 'ERROR: kimi seat does not support reviewer effort overrides' "$TEST_DIR/s3.out" \
   && [[ ! -s "$TEST_DIR/curl.log" ]]; then
  pass "Kimi effort: unsupported override fails before invocation"
else
  fail "Kimi effort override reached the API"
fi

# 4. Provider errors become fatal artifacts, never converged documents.
TOTAL=$((TOTAL + 1))
: > "$TEST_DIR/curl.log"
s4_rc=0
KIMI_API_KEY='test-only-kimi-key' KIMI_STUB_ERROR=1 \
  run_kimi "$TEST_DIR/runs4" "$TEST_DIR/s4.out" || s4_rc=$?
if [[ "$s4_rc" -ne 0 ]] \
   && grep -Fq 'returned a provider/API failure, not a document' "$TEST_DIR/s4.out"; then
  pass "Kimi provider error: bouncer aborts instead of reporting convergence"
else
  fail "Kimi provider error was accepted as a document"
fi

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  printf '%s/%s scenarios passed\n' "$passed" "$TOTAL"
  exit 0
fi
printf '%s/%s scenarios passed (%s failed)\n' "$passed" "$TOTAL" "$FAILURES" >&2
exit 1
