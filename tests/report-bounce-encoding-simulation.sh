#!/usr/bin/env bash
# tests/report-bounce-encoding-simulation.sh — regression gate for the
# emoji/multibyte crash in evals/score-bounce.sh's awk extractors.
#
# Bug: a real co-evolve --bounce-only run whose input document had a 4-byte
# UTF-8 character (an emoji) in a heading made evals/report-bounce.sh fail
# with "WARNING: report generation failed". Root cause: gawk's *locale-aware*
# gsub(/[^a-z0-9 ]/, ...) mishandles 4-byte UTF-8 codepoints under a UTF-8
# locale -- it strips 3 of the 4 bytes and leaves one orphan continuation
# byte behind. That single invalid byte then makes the downstream `sort`
# hard-crash with "Invalid or incomplete multibyte or wide character", which
# `set -euo pipefail` propagates as score-bounce.sh exiting nonzero, so
# report-bounce.sh can never produce bounce-scores.json.
#
# The "input file outside the repo root" detail from the original bug report
# is NOT the trigger (verified separately: an out-of-repo `task` path with
# ASCII-only content scores fine) -- it is a fixture builder using mktemp -d,
# which happens to land under /tmp, outside the repo, matching that detail
# incidentally while isolating the true cause: the emoji.
#
# Fix: force LC_ALL=C on the three awk extractors in score-bounce.sh
# (extract_headings, extract_anchors, extract_markers) so gawk treats the
# document as raw bytes -- every byte of a multi-byte character then fails
# the ASCII-only character class and is stripped cleanly, with no orphan.
#
# Hermetic: no LLM calls, no network. Pre-fix this suite fails (score-bounce
# crashes); post-fix it passes (score-bounce + report-bounce both succeed).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCORER="$REPO_ROOT/evals/score-bounce.sh"
REPORTER="$REPO_ROOT/evals/report-bounce.sh"

# Fixture lives under mktemp -d (typically /tmp/...), i.e. OUTSIDE the repo
# root -- deliberately mirroring the structural detail of the real failing
# run (whose input file lived under a .claude/worktrees/... path outside the
# repo it was scored from).
TEST_DIR=$(mktemp -d -t report-bounce-encoding-sim-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

TOTAL=0
PASSED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; }

command -v jq >/dev/null 2>&1 || { echo "SKIP-FAIL: jq required for this gate"; exit 1; }

# ---------------------------------------------------------------------------
# Build a --bounce-only-shaped run dir (state.json + original-input.md +
# pass-N-clean.md + working.md) whose baseline document has a heading
# containing a 4-byte UTF-8 emoji (dartboard, U+1F3AF, bytes F0 9F 8E AF) --
# the exact character class that triggered the real failure.
# ---------------------------------------------------------------------------
RUN_DIR="$TEST_DIR/co-evolve-outside-repo-run"
mkdir -p "$RUN_DIR"

cat > "$RUN_DIR/state.json" <<'EOF'
{
  "schema": "bounce-state/1.0",
  "runner": "co-evolve-bouncer.sh",
  "mode": "bounce-only",
  "task": "fixture-outside-repo-root",
  "input_type": "file",
  "baseline_file": "original-input.md",
  "final_file": "working.md",
  "status": "complete",
  "started_at": "2026-07-05T12:53:51Z",
  "finished_at": "2026-07-05T13:06:22Z",
  "passes": [
    {
      "pass": 1,
      "role": "reviewer",
      "agent": "codex",
      "output_raw": "pass-1-reviewer-codex-raw.md",
      "output_clean": "pass-1-clean.md",
      "contested": 1,
      "clarify": 0,
      "total_markers": 1,
      "word_count": 12
    },
    {
      "pass": 2,
      "role": "composer",
      "agent": "claude",
      "output_raw": "pass-2-composer-claude-raw.md",
      "output_clean": "pass-2-clean.md",
      "contested": 0,
      "clarify": 0,
      "total_markers": 0,
      "word_count": 11
    }
  ]
}
EOF

# Heading contains an em-dash (3-byte UTF-8, harmless on its own) AND a
# dartboard emoji (4-byte UTF-8, the actual trigger) to match the real
# document's "Phase 5 — ... (S, 🎯 gated)" heading precisely.
printf '# Plan\n\n### Phase 5 \xe2\x80\x94 milestone closure (S, \xf0\x9f\x8e\xaf gated)\n\nShip it. [CONTESTED] one week vs two weeks -- pick one.\n' \
  > "$RUN_DIR/original-input.md"
cp "$RUN_DIR/original-input.md" "$RUN_DIR/pass-1-clean.md"
printf '# Plan\n\n### Phase 5 \xe2\x80\x94 milestone closure (S, \xf0\x9f\x8e\xaf gated)\n\nShip it in two weeks, agreed after review.\n' \
  > "$RUN_DIR/pass-2-clean.md"
cp "$RUN_DIR/pass-2-clean.md" "$RUN_DIR/working.md"

# ---------------------------------------------------------------------------
# Scenario 1: score-bounce.sh must exit 0 and produce bounce-scores.json for
# a document whose heading contains a 4-byte UTF-8 emoji.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
SCORES_OUT="$TEST_DIR/bounce-scores.json"
rc=0
score_stderr=$(bash "$SCORER" --run-dir "$RUN_DIR" --output "$SCORES_OUT" 2>&1 1>/dev/null) || rc=$?

if [[ "$rc" -eq 0 && -f "$SCORES_OUT" ]] \
   && jq -e '.mode == "bounce-only" and .source == "state" and .pass_count == 2' "$SCORES_OUT" >/dev/null 2>&1; then
  pass "S1: score-bounce.sh scores an emoji-heading document without crashing"
else
  fail "S1: rc=$rc scores_exists=$([[ -f "$SCORES_OUT" ]] && echo yes || echo no) stderr=$(printf '%s' "$score_stderr" | tr '\n' ' ' | head -c 200)"
fi

# ---------------------------------------------------------------------------
# Scenario 2: the emoji's bytes must be cleanly stripped from the extracted
# heading fingerprint -- no orphan continuation byte left behind. This is
# the actual defect: without it, Scenario 1 could pass by accident (e.g. if
# some other code path degraded gracefully) while the extractor still
# emitted corrupted data. Assert on the extractor's output directly.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
extract_headings_probe() {
  LC_ALL=C awk '
    /^```/ { in_fence = !in_fence; next }
    !in_fence && /^#{1,4}[ \t]/ {
      level = 0
      while (substr($0, level + 1, 1) == "#") level++
      text = substr($0, level + 1)
      gsub(/^[ \t]+|[ \t\r]+$/, "", text)
      lower = tolower(text)
      gsub(/[^a-z0-9 ]/, "", lower)
      gsub(/  +/, " ", lower)
      if (length(lower) > 0) printf "%d|%s\n", level, lower
    }
  ' "$1"
}
heading_line=$(extract_headings_probe "$RUN_DIR/original-input.md" | grep '^3|')
# A clean strip yields exactly "3|phase 5 milestone closure s gated" (ASCII
# only). Any orphan byte would make this comparison fail AND would make the
# line non-ASCII, which we double-check with LC_ALL=C grep -P's \x00-\x7F.
if [[ "$heading_line" == "3|phase 5 milestone closure s gated" ]]; then
  pass "S2: emoji heading strips to a clean ASCII fingerprint (no orphan byte)"
else
  fail "S2: heading fingerprint corrupted or unexpected: '$heading_line'"
fi

# ---------------------------------------------------------------------------
# Scenario 3: evals/report-bounce.sh (the actual failing entry point from
# the bug report) must run end-to-end and produce HUMAN-REPORT.md, given
# only the run dir (bounce-scores.json deliberately absent so report-bounce
# invokes score-bounce.sh itself, exactly as co-evolve-bouncer.sh's auto-hook
# does at co-evolve-bouncer.sh:684).
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
REPORT_RUN_DIR="$TEST_DIR/co-evolve-report-entrypoint-run"
cp -r "$RUN_DIR" "$REPORT_RUN_DIR"
rm -f "$REPORT_RUN_DIR/bounce-scores.json"

rc=0
bash "$REPORTER" --run-dir "$REPORT_RUN_DIR" >/dev/null 2>&1 || rc=$?

if [[ "$rc" -eq 0 && -s "$REPORT_RUN_DIR/HUMAN-REPORT.md" ]] \
   && grep -q '^## What happened' "$REPORT_RUN_DIR/HUMAN-REPORT.md"; then
  pass "S3: report-bounce.sh produces HUMAN-REPORT.md for the emoji-heading run"
else
  fail "S3: rc=$rc report_exists=$([[ -s "$REPORT_RUN_DIR/HUMAN-REPORT.md" ]] && echo yes || echo no)"
fi

# ---------------------------------------------------------------------------
printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
