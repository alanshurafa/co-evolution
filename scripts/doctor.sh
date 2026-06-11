#!/usr/bin/env bash
# scripts/doctor.sh — preflight environment check for the co-evolution toolkit.
#
# Verifies every external dependency the runners, eval harness, and PEL lab
# reach for, and says which component needs each one. Run it on any fresh
# machine (macOS, Linux, Git Bash on Windows, WSL) before first use:
#
#   bash scripts/doctor.sh
#
# Exit codes: 0 = all required dependencies present; 1 = at least one required
# dependency missing. Optional gaps never fail the check — they print what
# degrades without them.

set -u

PASS=0
FAIL=0
WARN=0

ok()   { printf 'OK        %-12s %s\n' "$1" "$2"; PASS=$((PASS + 1)); }
miss() { printf 'MISSING   %-12s %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }
warn() { printf 'OPTIONAL  %-12s %s\n' "$1" "$2"; WARN=$((WARN + 1)); }

printf 'co-evolution doctor — %s\n' "$(uname -s) $(uname -m)"
printf -- '---------------------------------------------------------------\n'

# --- bash version -----------------------------------------------------------
# The toolkit is kept bash-3.2 compatible (stock macOS /bin/bash). Newer bash
# is fine. If this script is running, bash exists; report the version.
if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
  ok bash "v${BASH_VERSION} (4+ — full support)"
else
  ok bash "v${BASH_VERSION} (3.2 supported; 4+ recommended: brew install bash)"
fi

# --- core required ----------------------------------------------------------
if command -v git >/dev/null 2>&1; then
  ok git "$(git --version 2>/dev/null | head -1)"
else
  miss git "required everywhere (runs, worktrees, PEL sandboxes)"
fi

if command -v jq >/dev/null 2>&1; then
  ok jq "$(jq --version 2>/dev/null)"
else
  miss jq "required: state.json, verdicts, eval scoring"
fi

if command -v awk >/dev/null 2>&1; then
  ok awk "$(command -v awk)"
else
  miss awk "required: marker counting, scoring"
fi

# --- agent CLIs -------------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
  ok claude "$(command -v claude)"
  # Auth probe: `claude -p` on a missing/unauthenticated session prints an
  # auth error. A cheap --version-style probe is not enough; just remind.
  printf '          %-12s %s\n' '' 'if runs fail with auth errors: run `claude` once interactively to log in'
else
  miss claude "required: every co-evolve / dev-review pass uses the Claude CLI"
fi

if command -v codex >/dev/null 2>&1; then
  ok codex "$(command -v codex)"
else
  warn codex "dev-review's default composer/executor and the cross-AI bounce need it; co-evolve --vanilla works without it"
fi

# --- eval harness + PEL lab -------------------------------------------------
if command -v yq >/dev/null 2>&1; then
  if yq --version 2>&1 | grep -qi mikefarah; then
    ok yq "$(yq --version 2>&1)"
  else
    miss yq "wrong yq: the python yq is on PATH; evals + PEL need mikefarah/Go yq v4+ (brew install yq / scoop install yq)"
  fi
else
  warn yq "eval harness (evals/) and PEL lab (lab/pel/) need mikefarah yq v4+; core bounce flow does not"
fi

if command -v xxd >/dev/null 2>&1; then
  ok xxd "$(command -v xxd)"
else
  warn xxd "evals/score-run.sh uses xxd for byte-level diagnostics"
fi

if command -v gh >/dev/null 2>&1; then
  ok gh "$(gh --version 2>/dev/null | head -1)"
else
  warn gh "PEL pr-emitter draft-PR creation needs it (dry-run works without)"
fi

if command -v python3 >/dev/null 2>&1; then
  ok python3 "$(python3 --version 2>/dev/null)"
else
  warn python3 "fallback path resolver on platforms whose realpath lacks -m (macOS)"
fi

# --- timeout ----------------------------------------------------------------
if command -v timeout >/dev/null 2>&1; then
  ok timeout "$(command -v timeout)"
elif command -v gtimeout >/dev/null 2>&1; then
  ok gtimeout "$(command -v gtimeout) (GNU coreutils alias)"
elif command -v perl >/dev/null 2>&1; then
  warn timeout "absent; perl-alarm fallback active (stock macOS: brew install coreutils for timeout)"
else
  warn timeout "absent and no perl — per-phase timeouts degrade to unbounded dispatch"
fi

printf -- '---------------------------------------------------------------\n'
printf '%d ok, %d missing, %d optional-degraded\n' "$PASS" "$FAIL" "$WARN"

if (( FAIL > 0 )); then
  printf 'FAIL: install the MISSING items above before running the toolkit.\n'
  exit 1
fi
printf 'All required dependencies present.\n'
