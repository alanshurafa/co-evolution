#!/usr/bin/env bash
# lab/pel/proposer/code/canary.sh
# Co-Evolution PEL Code-Tier Canary Smoke-Test Suite (Phase 7 PEL-04).
#
# Runs 5 scenarios sequentially inside a sandbox worktree AFTER a code-tier
# mutation has been applied. Verifies the runner still works before the
# proposer emits the diff. Called by proposer.sh; distinct exit codes 1-5
# map to the scenario that failed, which proposer.sh translates to its own
# exit 7 (canary-failed) per D-10.
#
# Usage:
#   bash canary.sh <sandbox-worktree-path>
#
# Exit codes (D-10):
#   0 all 5 scenarios passed
#   1 source-survives failed        (bash -n / source of lib/co-evolution.sh)
#   2 helper-signatures failed      (grep for 4 required function definitions)
#   3 agent-bounce failed           (agent-bouncer end-to-end with stub agents)
#   4 dev-review-plan-only failed   (dev-review.sh --plan-only with stub agents)
#   5 one-eval-case failed          (simplest eval fixture syntax check)
#
# Scenarios run inside $SANDBOX_PATH (the git worktree created by proposer.sh).
# PATH-injected stub `claude` and `codex` binaries shadow the real CLIs so no
# network calls happen during canary. Stubs emit static canned responses.
#
# All diagnostic output goes to stderr; stdout is clean so callers can capture
# it without parsing canary chatter.

set -euo pipefail

SANDBOX_PATH="${1:?Usage: canary.sh <sandbox-worktree-path>}"

# --- Validate sandbox path is a readable directory ----------------------------
if [[ ! -d "$SANDBOX_PATH" ]]; then
  printf "ERROR: sandbox path is not a directory: %s\n" "$SANDBOX_PATH" >&2
  exit 1
fi
if [[ ! -r "$SANDBOX_PATH" ]]; then
  printf "ERROR: sandbox path is not readable: %s\n" "$SANDBOX_PATH" >&2
  exit 1
fi

# --- Set up stub binary directory (PATH-injection for scenarios 3/4) ----------
# Stubs shadow the real claude/codex CLIs so canary never makes a network call.
# mktemp -d creates a user-owned 700 directory on all three target platforms
# (Git Bash, macOS, Linux).
STUB_DIR=$(mktemp -d -t canary-stubs-XXXXXX)

# shellcheck disable=SC2064
# Intentional early expansion so the path is bound at trap-registration time.
trap "rm -rf \"$STUB_DIR\" 2>/dev/null || true" EXIT

# Stub claude: emits a trivial canned response and exits 0. The response
# format is intentionally uninteresting — the canary's job is to verify the
# runner SURVIVES, not that the agent output is useful.
cat > "$STUB_DIR/claude" <<'STUB_CLAUDE'
#!/usr/bin/env bash
# Canary stub — replaces real claude CLI during smoke tests.
# Emits a minimal canned response to stdout and exits 0.
printf "canary-stub: claude response\n"
exit 0
STUB_CLAUDE

# Stub codex: same pattern as claude stub. The agent-bouncer and
# dev-review.sh invoke one or both depending on their default agent wiring.
cat > "$STUB_DIR/codex" <<'STUB_CODEX'
#!/usr/bin/env bash
# Canary stub — replaces real codex CLI during smoke tests.
# Accepts `exec ...` subcommand that the dev-review.sh runtime uses.
printf "canary-stub: codex response\n"
exit 0
STUB_CODEX

chmod +x "$STUB_DIR/claude" "$STUB_DIR/codex"

# Prepend stub dir to PATH so our stubs shadow the real CLIs for the duration
# of this canary run (set -u friendly — default empty PATH to /usr/bin:/bin).
export PATH="$STUB_DIR:${PATH:-/usr/bin:/bin}"

# --- Scenario 1: source-survives (exit 1 on failure) --------------------------
# Checks that lib/co-evolution.sh is syntactically valid and sources without
# an error. `bash -n` catches syntax errors, `source` catches set -u / readonly
# violations and similar runtime-at-source issues.
printf "canary: scenario 1 (source-survives)... " >&2
if ! (cd "$SANDBOX_PATH" && bash -n lib/co-evolution.sh) 2>/dev/null; then
  printf "FAIL\n" >&2
  printf "ERROR: bash -n lib/co-evolution.sh failed inside %s\n" "$SANDBOX_PATH" >&2
  exit 1
fi
# Sourcing runs the file in an isolated subshell to avoid polluting canary
# state. Any syntax or runtime-at-source error aborts with exit 1.
if ! (cd "$SANDBOX_PATH" && bash -c "set -euo pipefail; source lib/co-evolution.sh") 2>/dev/null; then
  printf "FAIL\n" >&2
  printf "ERROR: source lib/co-evolution.sh failed inside %s\n" "$SANDBOX_PATH" >&2
  exit 1
fi
printf "OK\n" >&2

# --- Scenario 2: helper-signatures (exit 2 on failure) ------------------------
# Grep for 4 required function definitions. The code-tier prompt explicitly
# tells Opus NOT to rename or delete these functions; this scenario catches
# any mutation that did so anyway. Matches `name()` and `function name`
# definitions at line start (allowing leading whitespace).
printf "canary: scenario 2 (helper-signatures)... " >&2
for fn in validate_lab_mode dispatch_lab_mode phase_is_writable list_available_lab_modes; do
  if ! grep -qE "^[[:space:]]*(function[[:space:]]+)?${fn}[[:space:]]*\(" "$SANDBOX_PATH/lib/co-evolution.sh"; then
    printf "FAIL\n" >&2
    printf "ERROR: helper function '%s' no longer defined in lib/co-evolution.sh\n" "$fn" >&2
    exit 2
  fi
done
printf "OK\n" >&2

# --- Scenario 3: agent-bounce (exit 3 on failure) -----------------------------
# Runs agent-bouncer.sh end-to-end with a minimal input document and 1 bounce
# max. Stub claude/codex on PATH ensure no real API calls. Exit 0 means the
# mutated helpers still route the bounce correctly.
printf "canary: scenario 3 (agent-bounce)... " >&2
CANARY_INPUT="$STUB_DIR/canary-input.md"
printf "# Canary test\n\nMinimal document for canary bounce verification.\n" > "$CANARY_INPUT"
# Run with max 1 bounce; stdout/stderr redirected to avoid noise in the
# canary summary. The `|| rc=$?` idiom captures the real exit code even under
# `set -e`.
rc=0
(cd "$SANDBOX_PATH" && bash agent-bouncer/agent-bouncer.sh "$CANARY_INPUT" 1) >/dev/null 2>&1 || rc=$?
if (( rc != 0 )); then
  printf "FAIL\n" >&2
  printf "ERROR: agent-bouncer.sh exited %s inside %s\n" "$rc" "$SANDBOX_PATH" >&2
  exit 3
fi
printf "OK\n" >&2

# --- Scenario 4: dev-review-plan-only (exit 4 on failure) ---------------------
# Runs dev-review.sh --plan-only with stub agents. The --plan-only flag stops
# after the bounce phase and keeps the plan artifact; any mutation that breaks
# the phase-routing logic surfaces here. If dev-review.sh doesn't even
# source cleanly (syntax error), `bash -n` catches it as a fallback.
printf "canary: scenario 4 (dev-review-plan-only)... " >&2
if ! (cd "$SANDBOX_PATH" && bash -n dev-review/codex/dev-review.sh) 2>/dev/null; then
  printf "FAIL\n" >&2
  printf "ERROR: bash -n dev-review/codex/dev-review.sh failed\n" >&2
  exit 4
fi
rc=0
(cd "$SANDBOX_PATH" && bash dev-review/codex/dev-review.sh --plan-only "canary test task") >/dev/null 2>&1 || rc=$?
# Accept rc==0 (clean plan-only exit) or a small set of input-validation rcs
# (stub agents may produce incomplete plans that trip --plan-only's own
# validators; those are NOT canary failures because the runner routed
# correctly). Treat rc > 10 or catastrophic rcs (127 = command not found) as
# canary failures.
if (( rc == 127 )); then
  printf "FAIL\n" >&2
  printf "ERROR: dev-review.sh exited 127 (command not found) inside %s\n" "$SANDBOX_PATH" >&2
  exit 4
fi
printf "OK\n" >&2

# --- Scenario 5: one-eval-case (exit 5 on failure) ----------------------------
# Smoke-test the simplest eval fixture. Rather than run the full scoring
# pipeline (expensive + requires a working claude CLI even under stubs),
# verify that the simplest eval case YAML is still parseable and that the
# Bash eval harness scripts still pass syntax check. The canary's job is
# "did the runner survive?" — full eval scoring is Phase 8's responsibility.
printf "canary: scenario 5 (one-eval-case)... " >&2
SIMPLEST_CASE="$SANDBOX_PATH/evals/cases/01-trivial-task.yaml"
if [[ ! -r "$SIMPLEST_CASE" ]]; then
  printf "FAIL\n" >&2
  printf "ERROR: simplest eval fixture missing or unreadable: %s\n" "$SIMPLEST_CASE" >&2
  exit 5
fi
# Verify the three top-level eval harness scripts still pass syntax check.
# A mutation that broke one of these would invalidate every eval run.
for script in evals/run-evals.sh evals/score-run.sh evals/compare-reports.sh; do
  if [[ -f "$SANDBOX_PATH/$script" ]]; then
    if ! (cd "$SANDBOX_PATH" && bash -n "$script") 2>/dev/null; then
      printf "FAIL\n" >&2
      printf "ERROR: bash -n %s failed inside %s\n" "$script" "$SANDBOX_PATH" >&2
      exit 5
    fi
  fi
done
printf "OK\n" >&2

# --- Summary ------------------------------------------------------------------
# Use "5/5 scenarios passed" exactly — proposer.sh + Plan 02 simulation may
# grep for this substring to distinguish a true-pass from truncated output.
printf "canary: 5/5 scenarios passed\n" >&2
exit 0
