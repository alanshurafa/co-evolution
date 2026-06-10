#!/usr/bin/env bash
# tests/pr-emitter-simulation.sh
# Phase 8 Plan 02 — Hermetic SC-3 simulation of lab/pel/pr-emitter/ behavior.
#
# 12 scenarios (A-L). Final stdout line on success: "12/12 scenarios passed".
# Scenario K is the Bug #5 regression guard — proves pr-emitter treats
# run-evals.sh exit 1 + raw-scores.json present as scored-with-fails, not
# as a scorer crash. Uses PEL_RUN_EVALS_OVERRIDE test hook.
# Scenario L is the I-3 router-fires integration guard — proves the router
# is actually invoked (not silently failing and falling back to opus) by
# queueing a real router Haiku response and asserting the expected log line.
# Exit 0 iff all 12 pass, 1 otherwise.
#
# Scenarios (see <success_criteria> in 08-02-PLAN.md for full coverage matrix):
#   A: Happy-path, template tier   — stubbed classifier + template proposer;
#                                    body has Eval Delta + fenced diff + flavor;
#                                    branch pel/sim-pr-emitter/A.
#   B: Happy-path, policy tier     — JSON delta; body fenced JSON; branch
#                                    pel/sim-pr-emitter/B.
#   C: Happy-path, code tier       — canary-passing proposer; state.json
#                                    canary.passed=true; body "PASS (all 5)".
#   D: --dry-run wrapper            — DRY-RUN: gh stub logged; body captured.
#   E: [CANARY-FAILED] PR          — proposer exits 7 via syntax-breaking diff;
#                                    title prefixed [CANARY-FAILED].
#   F: Budget exceeded exit 6      — --budget 0; exit 6 + msg.
#   G: Tier auto-detect hard-err   — README.md → exit 10.
#   H: --tier override wins        — override logs; proposer pre-flight reject.
#   I: Byte-parity (SC-5)          — --help contains v1.1 + Phase 8 flags,
#                                    no PEL leaks in stderr.
#   J: Eval cache hit              — two runs both log "eval cache hit".
#
# Cross-platform: Git Bash Windows + Linux + macOS. Bash-only, no shell alternates.
# PATH-injected stubs: gh + claude + codex.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

# TEST_DIR under REPO_ROOT so proposer path-containment checks accept fixture
# paths. Same posture as Phase 5/6/7 simulations.
TEST_DIR=$(mktemp -d -p "$REPO_ROOT/tests" ".sim-pr-emitter-XXXXXX")
export TEST_DIR

# All PR branches we create during the simulation live under this prefix so
# the EXIT trap can deterministically delete them without touching other
# pel/* branches (e.g., user-created ones from real emitter invocations).
SIM_BRANCH_PREFIX="pel/sim-pr-emitter"

cleanup() {
  # Belt-and-suspenders: clean orphan pel-*-sandbox-* and pel-emitter-work-* dirs
  # if emitter EXIT trap failed to fire on mid-scenario aborts.
  local orphan b
  for orphan in "${TMPDIR:-/tmp}"/pel-score-sandbox-* "${TMPDIR:-/tmp}"/pel-emitter-work-* "${TMPDIR:-/tmp}"/pel-code-sandbox-* "${TMPDIR:-/tmp}"/co-evolve-dry-*; do
    [[ -e "$orphan" ]] || continue
    git -C "$REPO_ROOT" worktree remove --force "$orphan" 2>/dev/null || true
    rm -rf "$orphan" 2>/dev/null || true
  done
  # Delete any pel/sim-pr-emitter/* branches this run created.
  for b in $(git -C "$REPO_ROOT" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null | grep "^${SIM_BRANCH_PREFIX}/" || true); do
    git -C "$REPO_ROOT" branch -D "$b" >/dev/null 2>&1 || true
  done
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

FAILURES=0
TOTAL=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

# ---------------------------------------------------------------------------
# PATH-injected stubs — $TEST_DIR/bin prepended to PATH by each scenario
# before invoking the emitter.
# ---------------------------------------------------------------------------
mkdir -p "$TEST_DIR/bin"

# gh stub — logs argv BEFORE any shift; then captures --body-file content.
cat > "$TEST_DIR/bin/gh" <<'GHSTUB'
#!/usr/bin/env bash
# PATH-injected gh stub for hermetic pr-emitter simulation.
if [[ -n "${GH_ARGS_MARKER:-}" ]]; then
  printf 'called: %s\n' "$*" >> "$GH_ARGS_MARKER"
fi
# Extract --body-file value without mutating $@ so any later logic sees full argv.
body_path=""
prev=""
for a in "$@"; do
  if [[ "$prev" == "--body-file" ]]; then
    body_path="$a"
    break
  fi
  prev="$a"
done
if [[ -n "$body_path" && -n "${GH_BODY_SINK:-}" && -f "$body_path" ]]; then
  cp "$body_path" "$GH_BODY_SINK" 2>/dev/null || true
fi
# Drain stdin if present.
if [[ ! -t 0 ]]; then cat >/dev/null; fi
printf 'https://github.com/test/repo/pull/1\n'
exit 0
GHSTUB
chmod +x "$TEST_DIR/bin/gh"

# claude stub — echoes content from a rotator file per scenario.
cat > "$TEST_DIR/bin/claude" <<'CLAUDESTUB'
#!/usr/bin/env bash
# PATH-injected claude stub for hermetic pr-emitter simulation.
if [[ -n "${CLAUDE_STUB_MARKER:-}" ]]; then
  printf 'called: %s\n' "$*" >> "$CLAUDE_STUB_MARKER"
fi
if [[ "$*" == *"--version"* ]]; then
  echo "claude 1.0.0 (stub)"
  exit 0
fi
cat > /dev/null
if [[ -n "${CLAUDE_STUB_EXIT:-}" ]]; then
  exit "$CLAUDE_STUB_EXIT"
fi
if [[ -z "${CLAUDE_STUB_FILE:-}" || ! -f "${CLAUDE_STUB_FILE:-}" ]]; then
  echo "STUB ERROR: CLAUDE_STUB_FILE not set or file missing: ${CLAUDE_STUB_FILE:-<unset>}" >&2
  exit 99
fi
cat "$CLAUDE_STUB_FILE"
CLAUDESTUB
chmod +x "$TEST_DIR/bin/claude"

# codex stub — used by canary.sh's dev-review-plan-only scenario.
cat > "$TEST_DIR/bin/codex" <<'CODEXSTUB'
#!/usr/bin/env bash
printf "codex-stub: response\n"
exit 0
CODEXSTUB
chmod +x "$TEST_DIR/bin/codex"

# ---------------------------------------------------------------------------
# Eval cache pre-seed machinery (D-18/D-19)
# ---------------------------------------------------------------------------
CACHE_DIR="$REPO_ROOT/.co-evolve-cache/evals"
mkdir -p "$CACHE_DIR"

compute_emitter_cache_key() {
  # Duplicates lab/pel/pr-emitter/pr-emitter.sh::compute_cache_key verbatim.
  # WR-07: keep in sync with emitter's broadened hash inputs (cases/fixtures).
  local report_path="$1" worktree_dir="$2"
  local scripts_dir="$REPO_ROOT/evals"
  local fixture_hash scripts_hash worktree_hash dirty_hash
  fixture_hash=$(sha1sum "$report_path" | awk '{print $1}')
  scripts_hash=$(find "$scripts_dir" -maxdepth 3 -type f \
    \( -name '*.sh' -o -name '*.yaml' -o -name '*.json' -o -name '*.md' \) \
    -exec sha1sum {} + 2>/dev/null \
    | sort | sha1sum | awk '{print $1}')
  worktree_hash=$(git -C "$worktree_dir" rev-parse HEAD 2>/dev/null \
    | awk '{print substr($0,1,12)}')
  worktree_hash="${worktree_hash:-nohead}"
  dirty_hash=""
  if ! git -C "$worktree_dir" diff --quiet 2>/dev/null; then
    dirty_hash=$(git -C "$worktree_dir" diff 2>/dev/null | sha1sum | awk '{print substr($1,1,12)}')
  fi
  printf '%s-%s-%s%s' "$fixture_hash" "$scripts_hash" "$worktree_hash" "${dirty_hash:+-$dirty_hash}"
}

cat > "$TEST_DIR/canned-scores-before.json" <<'SCORES'
{
  "scored_at": "2026-04-19T10:00:00Z",
  "runner": "stub",
  "scenarios": [],
  "aggregate": { "fitness": 0.5, "convergence": 0.6, "verify_accuracy": 0.55 }
}
SCORES

cat > "$TEST_DIR/canned-scores-after.json" <<'SCORES'
{
  "scored_at": "2026-04-19T10:00:01Z",
  "runner": "stub",
  "scenarios": [],
  "aggregate": { "fitness": 0.7, "convergence": 0.8, "verify_accuracy": 0.75 }
}
SCORES

write_classifier_stub() {
  local flavor="$1" rationale="$2" out="$3"
  jq -n --arg f "$flavor" --arg r "$rationale" '{
    flavor: $f, rationale: $r, override: false,
    model: "claude-haiku-4-5-20251001",
    inputs: { task: "stub-task", bounce_step: "unknown", phase_type: "unknown" }
  }' > "$out"
}

write_template_diff() {
  local dest="$1" repo_rel="$2" sed_script="$3"
  local abs="$REPO_ROOT/$repo_rel"
  local base; base=$(basename "$repo_rel")
  local orig="$TEST_DIR/orig-$base" mod="$TEST_DIR/mod-$base"
  tr -d '\r' < "$abs" > "$orig"
  sed "$sed_script" "$orig" > "$mod"
  diff -u --label "a/$repo_rel" --label "b/$repo_rel" "$orig" "$mod" > "$dest" || true
  [[ -s "$dest" ]] || { echo "INTERNAL: write_template_diff produced empty diff for $repo_rel" >&2; exit 99; }
}

# Insert <inserted_line> before the FIRST line matching the awk ERE
# <anchor_regex>. awk (patterns via ENVIRON, no -v escape processing) replaces
# the previous GNU-sed `0,/pat/` script, which BSD sed (macOS) silently no-ops.
write_code_diff() {
  local dest="$1" repo_rel="$2" anchor_regex="$3" inserted_line="$4"
  local abs="$REPO_ROOT/$repo_rel"
  local base; base=$(basename "$repo_rel")
  local orig="$TEST_DIR/orig-$base" mod="$TEST_DIR/mod-$base"
  tr -d '\r' < "$abs" > "$orig"
  STUB_ANCHOR="$anchor_regex" STUB_INSERT="$inserted_line" awk '
    !done && $0 ~ ENVIRON["STUB_ANCHOR"] { print ENVIRON["STUB_INSERT"]; done = 1 }
    { print }
  ' "$orig" > "$mod"
  diff -u --label "a/$repo_rel" --label "b/$repo_rel" "$orig" "$mod" > "$dest" || true
  [[ -s "$dest" ]] || { echo "INTERNAL: write_code_diff produced empty diff for $repo_rel" >&2; exit 99; }
}

pick_template_target() {
  local f
  for f in "$REPO_ROOT"/skills/dev-review/templates/*.md; do
    [[ -f "$f" && -s "$f" ]] || continue
    printf '%s' "${f#"$REPO_ROOT"/}"
    return 0
  done
  echo "skills/dev-review/templates/compose-prompt.md"
}

pick_code_target() {
  head -n1 "$REPO_ROOT/lab/pel/proposer/code/allowlist.txt"
}

# Pre-seed cache for a scenario: before hashes REPO_ROOT; after hashes a sim
# sandbox where the diff is pre-applied (so dirty_hash matches what the
# emitter will compute when it applies the same diff in its own sandbox).
preseed_cache_for_scenario() {
  local report_path="$1" diff_file="$2" label="$3" tier="$4"
  local before_key after_key
  before_key=$(compute_emitter_cache_key "$report_path" "$REPO_ROOT")
  cp "$TEST_DIR/canned-scores-before.json" "$CACHE_DIR/${before_key}.json"

  local sim_sandbox="$TEST_DIR/after-sandbox-$label"
  rm -rf "$sim_sandbox"
  git -C "$REPO_ROOT" worktree add --detach "$sim_sandbox" HEAD >/dev/null 2>&1 || return 1
  if [[ "$tier" == "policy" ]]; then
    local target; target=$(jq -r '.policy_path' "$diff_file")
    # Policy path in sim stub is abs-prefixed with REPO_ROOT. Strip to get relative.
    target="${target#"$REPO_ROOT"/}"
    jq -c '.mutations[]' "$diff_file" | while IFS= read -r m; do
      local k v
      k=$(printf '%s' "$m" | jq -r '.key')
      v=$(printf '%s' "$m" | jq -r '.new')
      if printf '%s' "$v" | jq -e 'type == "number" or type == "boolean"' >/dev/null 2>&1; then
        yq -i ".$k = $v" "$sim_sandbox/$target" 2>/dev/null || true
      else
        yq -i ".$k = \"$v\"" "$sim_sandbox/$target" 2>/dev/null || true
      fi
    done
  else
    (cd "$sim_sandbox" && git apply --whitespace=nowarn "$diff_file") 2>/dev/null || true
  fi

  after_key=$(compute_emitter_cache_key "$report_path" "$sim_sandbox")
  cp "$TEST_DIR/canned-scores-after.json" "$CACHE_DIR/${after_key}.json"

  git -C "$REPO_ROOT" worktree remove --force "$sim_sandbox" >/dev/null 2>&1 || true
  rm -rf "$sim_sandbox" 2>/dev/null || true

  export SEED_BEFORE_KEY="$before_key" SEED_AFTER_KEY="$after_key"
}

clear_cache() {
  rm -f "$CACHE_DIR"/*.json 2>/dev/null || true
}

# Build a rotating claude stub: call N returns stub-queue/NN.txt.
write_claude_rotator() {
  local label="$1"
  # Any items after label are filenames (positional).
  shift
  local queue_dir="$TEST_DIR/stub-queue-$label"
  mkdir -p "$queue_dir"
  local i=1
  local f
  for f in "$@"; do
    cp "$f" "$(printf '%s/%02d.txt' "$queue_dir" "$i")"
    i=$((i+1))
  done
  cat > "$TEST_DIR/bin/claude-rotator-$label" <<ROTATOR
#!/usr/bin/env bash
if [[ ! -t 0 ]]; then cat >/dev/null; fi
counter_file="$TEST_DIR/counter-$label"
n=0
[[ -f "\$counter_file" ]] && n=\$(cat "\$counter_file")
n=\$((n+1))
echo "\$n" > "\$counter_file"
fname=\$(printf '%s/%02d.txt' "$queue_dir" "\$n")
if [[ ! -f "\$fname" ]]; then
  # Fallback: replay last queue item (handles tools that invoke claude more times than expected).
  last=\$(ls "$queue_dir"/??.txt 2>/dev/null | tail -1)
  [[ -f "\$last" ]] && cat "\$last" || { echo "STUB ERROR: exhausted queue at call \$n" >&2; exit 99; }
else
  cat "\$fname"
fi
ROTATOR
  chmod +x "$TEST_DIR/bin/claude-rotator-$label"
}

# Install rotator as $TEST_DIR/bin/claude (backing up generic).
activate_rotator() {
  local label="$1"
  mv "$TEST_DIR/bin/claude" "$TEST_DIR/bin/claude.generic-$label.bak" 2>/dev/null || true
  cp "$TEST_DIR/bin/claude-rotator-$label" "$TEST_DIR/bin/claude"
}

deactivate_rotator() {
  local label="$1"
  [[ -f "$TEST_DIR/bin/claude.generic-$label.bak" ]] \
    && cp "$TEST_DIR/bin/claude.generic-$label.bak" "$TEST_DIR/bin/claude" \
    || true
}

# ---------------------------------------------------------------------------
# Scenario A — Template tier happy-path
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  label="A"
  template_target=$(pick_template_target)
  write_template_diff "$TEST_DIR/diff-$label.patch" "$template_target" \
    '1a\
TEMPLATE BIAS COMMENT (bug-catcher, scenario A)'
  write_classifier_stub "bug-catcher" "template weakness (scenario A)" "$TEST_DIR/classifier-$label.json"

  write_claude_rotator "$label" \
    "$TEST_DIR/classifier-$label.json" \
    "$TEST_DIR/diff-$label.patch"
  activate_rotator "$label"

  preseed_cache_for_scenario \
    "$REPO_ROOT/tests/fixtures/pr-emitter/template-feedback.json" \
    "$TEST_DIR/diff-$label.patch" \
    "$label" \
    "template"

  export GH_BODY_SINK="$TEST_DIR/body-$label.md"
  export GH_ARGS_MARKER="$TEST_DIR/gh-args-$label"

  rc=0
  PATH="$TEST_DIR/bin:$PATH" \
  CO_EVOLVE_DRY_RUN=1 \
  PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/pr-emitter/template-feedback.json" \
  bash "$REPO_ROOT/lab/pel/pr-emitter/pr-emitter.sh" \
    --target "$template_target" \
    --pr-branch "$SIM_BRANCH_PREFIX/A" \
    --dry-run \
    "Scenario A task" \
    >"$TEST_DIR/stdout-$label" 2>"$TEST_DIR/stderr-$label" || rc=$?

  deactivate_rotator "$label"

  if [[ "$rc" -ne 0 ]]; then
    echo "$label: expected exit 0; got $rc" >&2
    echo "--- stderr ---" >&2; cat "$TEST_DIR/stderr-$label" >&2
    exit 1
  fi
  test -f "$GH_BODY_SINK" || { echo "$label: body not captured" >&2; exit 1; }
  grep -qE '^## PEL Mutation: template tier' "$GH_BODY_SINK" \
    || { echo "$label: body missing template heading" >&2; cat "$GH_BODY_SINK" >&2; exit 1; }
  grep -qF '```diff' "$GH_BODY_SINK" \
    || { echo "$label: body missing fenced diff block" >&2; exit 1; }
  grep -qF 'bug-catcher' "$GH_BODY_SINK" \
    || { echo "$label: body missing flavor" >&2; exit 1; }
  grep -qF -- "--head $SIM_BRANCH_PREFIX/A" "$GH_ARGS_MARKER" \
    || { echo "$label: gh missing --head $SIM_BRANCH_PREFIX/A" >&2; cat "$GH_ARGS_MARKER" >&2; exit 1; }
) && pass "Scenario A (template tier happy-path)" || fail "Scenario A (template tier happy-path)"
clear_cache

# ---------------------------------------------------------------------------
# Scenario B — Policy tier happy-path
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  label="B"
  policy_target="lab/pel/proposer/policy/policy.yaml"
  write_classifier_stub "faster-converger" "policy retry cap low (scenario B)" "$TEST_DIR/classifier-$label.json"

  # Policy proposer's adapter enforces .policy_path equals PEL_POLICY_PATH
  # verbatim. Emitter passes abs path → stub must echo abs path.
  cat > "$TEST_DIR/delta-$label.json" <<DELTA
{
  "mutations": [ { "key": "retry_cap", "new": 5 } ],
  "rationale": "increase retry cap (scenario B)",
  "flavor": "faster-converger",
  "policy_path": "$REPO_ROOT/lab/pel/proposer/policy/policy.yaml"
}
DELTA

  write_claude_rotator "$label" \
    "$TEST_DIR/classifier-$label.json" \
    "$TEST_DIR/delta-$label.json"
  activate_rotator "$label"

  preseed_cache_for_scenario \
    "$REPO_ROOT/tests/fixtures/pr-emitter/policy-feedback.json" \
    "$TEST_DIR/delta-$label.json" \
    "$label" \
    "policy"

  export GH_BODY_SINK="$TEST_DIR/body-$label.md"
  export GH_ARGS_MARKER="$TEST_DIR/gh-args-$label"

  rc=0
  PATH="$TEST_DIR/bin:$PATH" \
  CO_EVOLVE_DRY_RUN=1 \
  PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/pr-emitter/policy-feedback.json" \
  bash "$REPO_ROOT/lab/pel/pr-emitter/pr-emitter.sh" \
    --target "$policy_target" \
    --pr-branch "$SIM_BRANCH_PREFIX/B" \
    --dry-run \
    "Scenario B task" \
    >"$TEST_DIR/stdout-$label" 2>"$TEST_DIR/stderr-$label" || rc=$?

  deactivate_rotator "$label"

  if [[ "$rc" -ne 0 ]]; then
    echo "$label: expected exit 0; got $rc" >&2
    echo "--- stderr ---" >&2; cat "$TEST_DIR/stderr-$label" >&2
    exit 1
  fi
  test -f "$GH_BODY_SINK" || { echo "$label: body not captured" >&2; exit 1; }
  grep -qE '^## PEL Mutation: policy tier' "$GH_BODY_SINK" \
    || { echo "$label: body missing policy heading" >&2; exit 1; }
  grep -qF 'retry_cap' "$GH_BODY_SINK" \
    || { echo "$label: body missing retry_cap key" >&2; cat "$GH_BODY_SINK" >&2; exit 1; }
  grep -qF -- "--head $SIM_BRANCH_PREFIX/B" "$GH_ARGS_MARKER" \
    || { echo "$label: gh missing --head $SIM_BRANCH_PREFIX/B" >&2; exit 1; }
) && pass "Scenario B (policy tier happy-path)" || fail "Scenario B (policy tier happy-path)"
clear_cache

# ---------------------------------------------------------------------------
# Scenario C — Code tier happy-path (canary passes)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  label="C"
  code_target=$(pick_code_target)
  # Build a valid, non-syntax-breaking diff (insert a comment line).
  write_code_diff "$TEST_DIR/diff-$label.patch" "$code_target" \
    '^#' '# scenario-C bias annotation'
  write_classifier_stub "bug-catcher" "code retry audit (scenario C)" "$TEST_DIR/classifier-$label.json"

  write_claude_rotator "$label" \
    "$TEST_DIR/classifier-$label.json" \
    "$TEST_DIR/diff-$label.patch"
  activate_rotator "$label"

  preseed_cache_for_scenario \
    "$REPO_ROOT/tests/fixtures/pr-emitter/code-feedback.json" \
    "$TEST_DIR/diff-$label.patch" \
    "$label" \
    "code"

  export GH_BODY_SINK="$TEST_DIR/body-$label.md"
  export GH_ARGS_MARKER="$TEST_DIR/gh-args-$label"

  rc=0
  PATH="$TEST_DIR/bin:$PATH" \
  CO_EVOLVE_DRY_RUN=1 \
  PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/pr-emitter/code-feedback.json" \
  bash "$REPO_ROOT/lab/pel/pr-emitter/pr-emitter.sh" \
    --target "$code_target" \
    --pr-branch "$SIM_BRANCH_PREFIX/C" \
    --dry-run \
    "Scenario C task" \
    >"$TEST_DIR/stdout-$label" 2>"$TEST_DIR/stderr-$label" || rc=$?

  deactivate_rotator "$label"

  if [[ "$rc" -ne 0 ]]; then
    echo "$label: expected exit 0; got $rc" >&2
    echo "--- stderr ---" >&2; cat "$TEST_DIR/stderr-$label" >&2
    exit 1
  fi
  grep -qE '^## PEL Mutation: code tier' "$GH_BODY_SINK" \
    || { echo "$label: body missing code heading" >&2; exit 1; }
  grep -qF 'PASS (all 5 scenarios)' "$GH_BODY_SINK" \
    || { echo "$label: body missing canary PASS marker" >&2; cat "$GH_BODY_SINK" >&2; exit 1; }
  grep -qF -- "--head $SIM_BRANCH_PREFIX/C" "$GH_ARGS_MARKER" \
    || { echo "$label: gh missing --head $SIM_BRANCH_PREFIX/C" >&2; exit 1; }
) && pass "Scenario C (code tier happy-path, canary passes)" || fail "Scenario C (code tier happy-path, canary passes)"
clear_cache

# ---------------------------------------------------------------------------
# Scenario D — --dry-run wrapper
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  label="D"
  template_target=$(pick_template_target)
  write_template_diff "$TEST_DIR/diff-$label.patch" "$template_target" \
    '1a\
TEMPLATE BIAS (scenario D)'
  write_classifier_stub "general" "dry-run check (D)" "$TEST_DIR/classifier-$label.json"

  write_claude_rotator "$label" \
    "$TEST_DIR/classifier-$label.json" \
    "$TEST_DIR/diff-$label.patch"
  activate_rotator "$label"

  preseed_cache_for_scenario \
    "$REPO_ROOT/tests/fixtures/pr-emitter/template-feedback.json" \
    "$TEST_DIR/diff-$label.patch" \
    "$label" \
    "template"

  export GH_BODY_SINK="$TEST_DIR/body-$label.md"
  export GH_ARGS_MARKER="$TEST_DIR/gh-args-$label"

  rc=0
  PATH="$TEST_DIR/bin:$PATH" \
  CO_EVOLVE_DRY_RUN=1 \
  PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/pr-emitter/template-feedback.json" \
  bash "$REPO_ROOT/lab/pel/pr-emitter/pr-emitter.sh" \
    --target "$template_target" \
    --pr-branch "$SIM_BRANCH_PREFIX/D" \
    --dry-run \
    "Scenario D dry-run" \
    >"$TEST_DIR/stdout-$label" 2>"$TEST_DIR/stderr-$label" || rc=$?

  deactivate_rotator "$label"

  if [[ "$rc" -ne 0 ]]; then
    echo "$label: expected exit 0 under --dry-run; got $rc" >&2
    cat "$TEST_DIR/stderr-$label" >&2
    exit 1
  fi
  grep -qF 'DRY-RUN: gh' "$TEST_DIR/stderr-$label" \
    || { echo "$label: stderr missing DRY-RUN marker" >&2; exit 1; }
  test -f "$GH_BODY_SINK" \
    || { echo "$label: body not captured under --dry-run" >&2; exit 1; }
) && pass "Scenario D (--dry-run wrapper PATH-shadowed gh)" || fail "Scenario D (--dry-run wrapper PATH-shadowed gh)"
clear_cache

# ---------------------------------------------------------------------------
# Scenario E — [CANARY-FAILED] diagnostic PR (D-15)
#
# The code proposer's canary runs 5 scenarios inside the sandbox. Scenario 1
# (source-survives) invokes `bash -n lib/co-evolution.sh` which fails on any
# syntax-breaking mutation. We inject a diff that adds a dangling `{` so
# canary scenario 1 fails → canary.sh exits 1 → proposer.sh translates that
# to exit 7 per Phase 7 D-10.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  label="E"
  code_target="lib/co-evolution.sh"  # canary scenario 1 operates on this
  # Minimal syntax-breaking mutation: insert an unmatched `{` on its own line
  # after line 1. awk instead of `sed 1a\` — BSD sed's `a` text handling
  # differs from GNU sed and breaks inside single-quoted scripts.
  e_orig="$TEST_DIR/orig-E-co-evolution.sh" e_mod="$TEST_DIR/mod-E-co-evolution.sh"
  tr -d '\r' < "$REPO_ROOT/$code_target" > "$e_orig"
  awk 'NR == 1 { print; print "{"; next } { print }' "$e_orig" > "$e_mod"
  diff -u --label "a/$code_target" --label "b/$code_target" "$e_orig" "$e_mod" > "$TEST_DIR/diff-$label.patch" || true
  [[ -s "$TEST_DIR/diff-$label.patch" ]] || { echo "INTERNAL: scenario E produced empty diff" >&2; exit 99; }
  write_classifier_stub "bug-catcher" "canary-failed check (E)" "$TEST_DIR/classifier-$label.json"

  write_claude_rotator "$label" \
    "$TEST_DIR/classifier-$label.json" \
    "$TEST_DIR/diff-$label.patch"
  activate_rotator "$label"

  export GH_BODY_SINK="$TEST_DIR/body-$label.md"
  export GH_ARGS_MARKER="$TEST_DIR/gh-args-$label"

  rc=0
  PATH="$TEST_DIR/bin:$PATH" \
  CO_EVOLVE_DRY_RUN=1 \
  PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/pr-emitter/code-feedback.json" \
  bash "$REPO_ROOT/lab/pel/pr-emitter/pr-emitter.sh" \
    --target "$code_target" \
    --pr-branch "$SIM_BRANCH_PREFIX/E" \
    --dry-run \
    "Scenario E canary-failed" \
    >"$TEST_DIR/stdout-$label" 2>"$TEST_DIR/stderr-$label" || rc=$?

  deactivate_rotator "$label"

  if [[ "$rc" -ne 0 ]]; then
    echo "$label: expected exit 0 (emitter creates [CANARY-FAILED] PR); got $rc" >&2
    cat "$TEST_DIR/stderr-$label" >&2
    exit 1
  fi
  grep -qF -- '[CANARY-FAILED] pel(code):' "$GH_ARGS_MARKER" \
    || { echo "$label: PR title not prefixed [CANARY-FAILED]" >&2; cat "$GH_ARGS_MARKER" >&2; exit 1; }
  grep -qF 'FAIL at scenario:' "$GH_BODY_SINK" \
    || { echo "$label: body missing 'FAIL at scenario:' marker" >&2; cat "$GH_BODY_SINK" >&2; exit 1; }
) && pass "Scenario E ([CANARY-FAILED] diagnostic PR)" || fail "Scenario E ([CANARY-FAILED] diagnostic PR)"
clear_cache

# ---------------------------------------------------------------------------
# Scenario F — Budget exceeded exit 6
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  label="F"
  template_target=$(pick_template_target)
  write_template_diff "$TEST_DIR/diff-$label.patch" "$template_target" \
    '1a\
TEMPLATE (scenario F)'
  write_classifier_stub "general" "budget check (F)" "$TEST_DIR/classifier-$label.json"

  write_claude_rotator "$label" \
    "$TEST_DIR/classifier-$label.json" \
    "$TEST_DIR/diff-$label.patch"
  activate_rotator "$label"

  export GH_BODY_SINK="$TEST_DIR/body-$label.md"
  export GH_ARGS_MARKER="$TEST_DIR/gh-args-$label"

  # NO pre-seed: scorer must miss cache → budget check trips.
  rc=0
  PATH="$TEST_DIR/bin:$PATH" \
  CO_EVOLVE_DRY_RUN=1 \
  PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/pr-emitter/template-feedback.json" \
  bash "$REPO_ROOT/lab/pel/pr-emitter/pr-emitter.sh" \
    --target "$template_target" \
    --pr-branch "$SIM_BRANCH_PREFIX/F" \
    --dry-run \
    --budget 0 \
    "Scenario F budget" \
    >"$TEST_DIR/stdout-$label" 2>"$TEST_DIR/stderr-$label" || rc=$?

  deactivate_rotator "$label"

  if [[ "$rc" -ne 6 ]]; then
    echo "$label: expected exit 6; got $rc" >&2
    cat "$TEST_DIR/stderr-$label" >&2
    exit 1
  fi
  grep -qF 'emitter eval budget exhausted' "$TEST_DIR/stderr-$label" \
    || { echo "$label: stderr missing budget-exhausted marker" >&2; exit 1; }
) && pass "Scenario F (budget exceeded exit 6)" || fail "Scenario F (budget exceeded exit 6)"
clear_cache

# ---------------------------------------------------------------------------
# Scenario G — Tier auto-detect hard-error exit 10
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  label="G"
  rc=0
  PATH="$TEST_DIR/bin:$PATH" \
  CO_EVOLVE_DRY_RUN=1 \
  bash "$REPO_ROOT/lab/pel/pr-emitter/pr-emitter.sh" \
    --target "README.md" \
    --dry-run \
    "Scenario G hard-error" \
    >"$TEST_DIR/stdout-$label" 2>"$TEST_DIR/stderr-$label" || rc=$?

  if [[ "$rc" -ne 10 ]]; then
    echo "$label: expected exit 10; got $rc" >&2
    cat "$TEST_DIR/stderr-$label" >&2
    exit 1
  fi
  grep -qF "tier auto-detect: no rule matches" "$TEST_DIR/stderr-$label" \
    || { echo "$label: stderr missing auto-detect hard-error message" >&2; exit 1; }
) && pass "Scenario G (tier auto-detect hard-error exit 10)" || fail "Scenario G (tier auto-detect hard-error exit 10)"

# ---------------------------------------------------------------------------
# Scenario H — --tier override wins (auto-detect=template → override=code →
# code-proposer's allowlist pre-flight gate rejects the template-path target
# with exit 1 per proposer.sh). Tests that (a) override is logged, (b) override
# value is used for dispatch, (c) downstream failure propagates per D-16.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  label="H"
  template_target=$(pick_template_target)
  write_classifier_stub "bug-catcher" "override check (H)" "$TEST_DIR/classifier-$label.json"
  # Code proposer rejects allowlist violations before its claude call, so the
  # diff queue is unused. Provide a placeholder for safety.
  printf 'noop\n' > "$TEST_DIR/placeholder-$label.txt"

  write_claude_rotator "$label" \
    "$TEST_DIR/classifier-$label.json" \
    "$TEST_DIR/placeholder-$label.txt"
  activate_rotator "$label"

  rc=0
  PATH="$TEST_DIR/bin:$PATH" \
  CO_EVOLVE_DRY_RUN=1 \
  PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/pr-emitter/code-feedback.json" \
  bash "$REPO_ROOT/lab/pel/pr-emitter/pr-emitter.sh" \
    --target "$template_target" \
    --tier code \
    --pr-branch "$SIM_BRANCH_PREFIX/H" \
    --dry-run \
    "Scenario H override" \
    >"$TEST_DIR/stdout-$label" 2>"$TEST_DIR/stderr-$label" || rc=$?

  deactivate_rotator "$label"

  # Override notice MUST appear in stderr before any downstream failure.
  grep -qF "tier override: code" "$TEST_DIR/stderr-$label" \
    || { echo "$label: stderr missing 'tier override: code' line" >&2; cat "$TEST_DIR/stderr-$label" >&2; exit 1; }

  # The code proposer rejects the template path at the pre-flight allowlist
  # gate with exit 1 (input validation). The emitter propagates that per D-16.
  # Exit 1 is the correct propagated code; exit 5 (allowlist) would apply only
  # to a diff-targeted mismatch (the proposer catches the target mismatch
  # before it ever parses a diff).
  if [[ "$rc" -ne 1 ]]; then
    echo "$label: expected exit 1 (input-validation propagated); got $rc" >&2
    cat "$TEST_DIR/stderr-$label" >&2
    exit 1
  fi
  grep -qF "is not on the code-tier allowlist" "$TEST_DIR/stderr-$label" \
    || { echo "$label: stderr missing allowlist-rejection marker" >&2; exit 1; }
) && pass "Scenario H (--tier override wins; downstream propagates exit 1)" \
   || fail "Scenario H (--tier override wins; downstream propagates exit 1)"
clear_cache

# ---------------------------------------------------------------------------
# Scenario I — Byte-parity SC-5
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  label="I"
  rc=0
  bash "$REPO_ROOT/co-evolve-bouncer.sh" --help \
    >"$TEST_DIR/stdout-$label" 2>"$TEST_DIR/stderr-$label" || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "$label: --help unexpected exit $rc" >&2
    exit 1
  fi

  for flag in --skip-interview --auto --vanilla --exocortex --context \
              --audience --lens --chain --bounces --agents --dev-review \
              --bounce-only --output --lab --help; do
    grep -qF -- "$flag" "$TEST_DIR/stdout-$label" \
      || { echo "$label: help missing v1.1 flag $flag" >&2; exit 1; }
  done

  for flag in --target --tier --pr-branch --dry-run --budget --yes --flavor; do
    grep -qF -- "$flag" "$TEST_DIR/stdout-$label" \
      || { echo "$label: help missing Phase 8 flag $flag" >&2; exit 1; }
  done

  for marker in "pel-proposer" "tier auto-detect" "co-evolve-cache" "scoring"; do
    if grep -qF -- "$marker" "$TEST_DIR/stderr-$label"; then
      echo "$label: stderr leaked PEL marker '$marker' in --help" >&2
      exit 1
    fi
  done
) && pass "Scenario I (byte-parity SC-5: --help stable; no PEL leaks)" \
   || fail "Scenario I (byte-parity SC-5: --help stable; no PEL leaks)"

# ---------------------------------------------------------------------------
# Scenario J — Eval cache hit (two runs with same cache entries)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  label="J"
  template_target=$(pick_template_target)
  write_template_diff "$TEST_DIR/diff-$label.patch" "$template_target" \
    '1a\
TEMPLATE (scenario J)'
  write_classifier_stub "bug-catcher" "cache hit check (J)" "$TEST_DIR/classifier-$label.json"

  write_claude_rotator "$label" \
    "$TEST_DIR/classifier-$label.json" \
    "$TEST_DIR/diff-$label.patch"
  activate_rotator "$label"

  preseed_cache_for_scenario \
    "$REPO_ROOT/tests/fixtures/pr-emitter/template-feedback.json" \
    "$TEST_DIR/diff-$label.patch" \
    "$label" \
    "template"

  # Run 1
  export GH_BODY_SINK="$TEST_DIR/body-J1.md"
  export GH_ARGS_MARKER="$TEST_DIR/gh-args-J1"
  rc=0
  PATH="$TEST_DIR/bin:$PATH" \
  CO_EVOLVE_DRY_RUN=1 \
  PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/pr-emitter/template-feedback.json" \
  bash "$REPO_ROOT/lab/pel/pr-emitter/pr-emitter.sh" \
    --target "$template_target" \
    --pr-branch "$SIM_BRANCH_PREFIX/J1" \
    --dry-run \
    "Scenario J run-1" \
    >"$TEST_DIR/stdout-J1" 2>"$TEST_DIR/stderr-J1" || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "J: run-1 unexpected exit $rc" >&2
    cat "$TEST_DIR/stderr-J1" >&2
    exit 1
  fi
  grep -qF 'eval cache hit: before' "$TEST_DIR/stderr-J1" \
    || { echo "J: run-1 missing 'eval cache hit: before'" >&2; cat "$TEST_DIR/stderr-J1" >&2; exit 1; }
  grep -qF 'eval cache hit: after'  "$TEST_DIR/stderr-J1" \
    || { echo "J: run-1 missing 'eval cache hit: after'" >&2;  cat "$TEST_DIR/stderr-J1" >&2; exit 1; }

  # Run 2 — same cache entries, different branch name to avoid ref collision.
  # Reset claude rotator counter so run-2 sees the same call sequence.
  rm -f "$TEST_DIR/counter-J"
  export GH_BODY_SINK="$TEST_DIR/body-J2.md"
  export GH_ARGS_MARKER="$TEST_DIR/gh-args-J2"
  rc=0
  PATH="$TEST_DIR/bin:$PATH" \
  CO_EVOLVE_DRY_RUN=1 \
  PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/pr-emitter/template-feedback.json" \
  bash "$REPO_ROOT/lab/pel/pr-emitter/pr-emitter.sh" \
    --target "$template_target" \
    --pr-branch "$SIM_BRANCH_PREFIX/J2" \
    --dry-run \
    "Scenario J run-2" \
    >"$TEST_DIR/stdout-J2" 2>"$TEST_DIR/stderr-J2" || rc=$?

  deactivate_rotator "$label"

  if [[ "$rc" -ne 0 ]]; then
    echo "J: run-2 unexpected exit $rc" >&2
    cat "$TEST_DIR/stderr-J2" >&2
    exit 1
  fi
  grep -qF 'eval cache hit: before' "$TEST_DIR/stderr-J2" \
    || { echo "J: run-2 missing 'eval cache hit: before'" >&2; cat "$TEST_DIR/stderr-J2" >&2; exit 1; }
) && pass "Scenario J (eval cache hit — both runs hit cache)" || fail "Scenario J (eval cache hit — both runs hit cache)"
clear_cache

# ---------------------------------------------------------------------------
# Scenario K — Bug #5 regression: run-evals.sh exit 1 with raw-scores.json
# present MUST be treated as scored-with-fails, not scorer crash.
#
# Pre-Bug-5-fix: pr-emitter.sh:667-670 `if ! (run-evals)` then-branch died
# with "scorer run failed for before" whenever run-evals.sh exited 1, which
# run-evals.sh does any time ≥1 case robust-fails — valid scored output.
# Post-fix: exit code captured separately; file-presence check decides
# fatality; exit 1 + file = INFO log + continue.
# Uses PEL_RUN_EVALS_OVERRIDE hook (zero API cost, deterministic).
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  label="K"
  template_target=$(pick_template_target)
  write_template_diff "$TEST_DIR/diff-$label.patch" "$template_target" \
    '1a\
TEMPLATE BIAS COMMENT (bug-catcher, scenario K)'
  write_classifier_stub "bug-catcher" "template weakness (scenario K)" "$TEST_DIR/classifier-$label.json"

  write_claude_rotator "$label" \
    "$TEST_DIR/classifier-$label.json" \
    "$TEST_DIR/diff-$label.patch"
  activate_rotator "$label"

  # Deliberately skip preseed_cache_for_scenario — we want the scorer path to
  # fire so the run-evals-exit-code wire is exercised.
  clear_cache

  # Stub run-evals.sh: write a valid raw-scores.json + exit 1.
  stub_scorer="$TEST_DIR/stub-run-evals-$label.sh"
  cat > "$stub_scorer" <<'SCORER_STUB'
#!/usr/bin/env bash
# Scenario K stub run-evals.sh: produce valid scores, exit 1 (robust-fail).
set -u
ts=$(date -u +"%Y%m%dT%H%M%S")
report_dir="evals/reports/scenario-K-$ts-$$"
mkdir -p "$report_dir"
cat > "$report_dir/raw-scores.json" <<RAW
[
  {"case_id": "stub-case", "iteration": 1, "status": "scored",
   "scores": {"robustness": "FAIL", "composite": 0.3}, "composite": 0.3}
]
RAW
# Exit 1 as "some case robust-failed" — the classic Bug #5 trigger.
exit 1
SCORER_STUB
  chmod +x "$stub_scorer"

  export GH_BODY_SINK="$TEST_DIR/body-$label.md"
  export GH_ARGS_MARKER="$TEST_DIR/gh-args-$label"

  rc=0
  PATH="$TEST_DIR/bin:$PATH" \
  CO_EVOLVE_DRY_RUN=1 \
  PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/pr-emitter/template-feedback.json" \
  PEL_RUN_EVALS_OVERRIDE="$stub_scorer" \
  bash "$REPO_ROOT/lab/pel/pr-emitter/pr-emitter.sh" \
    --target "$template_target" \
    --pr-branch "$SIM_BRANCH_PREFIX/K" \
    --dry-run \
    "Scenario K task" \
    >"$TEST_DIR/stdout-$label" 2>"$TEST_DIR/stderr-$label" || rc=$?

  deactivate_rotator "$label"

  # Cleanup: remove scenario-K report dirs we wrote to REPO_ROOT and any
  # EMITTER_SANDBOX would be cleaned by pr-emitter's own trap.
  rm -rf "$REPO_ROOT"/evals/reports/scenario-K-* 2>/dev/null || true

  if [[ "$rc" -ne 0 ]]; then
    echo "$label: expected exit 0 (Bug #5 regression); got $rc" >&2
    echo "--- stderr ---" >&2; cat "$TEST_DIR/stderr-$label" >&2
    exit 1
  fi
  grep -qF 'treating as scored-with-fails' "$TEST_DIR/stderr-$label" \
    || { echo "$label: stderr missing 'treating as scored-with-fails' INFO log" >&2; cat "$TEST_DIR/stderr-$label" >&2; exit 1; }
  test -f "$GH_BODY_SINK" \
    || { echo "$label: body not captured" >&2; exit 1; }
  grep -qE '^## PEL Mutation: template tier' "$GH_BODY_SINK" \
    || { echo "$label: body missing template heading" >&2; cat "$GH_BODY_SINK" >&2; exit 1; }
) && pass "Scenario K (Bug #5 regression — run-evals exit 1 + scores present)" \
  || fail "Scenario K (Bug #5 regression)"
clear_cache

# ---------------------------------------------------------------------------
# Scenario L — I-3 integration guard: router fires in production flow.
#
# Context: Scenarios A-K all rotate the claude stub with 2 items (classifier +
# proposer). When pr-emitter invokes the router, it's the 3rd claude call,
# and the rotator's fallback replays the proposer response — which is not
# valid router JSON, so the router silently fails and pr-emitter falls back
# to the pre-adaptive "opus" default. That silent-fail path hid C-1 from the
# 2026-04-21 adaptive review.
#
# Scenario L queues THREE items (classifier, router, proposer) so the router's
# Haiku call gets a valid NORMAL/sonnet response and the router actually runs.
# Assertion: stderr contains "router picked complexity=NORMAL model=sonnet".
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  label="L"
  template_target=$(pick_template_target)
  write_template_diff "$TEST_DIR/diff-$label.patch" "$template_target" \
    '1a\
TEMPLATE BIAS COMMENT (bug-catcher, scenario L)'
  write_classifier_stub "bug-catcher" "router fires (scenario L)" "$TEST_DIR/classifier-$label.json"

  # Router Haiku response: NORMAL → router.sh constructs
  # {complexity: NORMAL, model: sonnet, fallback_model: sonnet, ...} JSON.
  cat > "$TEST_DIR/router-$label.json" <<'ROUTER'
{
  "complexity": "NORMAL",
  "rationale": "Small template tweak; routine wording — NORMAL."
}
ROUTER

  # Three-item queue: classifier → router → proposer. Preserves existing
  # rotator semantics (fallback-replay still works if callers exceed 3, but
  # template tier only makes 3 claude calls in this flow).
  write_claude_rotator "$label" \
    "$TEST_DIR/classifier-$label.json" \
    "$TEST_DIR/router-$label.json" \
    "$TEST_DIR/diff-$label.patch"
  activate_rotator "$label"

  preseed_cache_for_scenario \
    "$REPO_ROOT/tests/fixtures/pr-emitter/template-feedback.json" \
    "$TEST_DIR/diff-$label.patch" \
    "$label" \
    "template"

  export GH_BODY_SINK="$TEST_DIR/body-$label.md"
  export GH_ARGS_MARKER="$TEST_DIR/gh-args-$label"

  rc=0
  PATH="$TEST_DIR/bin:$PATH" \
  CO_EVOLVE_DRY_RUN=1 \
  PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/pr-emitter/template-feedback.json" \
  bash "$REPO_ROOT/lab/pel/pr-emitter/pr-emitter.sh" \
    --target "$template_target" \
    --pr-branch "$SIM_BRANCH_PREFIX/L" \
    --dry-run \
    "Scenario L task" \
    >"$TEST_DIR/stdout-$label" 2>"$TEST_DIR/stderr-$label" || rc=$?

  deactivate_rotator "$label"

  if [[ "$rc" -ne 0 ]]; then
    echo "$label: expected exit 0 (router-fires); got $rc" >&2
    echo "--- stderr ---" >&2; cat "$TEST_DIR/stderr-$label" >&2
    exit 1
  fi

  # Primary assertion: the router's routing log must appear, proving the
  # router consumed its queued response and ran to completion.
  grep -qF 'router picked complexity=NORMAL model=sonnet' "$TEST_DIR/stderr-$label" \
    || { echo "$label: stderr missing 'router picked complexity=NORMAL model=sonnet'" >&2; cat "$TEST_DIR/stderr-$label" >&2; exit 1; }

  # Negative assertion: router-failure WARN must NOT appear (that would mean
  # the queued response failed to reach the router, exposing a rotator bug).
  if grep -qF 'router invocation failed' "$TEST_DIR/stderr-$label"; then
    echo "$label: router fell back silently — queued router response never reached it" >&2
    cat "$TEST_DIR/stderr-$label" >&2
    exit 1
  fi

  test -f "$GH_BODY_SINK" \
    || { echo "$label: body not captured" >&2; exit 1; }
  grep -qE '^## PEL Mutation: template tier' "$GH_BODY_SINK" \
    || { echo "$label: body missing template heading" >&2; cat "$GH_BODY_SINK" >&2; exit 1; }
) && pass "Scenario L (I-3 router-fires — NORMAL/sonnet log line present)" \
  || fail "Scenario L (I-3 router-fires)"
clear_cache

# ---------------------------------------------------------------------------
# Final footer
# ---------------------------------------------------------------------------
passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
