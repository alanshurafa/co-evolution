---
phase: 07-code-tier-proposer
reviewed: 2026-04-18T00:00:00Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - lab/pel/README.md
  - lab/pel/proposer/code/adapter.sh
  - lab/pel/proposer/code/allowlist.txt
  - lab/pel/proposer/code/canary.sh
  - lab/pel/proposer/code/prompt.md
  - lab/pel/proposer/code/proposer.sh
  - tests/code-proposer-simulation.sh
  - tests/fixtures/code-feedback/error-handling-gap.json
  - tests/fixtures/code-feedback/lab-routing-edge.json
  - tests/fixtures/code-feedback/phase-timeout-improvement.json
  - tests/fixtures/code-feedback/retry-logic-weakness.json
findings:
  critical: 0
  warning: 5
  info: 5
  total: 10
status: issues_found
---

# Phase 7: Code Review Report

**Reviewed:** 2026-04-18T00:00:00Z
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

Phase 7 ships the code-tier mutation proposer — the most security-sensitive of
the three PEL proposer tiers because mutations target executable shell code.
The implementation demonstrates strong defense-in-depth: D-12 self-containment
is honored (zero imports outside `lab/pel/proposer/code/`), the 5-gate
pre-flight chain validates diffs before any sandbox I/O, `git worktree`
isolation prevents live-checkout contamination, and the canary smoke-test
catches runtime breakage that syntactic gates miss. Trust-boundary handling is
careful — `PEL_FLAVOR` hits a strict case-whitelist, `CODE_PROPOSER_MODEL` is
regex-validated before reaching `claude --model`, `PEL_CODE_TARGET` is
`grep -Fxq`'d against `allowlist.txt` (exact-line match rejecting trailing
slashes / absolute forms / `../` relative paths), and `PEL_CODE_FEEDBACK` is
resolved + REPO_ROOT-containment-checked before any file read.

No critical security issues found. Five warnings surface — most consequential
is a comment-vs-code mismatch in `canary.sh` scenario 4 (the "rc > 10"
tolerance described in a comment is not actually implemented); the others are
robustness/defensive-coding suggestions (JSON escaping in state.json heredocs,
error-message polish when the LLM returns no diff, a benign TOCTOU window on
the sandbox-path mktemp/rmdir/worktree-add sequence). Five info items document
non-blocking polish opportunities.

The code is production-ready for v1.2's lab role. Recommend addressing WR-01
(canary scenario 4 code-vs-comment drift) and WR-02 (state.json JSON escaping)
before Phase 8 consumes this surface.

## Warnings

### WR-01: canary.sh scenario 4 comment contradicts code (rc>10 tolerance not implemented)

**File:** `lab/pel/proposer/code/canary.sh:145-155`
**Issue:** The comment at lines 147-150 states: _"Accept rc==0 (clean plan-only exit) or a small set of input-validation rcs ... Treat rc > 10 or catastrophic rcs (127 = command not found) as canary failures."_ However, the actual check at line 151 only tests `if (( rc == 127 ))`. Any `rc > 10` (e.g., `rc == 20`, which would be a plausible catastrophic exit from a broken dev-review.sh) would be silently accepted as a canary pass. This defeats the purpose of scenario 4 — a mutation that corrupts dev-review.sh's routing logic and causes it to exit with, say, 137 (SIGKILL) would pass the canary.

**Fix:** Decide which posture the canary wants, then make the code match the comment:
```bash
# Either tighten the check to match the comment:
if (( rc == 127 )) || (( rc > 10 )); then
  printf "FAIL\n" >&2
  printf "ERROR: dev-review.sh exited %s inside %s\n" "$rc" "$SANDBOX_PATH" >&2
  exit 4
fi

# Or drop the "rc > 10" language from the comment if the looser posture is
# intentional (current code-behavior: only rc==127 fails; everything else
# is treated as "plan-only validator tripped, runner-routing survived").
```

### WR-02: state.json heredocs interpolate unescaped values into JSON body

**File:** `lab/pel/proposer/code/proposer.sh:355-367` and `lab/pel/proposer/code/proposer.sh:376-388`
**Issue:** Both state.json writes use bash heredocs with direct `$VAR` interpolation for `PEL_CODE_TARGET`, `PEL_FLAVOR`, `SANDBOX_PATH`, `timestamp`, and `failed_scenario`. All are currently validated upstream (allowlist check, case whitelist, mktemp-generated, `date -u` fixed format, internal switch statement) — so no injection exists today. However, the output is not structurally safe against future input changes: a `SANDBOX_PATH` containing a `"` (from a malicious `TMPDIR` like `/tmp/a"b`) or a backslash would produce malformed JSON. Phase 8's PR emitter parses `state.json` — malformed JSON there becomes a downstream crash.

**Fix:** Use `jq` to build the object (already a Phase 6 dependency; would also be added for Phase 7 if not already required):
```bash
jq -n \
  --arg outcome "canary-failed" \
  --argjson exit_code 7 \
  --arg target "$PEL_CODE_TARGET" \
  --arg flavor "$PEL_FLAVOR" \
  --argjson diff_lines "$diff_lines" \
  --argjson diff_budget "$DIFF_BUDGET" \
  --arg failed_at "$failed_scenario" \
  --arg sandbox_path "$SANDBOX_PATH" \
  --arg timestamp "$timestamp" \
  '{outcome: $outcome, exit_code: $exit_code, target: $target, flavor: $flavor,
    diff_lines: $diff_lines, diff_budget: $diff_budget,
    canary: {passed: false, scenarios: 5, failed_at: $failed_at},
    sandbox_path: $sandbox_path, timestamp: $timestamp}' \
  > "$SANDBOX_PATH/state.json"
```

### WR-03: misleading error message when LLM returns no diff (file_targets empty)

**File:** `lab/pel/proposer/code/proposer.sh:216-229`
**Issue:** When `diff_text` contains no `---`/`+++` header lines (LLM returned an empty string, a prose-only response, or garbage), the awk pipeline at line 216-220 produces an empty `file_targets`, and `grep -c '.' || true` at line 222 returns `0`. The single-file gate at line 225 triggers with error "diff touches 0 files; v1.2 requires exactly 1" and exit 4. The exit code is wrong taxonomically — this is NOT a single-file constraint violation, it's "LLM returned no diff at all" which is closer to exit 2 (Opus returned empty/unparseable). The adapter already handles the truly-empty case at adapter.sh:231 with exit 2; what slips through here is "non-empty response but no diff headers" (e.g., Opus emitted prose).

**Fix:** Add a dedicated non-empty-but-no-headers check before the count:
```bash
if [[ -z "$file_targets" ]]; then
  printf "ERROR: Opus response contained no unified-diff headers (--- / +++)\n" >&2
  printf "first 500 bytes of response:\n" >&2
  printf "%s\n" "$diff_text" | head -c 500 >&2
  printf "\n" >&2
  exit 2
fi
```

### WR-04: TOCTOU window on SANDBOX_PATH between rmdir and git worktree add

**File:** `lab/pel/proposer/code/proposer.sh:284-287, 306`
**Issue:** `mktemp -d` creates the directory, `rmdir` removes it, then `git worktree add` re-creates it. On a multi-user system a racing process could create a file at that path in the window, causing `git worktree add` to fail with a confusing error (maps to exit 8, but the diagnostic will blame git). Low probability — `$TMPDIR` is typically user-owned 700 — but a defensive pattern exists:

**Fix:** Use `mktemp -u` (generate name without creating) instead of the create-then-rmdir dance:
```bash
# mktemp -u generates a unique path without creating it, avoiding the
# rmdir window entirely. -u is standard on GNU + BSD mktemp.
SANDBOX_PATH=$(mktemp -u "${TMPDIR:-/tmp}/pel-code-sandbox-XXXXXX")
# (no rmdir needed — path was never created)
```

### WR-05: apply_err tempfile is reused across gates 5+8 without reset; diagnostics may bleed

**File:** `lab/pel/proposer/code/proposer.sh:263, 270, 306, 319`
**Issue:** `apply_err` is created at line 263 and used as the stderr sink for three separate operations: the pre-flight `git apply --check` (line 270), the `git worktree add` (line 306), and the in-sandbox `git apply` (line 319). Each reuse overwrites the previous content (`2>` not `2>>`). If the pre-flight `git apply --check` writes warnings to it (e.g., whitespace warnings silenced by `--whitespace=nowarn` but still captured), and the worktree-add then succeeds silently, a later failure in the sandbox-apply would read an `apply_err` file that had been truncated by the last `2>` — generally fine, but `head -c 500 "$apply_err" >&2` in the error paths assumes the file contents match the failing operation, and that's only true because `2>` truncates. Not a bug today, but fragile: if any of the three operations are ever reordered or refactored to append, diagnostics will bleed across ops.

**Fix:** Either document the truncation dependency explicitly, or use separate tempfiles:
```bash
# Option A (document the contract):
# apply_err is used as a scratch stderr sink; each 2>"$apply_err" truncates
# before write. Do NOT switch to 2>>"$apply_err" without adjusting the
# head -c 500 diagnostics below.

# Option B (separate tempfiles):
precheck_err=$(mktemp -t proposer-code-precheck-err-XXXXXX)
worktree_err=$(mktemp -t proposer-code-worktree-err-XXXXXX)
apply_err=$(mktemp -t proposer-code-apply-err-XXXXXX)
# update cleanup_sandbox to rm all three
```

## Info

### IN-01: adapter.sh lacks its own `set -euo pipefail`

**File:** `lab/pel/proposer/code/adapter.sh:1-251`
**Issue:** The adapter is sourced (not executed), so strict-mode flags set by `proposer.sh` do apply in the sourced scope. But if a future refactor sources `adapter.sh` from a less-strict parent, silent failures could slip through. The sibling `canary.sh` correctly sets its own strict-mode at line 29.
**Fix:** Add a defensive strict-mode enable near the top of `adapter.sh` (no-op when parent already has it):
```bash
# Defensive strict-mode — parent proposer.sh sets this too, but we don't
# rely on parent-scope leakage if this file is ever sourced elsewhere.
set -euo pipefail
```

### IN-02: head -c 500 on stderr sinks may split multi-byte UTF-8 characters

**File:** `lab/pel/proposer/code/proposer.sh:273,309,322` and `lab/pel/proposer/code/adapter.sh:224,232`
**Issue:** `head -c 500` truncates at byte 500, which could land mid-codepoint in UTF-8 output from `git` or `claude`. The resulting partial byte sequence printed to stderr may render as a replacement character or confuse terminal encoding detection. Cosmetic only — never security-sensitive.
**Fix:** Accept as-is (diagnostic truncation is inherently lossy), or switch to `head -c 512 | iconv -f utf-8 -t utf-8//IGNORE` for cleaner truncation.

### IN-03: canary stub claude does not differentiate on argv

**File:** `lab/pel/proposer/code/canary.sh:56-62`
**Issue:** The canary's stub `claude` always emits "canary-stub: claude response" regardless of which flag or prompt it receives. The comment at line 54-55 calls this out intentionally — canary validates _runner survival_, not agent output quality. Acceptable by design. Documenting here for future readers who may be tempted to tighten the stub.
**Fix:** No action required. If Phase 8 ever wants to smoke-test agent-output parsing, add a second stub mode gated by an env var.

### IN-04: simulation script's REAL_GIT discovery relies on hardcoded paths

**File:** `tests/code-proposer-simulation.sh:237`
**Issue:** `REAL_GIT=$(PATH="/usr/bin:/bin:/mingw64/bin:/c/Program Files/Git/cmd" command -v git ...)` hardcodes Windows + Linux path guesses. If git is installed at a non-standard location (e.g., `/opt/git/bin/git` on some Linux distros), the shim falls back to `command -v git` — but at that point PATH may already be polluted by an earlier PATH injection from outer scripts. Works on the three target platforms today; brittle for exotic setups.
**Fix:** No action required for v1.2. If simulation runs flake on contributor machines, pivot to passing git's path in via env:
```bash
REAL_GIT="${REAL_GIT:-$(command -v git)}"
```

### IN-05: TASK_HINT flows to prompt.md via bash parameter expansion (not a bug — documenting the trust boundary)

**File:** `lab/pel/proposer/code/adapter.sh:102` and `lab/pel/proposer/code/prompt.md:86`
**Issue:** `$1` captures the user-supplied task hint and reaches the Opus prompt via `${template//\{TASK_HINT\}/$TASK_HINT}` — string substitution, not shell eval. T-07-01 explicitly documents this as safe because the hint flows as prompt data, never as a shell command. Worth noting that a malicious hint CAN influence the LLM's diff output (prompt injection at the semantic layer), but the 5 pre-flight gates + canary + sandbox form the real defense. The marker comment at proposer.sh:56-61 already documents this; no action needed.
**Fix:** No action required. The architecture correctly treats the LLM output as untrusted bytes and enforces structural gates rather than trying to sanitize the prompt.

---

_Reviewed: 2026-04-18T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
