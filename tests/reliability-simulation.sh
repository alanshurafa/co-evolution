#!/usr/bin/env bash
# tests/reliability-simulation.sh — v1.3 Phase 1 reliability hardening gate.
#
# Covers the silent-failure class from docs/audits/2026-06-10-v13-audit.md:
#   R-1/R-2  auth-failure and CLI-missing detection (validate_agent_artifact)
#   C-2/S-2  template-fill metacharacter pinning (finding was a false positive
#            for bash parameter expansion — these tests pin that safety)
#   R-4      compute_execute_delta jq-unavailable fallback must say "unknown"
#   R-7      run-suffix entropy (same-second collision prevention)
#   S-1      protocol-marker stripping from TASK text
#   E2E      co-evolve-bouncer aborts (not "succeeds") when the agent CLI
#            returns an auth error — the original invoke_claude bug.
#
# Hermetic: stubs the agent CLIs via PATH injection; no network, no LLM cost.

set -euo pipefail

TEST_DIR=$(mktemp -d -t reliability-sim-XXXXXX)
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
# R-1/R-2: validate_agent_artifact
# ---------------------------------------------------------------------------

# Scenario 1: short auth-error text in the OUTPUT file -> fatal (rc 2).
TOTAL=$((TOTAL + 1))
out="$TEST_DIR/s1-out.md"; err="$TEST_DIR/s1-err.log"
printf 'Failed to authenticate. Please run `claude login` to continue.\n' > "$out"
: > "$err"
rc=0; validate_agent_artifact "$out" "$err" claude >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass "S1: auth error in output -> rc 2 (fail fast, no retry)"
else
  fail "S1: auth error in output -> expected rc 2, got $rc"
fi

# Scenario 2: empty output + auth-error text in STDERR -> fatal (rc 2).
TOTAL=$((TOTAL + 1))
out="$TEST_DIR/s2-out.md"; err="$TEST_DIR/s2-err.log"
: > "$out"
printf 'authentication_error: OAuth token expired\n' > "$err"
rc=0; validate_agent_artifact "$out" "$err" claude >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass "S2: auth error in stderr + empty output -> rc 2"
else
  fail "S2: auth error in stderr -> expected rc 2, got $rc"
fi

# Scenario 3: empty output + "command not found" in stderr -> fatal (rc 2).
TOTAL=$((TOTAL + 1))
out="$TEST_DIR/s3-out.md"; err="$TEST_DIR/s3-err.log"
: > "$out"
printf 'bash: line 1: claude: command not found\n' > "$err"
rc=0; validate_agent_artifact "$out" "$err" claude >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass "S3: CLI missing (command not found) -> rc 2"
else
  fail "S3: CLI missing -> expected rc 2, got $rc"
fi

# Scenario 4: a long legitimate document that MENTIONS auth terms -> OK (rc 0).
TOTAL=$((TOTAL + 1))
out="$TEST_DIR/s4-out.md"; err="$TEST_DIR/s4-err.log"
{
  printf '# Security Review of the Login Flow\n\n'
  printf 'The reviewer flagged that the service returns Unauthorized when the\n'
  printf 'session cookie is stale, and that the retry path must not loop. '
  for i in $(seq 1 60); do printf 'word%d ' "$i"; done
  printf '\n\nConclusion: rotate tokens on every Not authenticated response.\n'
} > "$out"
: > "$err"
rc=0; validate_agent_artifact "$out" "$err" claude >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "S4: long document mentioning auth terms -> rc 0 (no false positive)"
else
  fail "S4: long document mentioning auth terms -> expected rc 0, got $rc"
fi

# Scenario 5: empty output, quiet stderr -> retryable (rc 1).
TOTAL=$((TOTAL + 1))
out="$TEST_DIR/s5-out.md"; err="$TEST_DIR/s5-err.log"
: > "$out"; : > "$err"
rc=0; validate_agent_artifact "$out" "$err" claude >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 1 ]]; then
  pass "S5: empty output, quiet stderr -> rc 1 (retryable)"
else
  fail "S5: empty output -> expected rc 1, got $rc"
fi

# ---------------------------------------------------------------------------
# C-2/S-2: fill_template metacharacter pinning (false-positive verification)
# ---------------------------------------------------------------------------

# Scenario 6: &, backslash, backtick, $, and newlines survive byte-exact.
TOTAL=$((TOTAL + 1))
tpl="$TEST_DIR/s6-tpl.md"
printf 'BEGIN {CONTENT} END\n' > "$tpl"
value='amp & back \ slash tick ` dollar $VAR brace } done
second line'
got=$(fill_template "$tpl" "CONTENT=$value")
want="BEGIN $value END"
if [[ "$got" == "$want" ]]; then
  pass "S6: fill_template preserves & \\ \` \$ and newlines byte-exact"
else
  fail "S6: fill_template corrupted metacharacters: got [$got]"
fi

# Scenario 7: CRLF content survives (PC-authored document bounced on a Mac).
TOTAL=$((TOTAL + 1))
tpl="$TEST_DIR/s7-tpl.md"
printf 'A {CONTENT} B\n' > "$tpl"
value=$(printf 'crlf line one\r\ncrlf line two\r')
got=$(fill_template "$tpl" "CONTENT=$value")
want="A $value B"
if [[ "$got" == "$want" ]]; then
  pass "S7: fill_template preserves CRLF content byte-exact"
else
  fail "S7: fill_template corrupted CRLF content"
fi

# Scenario 8: content filled LAST keeps placeholder-like text literal — the
# documented reason both bouncers substitute PLAN_CONTENT after all other keys.
TOTAL=$((TOTAL + 1))
tpl="$TEST_DIR/s8-tpl.md"
printf 'task={TASK} doc={PLAN_CONTENT}\n' > "$tpl"
doc='this document contains a literal {TASK} placeholder'
rendered=$(fill_template "$tpl" "TASK=real task")
rendered="${rendered//\{PLAN_CONTENT\}/$doc}"
if [[ "$rendered" == "task=real task doc=this document contains a literal {TASK} placeholder" ]]; then
  pass "S8: PLAN_CONTENT-last ordering keeps {TASK} in documents literal"
else
  fail "S8: ordering violation: [$rendered]"
fi

# ---------------------------------------------------------------------------
# R-4: compute_execute_delta jq fallback
# ---------------------------------------------------------------------------

# Scenario 9: with jq -> delta_status "computed" and real arrays.
TOTAL=$((TOTAL + 1))
b="$TEST_DIR/s9-b.json"; c="$TEST_DIR/s9-c.json"; o="$TEST_DIR/s9-o.json"
printf '{"a.txt":"h1","b.txt":"h2"}\n' > "$b"
printf '{"a.txt":"h1-changed","c.txt":"h3"}\n' > "$c"
compute_execute_delta "$b" "$c" "$o"
if jq -e '.delta_status == "computed" and .modified == ["a.txt"] and .added == ["c.txt"] and .deleted == ["b.txt"]' "$o" >/dev/null 2>&1; then
  pass "S9: delta with jq -> delta_status=computed + correct arrays"
else
  fail "S9: delta with jq -> unexpected: $(cat "$o")"
fi

# Scenario 10: without jq -> delta_status "unknown" (NOT silent empty arrays).
TOTAL=$((TOTAL + 1))
o="$TEST_DIR/s10-o.json"
nojq_bin="$TEST_DIR/nojq-bin"
mkdir -p "$nojq_bin"
for tool in bash sh grep sed awk cat cp mv rm printf wc tr date mktemp dirname basename; do
  src=$(command -v "$tool" 2>/dev/null) || continue
  ln -s "$src" "$nojq_bin/$tool" 2>/dev/null || true
done
PATH="$nojq_bin" "$(command -v bash)" -c "source '$REPO_ROOT/lib/co-evolution.sh'; compute_execute_delta '$b' '$c' '$o'" 2>/dev/null
if grep -q '"delta_status":"unknown"' "$o"; then
  pass "S10: delta without jq -> delta_status=unknown"
else
  fail "S10: delta without jq -> missing unknown marker: $(cat "$o")"
fi

# ---------------------------------------------------------------------------
# R-7: run-suffix entropy
# ---------------------------------------------------------------------------

# Scenario 11: format + uniqueness across rapid consecutive draws.
TOTAL=$((TOTAL + 1))
s11_ok=true
suffixes=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  s=$(generate_run_suffix)
  case "$s" in
    *[!a-z0-9-]*) s11_ok=false ;;
  esac
  if printf '%s\n' "$suffixes" | grep -qx "$s"; then
    s11_ok=false
  fi
  suffixes="$suffixes$s
"
done
if [[ "$s11_ok" == true ]] && printf '%s' "$suffixes" | head -1 | grep -qE '^[0-9]{8}-[0-9]{6}-[0-9a-f]{6}$'; then
  pass "S11: generate_run_suffix format + 10 rapid draws unique"
else
  fail "S11: generate_run_suffix collision or bad format: $suffixes"
fi

# ---------------------------------------------------------------------------
# S-1: protocol-marker stripping from TASK text
# ---------------------------------------------------------------------------

# Scenario 12: bare and payload-bearing markers are removed from TASK.
TOTAL=$((TOTAL + 1))
got=$(strip_protocol_markers 'do X [CONTESTED] and [CLARIFY: why?] then [CONTESTED: claim vs claim] done')
if [[ "$got" != *'[CONTESTED'* && "$got" != *'[CLARIFY'* && "$got" == *'do X'* && "$got" == *'done'* ]]; then
  pass "S12: strip_protocol_markers removes bare + payload markers"
else
  fail "S12: markers survived: [$got]"
fi

# ---------------------------------------------------------------------------
# E2E: co-evolve-bouncer must ABORT when the agent returns an auth error
# (the original invoke_claude bug: error text accepted as the document).
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
printf 'Failed to authenticate. Please run `claude login`.\n'
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
if grep -rq 'Failed to authenticate' "$doc" 2>/dev/null; then
  final_doc_corrupted=true
fi
if [[ "$rc" -ne 0 && "$final_doc_corrupted" == false ]] \
   && grep -qiE 'auth' "$e2e/stdout.log" "$e2e/stderr.log" 2>/dev/null; then
  pass "S13: bouncer aborts on auth error; document not overwritten with error text"
else
  fail "S13: rc=$rc corrupted=$final_doc_corrupted (expected nonzero rc, clean doc, auth mention)"
fi

# ---------------------------------------------------------------------------

printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
