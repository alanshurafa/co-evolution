#!/usr/bin/env bash
# tests/auth-gate-simulation.sh — A-2 auth-gate blind-spot gate.
#
# Regression for the hole in validate_agent_artifact's OUTPUT path: before A-2,
# an auth-failure page was only treated as fatal when it was BOTH matched by the
# broad file_contains_auth_failure scan AND shorter than 50 words (deb4669's
# anti-false-positive ceiling). A real login/auth error page longer than 50
# words therefore fell through the <50-word gate and was accepted as if it were
# the document (rc 0) — the exact blind spot this suite pins shut.
#
# A-2 replaces the whole-file length heuristic with a strict, line-anchored
# head-scan (output_contains_auth_banner): an auth-context banner in the first
# ~20 non-empty lines is fatal regardless of total length, while a long
# legitimate document that merely echoes auth phrases mid-body still passes.
#
# tests/reliability-simulation.sh (S1–S5) already covers the short-banner and
# empty-output/stderr paths; this suite extends that with the length dimension
# (A1–A5) and the quoted-example dimension (A6–A9): a document that QUOTES a
# banner inside a ``` fence, a 4-space/tab indent, or a > blockquote in its
# head must pass — real CLI banners print at column 0 outside any code context.
#
# Hermetic: sources lib directly + stubs the agent CLI via PATH injection for
# the E2E leg. No network, no LLM cost.

set -euo pipefail

TEST_DIR=$(mktemp -d -t auth-gate-sim-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/co-evolution.sh"

TOTAL=0
PASSED=0

pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; }

# ---------------------------------------------------------------------------
# A1 (the blind spot): a >50-word auth-error PAGE in the OUTPUT is fatal (rc 2).
# The banner leads the page; the old <50-word ceiling would have accepted it.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
out="$TEST_DIR/a1-out.md"; err="$TEST_DIR/a1-err.log"
{
  printf 'Not logged in \xc2\xb7 Please run /login\n\n'
  printf 'You are not currently authenticated with the Claude CLI. To use this\n'
  printf 'command you must first sign in with your Anthropic account. Run the\n'
  printf 'login command in an interactive terminal, complete the browser flow,\n'
  printf 'and then re-run this command. If you continue to see this message after\n'
  printf 'logging in your session token may have expired or your organization may\n'
  printf 'not have access to this model tier. Contact your administrator for help.\n'
} > "$out"
: > "$err"
words=$(wc -w < "$out" | tr -d '\r\n ')
rc=0; validate_agent_artifact "$out" "$err" claude >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 && "$words" -ge 50 ]]; then
  pass "A1: >50-word auth-error page ($words words) in output -> rc 2 (blind spot closed)"
else
  fail "A1: >50-word auth page ($words words) -> expected rc 2, got $rc"
fi

# ---------------------------------------------------------------------------
# A2: a legitimate structured plan whose body contains the word "Unauthorized"
# (and is >50 words) must pass validation (rc 0) — no false positive. The auth
# token appears mid-line, never as a leading banner.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
out="$TEST_DIR/a2-out.md"; err="$TEST_DIR/a2-err.log"
{
  printf '# Retry Wrapper Implementation Plan\n\n'
  printf '## Goal\n'
  printf 'Add a resilient retry wrapper around the upstream API client so\n'
  printf 'transient failures do not abort the batch. The wrapper must classify\n'
  printf 'responses: a 503 is retryable, whereas a 401 Unauthorized is fatal and\n'
  printf 'must surface immediately without consuming the retry budget.\n\n'
  printf '## Approach\n'
  printf 'Use exponential backoff with jitter, cap attempts at three, and log\n'
  printf 'every attempt with structured fields so operators can audit exactly\n'
  printf 'what happened after a run. Treat an Unauthorized response as a hard\n'
  printf 'stop and emit a clear remediation hint rather than retrying blindly.\n'
} > "$out"
: > "$err"
words=$(wc -w < "$out" | tr -d '\r\n ')
rc=0; validate_agent_artifact "$out" "$err" claude >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 && "$words" -ge 50 ]]; then
  pass "A2: >50-word plan mentioning 'Unauthorized' mid-body ($words words) -> rc 0 (no false positive)"
else
  fail "A2: legit plan with 'Unauthorized' ($words words) -> expected rc 0, got $rc"
fi

# ---------------------------------------------------------------------------
# A3: an authentication_error API page longer than 50 words is also fatal — the
# strict matcher is not limited to the /login banner wording.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
out="$TEST_DIR/a3-out.md"; err="$TEST_DIR/a3-err.log"
{
  printf 'authentication_error: invalid x-api-key\n\n'
  printf 'The request was rejected because the provided credentials could not be\n'
  printf 'verified against the authentication service. Ensure the API key is set\n'
  printf 'correctly in the environment and has not been revoked or rotated since\n'
  printf 'it was issued. Retrying will not help until a valid key is supplied and\n'
  printf 'the session is re-established with the upstream provider once more now.\n'
} > "$out"
: > "$err"
words=$(wc -w < "$out" | tr -d '\r\n ')
rc=0; validate_agent_artifact "$out" "$err" claude >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 && "$words" -ge 50 ]]; then
  pass "A3: >50-word authentication_error page ($words words) -> rc 2"
else
  fail "A3: >50-word authentication_error page ($words words) -> expected rc 2, got $rc"
fi

# ---------------------------------------------------------------------------
# A4: a bare "Unauthorized" line in a short document must NOT be fatal. The
# broad matcher would flag a lone "Unauthorized"; the strict output detector
# deliberately does not, so a terse-but-legitimate artifact is not misread.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
out="$TEST_DIR/a4-out.md"; err="$TEST_DIR/a4-err.log"
printf '# Status Codes\n\n401 means Unauthorized and 403 means Forbidden.\n' > "$out"
: > "$err"
rc=0; validate_agent_artifact "$out" "$err" claude >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "A4: bare 'Unauthorized' in short doc -> rc 0 (strict detector ignores bare token)"
else
  fail "A4: bare 'Unauthorized' -> expected rc 0, got $rc"
fi

# ---------------------------------------------------------------------------
# A5 (E2E): the bouncer must ABORT — not overwrite the document — when the CLI
# emits a long auth-error PAGE (not just a one-line banner). This is the whole
# blind spot exercised end-to-end through co-evolve-bouncer.sh.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
e2e="$TEST_DIR/e2e"
mkdir -p "$e2e/bin"
cat > "$e2e/bin/claude" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in --version|-v) echo "claude 1.0.0 (stub)"; exit 0 ;; esac
done
while IFS= read -r _line; do :; done
# A long (>50-word) auth-error page, banner-leading — the case that used to
# slip past the <50-word ceiling and get accepted as the document.
cat <<'PAGE'
Not logged in · Please run /login

You are not currently authenticated with the Claude CLI. To use this command
you must first sign in with your Anthropic account. Run the login command in an
interactive terminal, complete the browser flow, and then re-run this command.
If you continue to see this message after logging in, your session token may
have expired or your organization may not have access to this model tier.
PAGE
exit 0
STUB
chmod +x "$e2e/bin/claude"
cp "$e2e/bin/claude" "$e2e/bin/codex"

doc="$e2e/doc.md"
printf '# Sample Plan\n\nA plan with enough words to be a real document for the bounce loop to process.\n' > "$doc"

rc=0
PATH="$e2e/bin:$PATH" bash "$REPO_ROOT/co-evolve-bouncer.sh" --vanilla --bounce-only "$doc" \
  > "$e2e/stdout.log" 2> "$e2e/stderr.log" || rc=$?

final_doc_corrupted=false
if grep -rq 'Not logged in' "$doc" 2>/dev/null; then
  final_doc_corrupted=true
fi
if [[ "$rc" -ne 0 && "$final_doc_corrupted" == false ]] \
   && grep -qiE 'auth' "$e2e/stdout.log" "$e2e/stderr.log" 2>/dev/null; then
  pass "A5: bouncer aborts on a >50-word auth page; document not overwritten"
else
  fail "A5: rc=$rc corrupted=$final_doc_corrupted (expected nonzero rc, clean doc, auth mention)"
fi

# ---------------------------------------------------------------------------
# A6: a legitimate auth-handling plan that QUOTES the banner as a 4-space
# indented code example inside the head window must pass (rc 0). Documents
# ABOUT this gate are the realistic corpus for this tool — matching quoted
# examples would let the detector DOS its own users.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
out="$TEST_DIR/a6-out.md"; err="$TEST_DIR/a6-err.log"
{
  printf '# Auth Failure Handling Plan\n\n'
  printf 'When the CLI is unauthenticated it prints a banner that looks like:\n\n'
  printf '    Not logged in \xc2\xb7 Please run /login\n\n'
  printf 'The validation gate must treat that page as fatal instead of accepting\n'
  printf 'it as a document. This plan wires the detector into the compose and\n'
  printf 'bounce paths, keeps the stderr scan broad, and adds fixtures so the\n'
  printf 'quoted example above never trips the strict matcher during validation.\n'
} > "$out"
: > "$err"
words=$(wc -w < "$out" | tr -d '\r\n ')
rc=0; validate_agent_artifact "$out" "$err" claude >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 && "$words" -ge 50 ]]; then
  pass "A6: banner quoted as 4-space indented example ($words words) -> rc 0"
else
  fail "A6: indented banner example ($words words) -> expected rc 0, got $rc"
fi

# ---------------------------------------------------------------------------
# A7: same document shape, banner quoted in a > blockquote -> rc 0.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
out="$TEST_DIR/a7-out.md"; err="$TEST_DIR/a7-err.log"
{
  printf '# Auth Failure Handling Plan\n\n'
  printf 'When the CLI is unauthenticated it prints a banner that looks like:\n\n'
  printf '> Not logged in \xc2\xb7 Please run /login\n\n'
  printf 'The validation gate must treat that page as fatal instead of accepting\n'
  printf 'it as a document. This plan wires the detector into the compose and\n'
  printf 'bounce paths, keeps the stderr scan broad, and adds fixtures so the\n'
  printf 'quoted example above never trips the strict matcher during validation.\n'
} > "$out"
: > "$err"
words=$(wc -w < "$out" | tr -d '\r\n ')
rc=0; validate_agent_artifact "$out" "$err" claude >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 && "$words" -ge 50 ]]; then
  pass "A7: banner quoted in a blockquote ($words words) -> rc 0"
else
  fail "A7: blockquoted banner example ($words words) -> expected rc 0, got $rc"
fi

# ---------------------------------------------------------------------------
# A8: same document shape, banner quoted inside a ``` fence -> rc 0.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
out="$TEST_DIR/a8-out.md"; err="$TEST_DIR/a8-err.log"
{
  printf '# Auth Failure Handling Plan\n\n'
  printf 'When the CLI is unauthenticated it prints a banner that looks like:\n\n'
  printf '```text\n'
  printf 'Not logged in \xc2\xb7 Please run /login\n'
  printf '```\n\n'
  printf 'The validation gate must treat that page as fatal instead of accepting\n'
  printf 'it as a document. This plan wires the detector into the compose and\n'
  printf 'bounce paths, keeps the stderr scan broad, and adds fixtures so the\n'
  printf 'quoted example above never trips the strict matcher during validation.\n'
} > "$out"
: > "$err"
words=$(wc -w < "$out" | tr -d '\r\n ')
rc=0; validate_agent_artifact "$out" "$err" claude >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 && "$words" -ge 50 ]]; then
  pass "A8: banner quoted inside a code fence ($words words) -> rc 0"
else
  fail "A8: fenced banner example ($words words) -> expected rc 0, got $rc"
fi

# ---------------------------------------------------------------------------
# A9 (toggle guard): fence state must CLOSE — a banner at column 0 AFTER a
# closed fence is still a real banner (rc 2). Guards against a stuck in-fence
# flag masking genuine failures behind an earlier quoted example.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
out="$TEST_DIR/a9-out.md"; err="$TEST_DIR/a9-err.log"
{
  printf '```text\n'
  printf 'example output quoted from an earlier run\n'
  printf '```\n\n'
  printf 'Not logged in \xc2\xb7 Please run /login\n\n'
  printf 'You are not currently authenticated with the Claude CLI. Run the login\n'
  printf 'command in an interactive terminal and complete the browser flow.\n'
} > "$out"
: > "$err"
rc=0; validate_agent_artifact "$out" "$err" claude >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass "A9: column-0 banner after a CLOSED fence -> rc 2 (fence state toggles back)"
else
  fail "A9: banner after closed fence -> expected rc 2, got $rc"
fi

# ---------------------------------------------------------------------------

printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
