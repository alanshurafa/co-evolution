#!/usr/bin/env bash
# tests/template-proposer-simulation.sh
# Phase 5 PEL-02: Hermetic simulation of lab/pel/proposer/template/ behavior.
#
# SC-4 gate — 8 primary scenarios (all required), exits 0 with "8/8 scenarios
# passed" as the final line on clean Plan 01 proposer surface. No real Opus
# invocation; claude CLI is PATH-injected stub returning canned diffs per
# scenario; no network traffic.
#
# Scenarios:
#   A: Flavor = bug-catcher               — stub returns a valid 1-file, 1-hunk
#                                           diff modifying bounce-protocol.md.
#                                           Assert exit 0 + stdout contains
#                                           --- a/tests/fixtures/templates/bounce-protocol.md + @@.
#   B: Flavor = faster-converger          — valid diff against
#                                           bounce-prompt-portable.md fixture.
#   C: Flavor = blind-spot-surfacer       — valid diff against
#                                           review-prompt-opus.md fixture.
#   D: Flavor = general                   — valid diff against
#                                           dev-prompt-opus.md fixture.
#   E: Multi-file diff rejection (D-09)   — stub emits a diff touching TWO
#                                           files under tests/fixtures/templates/.
#                                           Proposer must die exit 4 with
#                                           "single-file" / "1" / "2 files"
#                                           mention in stderr.
#   F: Non-template-path rejection (D-09) — stub emits a diff targeting
#                                           lab/pel/classifier/adapter.sh
#                                           (outside allowed template
#                                           prefixes). Proposer dies exit 4
#                                           with "template" / "allowed" /
#                                           "prefix" / "skills/dev-review/templates"
#                                           mention.
#   G: Malformed-diff rejection (D-10)    — stub emits text with --- a/ and
#                                           +++ b/ headers but NO @@ hunk
#                                           header. Proposer dies exit 3
#                                           with "apply" / "malformed" /
#                                           "does not apply" / "diff" mention.
#   H: Missing required env var (D-03)    — PEL_EVAL_REPORT unset. Proposer
#                                           dies exit 1 with PEL_EVAL_REPORT
#                                           + required / readable / must be
#                                           set mention.
#
# Final line on success: "8/8 scenarios passed" (matches v1.2 phase-gate
# convention: Phase 2 13/13, Phase 3 4/4, Phase 4 6/6).
# Exit 0 iff all 8 scenarios pass; exit 1 otherwise.
#
# Dependencies: bash, jq, git, diff, cp, sed, awk. No claude CLI (stubbed),
# no network.

set -euo pipefail

TEST_DIR=$(mktemp -d -t proposer-template-sim-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

FAILURES=0
TOTAL=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

# ---------------------------------------------------------------------------
# Stub claude CLI (PATH-injected). Echoes whatever canned diff the test
# placed in $PROPOSER_STUB_FILE. Writes a fingerprint marker per call so
# future phases can prove bypass invariants (not used by any current
# scenario — reserved for the same reason Phase 4 reserved it).
#
# Env var prefix PROPOSER_* (not CLASSIFIER_*) keeps the stub independent
# from the Phase 4 stub — both simulations may coexist in CI without
# env collision.
# ---------------------------------------------------------------------------

mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
# PATH-injected stub for hermetic template-tier proposer simulation.
#
# Fingerprint: record every invocation so future tests can assert bypass
# invariants. Current scenarios do not rely on this.
if [[ -n "${PROPOSER_STUB_MARKER:-}" ]]; then
  printf 'called\n' >> "$PROPOSER_STUB_MARKER"
fi

# --version handling so any require_claude_cli probe path works.
if [[ "$*" == *"--version"* ]]; then
  echo "claude 1.0.0 (stub)"
  exit 0
fi

# Consume stdin so the upstream prompt-file redirect doesn't leak.
cat > /dev/null

# Optional forced-exit path for negative scenarios (reserved).
if [[ -n "${PROPOSER_STUB_EXIT:-}" ]]; then
  exit "$PROPOSER_STUB_EXIT"
fi

# Emit the canned diff response.
if [[ -z "${PROPOSER_STUB_FILE:-}" || ! -f "${PROPOSER_STUB_FILE:-}" ]]; then
  echo "STUB ERROR: PROPOSER_STUB_FILE not set or file missing" >&2
  exit 99
fi
cat "$PROPOSER_STUB_FILE"
STUB
chmod +x "$TEST_DIR/bin/claude"

# ---------------------------------------------------------------------------
# Helper: write a valid stub diff by modifying a copy of a fixture and
# computing the unified diff between the original and modified copy. This
# avoids hand-authored line numbers that might drift if the fixture changes.
#
#   write_valid_stub_diff <dest_stub_file> <repo_rel_fixture_path> <sed_script>
#
# sed_script runs on the fixture content (stdin -> stdout) to produce the
# "modified" version. The resulting diff header uses the repo-relative path
# so the proposer's D-09 gate sees the correct target.
# ---------------------------------------------------------------------------
write_valid_stub_diff() {
  local dest="$1"
  local repo_rel="$2"
  local sed_script="$3"
  local abs="$REPO_ROOT/$repo_rel"
  local orig_copy="$TEST_DIR/orig-$(basename "$repo_rel")"
  local mod_copy="$TEST_DIR/mod-$(basename "$repo_rel")"
  # Normalize to LF-only for both orig and mod so the resulting diff is
  # internally consistent. On Git Bash Windows the fixtures on disk have
  # CRLF line endings (git core.autocrlf=true default); mixing a sed-inserted
  # LF-only new line into CRLF context lines produces a malformed diff that
  # `git apply --check` rejects. Stripping CR from both sides gives clean
  # LF-only hunks. Git's apply is smart enough to apply an LF-only diff
  # against a CRLF on-disk target, so this is safe cross-platform (Linux/
  # macOS fixtures are LF-only to begin with — tr -d '\r' is a no-op there).
  tr -d '\r' < "$abs" > "$orig_copy"
  sed "$sed_script" "$orig_copy" > "$mod_copy"
  # Use diff -u with explicit labels so the headers say "a/<repo_rel>" and
  # "b/<repo_rel>" instead of the temp-path basenames. This matches what
  # `git apply` expects.
  diff -u --label "a/$repo_rel" --label "b/$repo_rel" "$orig_copy" "$mod_copy" > "$dest" || true
  # Sanity: the diff must be non-empty (otherwise the sed script didn't
  # change anything and Scenarios A-D will have no body to validate).
  if [[ ! -s "$dest" ]]; then
    echo "INTERNAL ERROR: write_valid_stub_diff produced an empty diff for $repo_rel" >&2
    exit 99
  fi
}

# ---------------------------------------------------------------------------
# Scenario A: Flavor = bug-catcher — valid diff against bounce-protocol.md
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-A.diff"
  # Sed script: add a bug-catcher bias line after the "focus on polish only"
  # convergence rule. The exact line may shift if the fixture changes — the
  # diff -u call computes the correct hunk header dynamically.
  write_valid_stub_diff "$stub_file" \
    "tests/fixtures/templates/bounce-protocol.md" \
    's|Convergence:|Convergence:\n- Bug-catcher bias: before declaring convergence, enumerate at least one adversarial case the current plan does not address.|'

  rc=0
  result=$(PROPOSER_STUB_FILE="$stub_file" \
           PROPOSER_STUB_MARKER="$TEST_DIR/marker-A" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/eval-failures/bounce-protocol-weakness.json" \
           PEL_TEMPLATE_PATH="tests/fixtures/templates/bounce-protocol.md" \
           PEL_FLAVOR=bug-catcher \
           bash "$REPO_ROOT/lab/pel/proposer/template/proposer.sh" \
             "focus mutation on the bounce-protocol convergence rule" 2>"$TEST_DIR/stderr-A") || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "A: proposer exited $rc; stderr: $(cat "$TEST_DIR/stderr-A")" >&2
    exit 1
  fi
  echo "$result" | grep -qE '^--- a/tests/fixtures/templates/bounce-protocol\.md' \
    || { echo "A: stdout missing --- header; got: $result" >&2; exit 1; }
  echo "$result" | grep -qE '^\+\+\+ b/tests/fixtures/templates/bounce-protocol\.md' \
    || { echo "A: stdout missing +++ header; got: $result" >&2; exit 1; }
  echo "$result" | grep -qF '@@' \
    || { echo "A: stdout missing @@ hunk header; got: $result" >&2; exit 1; }
) && pass "Scenario A (flavor=bug-catcher, valid diff against bounce-protocol.md)" \
  || fail "Scenario A (bug-catcher)"

# ---------------------------------------------------------------------------
# Scenario B: Flavor = faster-converger — valid diff against bounce-prompt-portable.md
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-B.diff"
  # Sed script: trim a redundant clause to bias toward concision (the
  # faster-converger flavor's editorial direction).
  write_valid_stub_diff "$stub_file" \
    "tests/fixtures/templates/bounce-prompt-portable.md" \
    's|Convergence:|Convergence (early-exit bias — converge on the first CONTESTED-and-CLARIFY-free pass):|'

  rc=0
  result=$(PROPOSER_STUB_FILE="$stub_file" \
           PROPOSER_STUB_MARKER="$TEST_DIR/marker-B" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/eval-failures/compose-prompt-weakness.json" \
           PEL_TEMPLATE_PATH="tests/fixtures/templates/bounce-prompt-portable.md" \
           PEL_FLAVOR=faster-converger \
           bash "$REPO_ROOT/lab/pel/proposer/template/proposer.sh" \
             "tighten convergence to fewer rounds" 2>"$TEST_DIR/stderr-B") || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "B: proposer exited $rc; stderr: $(cat "$TEST_DIR/stderr-B")" >&2
    exit 1
  fi
  echo "$result" | grep -qE '^--- a/tests/fixtures/templates/bounce-prompt-portable\.md' \
    || { echo "B: stdout missing --- header; got: $result" >&2; exit 1; }
  echo "$result" | grep -qE '^\+\+\+ b/tests/fixtures/templates/bounce-prompt-portable\.md' \
    || { echo "B: stdout missing +++ header; got: $result" >&2; exit 1; }
  echo "$result" | grep -qF '@@' \
    || { echo "B: stdout missing @@ hunk header; got: $result" >&2; exit 1; }
) && pass "Scenario B (flavor=faster-converger, valid diff against bounce-prompt-portable.md)" \
  || fail "Scenario B (faster-converger)"

# ---------------------------------------------------------------------------
# Scenario C: Flavor = blind-spot-surfacer — valid diff against review-prompt-opus.md
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-C.diff"
  # Sed script: add an adversarial-case surfacing rider.
  write_valid_stub_diff "$stub_file" \
    "tests/fixtures/templates/review-prompt-opus.md" \
    's|## Filtering|## Adversarial surfacing\n- Actively search for edge cases the original task description did not enumerate. A single missed edge case is worth more than three ratified certainties.\n\n## Filtering|'

  rc=0
  result=$(PROPOSER_STUB_FILE="$stub_file" \
           PROPOSER_STUB_MARKER="$TEST_DIR/marker-C" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/eval-failures/review-prompt-weakness.json" \
           PEL_TEMPLATE_PATH="tests/fixtures/templates/review-prompt-opus.md" \
           PEL_FLAVOR=blind-spot-surfacer \
           bash "$REPO_ROOT/lab/pel/proposer/template/proposer.sh" \
             "surface unknown-unknown edge cases" 2>"$TEST_DIR/stderr-C") || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "C: proposer exited $rc; stderr: $(cat "$TEST_DIR/stderr-C")" >&2
    exit 1
  fi
  echo "$result" | grep -qE '^--- a/tests/fixtures/templates/review-prompt-opus\.md' \
    || { echo "C: stdout missing --- header; got: $result" >&2; exit 1; }
  echo "$result" | grep -qE '^\+\+\+ b/tests/fixtures/templates/review-prompt-opus\.md' \
    || { echo "C: stdout missing +++ header; got: $result" >&2; exit 1; }
  echo "$result" | grep -qF '@@' \
    || { echo "C: stdout missing @@ hunk header; got: $result" >&2; exit 1; }
) && pass "Scenario C (flavor=blind-spot-surfacer, valid diff against review-prompt-opus.md)" \
  || fail "Scenario C (blind-spot-surfacer)"

# ---------------------------------------------------------------------------
# Scenario D: Flavor = general — valid diff against dev-prompt-opus.md
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-D.diff"
  # Sed script: balanced improvement — tighten one instruction without
  # rewriting the template.
  write_valid_stub_diff "$stub_file" \
    "tests/fixtures/templates/dev-prompt-opus.md" \
    's|## Instructions|## Instructions\n\nBalanced improvement bias: prefer a single cohesive edit that raises multiple signals modestly.\n|'

  rc=0
  result=$(PROPOSER_STUB_FILE="$stub_file" \
           PROPOSER_STUB_MARKER="$TEST_DIR/marker-D" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/eval-failures/dev-prompt-weakness.json" \
           PEL_TEMPLATE_PATH="tests/fixtures/templates/dev-prompt-opus.md" \
           PEL_FLAVOR=general \
           bash "$REPO_ROOT/lab/pel/proposer/template/proposer.sh" \
             "" 2>"$TEST_DIR/stderr-D") || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "D: proposer exited $rc; stderr: $(cat "$TEST_DIR/stderr-D")" >&2
    exit 1
  fi
  echo "$result" | grep -qE '^--- a/tests/fixtures/templates/dev-prompt-opus\.md' \
    || { echo "D: stdout missing --- header; got: $result" >&2; exit 1; }
  echo "$result" | grep -qE '^\+\+\+ b/tests/fixtures/templates/dev-prompt-opus\.md' \
    || { echo "D: stdout missing +++ header; got: $result" >&2; exit 1; }
  echo "$result" | grep -qF '@@' \
    || { echo "D: stdout missing @@ hunk header; got: $result" >&2; exit 1; }
) && pass "Scenario D (flavor=general, valid diff against dev-prompt-opus.md, empty task hint)" \
  || fail "Scenario D (general)"

# ---------------------------------------------------------------------------
# Scenario E: Multi-file diff rejection (D-09 single-file gate)
# ---------------------------------------------------------------------------
# Concatenate two valid per-file diffs into one stub response. The proposer's
# D-09 parser counts unique file targets and must reject with exit 4 when
# the count exceeds 1.
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-E.diff"
  # Build diff A (bounce-protocol.md). Normalize to LF for internally-
  # consistent diff (see write_valid_stub_diff comment above).
  orig_A="$TEST_DIR/orig-E-A.md"
  mod_A="$TEST_DIR/mod-E-A.md"
  tr -d '\r' < "$REPO_ROOT/tests/fixtures/templates/bounce-protocol.md" > "$orig_A"
  sed 's|Convergence:|Convergence (multi-file test variant):|' "$orig_A" > "$mod_A"
  diff -u --label "a/tests/fixtures/templates/bounce-protocol.md" --label "b/tests/fixtures/templates/bounce-protocol.md" \
    "$orig_A" "$mod_A" > "$stub_file" || true

  # Build diff B (bounce-prompt-portable.md) and append.
  orig_B="$TEST_DIR/orig-E-B.md"
  mod_B="$TEST_DIR/mod-E-B.md"
  tr -d '\r' < "$REPO_ROOT/tests/fixtures/templates/bounce-prompt-portable.md" > "$orig_B"
  sed 's|Convergence:|Convergence (multi-file test variant):|' "$orig_B" > "$mod_B"
  diff -u --label "a/tests/fixtures/templates/bounce-prompt-portable.md" --label "b/tests/fixtures/templates/bounce-prompt-portable.md" \
    "$orig_B" "$mod_B" >> "$stub_file" || true

  rc=0
  result=$(PROPOSER_STUB_FILE="$stub_file" \
           PROPOSER_STUB_MARKER="$TEST_DIR/marker-E" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/eval-failures/bounce-protocol-weakness.json" \
           PEL_TEMPLATE_PATH="tests/fixtures/templates/bounce-protocol.md" \
           PEL_FLAVOR=bug-catcher \
           bash "$REPO_ROOT/lab/pel/proposer/template/proposer.sh" \
             "multi-file test" 2>"$TEST_DIR/stderr-E") || rc=$?

  if [[ "$rc" -ne 4 ]]; then
    echo "E: expected exit 4 (D-09 single-file violation), got exit $rc" >&2
    echo "E: stderr: $(cat "$TEST_DIR/stderr-E")" >&2
    echo "E: stdout: $result" >&2
    exit 1
  fi
  # Permissive match — any of the D-09-related keywords.
  if ! grep -qE 'single-file|1 file|2 files|D-09|constraint' "$TEST_DIR/stderr-E"; then
    echo "E: stderr missing D-09 single-file violation message; got: $(cat "$TEST_DIR/stderr-E")" >&2
    exit 1
  fi
) && pass "Scenario E (multi-file diff rejected by D-09 with exit 4)" \
  || fail "Scenario E (D-09 single-file)"

# ---------------------------------------------------------------------------
# Scenario F: Non-template-path rejection (D-09 path-prefix gate)
# ---------------------------------------------------------------------------
# Stub emits a valid-shape unified diff targeting lab/pel/classifier/adapter.sh
# — a file outside the allowed skills/dev-review/templates/ and
# tests/fixtures/templates/ prefixes. Proposer must die exit 4.
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-F.diff"
  # Use a real sibling file for the diff body so the diff is structurally
  # valid. D-09 path-prefix gate rejects BEFORE D-10 git apply --check runs,
  # so this diff only needs a clean structure — line endings don't matter
  # for this scenario, but normalize for consistency with Scenarios A-D/E.
  orig="$TEST_DIR/orig-F.sh"
  mod="$TEST_DIR/mod-F.sh"
  tr -d '\r' < "$REPO_ROOT/lab/pel/classifier/adapter.sh" > "$orig"
  # A small single-line edit so diff -u produces a clean hunk.
  sed 's|# Inline die()|# Inline die() (path-escape test variant)|' "$orig" > "$mod"
  diff -u --label "a/lab/pel/classifier/adapter.sh" --label "b/lab/pel/classifier/adapter.sh" \
    "$orig" "$mod" > "$stub_file" || true

  rc=0
  result=$(PROPOSER_STUB_FILE="$stub_file" \
           PROPOSER_STUB_MARKER="$TEST_DIR/marker-F" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/eval-failures/bounce-protocol-weakness.json" \
           PEL_TEMPLATE_PATH="tests/fixtures/templates/bounce-protocol.md" \
           PEL_FLAVOR=bug-catcher \
           bash "$REPO_ROOT/lab/pel/proposer/template/proposer.sh" \
             "path-escape test" 2>"$TEST_DIR/stderr-F") || rc=$?

  if [[ "$rc" -ne 4 ]]; then
    echo "F: expected exit 4 (D-09 path-prefix violation), got exit $rc" >&2
    echo "F: stderr: $(cat "$TEST_DIR/stderr-F")" >&2
    echo "F: stdout: $result" >&2
    exit 1
  fi
  if ! grep -qE 'template|allowed|prefix|skills/dev-review/templates' "$TEST_DIR/stderr-F"; then
    echo "F: stderr missing path-prefix violation message; got: $(cat "$TEST_DIR/stderr-F")" >&2
    exit 1
  fi
) && pass "Scenario F (non-template-path diff rejected by D-09 with exit 4)" \
  || fail "Scenario F (D-09 path-prefix)"

# ---------------------------------------------------------------------------
# Scenario G: Malformed-diff rejection (D-10 git apply --check gate)
# ---------------------------------------------------------------------------
# Stub emits --- a/ and +++ b/ headers but NO @@ hunk header. git apply
# --check rejects this as structurally malformed. Proposer dies exit 3.
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-G.diff"
  # Single-file target (passes D-09) but no hunk header (fails D-10).
  cat > "$stub_file" <<'MALFORMED'
--- a/tests/fixtures/templates/bounce-protocol.md
+++ b/tests/fixtures/templates/bounce-protocol.md
 This is text that looks like a diff context line
-but is missing the required @@ hunk header above.
+The proposer should reject this via git apply --check.
MALFORMED

  rc=0
  result=$(PROPOSER_STUB_FILE="$stub_file" \
           PROPOSER_STUB_MARKER="$TEST_DIR/marker-G" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_EVAL_REPORT="$REPO_ROOT/tests/fixtures/eval-failures/bounce-protocol-weakness.json" \
           PEL_TEMPLATE_PATH="tests/fixtures/templates/bounce-protocol.md" \
           PEL_FLAVOR=bug-catcher \
           bash "$REPO_ROOT/lab/pel/proposer/template/proposer.sh" \
             "malformed-diff test" 2>"$TEST_DIR/stderr-G") || rc=$?

  if [[ "$rc" -ne 3 ]]; then
    echo "G: expected exit 3 (D-10 malformed diff), got exit $rc" >&2
    echo "G: stderr: $(cat "$TEST_DIR/stderr-G")" >&2
    echo "G: stdout: $result" >&2
    exit 1
  fi
  if ! grep -qE 'apply|malformed|does not apply|diff' "$TEST_DIR/stderr-G"; then
    echo "G: stderr missing D-10 failure message; got: $(cat "$TEST_DIR/stderr-G")" >&2
    exit 1
  fi
) && pass "Scenario G (malformed diff rejected by D-10 with exit 3)" \
  || fail "Scenario G (D-10 malformed)"

# ---------------------------------------------------------------------------
# Scenario H: Missing required env var (D-03 fail-fast)
# ---------------------------------------------------------------------------
# Unset PEL_EVAL_REPORT in the subshell. Proposer must die exit 1 with a
# specific error message mentioning PEL_EVAL_REPORT + required/readable/must.
TOTAL=$((TOTAL + 1))
(
  unset PEL_EVAL_REPORT
  rc=0
  result=$(PATH="$TEST_DIR/bin:$PATH" \
           PEL_TEMPLATE_PATH="tests/fixtures/templates/bounce-protocol.md" \
           PEL_FLAVOR=bug-catcher \
           bash "$REPO_ROOT/lab/pel/proposer/template/proposer.sh" \
             "" 2>"$TEST_DIR/stderr-H") || rc=$?

  if [[ "$rc" -ne 1 ]]; then
    echo "H: expected exit 1 (D-03 missing env var), got exit $rc" >&2
    echo "H: stderr: $(cat "$TEST_DIR/stderr-H")" >&2
    echo "H: stdout: $result" >&2
    exit 1
  fi
  if ! grep -qE 'PEL_EVAL_REPORT' "$TEST_DIR/stderr-H"; then
    echo "H: stderr missing PEL_EVAL_REPORT reference; got: $(cat "$TEST_DIR/stderr-H")" >&2
    exit 1
  fi
  if ! grep -qE 'required|readable|must be set' "$TEST_DIR/stderr-H"; then
    echo "H: stderr missing required/readable/must-be-set context; got: $(cat "$TEST_DIR/stderr-H")" >&2
    exit 1
  fi
) && pass "Scenario H (missing PEL_EVAL_REPORT rejected by D-03 with exit 1)" \
  || fail "Scenario H (D-03 fail-fast)"

# ---------------------------------------------------------------------------
# Summary footer (matches v1.2 phase-gate convention: Phase 2 13/13,
# Phase 3 4/4, Phase 4 6/6). All 8 scenarios are primary per CONTEXT D-15
# (no bonus split in this phase).
# ---------------------------------------------------------------------------

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
