#!/usr/bin/env bash
# tests/review-verdict-schema-simulation.sh
# Hermetic gate for review-verdict.json: shape drift (F-2) + size caps (Phase 2, A-7).
#
# THREE copies exist, in TWO deliberate groups:
#   - FROZEN PAIR consumed by the PowerShell runner: schemas/ and
#     runners/codex-ps/schemas/. These stay byte-for-byte in lockstep with each
#     other (runners/codex-ps/ is change-forbidden), at the loose F-2 shape.
#   - LIVE runtime copy consumed by the Bash runner (`codex exec --output-schema`):
#     skills/dev-review/schemas/. This is where the Phase 2 token-discipline size
#     caps (maxItems/maxLength) live, so it is a STRICT SUPERSET of the frozen pair.
#
# This gate:
#   1. fails if the frozen pair drifts apart, or if the runtime copy stops being a
#      superset of it, or if the runtime caps go missing (structural checks via jq);
#   2. pins validate_review_verdict's loose contract with positive + negative
#      fixtures, INCLUDING the Phase 2 caps (oversized verdict rejected via the
#      invalid-verdict path; a compliant one passes) in both the jq and jq-less
#      branches;
#   3. asserts the verifier prompt templates and the composer prompt carry the
#      matching human-readable output contract (backstop for the schema caps).
#
# Requires jq (a declared project dependency).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/lib/co-evolution.sh"

S1="$REPO_ROOT/schemas/review-verdict.json"
S2="$REPO_ROOT/runners/codex-ps/schemas/review-verdict.json"
S3="$REPO_ROOT/skills/dev-review/schemas/review-verdict.json"

TEST_DIR="$(mktemp -d -t review-verdict-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
FAILURES=0
pass() { printf "PASS: %s\n" "$1"; }
fail() { printf "FAIL: %s\n" "$1" >&2; FAILURES=$((FAILURES + 1)); }

# --- Scenario 1a: frozen PS-runner pair stays byte-identical to each other ---
# schemas/ and runners/codex-ps/schemas/ are both consumed by the PowerShell
# runner and must not drift apart. runners/codex-ps/ is change-forbidden, so the
# root copy is pinned to it (loose F-2 shape, no caps).
TOTAL=$((TOTAL + 1))
if diff <(jq -S . "$S1") <(jq -S . "$S2") >/dev/null 2>&1; then
  pass "frozen PS-runner pair (schemas/ == runners/codex-ps/schemas/) is structurally identical"
else
  fail "frozen PS-runner pair drifted (schemas/ != runners/codex-ps/schemas/) — re-pin schemas/ to the frozen codex-ps copy"
fi

# --- Scenario 1b: live runtime copy is a STRICT SUPERSET of the frozen shape ---
# Every property the frozen pair defines must still exist in the runtime copy
# (same required[] and same property names), so the caps are additive, not a
# reshape. Compared by the set of top-level + per-issue property names + required[].
TOTAL=$((TOTAL + 1))
frozen_shape=$(jq -S '{req: .required, props: (.properties | keys), issue_props: (.properties.issues.items.properties | keys), issue_req: .properties.issues.items.required}' "$S1")
runtime_shape=$(jq -S '{req: .required, props: (.properties | keys), issue_props: (.properties.issues.items.properties | keys), issue_req: .properties.issues.items.required}' "$S3")
if [[ "$frozen_shape" == "$runtime_shape" ]]; then
  pass "runtime copy (skills/dev-review/) keeps the frozen shape (same fields + required[]) — caps are additive"
else
  fail "runtime copy reshaped the verdict (fields/required drift from the frozen pair), not just added caps"
fi

# --- Scenario 1c: the runtime copy actually carries the Phase 2 size caps ---
# If someone reverts the caps the schema half of the contract is gone, so pin them.
TOTAL=$((TOTAL + 1))
if jq -e '
     .properties.issues.maxItems == 5
     and .properties.summary.maxLength == 320
     and .properties.iteration_notes.maxLength == 600
     and .properties.issues.items.properties.file.maxLength == 240
     and .properties.issues.items.properties.line_range.maxLength == 240
     and .properties.issues.items.properties.description.maxLength == 240
     and .properties.issues.items.properties.suggestion.maxLength == 240
   ' "$S3" >/dev/null 2>&1; then
  pass "runtime copy carries the Phase 2 caps (issues.maxItems=5; summary/notes/issue-field maxLength)"
else
  fail "runtime copy is missing one or more Phase 2 size caps (maxItems/maxLength)"
fi

# --- Scenario 1d: the frozen pair must NOT grow caps (it feeds the frozen PS runner) ---
TOTAL=$((TOTAL + 1))
if jq -e 'any(.. | objects; has("maxItems") or has("maxLength")) | not' "$S1" >/dev/null 2>&1; then
  pass "frozen copy (schemas/) stays cap-free (loose F-2 shape for the PS runner)"
else
  fail "frozen copy (schemas/) unexpectedly grew a cap keyword — it must stay the loose F-2 shape"
fi

# Source the library to exercise the real validator.
# shellcheck disable=SC1090
source "$LIB" >/dev/null 2>&1

write_fixture() { local p="$TEST_DIR/$1.json"; printf '%s' "$2" > "$p"; printf '%s' "$p"; }

check_valid() {   # $1 desc, $2 json
  TOTAL=$((TOTAL + 1))
  local f; f="$(write_fixture "fx$TOTAL" "$2")"
  if validate_review_verdict "$f" >/dev/null 2>&1; then pass "$1"; else fail "$1 (expected accept, got reject)"; fi
}
check_invalid() { # $1 desc, $2 json
  TOTAL=$((TOTAL + 1))
  local f; f="$(write_fixture "fx$TOTAL" "$2")"
  if validate_review_verdict "$f" >/dev/null 2>&1; then fail "$1 (expected reject, got accept)"; else pass "$1"; fi
}

# --- Scenarios 2-3: validator accepts LOOSE verdicts (no strict-only fields) ---
check_valid "validator accepts a minimal APPROVED verdict (no file/line_range/suggestion)" \
  '{"verdict":"APPROVED","confidence":90,"summary":"looks good","issues":[]}'
check_valid "validator accepts REVISE with a loose issue (severity+description only)" \
  '{"verdict":"REVISE","confidence":60,"summary":"needs work","issues":[{"severity":"HIGH","description":"a real bug"}]}'

# --- Scenarios 4-5: validator rejects malformed verdicts ---
check_invalid "validator rejects a verdict missing the issues field" \
  '{"verdict":"APPROVED","confidence":90,"summary":"looks good"}'
check_invalid "validator rejects an unsupported verdict enum value" \
  '{"verdict":"MAYBE","confidence":90,"summary":"looks good","issues":[]}'

# ===========================================================================
# Phase 2 (A-7): size-cap enforcement in validate_review_verdict. An oversized
# verdict must take the SAME invalid-verdict path as a malformed one (the runner
# then logs "verifier output was unusable" and returns 2). Fixtures are built with
# jq so the counts/lengths are exact.
# ===========================================================================

# Build a REVISE verdict with N HIGH issues (each issue otherwise valid).
verdict_with_n_issues() { # $1 = n
  jq -cn --argjson n "$1" '
    {verdict:"REVISE", confidence:60, summary:"needs work",
     issues:[range(0;$n) | {severity:"HIGH", file:("f"+(.|tostring)+".py"),
                            line_range:"1-2", description:"a bug", suggestion:"fix it"}],
     scope_creep_detected:false, iteration_notes:"do the fixes"}'
}
# Build an APPROVED verdict whose summary is `len` characters long.
verdict_with_summary_len() { # $1 = len
  jq -cn --arg s "$(printf 'x%.0s' $(seq 1 "$1"))" \
    '{verdict:"APPROVED", confidence:90, summary:$s, issues:[],
      scope_creep_detected:false, iteration_notes:"ok"}'
}
# Build a REVISE verdict whose single issue.description is `len` characters long.
verdict_with_desc_len() { # $1 = len
  jq -cn --arg d "$(printf 'x%.0s' $(seq 1 "$1"))" \
    '{verdict:"REVISE", confidence:60, summary:"needs work",
      issues:[{severity:"HIGH", file:"a.py", line_range:"1-2", description:$d, suggestion:"fix"}],
      scope_creep_detected:false, iteration_notes:"fix it"}'
}
# Build a REVISE verdict whose iteration_notes is `len` characters long.
verdict_with_notes_len() { # $1 = len
  jq -cn --arg n "$(printf 'x%.0s' $(seq 1 "$1"))" \
    '{verdict:"REVISE", confidence:60, summary:"needs work",
      issues:[{severity:"HIGH", file:"a.py", line_range:"1-2", description:"bug", suggestion:"fix"}],
      scope_creep_detected:false, iteration_notes:$n}'
}

# Cap boundaries + violations (jq branch).
check_valid   "validator accepts exactly 5 issues (maxItems boundary)"       "$(verdict_with_n_issues 5)"
check_invalid "validator rejects 6 issues (over maxItems=5)"                 "$(verdict_with_n_issues 6)"
check_valid   "validator accepts a 320-char summary (maxLength boundary)"    "$(verdict_with_summary_len 320)"
check_invalid "validator rejects a 321-char summary (over maxLength=320)"    "$(verdict_with_summary_len 321)"
check_invalid "validator rejects a 300-char issue.description (over 240)"    "$(verdict_with_desc_len 300)"
check_invalid "validator rejects a 700-char iteration_notes (over 600)"      "$(verdict_with_notes_len 700)"

# ===========================================================================
# Phase 2: the SAME caps must hold in the jq-less fallback branch. Force it by
# shadowing `command` so `command -v jq` reports absent (coreutils stay intact).
# check_valid/check_invalid above use the live jq branch; these re-check the two
# load-bearing caps (issue count + summary length) through the fallback code.
# ===========================================================================
fallback_verdict_check() { # $1 desc, $2 expect(accept|reject), $3 json
  TOTAL=$((TOTAL + 1))
  local f; f="$(write_fixture "fbfx$TOTAL" "$3")"
  local got
  if ( command() { if [[ "$1" == "-v" && "$2" == "jq" ]]; then return 1; fi; builtin command "$@"; }
       validate_review_verdict "$f" >/dev/null 2>&1 ); then got="accept"; else got="reject"; fi
  if [[ "$got" == "$2" ]]; then pass "$1"; else fail "$1 (expected $2, got $got)"; fi
}
fallback_verdict_check "fallback: accepts a compliant 1-issue verdict"       accept "$(verdict_with_n_issues 1)"
fallback_verdict_check "fallback: rejects 6 issues (over maxItems=5)"        reject "$(verdict_with_n_issues 6)"
fallback_verdict_check "fallback: rejects a 321-char summary (over 320)"     reject "$(verdict_with_summary_len 321)"

# ===========================================================================
# Phase 2: the human-readable output contract must reach the assembled verifier
# prompt (backstop for the schema caps). Extract build_review_prompt from the
# runner (sed range + source; same bash-3.2-safe idiom as preset-expansion's
# alias extraction), give it the deps it needs (fill_template from LIB is already
# sourced; REPO_ROOT + TASK), and assert the rendered prompt carries the caps.
# ===========================================================================
RUNNER="$REPO_ROOT/dev-review/codex/dev-review.sh"
sed -n '/^build_review_prompt() {/,/^}$/p' "$RUNNER" > "$TEST_DIR/_brp.sh"
# shellcheck disable=SC1090
source "$TEST_DIR/_brp.sh"
TASK="do the thing"

assert_prompt_has() { # $1 desc, $2 verifier(opus|codex), $3 ERE-pattern
  TOTAL=$((TOTAL + 1))
  local rendered
  rendered=$(build_review_prompt "$2" "PLAN BODY" "DIFF BODY" "STAT BODY")
  if printf '%s' "$rendered" | grep -Eiq -- "$3"; then
    pass "$1"
  else
    fail "$1 — pattern not found in assembled $2 verifier prompt: /$3/"
  fi
}
assert_prompt_has "opus verifier prompt states the <=40-word summary cap"   opus  '<= ?40 words'
assert_prompt_has "opus verifier prompt states the <=5-issues cap"          opus  '<= ?5'
assert_prompt_has "opus verifier prompt forbids pasting file contents"      opus  'not paste file contents|no pasted file contents|do not paste'
assert_prompt_has "codex verifier prompt states the <=40-word summary cap"  codex '<= ?40 words'
assert_prompt_has "codex verifier prompt states the <=5-issues cap"         codex '<= ?5'

# The composer prompt is built inline in run_compose_phase; assert the <=120-line
# plan cap text is present in the runner source (the composition point).
TOTAL=$((TOTAL + 1))
if grep -Eq -- 'plan body <= ?120 lines' "$RUNNER"; then
  pass "composer prompt caps the plan body at <=120 lines"
else
  fail "composer prompt is missing the <=120-line plan cap"
fi

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
