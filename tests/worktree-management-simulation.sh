#!/usr/bin/env bash
# tests/worktree-management-simulation.sh
# RTUX-02: Smoke test for --branch / --worktree / DEV_REVIEW_BRANCH /
# DEV_REVIEW_WORKTREE flags. Runs without network, without codex/claude CLIs.
# Each scenario creates its own ephemeral git repo under $TEST_DIR so the
# test is hermetic on Linux/macOS/Git Bash.
#
# Scenarios:
#   A: --branch auto creates `dev-review/auto-<ts>-<slug>` off HEAD and checks out.
#   B: --worktree auto creates sibling worktree at `<parent>/<base>-dr-<ts>`.
#   C: Non-git-repo: both helpers log WARNING, return empty, never exit non-zero.
#   D: Empty flag value: both helpers log WARNING, return empty, repo untouched.
#   E: Mutual exclusion at the runner level: `--branch auto --worktree auto`
#      exits 1 with "mutually exclusive" message BEFORE any RUN_DIR is created.

set -euo pipefail

TEST_DIR=$(mktemp -d -t wt-sim-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

FAILURES=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }

# Helper: create a minimal git repo with one commit at $1
init_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main 2>/dev/null || git -C "$dir" init -q
  git -C "$dir" config user.email "sim@test.local"
  git -C "$dir" config user.name "sim"
  echo "seed" > "$dir/README.md"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "seed"
}

# --- Scenario A: --branch auto ---
(
  export LOG_FILE="$TEST_DIR/a.log"
  : > "$LOG_FILE"
  export TIMESTAMP=20260101-000000
  init_repo "$TEST_DIR/repo-a"
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/co-evolution.sh"
  branch=$(maybe_setup_branch "$TEST_DIR/repo-a" "auto" "Fix the broken auth flow promptly")
  expected="dev-review/auto-20260101-000000-fix-the-broken-auth-flow"
  [[ "$branch" == "$expected" ]] || { echo "A: expected '$expected', got '$branch'" >&2; exit 1; }
  current=$(git -C "$TEST_DIR/repo-a" rev-parse --abbrev-ref HEAD)
  [[ "$current" == "$expected" ]] || { echo "A: HEAD is '$current', expected '$expected'" >&2; exit 1; }
  grep -q "Branch created: $expected" "$LOG_FILE" || { echo "A: log missing 'Branch created' line" >&2; cat "$LOG_FILE" >&2; exit 1; }
) || fail "Scenario A (--branch auto)"

# --- Scenario B: --worktree auto ---
(
  export LOG_FILE="$TEST_DIR/b.log"
  : > "$LOG_FILE"
  export TIMESTAMP=20260101-000000
  init_repo "$TEST_DIR/repo-b"
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/co-evolution.sh"
  wt=$(maybe_setup_worktree "$TEST_DIR/repo-b" "auto" "some task")
  [[ -n "$wt" ]] || { echo "B: worktree path empty" >&2; cat "$LOG_FILE" >&2; exit 1; }
  [[ -d "$wt" ]] || { echo "B: worktree dir '$wt' does not exist" >&2; exit 1; }
  inside=$(git -C "$wt" rev-parse --is-inside-work-tree 2>/dev/null || echo "no")
  [[ "$inside" == "true" ]] || { echo "B: worktree is not inside a work tree: $inside" >&2; exit 1; }
  # Match by basename to avoid path-style mismatches on Git Bash for Windows
  # (git outputs `C:/Users/.../wt-...` while our helper returns `/c/Users/.../wt-...`).
  wt_base=$(basename "$wt")
  git -C "$TEST_DIR/repo-b" worktree list | grep -q "$wt_base" \
    || { echo "B: worktree not listed by 'git worktree list' (looking for basename '$wt_base')" >&2; git -C "$TEST_DIR/repo-b" worktree list >&2; exit 1; }
  # Shape check: path must end with -dr-<TIMESTAMP>
  [[ "$wt" == *"-dr-20260101-000000" ]] || { echo "B: worktree path missing expected suffix: $wt" >&2; exit 1; }
) || fail "Scenario B (--worktree auto)"

# --- Scenario C: non-git-repo fallback ---
(
  export LOG_FILE="$TEST_DIR/c.log"
  : > "$LOG_FILE"
  mkdir -p "$TEST_DIR/not-a-repo"
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/co-evolution.sh"
  out_b=$(maybe_setup_branch "$TEST_DIR/not-a-repo" "auto" "task")
  [[ -z "$out_b" ]] || { echo "C: branch helper returned non-empty: '$out_b'" >&2; exit 1; }
  out_w=$(maybe_setup_worktree "$TEST_DIR/not-a-repo" "auto" "task")
  [[ -z "$out_w" ]] || { echo "C: worktree helper returned non-empty: '$out_w'" >&2; exit 1; }
  b_warn=$(grep -c "WARNING: --branch ignored:.*not a git repo" "$LOG_FILE" || true)
  w_warn=$(grep -c "WARNING: --worktree ignored:.*not a git repo" "$LOG_FILE" || true)
  [[ "$b_warn" == "1" ]] || { echo "C: expected 1 branch warning, got $b_warn" >&2; exit 1; }
  [[ "$w_warn" == "1" ]] || { echo "C: expected 1 worktree warning, got $w_warn" >&2; exit 1; }
) || fail "Scenario C (non-git-repo fallback)"

# --- Scenario D: empty flag value fallback ---
(
  export LOG_FILE="$TEST_DIR/d.log"
  : > "$LOG_FILE"
  init_repo "$TEST_DIR/repo-d"
  branches_before=$(git -C "$TEST_DIR/repo-d" branch | wc -l)
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/co-evolution.sh"
  out_b=$(maybe_setup_branch "$TEST_DIR/repo-d" "" "task")
  [[ -z "$out_b" ]] || { echo "D: branch helper returned non-empty on empty spec: '$out_b'" >&2; exit 1; }
  out_w=$(maybe_setup_worktree "$TEST_DIR/repo-d" "" "task")
  [[ -z "$out_w" ]] || { echo "D: worktree helper returned non-empty on empty spec: '$out_w'" >&2; exit 1; }
  b_warn=$(grep -c "WARNING: --branch ignored: value is empty" "$LOG_FILE" || true)
  w_warn=$(grep -c "WARNING: --worktree ignored: value is empty" "$LOG_FILE" || true)
  [[ "$b_warn" == "1" ]] || { echo "D: expected 1 branch empty-warning, got $b_warn" >&2; exit 1; }
  [[ "$w_warn" == "1" ]] || { echo "D: expected 1 worktree empty-warning, got $w_warn" >&2; exit 1; }
  branches_after=$(git -C "$TEST_DIR/repo-d" branch | wc -l)
  [[ "$branches_before" == "$branches_after" ]] \
    || { echo "D: branch count changed from $branches_before to $branches_after" >&2; exit 1; }
) || fail "Scenario D (empty flag values)"

# --- Scenario E: mutual exclusion at runner level ---
(
  # Use a distinctive TIMESTAMP so we can prove no RUN_DIR was created.
  export TIMESTAMP="mutex-test-$RANDOM"
  pre_count=$(ls -1 "$REPO_ROOT/runs" 2>/dev/null | wc -l || echo 0)
  set +e
  output=$(bash "$REPO_ROOT/dev-review/codex/dev-review.sh" --branch auto --worktree auto "some task" 2>&1)
  rc=$?
  set -e
  [[ "$rc" == "1" ]] || { echo "E: expected exit 1, got $rc" >&2; echo "$output" >&2; exit 1; }
  echo "$output" | grep -q "mutually exclusive" \
    || { echo "E: output missing 'mutually exclusive'" >&2; echo "$output" >&2; exit 1; }
  # No RUN_DIR created for this TIMESTAMP (die fired before mkdir).
  ! ls -1 "$REPO_ROOT/runs" 2>/dev/null | grep -q "dev-review-${TIMESTAMP}" \
    || { echo "E: RUN_DIR was created despite die — side-effect leaked" >&2; exit 1; }
) || fail "Scenario E (mutual exclusion)"

# --- Scenario F: WR-04 regression — INITIAL_GIT_DIRTY capture must happen
# AFTER the branch/worktree setup block so --worktree mode captures the
# worktree's git state, not the parent repo's. Static-order check on the
# runner source: if a future refactor moves the capture back above the
# setup block, this scenario fails. ---
(
  runner="$REPO_ROOT/dev-review/codex/dev-review.sh"
  [[ -f "$runner" ]] || { echo "F: runner not found at $runner" >&2; exit 1; }

  setup_line=$(grep -n 'if \[\[ -n "\$BRANCH_SPEC" \]\]; then' "$runner" | head -1 | cut -d: -f1)
  capture_line=$(grep -n 'INITIAL_GIT_STATUS=\$(git -C "\$WORKDIR" status --short)' "$runner" | head -1 | cut -d: -f1)

  [[ -n "$setup_line" ]] \
    || { echo "F: could not locate branch/worktree setup block in runner" >&2; exit 1; }
  [[ -n "$capture_line" ]] \
    || { echo "F: could not locate INITIAL_GIT_STATUS capture in runner" >&2; exit 1; }
  (( capture_line > setup_line )) \
    || { echo "F: INITIAL_GIT_STATUS capture at line $capture_line happens BEFORE branch/worktree setup at line $setup_line — WR-04 regression (worktree mode would silently skip verify on dirty parent)" >&2; exit 1; }
) || fail "Scenario F (WR-04 capture-order regression)"

if (( FAILURES == 0 )); then
  echo "ALL SCENARIOS PASSED"
  exit 0
else
  echo "FAILED: $FAILURES scenario(s)" >&2
  exit 1
fi
