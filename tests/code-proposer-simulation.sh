#!/usr/bin/env bash
# tests/code-proposer-simulation.sh
# Phase 7 PEL-04: Hermetic simulation of lab/pel/proposer/code/ behavior.
#
# SC-5 gate — 16 primary scenarios (all required), exits 0 with the
# "16/16 scenarios passed" line as the final stdout line on clean Plan 01
# proposer surface. No real Opus invocation; claude CLI is PATH-injected stub
# returning canned diffs per scenario; no network traffic.
#
# Scenarios (see <threat_model> in 07-02-PLAN.md for STRIDE mappings):
#
#   Happy-path (4 flavors, one each — exit 0):
#   A: Flavor=bug-catcher              — valid diff against lib/co-evolution.sh
#                                        (retry-logic-weakness feedback); canary
#                                        must pass with stub infrastructure;
#                                        state.json must have outcome=accepted,
#                                        canary.passed=true, diff_lines<=20.
#   B: Flavor=faster-converger         — valid diff against
#                                        dev-review/codex/dev-review.sh
#                                        (phase-timeout-improvement feedback).
#   C: Flavor=blind-spot-surfacer      — valid diff against
#                                        agent-bouncer/agent-bouncer.sh
#                                        (error-handling-gap feedback).
#   D: Flavor=general                  — valid diff against lib/co-evolution.sh
#                                        (lab-routing-edge feedback, different
#                                        mutation from A); state.json.flavor
#                                        must be "general".
#
#   Text-pipeline edge cases (from phase-7-simulation-lessons.md — exit 0):
#   E: Empty-line context marker       — hunk contains a single-space context
#                                        line (meaningful empty-line marker in
#                                        unified diff format). Proves capture
#                                        pipeline preserves it.
#   F: No trailing newline             — diff ends with "\ No newline at end of
#                                        file" marker. Proves trailing-newline
#                                        recovery works.
#   G: CRLF-on-disk file               — LF-only stub diff applies against a
#                                        target that may have CRLF on disk (Git
#                                        Bash autocrlf=true). Proves
#                                        --whitespace=nowarn is wired.
#   H: Shell metacharacters            — diff + lines contain $VAR, backticks,
#                                        heredoc markers, globs. Proves no
#                                        eval/misparse in capture->apply.
#   I: patch-vs-git-apply divergence   — diff with mis-counted hunk header
#                                        (patch would auto-fix, git apply
#                                        rejects). Proves consistent tool
#                                        choice (git apply, not patch). Exit 3.
#
#   Adversarial rejections (exit codes 1/3/4/5/6/7):
#   J: Diff targets lab/pel/classifier/adapter.sh       → exit 5 (allowlist, frozen)
#   K: Diff targets .planning/STATE.md                  → exit 5 (planning)
#   L: Diff targets tests/classifier-simulation.sh      → exit 5 (test integrity)
#   M: Diff exceeds 20-line budget                      → exit 6 (budget)
#   N: Diff touches 2 files                             → exit 4 (single-file)
#   O: Missing PEL_CODE_FEEDBACK                        → exit 1 (input validation)
#   P: Canary failure (diff breaks bash -n)             → exit 7 (canary-failed)
#
# Final line on success: "16/16 scenarios passed" (matches v1.2 phase-gate
# convention — Phase 2 13/13, Phase 3 4/4, Phase 4 6/6, Phase 5 8/8, Phase 6 8/8).
# Exit 0 iff all 16 scenarios pass; exit 1 otherwise.
#
# Dependencies: bash, jq, git, diff, cp, sed, awk. No claude CLI (stubbed),
# no network.
#
# Cross-platform: Git Bash Windows + Linux + macOS. MSYS_NO_PATHCONV=1 used
# around any jq call that takes a path-like argument. tr -d '\r' for LF
# normalization before diff -u.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

# TEST_DIR must be INSIDE REPO_ROOT so proposer.sh's T-07-05 containment
# check accepts fixture paths. Using /tmp (mktemp default) would make every
# fixture "outside repo root" and die exit 1 before the scenario's true
# failure mode is exercised. Same pattern as policy-proposer-simulation.sh.
TEST_DIR=$(mktemp -d -p "$REPO_ROOT/tests" ".sim-code-XXXXXX")
# Export TEST_DIR so the PATH-injected git shim (below) can find its snapshot
# target location when invoked from inside proposer.sh's subshell.
export TEST_DIR

# Scope every sandbox this run creates to a private TMPDIR. proposer.sh puts
# sandboxes at ${TMPDIR:-/tmp}/pel-code-sandbox-*, and the machine-global /tmp
# let any concurrent suite's orphan-cleanup glob delete a live sandbox
# mid-canary (run-all --jobs collision, 2026-08-29). The cleanup glob below
# then also self-scopes to this run's dirs only.
export TMPDIR="$TEST_DIR/tmp"
mkdir -p "$TMPDIR"

cleanup() {
  # Belt-and-suspenders: clean any leftover pel-code-sandbox-* worktrees from
  # happy-path scenarios whose trap-EXIT from proposer.sh may not have fully
  # torn down if the outer test subshell exited mid-run.
  local orphan
  for orphan in "${TMPDIR:-/tmp}"/pel-code-sandbox-*; do
    [[ -e "$orphan" ]] || continue
    git -C "$REPO_ROOT" worktree remove --force "$orphan" 2>/dev/null || true
    rm -rf "$orphan" 2>/dev/null || true
  done
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

FAILURES=0
TOTAL=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

# ---------------------------------------------------------------------------
# Stub claude CLI (PATH-injected). Echoes whatever canned diff the test
# placed in $CODE_PROPOSER_STUB_FILE. Writes a fingerprint marker per call
# so future tests can prove invocation invariants.
#
# Env var prefix CODE_PROPOSER_* (not PROPOSER_* or POLICY_*) keeps this stub
# independent from Phase 4/5/6 stubs — all four simulations may coexist in CI
# without env collision.
# ---------------------------------------------------------------------------

mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
# PATH-injected stub for hermetic code-tier proposer simulation.
if [[ -n "${CODE_PROPOSER_STUB_MARKER:-}" ]]; then
  printf 'called\n' >> "$CODE_PROPOSER_STUB_MARKER"
fi
if [[ "$*" == *"--version"* ]]; then
  echo "claude 1.0.0 (stub)"
  exit 0
fi
# Drain stdin so the adapter's prompt-file redirect doesn't leak.
cat > /dev/null
# Optional forced-exit for negative scenarios (reserved).
if [[ -n "${CODE_PROPOSER_STUB_EXIT:-}" ]]; then
  exit "$CODE_PROPOSER_STUB_EXIT"
fi
if [[ -z "${CODE_PROPOSER_STUB_FILE:-}" || ! -f "${CODE_PROPOSER_STUB_FILE:-}" ]]; then
  echo "STUB ERROR: CODE_PROPOSER_STUB_FILE not set or file missing" >&2
  exit 99
fi
cat "$CODE_PROPOSER_STUB_FILE"
STUB
chmod +x "$TEST_DIR/bin/claude"

# canary.sh creates its own stub dir (PATH-injected claude + codex) inside the
# sandbox worktree at runtime, so the simulation does NOT need to pre-inject
# canary stubs. The canary stubs live inside canary.sh itself (Plan 01
# surface — treated as black box here). This simulation ONLY needs the claude
# stub above for proposer.sh's Opus adapter path.

# ---------------------------------------------------------------------------
# Helper: write_valid_stub_diff <dest_stub_file> <repo_rel_target_path> \
#                                <anchor_regex> <inserted_line>
#
# Same pattern as template-proposer-simulation.sh: copy real target file to
# $TEST_DIR, normalize to LF (tr -d '\r'), insert <inserted_line> immediately
# before the FIRST line matching the awk ERE <anchor_regex>, compute diff -u
# with --label for correct a/ b/ headers. Produces self-consistent diffs
# without hand-authored line numbers.
#
# awk (patterns passed via ENVIRON to avoid -v escape processing) replaces the
# previous GNU-sed `0,/pat/s|…|…\n…|` script: BSD sed on macOS does not
# support the `0,` address and silently produced an unmodified copy.
#
# Used for happy-path scenarios A-D. Edge-case scenarios E-I and adversarial
# J-P hand-craft their stubs to inject specific structural violations.
# ---------------------------------------------------------------------------
write_valid_stub_diff() {
  local dest="$1"
  local repo_rel="$2"
  local anchor_regex="$3"
  local inserted_line="$4"
  local abs="$REPO_ROOT/$repo_rel"
  local basename_rel
  basename_rel=$(basename "$repo_rel")
  local orig_copy="$TEST_DIR/orig-$basename_rel"
  local mod_copy="$TEST_DIR/mod-$basename_rel"
  # Normalize both sides to LF so the resulting diff is internally consistent.
  # On Git Bash Windows the target file on disk may have CRLF (autocrlf=true);
  # git apply with --whitespace=nowarn handles the on-disk CRLF, but the diff
  # body itself must be LF-only for the hunk-count math to line up.
  tr -d '\r' < "$abs" > "$orig_copy"
  STUB_ANCHOR="$anchor_regex" STUB_INSERT="$inserted_line" awk '
    !done && $0 ~ ENVIRON["STUB_ANCHOR"] { print ENVIRON["STUB_INSERT"]; done = 1 }
    { print }
  ' "$orig_copy" > "$mod_copy"
  diff -u --label "a/$repo_rel" --label "b/$repo_rel" "$orig_copy" "$mod_copy" > "$dest" || true
  if [[ ! -s "$dest" ]]; then
    echo "INTERNAL ERROR: write_valid_stub_diff produced an empty diff for $repo_rel" >&2
    exit 99
  fi
}

# ---------------------------------------------------------------------------
# Helper: locate state.json in the most recently-created sandbox worktree.
# proposer.sh writes state.json to $SANDBOX_PATH/state.json (D-20) BEFORE the
# trap EXIT handler removes the worktree. Since the proposer exits normally
# for happy-path, the sandbox is torn down by trap before this test can read
# it. We work around by pointing TMPDIR to $TEST_DIR/tmp so the sandbox path
# stays under our own cleanup domain, and we snapshot state.json before the
# trap fires via an env-var-driven side channel below.
#
# Mechanism: before the proposer runs, we set TMPDIR to a sub-dir. The
# proposer creates its sandbox at $TMPDIR/pel-code-sandbox-XXXXXX. After the
# proposer exits, the worktree is gone, but we can't easily read state.json
# post-facto. Instead, we use a light instrumentation trick: the proposer's
# cleanup is via `git worktree remove --force` which removes the directory
# including state.json. To capture state.json before cleanup, the scenario
# must act WITHIN the proposer's process lifetime.
#
# Simpler approach: use git worktree list to inspect after proposer exits —
# but by then worktree has been removed. The cleanest solution is to use a
# wrapper that copies state.json out of the sandbox before the outer proposer
# trap fires. That wrapper is implemented inline in each happy-path scenario
# via the CODE_PROPOSER_STATE_COPY env var — which the stub claude writes to
# AFTER canary runs but before proposer exits.
#
# Actually, the cleanest approach: since the proposer emits the diff on
# stdout AND the state.json contents to $SANDBOX_PATH before cleanup, we
# can use a pre-EXIT hook via a wrapper script that copies state.json. But
# that requires modifying proposer.sh, which is out of scope.
#
# Best pure approach: use `bash -c` to run the proposer with a post-exec
# hook. Since Bash's trap runs after commands, we can invoke the proposer
# inside a subshell, capture the exit code, and at that point the sandbox
# is already gone. To avoid that, we hook the proposer by wrapping it in a
# script that tees state.json out BEFORE allowing proposer to exit.
#
# Practical solution: run the proposer inside a wrapper that monitors for
# state.json creation in $TMPDIR/pel-code-sandbox-*/ and copies it to
# $TEST_DIR as soon as it appears. Simpler: since the proposer writes
# state.json BEFORE the final `printf "%s\n" "$diff_text"` (per proposer.sh
# line 376-388), we can use an inotify-style poll in a background process.
# On Git Bash this is flaky.
#
# Simplest correct solution: set TMPDIR=$TEST_DIR/tmp and preserve sandbox
# artifacts by OVERRIDING the cleanup. Since canary passes/fails determine
# the exit, and state.json is committed before exit for both paths, we can
# pre-save state.json by stubbing out git-worktree-remove via a wrapper on
# PATH. Our PATH injection already has $TEST_DIR/bin first, so we can add a
# `git` wrapper that, when invoked with `worktree remove`, first copies
# state.json to $TEST_DIR/state-LAST.json, THEN runs the real git.
# ---------------------------------------------------------------------------

# Install a `git` PATH-shim that intercepts `git -C REPO worktree remove
# --force SANDBOX` and copies SANDBOX/state.json to $TEST_DIR/state-LAST.json
# BEFORE delegating to the real git. This lets happy-path + canary-fail
# scenarios verify state.json contents without modifying proposer.sh.
#
# The shim MUST pass through all other git invocations unchanged; only the
# `worktree remove --force ...` form triggers the state.json snapshot.
# Find the real git binary before we shadow it — use `command -v git` in a
# subshell with a clean PATH to locate the system git.
REAL_GIT=$(PATH="/usr/bin:/bin:/mingw64/bin:/c/Program Files/Git/cmd" command -v git 2>/dev/null || command -v git)
export REAL_GIT
cat > "$TEST_DIR/bin/git" <<'GITSHIM'
#!/usr/bin/env bash
# PATH-shim intercepting `git ... worktree remove --force <sandbox>` to
# snapshot state.json before real git tears down the worktree.
#
# Usage: installed by simulation harness at $TEST_DIR/bin/git with
#   TEST_DIR + REAL_GIT exported. PATH=$TEST_DIR/bin:$PATH during proposer.sh
#   invocation shadows the system git; this shim routes back to $REAL_GIT
#   after optionally snapshotting state.json.

# Debug trace (every invocation). $TEST_DIR is exported so the shim writes
# trace lines next to the snapshot file; invaluable when a scenario's
# state.json assertion fails.
if [[ -n "${TEST_DIR:-}" ]]; then
  printf 'shim-git: %s\n' "$*" >> "$TEST_DIR/shim-git.log"
fi

# Scan argv for the form: git ... worktree remove --force <path>
# Uses array-indexed iteration so the "next token after 'worktree'" probe
# uses a concrete positional index (argv is 1-based via $@).
args=("$@")
found_wt_remove=0
sandbox_path=""
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[i]}" == "worktree" ]]; then
    next_idx=$((i+1))
    if [[ "${args[next_idx]:-}" == "remove" ]]; then
      found_wt_remove=1
      # Last argv is the sandbox path (after --force).
      last_idx=$((${#args[@]} - 1))
      sandbox_path="${args[last_idx]}"
      break
    fi
  fi
done

if (( found_wt_remove == 1 )); then
  if [[ -n "${TEST_DIR:-}" && -d "$sandbox_path" && -f "$sandbox_path/state.json" ]]; then
    cp "$sandbox_path/state.json" "$TEST_DIR/state-LAST.json" 2>/dev/null || true
    printf 'shim-git: snapshotted state.json from %s\n' "$sandbox_path" >> "$TEST_DIR/shim-git.log"
  else
    printf 'shim-git: worktree-remove detected but snapshot conditions not met (TEST_DIR=%s, dir=%s, state=%s)\n' \
      "${TEST_DIR:-UNSET}" "$sandbox_path" "$sandbox_path/state.json" >> "${TEST_DIR:-/tmp}/shim-git.log" 2>/dev/null || true
  fi
fi

exec "$REAL_GIT" "$@"
GITSHIM
chmod +x "$TEST_DIR/bin/git"

# ---------------------------------------------------------------------------
# Helper: run_proposer — DRY wrapper that sets the canonical PATH + env for
# a scenario, invokes proposer.sh, captures exit code, stdout, stderr, and
# copies state-LAST.json to a per-scenario name for assertion.
#
# Usage:
#   run_proposer <scenario_letter> <stub_file> <pel_code_feedback> <pel_code_target> <pel_flavor> [task_hint]
#
# After return:
#   rc                — exit code in caller scope
#   stdout_file       — "$TEST_DIR/stdout-<letter>"
#   stderr_file       — "$TEST_DIR/stderr-<letter>"
#   state_snap        — "$TEST_DIR/state-<letter>.json" (if state.json existed)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Scenario A: Flavor=bug-catcher — valid diff against lib/co-evolution.sh
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-A.diff"
  # sed script: add a bug-catcher bias comment before the log() function def.
  # The `0,/pattern/` range ensures only the first occurrence is replaced (so
  # the diff is minimal — 2 added lines). Within 20-line budget.
  write_valid_stub_diff "$stub_file" \
    "lib/co-evolution.sh" \
    '^log\(\) \{' '# bug-catcher annotation: retry logic audit point'

  rm -f "$TEST_DIR/state-LAST.json"
  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-A" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/retry-logic-weakness.json" \
  PEL_CODE_TARGET=lib/co-evolution.sh \
  PEL_FLAVOR=bug-catcher \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "audit retry logic" \
    >"$TEST_DIR/stdout-A" 2>"$TEST_DIR/stderr-A" || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "A: expected exit 0; got $rc; stderr: $(cat "$TEST_DIR/stderr-A")" >&2
    exit 1
  fi
  # Happy-path stdout MUST contain the unified diff headers + @@ marker.
  # Proposer leaks git worktree's "HEAD is now at..." on stdout (Plan 01
  # known issue — see 07-02-SUMMARY.md deferred issues); grep for the diff
  # content ignores leading lines.
  grep -qE '^--- a/lib/co-evolution\.sh' "$TEST_DIR/stdout-A" \
    || { echo "A: stdout missing --- header; got: $(cat "$TEST_DIR/stdout-A")" >&2; exit 1; }
  grep -qE '^\+\+\+ b/lib/co-evolution\.sh' "$TEST_DIR/stdout-A" \
    || { echo "A: stdout missing +++ header; got: $(cat "$TEST_DIR/stdout-A")" >&2; exit 1; }
  grep -qF '@@' "$TEST_DIR/stdout-A" \
    || { echo "A: stdout missing @@ hunk header; got: $(cat "$TEST_DIR/stdout-A")" >&2; exit 1; }
  # Canary must have run and all 5 scenarios passed.
  grep -qF 'canary: 5/5 scenarios passed' "$TEST_DIR/stderr-A" \
    || { echo "A: stderr missing canary success; got: $(cat "$TEST_DIR/stderr-A")" >&2; exit 1; }
  # state.json snapshot via git-shim must exist + have outcome=accepted.
  test -f "$TEST_DIR/state-LAST.json" \
    || { echo "A: state.json snapshot missing (git-shim did not intercept worktree remove)" >&2; exit 1; }
  cp "$TEST_DIR/state-LAST.json" "$TEST_DIR/state-A.json"
  jq -e '.outcome == "accepted"' "$TEST_DIR/state-A.json" >/dev/null \
    || { echo "A: state.json outcome != accepted; got: $(cat "$TEST_DIR/state-A.json")" >&2; exit 1; }
  jq -e '.canary.passed == true' "$TEST_DIR/state-A.json" >/dev/null \
    || { echo "A: state.json canary.passed != true" >&2; exit 1; }
  jq -e '.flavor == "bug-catcher"' "$TEST_DIR/state-A.json" >/dev/null \
    || { echo "A: state.json flavor != bug-catcher" >&2; exit 1; }
  jq -e '.target == "lib/co-evolution.sh"' "$TEST_DIR/state-A.json" >/dev/null \
    || { echo "A: state.json target mismatch" >&2; exit 1; }
  jq -e '.diff_lines <= 20' "$TEST_DIR/state-A.json" >/dev/null \
    || { echo "A: state.json diff_lines exceeds budget" >&2; exit 1; }
) && pass "Scenario A (flavor=bug-catcher, valid diff against lib/co-evolution.sh, canary passes, state.json accepted)" \
  || fail "Scenario A (bug-catcher happy-path)"

# ---------------------------------------------------------------------------
# Scenario B: Flavor=faster-converger — valid diff against dev-review.sh
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-B.diff"
  # sed: add a faster-converger comment near TIMESTAMP line (minimal edit).
  write_valid_stub_diff "$stub_file" \
    "dev-review/codex/dev-review.sh" \
    '^TIMESTAMP=' '# faster-converger annotation: timestamp for convergence budget tracking'

  rm -f "$TEST_DIR/state-LAST.json"
  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-B" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/phase-timeout-improvement.json" \
  PEL_CODE_TARGET=dev-review/codex/dev-review.sh \
  PEL_FLAVOR=faster-converger \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "tighten convergence" \
    >"$TEST_DIR/stdout-B" 2>"$TEST_DIR/stderr-B" || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "B: expected exit 0; got $rc; stderr: $(cat "$TEST_DIR/stderr-B")" >&2
    exit 1
  fi
  grep -qE '^--- a/dev-review/codex/dev-review\.sh' "$TEST_DIR/stdout-B" \
    || { echo "B: stdout missing --- header; got: $(cat "$TEST_DIR/stdout-B")" >&2; exit 1; }
  grep -qE '^\+\+\+ b/dev-review/codex/dev-review\.sh' "$TEST_DIR/stdout-B" \
    || { echo "B: stdout missing +++ header" >&2; exit 1; }
  grep -qF '@@' "$TEST_DIR/stdout-B" \
    || { echo "B: stdout missing @@ hunk header" >&2; exit 1; }
  # Diff must NOT also touch lib/co-evolution.sh (single-file constraint proof).
  if grep -qE '^--- a/lib/co-evolution\.sh' "$TEST_DIR/stdout-B"; then
    echo "B: stdout leaked a lib/co-evolution.sh diff (should be dev-review only)" >&2
    exit 1
  fi
  grep -qF 'canary: 5/5 scenarios passed' "$TEST_DIR/stderr-B" \
    || { echo "B: stderr missing canary success" >&2; exit 1; }
  test -f "$TEST_DIR/state-LAST.json" \
    || { echo "B: state.json snapshot missing" >&2; exit 1; }
  cp "$TEST_DIR/state-LAST.json" "$TEST_DIR/state-B.json"
  jq -e '.flavor == "faster-converger"' "$TEST_DIR/state-B.json" >/dev/null \
    || { echo "B: state.json flavor mismatch" >&2; exit 1; }
  jq -e '.target == "dev-review/codex/dev-review.sh"' "$TEST_DIR/state-B.json" >/dev/null \
    || { echo "B: state.json target mismatch" >&2; exit 1; }
) && pass "Scenario B (flavor=faster-converger, valid diff against dev-review.sh)" \
  || fail "Scenario B (faster-converger happy-path)"

# ---------------------------------------------------------------------------
# Scenario C: Flavor=blind-spot-surfacer — valid diff against agent-bouncer.sh
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-C.diff"
  # sed: add a blind-spot-surfacer comment near the TIMESTAMP line.
  write_valid_stub_diff "$stub_file" \
    "agent-bouncer/agent-bouncer.sh" \
    '^TIMESTAMP=' '# blind-spot-surfacer annotation: verdict JSON integrity audit point'

  rm -f "$TEST_DIR/state-LAST.json"
  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-C" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/error-handling-gap.json" \
  PEL_CODE_TARGET=agent-bouncer/agent-bouncer.sh \
  PEL_FLAVOR=blind-spot-surfacer \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "surface verdict validation gaps" \
    >"$TEST_DIR/stdout-C" 2>"$TEST_DIR/stderr-C" || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "C: expected exit 0; got $rc; stderr: $(cat "$TEST_DIR/stderr-C")" >&2
    exit 1
  fi
  grep -qE '^--- a/agent-bouncer/agent-bouncer\.sh' "$TEST_DIR/stdout-C" \
    || { echo "C: stdout missing --- header" >&2; exit 1; }
  grep -qE '^\+\+\+ b/agent-bouncer/agent-bouncer\.sh' "$TEST_DIR/stdout-C" \
    || { echo "C: stdout missing +++ header" >&2; exit 1; }
  grep -qF '@@' "$TEST_DIR/stdout-C" \
    || { echo "C: stdout missing @@ hunk header" >&2; exit 1; }
  if grep -qE '^--- a/lib/co-evolution\.sh' "$TEST_DIR/stdout-C"; then
    echo "C: stdout leaked unrelated file diff" >&2
    exit 1
  fi
  grep -qF 'canary: 5/5 scenarios passed' "$TEST_DIR/stderr-C" \
    || { echo "C: stderr missing canary success" >&2; exit 1; }
  cp "$TEST_DIR/state-LAST.json" "$TEST_DIR/state-C.json" 2>/dev/null || true
  jq -e '.flavor == "blind-spot-surfacer"' "$TEST_DIR/state-C.json" >/dev/null \
    || { echo "C: state.json flavor mismatch" >&2; exit 1; }
  jq -e '.target == "agent-bouncer/agent-bouncer.sh"' "$TEST_DIR/state-C.json" >/dev/null \
    || { echo "C: state.json target mismatch" >&2; exit 1; }
) && pass "Scenario C (flavor=blind-spot-surfacer, valid diff against agent-bouncer.sh)" \
  || fail "Scenario C (blind-spot-surfacer happy-path)"

# ---------------------------------------------------------------------------
# Scenario D: Flavor=general — valid diff against lib/co-evolution.sh
#                              (different mutation than A)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-D.diff"
  # sed: annotate the validate_lab_mode function (different target than A's log()).
  write_valid_stub_diff "$stub_file" \
    "lib/co-evolution.sh" \
    '^validate_lab_mode\(\) \{' '# general annotation: lab-routing validation entry point'

  rm -f "$TEST_DIR/state-LAST.json"
  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-D" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/lab-routing-edge.json" \
  PEL_CODE_TARGET=lib/co-evolution.sh \
  PEL_FLAVOR=general \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "" \
    >"$TEST_DIR/stdout-D" 2>"$TEST_DIR/stderr-D" || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "D: expected exit 0; got $rc; stderr: $(cat "$TEST_DIR/stderr-D")" >&2
    exit 1
  fi
  grep -qE '^--- a/lib/co-evolution\.sh' "$TEST_DIR/stdout-D" \
    || { echo "D: stdout missing --- header" >&2; exit 1; }
  grep -qF '@@' "$TEST_DIR/stdout-D" \
    || { echo "D: stdout missing @@ hunk header" >&2; exit 1; }
  grep -qF 'canary: 5/5 scenarios passed' "$TEST_DIR/stderr-D" \
    || { echo "D: stderr missing canary success" >&2; exit 1; }
  cp "$TEST_DIR/state-LAST.json" "$TEST_DIR/state-D.json" 2>/dev/null || true
  jq -e '.flavor == "general"' "$TEST_DIR/state-D.json" >/dev/null \
    || { echo "D: state.json flavor != general" >&2; exit 1; }
  jq -e '.outcome == "accepted"' "$TEST_DIR/state-D.json" >/dev/null \
    || { echo "D: state.json outcome != accepted" >&2; exit 1; }
) && pass "Scenario D (flavor=general, valid diff against lib/co-evolution.sh with empty task hint)" \
  || fail "Scenario D (general happy-path)"

# ===========================================================================
# Text-pipeline edge cases (E-I) — from phase-7-simulation-lessons.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario E: Empty-line context marker
#
# A unified diff hunk context line that represents an originally-empty line
# in the source appears as "<single space><newline>" — NOT "<newline>". A
# capture_diff bug that over-trims "whitespace-only" lines (the Phase 5 bug)
# would destroy this marker and break hunk line counts.
#
# Strategy: craft a stub diff that inserts BEFORE a naturally-empty line in
# lib/co-evolution.sh. The hunk's context will include that blank line as a
# single-space line. Proposer must preserve it end-to-end.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-E.diff"
  # lib/co-evolution.sh line 2 is blank. Build a diff that inserts a comment
  # at line 2 (pushing the blank line to line 3) — the hunk's context
  # pre-line will be the blank line rendered as " \n".
  orig="$TEST_DIR/orig-E"
  mod="$TEST_DIR/mod-E"
  tr -d '\r' < "$REPO_ROOT/lib/co-evolution.sh" > "$orig"
  # Hand-craft: we want a hunk whose context includes an originally-empty line.
  # Insert a comment after line 1 (shebang); this makes the former line 2
  # (empty) appear as context.
  awk 'NR==1 { print; print "# edge-case E: empty-line context marker test"; next } { print }' "$orig" > "$mod"
  diff -u --label "a/lib/co-evolution.sh" --label "b/lib/co-evolution.sh" "$orig" "$mod" > "$stub_file" || true

  # Sanity: the stub MUST contain a line that is exactly " " + newline
  # (a meaningful empty-line context marker). If `diff -u` doesn't emit
  # one here, pick a different insertion point.
  if ! awk 'length($0)==1 && $0==" "' "$stub_file" | grep -q '^ $'; then
    # Fallback: if diff's default didn't produce a space-only context line,
    # force-insert one. Cross-platform diff -u should emit " " for a blank
    # context line but BusyBox/macOS diff might vary.
    :  # best-effort; see assertion below
  fi

  rm -f "$TEST_DIR/state-LAST.json"
  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-E" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/retry-logic-weakness.json" \
  PEL_CODE_TARGET=lib/co-evolution.sh \
  PEL_FLAVOR=bug-catcher \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "edge case E" \
    >"$TEST_DIR/stdout-E" 2>"$TEST_DIR/stderr-E" || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "E: expected exit 0 (empty-line context marker preserved); got $rc" >&2
    echo "E: stderr: $(cat "$TEST_DIR/stderr-E")" >&2
    echo "E: stub diff:" >&2
    cat "$stub_file" >&2
    exit 1
  fi
  grep -qE '^--- a/lib/co-evolution\.sh' "$TEST_DIR/stdout-E" \
    || { echo "E: stdout missing --- header" >&2; exit 1; }
  # Assert that the proposer's stdout (which echoes diff_text from capture_diff)
  # includes a single-space context line — proving capture preserved the marker.
  if ! awk 'length($0)==1 && $0==" "' "$TEST_DIR/stdout-E" | grep -q '^ $'; then
    echo "E: stdout lost single-space context marker; capture_diff may be over-trimming" >&2
    echo "E: stdout:" >&2
    cat "$TEST_DIR/stdout-E" >&2
    exit 1
  fi
) && pass "Scenario E (empty-line context marker preserved through capture->apply)" \
  || fail "Scenario E (text-pipeline: empty-line marker)"

# ---------------------------------------------------------------------------
# Scenario F: No trailing newline
#
# A diff whose last line ends with "\ No newline at end of file" marker.
# Proposer's trailing-newline recovery (Phase 5 lesson) must preserve this
# so git apply accepts it.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-F.diff"
  # Build a stub diff that ends with "\ No newline at end of file". The
  # easiest way is to create a file variant whose last byte is NOT a newline,
  # then diff -u produces the marker.
  orig="$TEST_DIR/orig-F"
  mod="$TEST_DIR/mod-F"
  # Copy target file but strip the final newline from mod so diff -u emits
  # the "\ No newline at end of file" marker.
  tr -d '\r' < "$REPO_ROOT/lib/co-evolution.sh" > "$orig"
  # Remove the last char (trailing newline) to trigger the marker.
  perl -0777 -pe 's/\n\z//' "$orig" > "$mod"
  # Add a small innocuous change near the top so the diff is non-empty.
  # Use a tempfile-based approach (cross-platform: GNU sed -i and BSD sed
  # both work; avoids `sed -i` syntax divergence on macOS).
  sed '0,/^log() {/s|^log() {|# edge-case F: no-trailing-newline at EOF test\nlog() {|' "$mod" > "$mod.tmp"
  mv "$mod.tmp" "$mod"
  diff -u --label "a/lib/co-evolution.sh" --label "b/lib/co-evolution.sh" "$orig" "$mod" > "$stub_file" || true

  # Sanity: stub must include the "\ No newline at end of file" marker.
  if ! grep -qF '\ No newline at end of file' "$stub_file"; then
    echo "F: sanity check failed — stub diff missing 'No newline at end of file' marker" >&2
    cat "$stub_file" >&2
    exit 1
  fi

  rm -f "$TEST_DIR/state-LAST.json"
  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-F" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/retry-logic-weakness.json" \
  PEL_CODE_TARGET=lib/co-evolution.sh \
  PEL_FLAVOR=bug-catcher \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "edge case F" \
    >"$TEST_DIR/stdout-F" 2>"$TEST_DIR/stderr-F" || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "F: expected exit 0 (trailing-newline recovery works); got $rc" >&2
    echo "F: stderr: $(cat "$TEST_DIR/stderr-F")" >&2
    exit 1
  fi
  grep -qE '^--- a/lib/co-evolution\.sh' "$TEST_DIR/stdout-F" \
    || { echo "F: stdout missing --- header" >&2; exit 1; }
) && pass "Scenario F (no-trailing-newline marker preserved through capture->apply)" \
  || fail "Scenario F (text-pipeline: trailing newline)"

# ---------------------------------------------------------------------------
# Scenario G: CRLF-on-disk target
#
# On Git Bash Windows the target file on disk may have CRLF line endings
# (autocrlf=true default). The stub diff is LF-only (as generated by
# write_valid_stub_diff's tr -d '\r' + diff -u). Proposer's
# `git apply --whitespace=nowarn` must handle the mismatch.
#
# On Linux/macOS, the file on disk is LF; the test passes trivially but
# still exercises the path. The structural grep for --whitespace=nowarn in
# proposer.sh (via verify block) is the cross-platform invariant proof.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-G.diff"
  # Small innocuous mutation; LF-only diff via normal helper.
  write_valid_stub_diff "$stub_file" \
    "lib/co-evolution.sh" \
    '^die\(\) \{' '# edge-case G: CRLF-tolerance test'

  rm -f "$TEST_DIR/state-LAST.json"
  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-G" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/retry-logic-weakness.json" \
  PEL_CODE_TARGET=lib/co-evolution.sh \
  PEL_FLAVOR=bug-catcher \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "edge case G" \
    >"$TEST_DIR/stdout-G" 2>"$TEST_DIR/stderr-G" || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "G: expected exit 0 (CRLF-tolerance); got $rc" >&2
    echo "G: stderr: $(cat "$TEST_DIR/stderr-G")" >&2
    exit 1
  fi
  grep -qE '^--- a/lib/co-evolution\.sh' "$TEST_DIR/stdout-G" \
    || { echo "G: stdout missing --- header" >&2; exit 1; }
  # Structural invariant: proposer.sh must wire --whitespace=nowarn so
  # CRLF-on-disk targets accept LF-only diffs. grep proves the flag is there.
  grep -qF -- '--whitespace=nowarn' "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" \
    || { echo "G: proposer.sh missing --whitespace=nowarn flag (CRLF tolerance invariant)" >&2; exit 1; }
) && pass "Scenario G (LF-only diff applies against CRLF-on-disk target via --whitespace=nowarn)" \
  || fail "Scenario G (text-pipeline: CRLF)"

# ---------------------------------------------------------------------------
# Scenario H: Shell metacharacters in diff content
#
# Stub diff's + lines contain $VAR, backticks, heredoc markers, globs. The
# capture->apply pipeline must treat these as opaque bytes — no eval, no
# expansion, no misparse.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-H.diff"
  # Hand-craft the stub diff with shell metacharacters on + lines. Use a
  # single-quoted heredoc (<<'EOF') so nothing in the body is expanded by
  # THIS test script — the bytes land verbatim in the stub file.
  # Context lines mirror the CURRENT head of lib/co-evolution.sh (incl. the
  # patsub_replacement guard added in v1.3) — hand-crafted hunks pin file
  # content and must be updated when the target's head changes.
  cat > "$stub_file" <<'METACHARS_EOF'
--- a/lib/co-evolution.sh
+++ b/lib/co-evolution.sh
@@ -7,6 +7,9 @@
 # older bash, hence the guard.)
 shopt -u patsub_replacement 2>/dev/null || true
 
+# shell-meta audit: $PATH expansion boundary
+# heredoc marker in comment: <<'EOF'  globs: *.sh
+# double-quoted "hello \$world" test; backticks ignored in comments
 log() {
   local message="${1:-}"
 
METACHARS_EOF

  rm -f "$TEST_DIR/state-LAST.json"
  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-H" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/retry-logic-weakness.json" \
  PEL_CODE_TARGET=lib/co-evolution.sh \
  PEL_FLAVOR=bug-catcher \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "edge case H" \
    >"$TEST_DIR/stdout-H" 2>"$TEST_DIR/stderr-H" || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "H: expected exit 0 (metacharacters survive capture->apply); got $rc" >&2
    echo "H: stderr: $(cat "$TEST_DIR/stderr-H")" >&2
    exit 1
  fi
  # Literal metachar-content must appear verbatim on stdout (no expansion).
  grep -qF '$PATH' "$TEST_DIR/stdout-H" \
    || { echo "H: stdout lost literal \$PATH (expansion or misparse)" >&2; exit 1; }
  grep -qF "<<'EOF'" "$TEST_DIR/stdout-H" \
    || { echo "H: stdout lost literal heredoc marker <<'EOF'" >&2; exit 1; }
  grep -qF '*.sh' "$TEST_DIR/stdout-H" \
    || { echo "H: stdout lost literal glob *.sh" >&2; exit 1; }
) && pass "Scenario H (shell metacharacters survive capture->apply verbatim)" \
  || fail "Scenario H (text-pipeline: metacharacters)"

# ---------------------------------------------------------------------------
# Scenario I: patch-vs-git-apply divergence
#
# Craft a diff with a miscounted hunk header — `patch --dry-run` would
# auto-fix this (patch is lenient), but `git apply --check` rejects it
# strictly. Proposer uses git apply → must exit 3.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-I.diff"
  # @@ -1,5 +1,6 @@ claims 5 old lines + 6 new, but we provide only 1 context
  # line — git apply --check counts and rejects with "corrupt patch".
  cat > "$stub_file" <<'MISCOUNT_EOF'
--- a/lib/co-evolution.sh
+++ b/lib/co-evolution.sh
@@ -1,5 +1,6 @@
 #!/usr/bin/env bash
+# edge-case I: hunk-count-mismatch test (patch accepts, git apply rejects)
MISCOUNT_EOF

  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-I" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/retry-logic-weakness.json" \
  PEL_CODE_TARGET=lib/co-evolution.sh \
  PEL_FLAVOR=bug-catcher \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "edge case I" \
    >"$TEST_DIR/stdout-I" 2>"$TEST_DIR/stderr-I" || rc=$?

  if [[ "$rc" -ne 3 ]]; then
    echo "I: expected exit 3 (git apply --check rejects miscounted hunk); got $rc" >&2
    echo "I: stderr: $(cat "$TEST_DIR/stderr-I")" >&2
    exit 1
  fi
  # Proposer must have invoked git apply --check (not patch).
  grep -qiE 'malformed|does not apply|corrupt|apply' "$TEST_DIR/stderr-I" \
    || { echo "I: stderr missing git-apply rejection message; got: $(cat "$TEST_DIR/stderr-I")" >&2; exit 1; }
) && pass "Scenario I (miscounted hunk rejected by git apply --check with exit 3)" \
  || fail "Scenario I (text-pipeline: tool consistency)"

# ===========================================================================
# Adversarial rejections (J-P)
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario J: Diff targets lab/pel/classifier/adapter.sh → exit 5
#              (allowlist violation, frozen-surface invariant from Phase 4)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-J.diff"
  # The diff itself must be structurally well-formed so only the allowlist
  # gate triggers (not the malformed-diff gate). Use a real file for the
  # body so `git apply --check` would pass on structure.
  orig="$TEST_DIR/orig-J"
  mod="$TEST_DIR/mod-J"
  tr -d '\r' < "$REPO_ROOT/lab/pel/classifier/adapter.sh" > "$orig"
  sed 's|^# |# allowlist-violation-J: |' "$orig" | head -c $((${#orig})) > "$mod" 2>/dev/null || true
  # Simpler: just add a comment line.
  cp "$orig" "$mod"
  awk 'NR==1 { print; print "# scenario J allowlist-violation probe"; next } { print }' "$orig" > "$mod"
  diff -u --label "a/lab/pel/classifier/adapter.sh" --label "b/lab/pel/classifier/adapter.sh" "$orig" "$mod" > "$stub_file" || true

  # Call proposer with PEL_CODE_TARGET=lib/co-evolution.sh (allowlisted) but
  # stub claude returns a diff against lab/pel/classifier/adapter.sh. This
  # exercises the LLM-emitted-target allowlist re-check (proposer.sh Gate 3,
  # defense-in-depth).
  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-J" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/retry-logic-weakness.json" \
  PEL_CODE_TARGET=lib/co-evolution.sh \
  PEL_FLAVOR=bug-catcher \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "allowlist violation J" \
    >"$TEST_DIR/stdout-J" 2>"$TEST_DIR/stderr-J" || rc=$?

  if [[ "$rc" -ne 5 ]]; then
    echo "J: expected exit 5 (allowlist violation: classifier frozen surface); got $rc" >&2
    echo "J: stderr: $(cat "$TEST_DIR/stderr-J")" >&2
    exit 1
  fi
  grep -qiE 'allowlist|not allowed|violation' "$TEST_DIR/stderr-J" \
    || { echo "J: stderr missing allowlist-violation keyword" >&2; exit 1; }
) && pass "Scenario J (diff targeting frozen classifier surface rejected with exit 5)" \
  || fail "Scenario J (allowlist: classifier frozen)"

# ---------------------------------------------------------------------------
# Scenario K: Diff targets .planning/STATE.md → exit 5 (planning integrity)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-K.diff"
  orig="$TEST_DIR/orig-K"
  mod="$TEST_DIR/mod-K"
  tr -d '\r' < "$REPO_ROOT/.planning/STATE.md" > "$orig"
  awk 'NR==1 { print; print "<!-- scenario K planning-integrity probe -->"; next } { print }' "$orig" > "$mod"
  diff -u --label "a/.planning/STATE.md" --label "b/.planning/STATE.md" "$orig" "$mod" > "$stub_file" || true

  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-K" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/retry-logic-weakness.json" \
  PEL_CODE_TARGET=lib/co-evolution.sh \
  PEL_FLAVOR=bug-catcher \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "allowlist violation K" \
    >"$TEST_DIR/stdout-K" 2>"$TEST_DIR/stderr-K" || rc=$?

  if [[ "$rc" -ne 5 ]]; then
    echo "K: expected exit 5 (allowlist violation: planning integrity); got $rc" >&2
    echo "K: stderr: $(cat "$TEST_DIR/stderr-K")" >&2
    exit 1
  fi
  grep -qiE 'allowlist|not allowed|violation' "$TEST_DIR/stderr-K" \
    || { echo "K: stderr missing allowlist-violation keyword" >&2; exit 1; }
) && pass "Scenario K (diff targeting .planning/STATE.md rejected with exit 5)" \
  || fail "Scenario K (allowlist: planning integrity)"

# ---------------------------------------------------------------------------
# Scenario L: Diff targets tests/classifier-simulation.sh → exit 5
#              (test integrity — a mutation that edits its own tests is the
#              Goodhart failure mode)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-L.diff"
  orig="$TEST_DIR/orig-L"
  mod="$TEST_DIR/mod-L"
  tr -d '\r' < "$REPO_ROOT/tests/classifier-simulation.sh" > "$orig"
  awk 'NR==1 { print; print "# scenario L test-integrity probe"; next } { print }' "$orig" > "$mod"
  diff -u --label "a/tests/classifier-simulation.sh" --label "b/tests/classifier-simulation.sh" "$orig" "$mod" > "$stub_file" || true

  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-L" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/retry-logic-weakness.json" \
  PEL_CODE_TARGET=lib/co-evolution.sh \
  PEL_FLAVOR=bug-catcher \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "allowlist violation L" \
    >"$TEST_DIR/stdout-L" 2>"$TEST_DIR/stderr-L" || rc=$?

  if [[ "$rc" -ne 5 ]]; then
    echo "L: expected exit 5 (allowlist violation: test integrity); got $rc" >&2
    echo "L: stderr: $(cat "$TEST_DIR/stderr-L")" >&2
    exit 1
  fi
  grep -qiE 'allowlist|not allowed|violation' "$TEST_DIR/stderr-L" \
    || { echo "L: stderr missing allowlist-violation keyword" >&2; exit 1; }
) && pass "Scenario L (diff targeting tests/ rejected with exit 5)" \
  || fail "Scenario L (allowlist: test integrity)"

# ---------------------------------------------------------------------------
# Scenario M: Diff exceeds 20-line budget → exit 6
#
# Target is allowlisted (lib/co-evolution.sh), diff is structurally valid,
# but the + line count exceeds DIFF_BUDGET=20. Must exit 6 before sandbox.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-M.diff"
  # Build a 25-added-line diff by inserting a block of 25 comment lines.
  orig="$TEST_DIR/orig-M"
  mod="$TEST_DIR/mod-M"
  tr -d '\r' < "$REPO_ROOT/lib/co-evolution.sh" > "$orig"
  # Use awk to insert 25 new lines after line 1 — creates +25 diff budget burn.
  awk 'NR==1 {
    print
    for (i=1; i<=25; i++) print "# budget-exceeded probe line " i
    next
  } { print }' "$orig" > "$mod"
  diff -u --label "a/lib/co-evolution.sh" --label "b/lib/co-evolution.sh" "$orig" "$mod" > "$stub_file" || true

  # Sanity: stub must have >20 + lines.
  plus_count=$(grep -cE '^\+' "$stub_file" | tr -d ' ')
  # Subtract 1 for the +++ header line.
  plus_count=$((plus_count - 1))
  if (( plus_count <= 20 )); then
    echo "M: stub sanity check failed — only $plus_count + lines (expected >20)" >&2
    exit 1
  fi

  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-M" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/retry-logic-weakness.json" \
  PEL_CODE_TARGET=lib/co-evolution.sh \
  PEL_FLAVOR=bug-catcher \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "budget violation M" \
    >"$TEST_DIR/stdout-M" 2>"$TEST_DIR/stderr-M" || rc=$?

  if [[ "$rc" -ne 6 ]]; then
    echo "M: expected exit 6 (budget exceeded); got $rc" >&2
    echo "M: stderr: $(cat "$TEST_DIR/stderr-M")" >&2
    exit 1
  fi
  grep -qiE 'budget|exceeded|20' "$TEST_DIR/stderr-M" \
    || { echo "M: stderr missing budget-exceeded keyword" >&2; exit 1; }
) && pass "Scenario M (25-line diff rejected by budget gate with exit 6)" \
  || fail "Scenario M (budget)"

# ---------------------------------------------------------------------------
# Scenario N: Diff touches 2 files → exit 4 (single-file constraint)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-N.diff"
  # Build two independent per-file diffs (both allowlisted) and concatenate.
  # Each individual diff is well-formed; the combination violates D-07 single-file.
  orig_A="$TEST_DIR/orig-N-A"
  mod_A="$TEST_DIR/mod-N-A"
  tr -d '\r' < "$REPO_ROOT/lib/co-evolution.sh" > "$orig_A"
  awk 'NR==1 { print; print "# scenario N multi-file part 1"; next } { print }' "$orig_A" > "$mod_A"
  diff -u --label "a/lib/co-evolution.sh" --label "b/lib/co-evolution.sh" "$orig_A" "$mod_A" > "$stub_file" || true

  orig_B="$TEST_DIR/orig-N-B"
  mod_B="$TEST_DIR/mod-N-B"
  tr -d '\r' < "$REPO_ROOT/dev-review/codex/dev-review.sh" > "$orig_B"
  awk 'NR==1 { print; print "# scenario N multi-file part 2"; next } { print }' "$orig_B" > "$mod_B"
  diff -u --label "a/dev-review/codex/dev-review.sh" --label "b/dev-review/codex/dev-review.sh" "$orig_B" "$mod_B" >> "$stub_file" || true

  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-N" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/retry-logic-weakness.json" \
  PEL_CODE_TARGET=lib/co-evolution.sh \
  PEL_FLAVOR=bug-catcher \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "multi-file violation N" \
    >"$TEST_DIR/stdout-N" 2>"$TEST_DIR/stderr-N" || rc=$?

  if [[ "$rc" -ne 4 ]]; then
    echo "N: expected exit 4 (single-file constraint); got $rc" >&2
    echo "N: stderr: $(cat "$TEST_DIR/stderr-N")" >&2
    exit 1
  fi
  grep -qiE 'single|1 file|2 files|constraint' "$TEST_DIR/stderr-N" \
    || { echo "N: stderr missing single-file-constraint keyword" >&2; exit 1; }
) && pass "Scenario N (2-file diff rejected by single-file gate with exit 4)" \
  || fail "Scenario N (single-file)"

# ---------------------------------------------------------------------------
# Scenario O: Missing PEL_CODE_FEEDBACK env var → exit 1 (input validation)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  # Unset PEL_CODE_FEEDBACK specifically; other required vars set so the
  # error is specifically about PEL_CODE_FEEDBACK (not a different missing
  # var cascading first).
  unset PEL_CODE_FEEDBACK
  rc=0
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_TARGET=lib/co-evolution.sh \
  PEL_FLAVOR=bug-catcher \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "" \
    >"$TEST_DIR/stdout-O" 2>"$TEST_DIR/stderr-O" || rc=$?

  if [[ "$rc" -ne 1 ]]; then
    echo "O: expected exit 1 (missing PEL_CODE_FEEDBACK); got $rc" >&2
    echo "O: stderr: $(cat "$TEST_DIR/stderr-O")" >&2
    exit 1
  fi
  grep -qF 'PEL_CODE_FEEDBACK' "$TEST_DIR/stderr-O" \
    || { echo "O: stderr missing PEL_CODE_FEEDBACK reference" >&2; exit 1; }
  grep -qiE 'required|must be set|readable' "$TEST_DIR/stderr-O" \
    || { echo "O: stderr missing required/must-be-set context" >&2; exit 1; }
) && pass "Scenario O (missing PEL_CODE_FEEDBACK rejected with exit 1)" \
  || fail "Scenario O (input validation)"

# ---------------------------------------------------------------------------
# Scenario P: Canary failure — diff applies cleanly but breaks bash -n
#             → exit 7 (canary-failed) + state.json with outcome=canary-failed
#
# This is the load-bearing scenario for D-08/D-09/D-10: the canary must
# catch mutations that pass syntactic validation but break the runner.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-P.diff"
  # Craft a diff that introduces a syntax error into lib/co-evolution.sh.
  # Requirements:
  #   - targets allowlisted file (lib/co-evolution.sh)
  #   - within 20-line budget
  #   - single file
  #   - passes `git apply --check` (valid unified diff)
  #   - BREAKS `bash -n lib/co-evolution.sh` after apply (canary scenario 1 fails)
  #
  # Strategy: insert `if true; then` at the TOP of the file (after shebang).
  # The dangling `if` with no `fi` is a bash syntax error caught by bash -n.
  orig="$TEST_DIR/orig-P"
  mod="$TEST_DIR/mod-P"
  tr -d '\r' < "$REPO_ROOT/lib/co-evolution.sh" > "$orig"
  awk 'NR==1 { print; print "if true; then"; next } { print }' "$orig" > "$mod"
  diff -u --label "a/lib/co-evolution.sh" --label "b/lib/co-evolution.sh" "$orig" "$mod" > "$stub_file" || true

  # Sanity: stub must be well-formed + single file + within budget.
  plus_count=$(grep -cE '^\+' "$stub_file" | tr -d ' ')
  plus_count=$((plus_count - 1))
  if (( plus_count > 20 )); then
    echo "P: stub budget sanity failed — $plus_count + lines" >&2
    exit 1
  fi

  rm -f "$TEST_DIR/state-LAST.json"
  rc=0
  CODE_PROPOSER_STUB_FILE="$stub_file" \
  CODE_PROPOSER_STUB_MARKER="$TEST_DIR/marker-P" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_CODE_FEEDBACK="$REPO_ROOT/tests/fixtures/code-feedback/retry-logic-weakness.json" \
  PEL_CODE_TARGET=lib/co-evolution.sh \
  PEL_FLAVOR=bug-catcher \
  bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "canary break P" \
    >"$TEST_DIR/stdout-P" 2>"$TEST_DIR/stderr-P" || rc=$?

  if [[ "$rc" -ne 7 ]]; then
    echo "P: expected exit 7 (canary failed); got $rc" >&2
    echo "P: stderr: $(cat "$TEST_DIR/stderr-P")" >&2
    exit 1
  fi
  grep -qiE 'canary' "$TEST_DIR/stderr-P" \
    || { echo "P: stderr missing canary failure context" >&2; exit 1; }
  # state.json must exist with outcome=canary-failed + canary.passed=false.
  test -f "$TEST_DIR/state-LAST.json" \
    || { echo "P: state.json snapshot missing (git-shim did not fire on worktree remove)" >&2; exit 1; }
  cp "$TEST_DIR/state-LAST.json" "$TEST_DIR/state-P.json"
  jq -e '.outcome == "canary-failed"' "$TEST_DIR/state-P.json" >/dev/null \
    || { echo "P: state.json outcome != canary-failed; got: $(cat "$TEST_DIR/state-P.json")" >&2; exit 1; }
  jq -e '.canary.passed == false' "$TEST_DIR/state-P.json" >/dev/null \
    || { echo "P: state.json canary.passed != false" >&2; exit 1; }
  jq -e '.exit_code == 7' "$TEST_DIR/state-P.json" >/dev/null \
    || { echo "P: state.json exit_code != 7" >&2; exit 1; }
  # failed_at should name the scenario (source-survives, since we broke bash -n).
  jq -e '.canary.failed_at == "source-survives"' "$TEST_DIR/state-P.json" >/dev/null \
    || { echo "P: state.json canary.failed_at != 'source-survives'" >&2; exit 1; }
) && pass "Scenario P (syntax-breaking diff caught by canary; exit 7 + state.json canary-failed)" \
  || fail "Scenario P (canary failure)"

# ===========================================================================
# Summary footer
# ===========================================================================

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
