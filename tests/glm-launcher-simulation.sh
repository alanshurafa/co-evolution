#!/usr/bin/env bash
# Hermetic launcher checks: the GLM child receives only the intended Z.AI route,
# while inherited Claude gateway selectors, headers, and credentials stay out.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$(mktemp -d -t glm-launcher-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
FAILURES=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

provider_vars='ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY'

mkdir -p "$TEST_DIR/bash-bin"
cat > "$TEST_DIR/bash-bin/claude" <<'BASH_STUB'
#!/usr/bin/env bash
{
  printf 'ARGV=%s\n' "$*"
  [[ "${ANTHROPIC_BASE_URL:-}" == 'https://api.z.ai/api/anthropic' ]] && printf '%s\n' 'BASE_MATCH=1'
  [[ "${ANTHROPIC_AUTH_TOKEN:-}" == 'launcher-test-key' ]] && printf '%s\n' 'TOKEN_MATCH=1'
  [[ "${CLAUDE_CONFIG_DIR:-}" == */.claude-glm ]] && printf '%s\n' 'CONFIG_MATCH=1'
  for name in ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS CLAUDE_CODE_OAUTH_TOKEN \
    CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY; do
    [[ -n "${!name+x}" ]] && printf '%s_PRESENT=1\n' "$name"
  done
} > "$GLM_LAUNCHER_LOG"
exit 0
BASH_STUB
chmod +x "$TEST_DIR/bash-bin/claude"

# Scenario 1: portable Bash launcher scrubs inherited provider state.
TOTAL=$((TOTAL + 1))
bash_log="$TEST_DIR/bash-child.log"
s1_rc=0
(
  export PATH="$TEST_DIR/bash-bin:$PATH"
  export GLM_LAUNCHER_LOG="$bash_log"
  export ZAI_API_KEY='launcher-test-key'
  export ANTHROPIC_API_KEY='inherited-secret'
  export ANTHROPIC_CUSTOM_HEADERS='x-secret: inherited'
  export CLAUDE_CODE_OAUTH_TOKEN='inherited-oauth'
  export CLAUDE_CODE_USE_BEDROCK=1 CLAUDE_CODE_USE_VERTEX=1 CLAUDE_CODE_USE_FOUNDRY=1
  "$REPO_ROOT/scripts/launchers/glm.sh" 'hello world'
) > "$TEST_DIR/s1.out" 2>&1 || s1_rc=$?
s1_ok=true
[[ "$s1_rc" -eq 0 ]] || s1_ok=false
grep -Fq 'ARGV=--safe-mode --model glm-5.3-flash hello world' "$bash_log" || s1_ok=false
grep -Fq 'BASE_MATCH=1' "$bash_log" || s1_ok=false
grep -Fq 'TOKEN_MATCH=1' "$bash_log" || s1_ok=false
grep -Fq 'CONFIG_MATCH=1' "$bash_log" || s1_ok=false
for name in $provider_vars; do
  if grep -Fq "${name}_PRESENT=1" "$bash_log"; then s1_ok=false; fi
done
if [[ "$s1_ok" == true ]]; then
  pass "GLM Bash launcher: child route is isolated from inherited provider secrets"
else
  fail "GLM Bash launcher leaked or misrouted provider environment"
  { cat "$TEST_DIR/s1.out"; cat "$bash_log"; } >&2
fi

# Scenario 2: Windows PowerShell launcher applies the same child-env scrub.
TOTAL=$((TOTAL + 1))
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    mkdir -p "$TEST_DIR/ps-bin"
    cat > "$TEST_DIR/ps-bin/claude.cmd" <<'CMD_STUB'
@echo off
> "%GLM_LAUNCHER_LOG%" (
  echo ARGV=%*
  if "%ANTHROPIC_BASE_URL%"=="https://api.z.ai/api/anthropic" echo BASE_MATCH=1
  if "%ANTHROPIC_AUTH_TOKEN%"=="launcher-test-key" echo TOKEN_MATCH=1
  if defined CLAUDE_CONFIG_DIR echo CONFIG_PRESENT=1
  if defined ANTHROPIC_API_KEY echo ANTHROPIC_API_KEY_PRESENT=1
  if defined ANTHROPIC_CUSTOM_HEADERS echo ANTHROPIC_CUSTOM_HEADERS_PRESENT=1
  if defined CLAUDE_CODE_OAUTH_TOKEN echo CLAUDE_CODE_OAUTH_TOKEN_PRESENT=1
  if defined CLAUDE_CODE_USE_BEDROCK echo CLAUDE_CODE_USE_BEDROCK_PRESENT=1
  if defined CLAUDE_CODE_USE_VERTEX echo CLAUDE_CODE_USE_VERTEX_PRESENT=1
  if defined CLAUDE_CODE_USE_FOUNDRY echo CLAUDE_CODE_USE_FOUNDRY_PRESENT=1
)
exit /b 0
CMD_STUB
    ps_log="$TEST_DIR/ps-child.log"
    ps_log_win=$(cygpath -w "$ps_log")
    ps_launcher_win=$(cygpath -w "$REPO_ROOT/scripts/launchers/glm.ps1")
    s2_rc=0
    (
      export PATH="$TEST_DIR/ps-bin:$PATH"
      export GLM_LAUNCHER_LOG="$ps_log_win"
      export ZAI_API_KEY='launcher-test-key'
      export ANTHROPIC_API_KEY='inherited-secret'
      export ANTHROPIC_CUSTOM_HEADERS='x-secret: inherited'
      export CLAUDE_CODE_OAUTH_TOKEN='inherited-oauth'
      export CLAUDE_CODE_USE_BEDROCK=1 CLAUDE_CODE_USE_VERTEX=1 CLAUDE_CODE_USE_FOUNDRY=1
      powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$ps_launcher_win" 'hello world'
    ) > "$TEST_DIR/s2.out" 2>&1 || s2_rc=$?
    s2_ok=true
    [[ "$s2_rc" -eq 0 ]] || s2_ok=false
    grep -Fq 'ARGV=--safe-mode --model glm-5.3-flash "hello world"' "$ps_log" || s2_ok=false
    grep -Fq 'BASE_MATCH=1' "$ps_log" || s2_ok=false
    grep -Fq 'TOKEN_MATCH=1' "$ps_log" || s2_ok=false
    grep -Fq 'CONFIG_PRESENT=1' "$ps_log" || s2_ok=false
    for name in $provider_vars; do
      if grep -Fq "${name}_PRESENT=1" "$ps_log"; then s2_ok=false; fi
    done
    if [[ "$s2_ok" == true ]]; then
      pass "GLM PowerShell launcher: child route is isolated from inherited provider secrets"
    else
      fail "GLM PowerShell launcher leaked or misrouted provider environment"
      { cat "$TEST_DIR/s2.out"; cat "$ps_log"; } >&2
    fi
    ;;
  *)
    pass "GLM PowerShell launcher: Windows-only check not exercised on this host"
    ;;
esac

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
fi

echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
exit 1
