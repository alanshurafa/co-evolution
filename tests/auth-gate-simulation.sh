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
# A4 (contract updated for C-8): a SHORT (<50-word) output containing a bare
# "Unauthorized" IS fatal again. The anchored matcher alone deliberately skips
# bare tokens, but output_is_auth_failure restores the old loose-when-short
# catch: a real work product is never under 50 words, so a terse output with
# an auth token is the CLI's own error, not a document. (The >50-word legit
# doc mentioning "Unauthorized" mid-body stays covered by A2/C1-*-legit/C6-ok.)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
out="$TEST_DIR/a4-out.md"; err="$TEST_DIR/a4-err.log"
printf '# Status Codes\n\n401 means Unauthorized and 403 means Forbidden.\n' > "$out"
: > "$err"
rc=0; validate_agent_artifact "$out" "$err" claude >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass "A4: bare 'Unauthorized' in <50-word output -> rc 2 (C-8 short+loose catch)"
else
  fail "A4: bare 'Unauthorized' in short output -> expected rc 2, got $rc"
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
# CO_EVOLVE_RUNS_DIR: land run artifacts inside TEST_DIR (EXIT-trap cleaned)
# instead of leaking co-evolve-tmp-* dirs into the repo's shared runs/.
CO_EVOLVE_RUNS_DIR="$TEST_DIR/co-evolve-runs" PATH="$e2e/bin:$PATH" \
  bash "$REPO_ROOT/co-evolve-bouncer.sh" --vanilla --bounce-only "$doc" \
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
# C-1 / C-6 dev-review.sh gates. The code pipeline's own auth detectors
# (agent_auth_failed at the execute+verify gates, inspect_plan_output at the
# compose/bounce gate) previously used the loose file_contains_auth_failure +
# whole-file <50-word ceiling — the same blind spot A-2 closed for the document
# pipeline. These scenarios extract the real dev-review.sh functions and pin the
# anchored-matcher behavior directly. Extraction (not `source dev-review.sh`)
# because the script runs its main flow at EOF; temp-file source, not process
# substitution, because bash 3.2 (stock macOS) silently sources nothing from
# `source <(...)`.
# ---------------------------------------------------------------------------
sed -n '/^agent_cli_name() {/,/^}$/p; /^agent_auth_failed() {/,/^}$/p; /^inspect_plan_output() {/,/^}$/p; /^abort_on_timeout() {/,/^}$/p' \
  "$REPO_ROOT/dev-review/codex/dev-review.sh" > "$TEST_DIR/_dev_review_fns.sh"
# abort_on_timeout calls cleanup_runtime_artifacts (defined further down in
# dev-review.sh, not extracted); stub it so the timeout scenario runs hermetically.
cleanup_runtime_artifacts() { :; }
# shellcheck disable=SC1090,SC1091
source "$TEST_DIR/_dev_review_fns.sh"
if ! declare -F agent_auth_failed >/dev/null || ! declare -F inspect_plan_output >/dev/null \
   || ! declare -F abort_on_timeout >/dev/null; then
  echo "FAIL: dev-review.sh functions not sourced — simulation cannot continue"
  exit 1
fi

# ---------------------------------------------------------------------------
# (a) agent_auth_failed — a >50-word auth-error PAGE in the output is an auth
# failure (rc 0) at BOTH the execute gate (executor agent) and the verify gate
# (verifier agent). The old <50-word ceiling accepted this page as work product.
# The two callers (887/897 execute, 1039 verify) invoke the same function with
# their respective agent types, so exercising both names covers both gates.
# ---------------------------------------------------------------------------
authpage="$TEST_DIR/authpage.md"
{
  printf 'Not logged in \xc2\xb7 Please run /login\n\n'
  printf 'You are not currently authenticated with the Claude CLI. To use this\n'
  printf 'command you must first sign in with your Anthropic account. Run the\n'
  printf 'login command in an interactive terminal, complete the browser flow,\n'
  printf 'and then re-run. If you continue to see this message your session token\n'
  printf 'may have expired or your organization may not have access to this tier.\n'
} > "$authpage"
authpage_words=$(wc -w < "$authpage" | tr -d '\r\n ')

for gate in "execute:opus" "verify:codex"; do
  gate_name="${gate%%:*}"; gate_agent="${gate##*:}"
  TOTAL=$((TOTAL + 1))
  err="$TEST_DIR/${gate_name}-err.log"; : > "$err"
  rc=0; agent_auth_failed "$gate_agent" "$authpage" "$err" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 0 && "$authpage_words" -ge 50 ]]; then
    pass "C1-${gate_name}: >50-word auth page ($authpage_words words) at ${gate_name} gate -> auth failure (rc 0)"
  else
    fail "C1-${gate_name}: >50-word auth page ($authpage_words words) -> expected rc 0, got $rc"
  fi
done

# ---------------------------------------------------------------------------
# (b) agent_auth_failed — a legitimate long output that echoes "Unauthorized"
# and "Not logged in" MID-body (never line-leading) passes BOTH gates: it is
# real work product, not the CLI's own banner, so the function returns 1.
# ---------------------------------------------------------------------------
legit="$TEST_DIR/legit-exec.md"
{
  printf '# Auth Handling Change — Execution Log\n\n'
  printf 'Wired the retry wrapper so a response marked Unauthorized is treated as\n'
  printf 'fatal and surfaces immediately. When the token is missing the upstream\n'
  printf 'returns a body that reads "Not logged in" and the wrapper must not retry\n'
  printf 'that case. Added structured logging so operators can audit every attempt\n'
  printf 'and see exactly why a request was rejected as Unauthorized after a run.\n'
} > "$legit"
legit_words=$(wc -w < "$legit" | tr -d '\r\n ')

for gate in "execute:opus" "verify:codex"; do
  gate_name="${gate%%:*}"; gate_agent="${gate##*:}"
  TOTAL=$((TOTAL + 1))
  err="$TEST_DIR/${gate_name}-legit-err.log"; : > "$err"
  rc=0; agent_auth_failed "$gate_agent" "$legit" "$err" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 1 && "$legit_words" -ge 50 ]]; then
    pass "C1-${gate_name}-legit: long output echoing auth phrases mid-body ($legit_words words) passes ${gate_name} gate (rc 1)"
  else
    fail "C1-${gate_name}-legit: legit output ($legit_words words) -> expected rc 1, got $rc"
  fi
done

# ---------------------------------------------------------------------------
# C-6 inspect_plan_output — a legitimate plan discussing "401 Unauthorized" and
# "npm login required" mid-body must NOT be routed to manual review (status
# stays "ok"); a leading auth banner still is (status "review").
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
c6ok="$TEST_DIR/c6-ok.md"; c6err="$TEST_DIR/c6-err.log"
{
  printf '# Publish Pipeline Plan\n\n## Goal\n'
  printf 'Automate the npm publish. The CI job fails with "401 Unauthorized" when\n'
  printf 'the token is stale, and the local dry-run prints "npm login required" —\n'
  printf 'both are expected states the plan must handle by refreshing credentials\n'
  printf 'before the release step rather than aborting the whole pipeline run.\n\n'
  printf '## Steps\n1. Validate the token.\n2. Refresh on failure.\n3. Publish.\n'
} > "$c6ok"
: > "$c6err"
PLAN_OUTPUT_STATUS=""; PLAN_OUTPUT_REASON=""
rc=0; inspect_plan_output opus "$c6ok" "$c6err" >/dev/null 2>&1 || rc=$?
# A valid plan may still be flagged "thin" by later checks, but it must NOT be
# "review" on the auth leg — that is the C-6 false positive under test.
if [[ "$PLAN_OUTPUT_STATUS" != "review" ]]; then
  pass "C6-ok: plan discussing '401 Unauthorized'/'npm login required' mid-body -> status '$PLAN_OUTPUT_STATUS' (not routed to auth review)"
else
  fail "C6-ok: legit plan -> unexpectedly routed to review ($PLAN_OUTPUT_REASON)"
fi

TOTAL=$((TOTAL + 1))
c6bad="$TEST_DIR/c6-bad.md"
cp "$authpage" "$c6bad"
PLAN_OUTPUT_STATUS=""; PLAN_OUTPUT_REASON=""
rc=0; inspect_plan_output opus "$c6bad" "$c6err" >/dev/null 2>&1 || rc=$?
if [[ "$PLAN_OUTPUT_STATUS" == "review" && "$rc" -eq 1 ]]; then
  pass "C6-bad: leading auth banner in plan output -> status 'review' (rc 1)"
else
  fail "C6-bad: auth-banner plan -> expected status 'review' rc 1, got '$PLAN_OUTPUT_STATUS' rc $rc"
fi

# ---------------------------------------------------------------------------
# C-8 (cross-vendor review): a CLI whose ENTIRE output is a bare "Unauthorized"
# line. The anchored banner scan deliberately skips bare tokens, so removing
# the <50-word ceiling reopened exactly this case; output_is_auth_failure
# restores the loose-when-short catch. Pin it at every output-path gate:
# execute + verify (agent_auth_failed) and the plan gate (inspect_plan_output).
# The >50-word mid-body regression guards for the same helper path are
# C1-execute-legit / C1-verify-legit / C6-ok above.
# ---------------------------------------------------------------------------
bare="$TEST_DIR/c8-bare.md"; c8err="$TEST_DIR/c8-err.log"
printf 'Unauthorized\n' > "$bare"
: > "$c8err"

for gate in "execute:opus" "verify:codex"; do
  gate_name="${gate%%:*}"; gate_agent="${gate##*:}"
  TOTAL=$((TOTAL + 1))
  rc=0; agent_auth_failed "$gate_agent" "$bare" "$c8err" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "C8-${gate_name}: sole bare 'Unauthorized' output at ${gate_name} gate -> auth failure (rc 0)"
  else
    fail "C8-${gate_name}: bare 'Unauthorized' output -> expected rc 0, got $rc"
  fi
done

TOTAL=$((TOTAL + 1))
PLAN_OUTPUT_STATUS=""; PLAN_OUTPUT_REASON=""
rc=0; inspect_plan_output opus "$bare" "$c8err" >/dev/null 2>&1 || rc=$?
if [[ "$PLAN_OUTPUT_STATUS" == "review" && "$rc" -eq 1 ]]; then
  pass "C8-plan: sole bare 'Unauthorized' output at plan gate -> status 'review' (rc 1)"
else
  fail "C8-plan: bare 'Unauthorized' plan output -> expected status 'review' rc 1, got '$PLAN_OUTPUT_STATUS' rc $rc"
fi

# Same bare-line variant with "Not authenticated" — the other token the
# anchored matcher deliberately excludes; the short+loose catch must hold too.
TOTAL=$((TOTAL + 1))
printf 'Not authenticated\n' > "$bare"
rc=0; agent_auth_failed opus "$bare" "$c8err" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "C8-notauth: sole bare 'Not authenticated' output -> auth failure (rc 0)"
else
  fail "C8-notauth: bare 'Not authenticated' output -> expected rc 0, got $rc"
fi

# ---------------------------------------------------------------------------
# (c) abort_on_timeout — a timeout abort is a terminal exit-1 run: state.json
# must read status="failed" with current_phase=null, not the "pending" init
# (which a status reader treats as "still running"). Runs in a subshell because
# abort_on_timeout exits; the state writes land before exit, so the parent then
# inspects the file. Requires jq (as every state.json sim does).
# ---------------------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  TOTAL=$((TOTAL + 1))
  STATE_JSON="$TEST_DIR/timeout-state.json"
  init_state_json "$STATE_JSON" "sim-timeout" "sim task" "codex" "codex" "opus"
  # abort_on_timeout only fires when LAST_INVOKE_EXIT_CODE==124.
  LAST_INVOKE_EXIT_CODE=124
  PHASE_TIMEOUT=1800
  sub_rc=0
  ( abort_on_timeout "execute" "2026-07-07T00:00:00Z" ) >/dev/null 2>&1 || sub_rc=$?
  status_val=$(jq -r '.status' "$STATE_JSON")
  phase_val=$(jq -r '.current_phase' "$STATE_JSON")
  if [[ "$sub_rc" -eq 1 && "$status_val" == "failed" && "$phase_val" == "null" ]]; then
    pass "C-timeout: abort_on_timeout leaves status='failed', current_phase=null, exit 1"
  else
    fail "C-timeout: got rc=$sub_rc status='$status_val' current_phase='$phase_val' (expected 1/failed/null)"
  fi
  unset LAST_INVOKE_EXIT_CODE PHASE_TIMEOUT STATE_JSON
else
  printf 'SKIP: C-timeout scenario needs jq (not found)\n'
fi

# ---------------------------------------------------------------------------
# phase_is_writable negative case: an unknown phase name resolves read-only.
# The writable set is a fixed allowlist (execute/execute-retry/fix) plus the
# ^execute-[0-9]+$ revise-pass pattern; anything else — including a plausible
# typo like "verify" or an injection-shaped string — must return "false" so a
# read-only phase never gains write access by accident. (An empty/unset name is
# out of scope here: phase_is_writable :?-guards it, force-exiting by design.)
# ---------------------------------------------------------------------------
for bogus in "compose" "verify" "bounce" "execute-x" "exec" "execute; rm -rf"; do
  TOTAL=$((TOTAL + 1))
  verdict=$(phase_is_writable "$bogus")
  if [[ "$verdict" == "false" ]]; then
    pass "phase_is_writable: '${bogus}' -> read-only (false)"
  else
    fail "phase_is_writable: '${bogus}' -> expected false, got '$verdict'"
  fi
done

# Positive control: a real writable phase and a numbered revise pass stay true.
for good in "execute" "execute-2"; do
  TOTAL=$((TOTAL + 1))
  verdict=$(phase_is_writable "$good")
  if [[ "$verdict" == "true" ]]; then
    pass "phase_is_writable: '${good}' -> writable (true)"
  else
    fail "phase_is_writable: '${good}' -> expected true, got '$verdict'"
  fi
done

# ---------------------------------------------------------------------------

printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
