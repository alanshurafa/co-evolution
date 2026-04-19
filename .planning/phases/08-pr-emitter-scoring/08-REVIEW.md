---
phase: 08-pr-emitter-scoring
reviewed: 2026-04-18T00:00:00Z
depth: standard
files_reviewed: 14
files_reviewed_list:
  - .gitignore
  - co-evolve-bouncer.sh
  - dev-review/codex/dev-review.sh
  - evals/README.md
  - lab/pel-proposer/entry.sh
  - lab/pel/README.md
  - lab/pel/pr-emitter/entry.sh
  - lab/pel/pr-emitter/pr-body-template.md
  - lab/pel/pr-emitter/pr-emitter.sh
  - lab/pel/proposer/code/proposer.sh
  - tests/fixtures/pr-emitter/code-feedback.json
  - tests/fixtures/pr-emitter/policy-feedback.json
  - tests/fixtures/pr-emitter/template-feedback.json
  - tests/pr-emitter-simulation.sh
findings:
  critical: 1
  warning: 8
  info: 6
  total: 15
status: issues_found
---

# Phase 8: Code Review Report

**Reviewed:** 2026-04-18T00:00:00Z
**Depth:** standard
**Files Reviewed:** 14
**Status:** issues_found

## Summary

Phase 8 wires Phases 4-7 into a single `co-evolve --lab pel-proposer --target <file>` command that classifies, proposes, scores, and drafts a GitHub PR. The architecture is sound: argv flags default off to preserve v1.1 byte-parity (SC-5); proposer dispatch is gated on `LAB_MODE=="pel-proposer"`; PR-body rendering uses bash parameter expansion with no eval, mitigating interpolation attacks; a PATH-injected `git` shim snapshots `state.json` before the proposer cleans up its worktree.

One Critical finding: the policy-tier `yq -i` mutation apply path interpolates LLM-emitted `$key` and `$new_val` values into a yq expression without sanitization or defense-in-depth validation. The policy proposer's `bounds.jq` is supposed to constrain these upstream, but the emitter trusts proposer output without re-validating, creating a second-order yq-expression injection vector.

Eight Warnings concern cross-platform portability (GNU-only `find -printf`), dead code (`--yes` parsed but never used), subshell error swallowing in the policy mutation loop, unified-diff fence escape in the PR body markdown, branch-ref pollution on dry-run, and an unresolved canary-failed PR issue (the [CANARY-FAILED] branch has no commit on top of HEAD, which may cause `gh pr create` to reject).

Six Info items cover code smells: tier-glob regex doesn't match the documented `**.md` pattern, `pr_url` captures stderr via `2>&1`, scripts_hash excludes non-`.sh` eval dependencies, and minor consistency issues.

## Critical Issues

### CR-01: Policy-tier yq interpolation trusts LLM-emitted key/value verbatim (defense-in-depth gap)

**File:** `lab/pel/pr-emitter/pr-emitter.sh:456-466`
**Issue:** In the policy-tier mutation apply path, the emitter reads `$key` and `$new_val` from the proposer's JSON output and interpolates them into a yq expression:

```bash
key=$(printf '%s' "$mutation" | jq -r '.key')
new_val=$(printf '%s' "$mutation" | jq -r '.new')
if printf '%s' "$new_val" | jq -e 'type == "number" or type == "boolean"' >/dev/null 2>&1; then
  yq -i ".$key = $new_val" "$policy_sandbox_path"
else
  yq -i ".$key = \"$new_val\"" "$policy_sandbox_path"
fi
```

The emitter does NOT re-validate either field against the frozen 6-knob enumeration or the bounds table documented in `lab/pel/README.md:345-355`. The policy proposer's `bounds.jq` enforces these upstream, but:

1. The emitter is a distinct trust boundary — it reads proposer stdout, which is attacker-controlled in the threat model where a compromised/buggy proposer or prompt-injected LLM returns malformed JSON.
2. A `.key` of `retry_cap) | env(X)` or similar would inject yq expressions. Even if `bounds.jq` intercepted this upstream, the emitter's own defense should not depend on it.
3. For the string path, a `$new_val` containing `"` or `\` breaks out of the quoted yq literal.

This violates the project's "validate inputs at system boundaries" discipline (CLAUDE.md: "Validate inputs at system boundaries. Fail early with clear messages.") — the emitter crosses the boundary from proposer-output to live-file-mutation without re-validating.

**Fix:** Add an allowlist check and value-type sanity check before calling yq:

```bash
printf '%s\n' "$diff_content" | jq -c '.mutations[]' | while IFS= read -r mutation; do
  key=$(printf '%s' "$mutation" | jq -r '.key')
  new_val=$(printf '%s' "$mutation" | jq -r '.new')

  # Defense-in-depth: re-enforce the 6-knob enumeration from policy.yaml.
  case "$key" in
    retry_cap|marker_semantics|writable_phase_default|arbitrate_threshold|max_passes|flavor_weights) ;;
    *) die "policy mutation rejected: key '$key' not in enumerated knob set" 5 ;;
  esac

  # Reject shell/yq metacharacters in key (should be impossible given case-match, but belt).
  [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
    || die "policy mutation rejected: key '$key' contains disallowed characters" 5

  if printf '%s' "$new_val" | jq -e 'type == "number" or type == "boolean"' >/dev/null 2>&1; then
    yq -i ".$key = $new_val" "$policy_sandbox_path" \
      || die "yq mutation failed for key=$key new=$new_val" 3
  else
    # Use yq's env-var indirection to avoid shell-quoting the value into the expression.
    VAL="$new_val" yq -i ".$key = strenv(VAL)" "$policy_sandbox_path" \
      || die "yq mutation failed for key=$key" 3
  fi
done
```

The `strenv(VAL)` pattern (yq v4+) reads the value from a single env var, bypassing shell-string quoting entirely — this is yq's documented safe-interpolation idiom.

## Warnings

### WR-01: `--yes` flag parsed but never consumed

**File:** `lab/pel/pr-emitter/pr-emitter.sh:84, 118-121`
**Issue:** `AUTO_YES` is initialized to `false` and set to `true` when `--yes` is passed, but the variable is never read elsewhere in the file. The help text promises it "skips interactive preflight cost-estimate prompt" but the emitter has no interactive prompt. This is a dead feature / unimplemented contract.

**Fix:** Either implement the preflight cost-estimate prompt (check estimated cost before running evals, `printf 'Estimated cost: $X. Continue? [y/N]: '`; gate on `AUTO_YES` to skip) or remove the flag and its documentation. If deferred to v1.3+, annotate the parser with a `# TODO(v1.3): implement preflight prompt` comment so the dead path is visible.

### WR-02: `find -printf` is GNU-only; macOS fallback missing

**File:** `lab/pel/pr-emitter/pr-emitter.sh:305-306`
**Issue:** The default-report discovery uses GNU `find -printf '%T@ %p\n'`, which BSD `find` on macOS does not support. On macOS the command fails silently (`2>/dev/null`), producing empty output, and the emitter dies with "PEL_EVAL_REPORT env var not set and no default report" even when reports exist. The `list_available_lab_modes` function in `lib/co-evolution.sh:97-104` already follows the `find --version | grep GNU` detection pattern; apply the same here.

**Fix:**
```bash
if find --version 2>/dev/null | grep -q GNU; then
  latest_report=$(find "$REPO_ROOT/evals/reports" -maxdepth 2 -name 'raw-scores.json' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | head -1 | awk '{print $2}')
else
  # BSD find fallback — stat prints mtime separately.
  latest_report=$(find "$REPO_ROOT/evals/reports" -maxdepth 2 -name 'raw-scores.json' 2>/dev/null \
    | while read -r f; do printf '%s %s\n' "$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f")" "$f"; done \
    | sort -nr | head -1 | awk '{print $2}')
fi
```

### WR-03: Policy mutation-apply loop silently swallows `yq -i` failures

**File:** `lab/pel/pr-emitter/pr-emitter.sh:456-466`
**Issue:** The `while IFS= read -r mutation; do ... done` runs in a subshell because it's on the receiving end of a pipe. Under `set -e`, a non-zero exit from `yq -i` inside the subshell does NOT terminate the outer script — the loop silently continues with the next mutation, and the subshell's failure does not propagate. If `yq -i` fails on one mutation (e.g., invalid YAML path syntax, file permission error), the scoring continues against a partially-mutated policy file with no diagnostic.

**Fix:** Use process substitution instead of a pipe to keep the loop in the parent shell, and add explicit error handling:

```bash
while IFS= read -r mutation; do
  key=$(printf '%s' "$mutation" | jq -r '.key')
  new_val=$(printf '%s' "$mutation" | jq -r '.new')
  # ... (defensive checks per CR-01 fix)
  if ! yq -i "..." "$policy_sandbox_path"; then
    die "yq mutation failed for key=$key new=$new_val" 3
  fi
done < <(printf '%s\n' "$diff_content" | jq -c '.mutations[]')
```

This also composes with CR-01's `die` on unknown key.

### WR-04: [CANARY-FAILED] branch has no commit — `gh pr create` will likely reject in production

**File:** `lab/pel/pr-emitter/pr-emitter.sh:607-635`
**Issue:** When `CANARY_FAILED_MODE=true`, Section G creates a fresh sandbox on demand (line 607-612) from HEAD but skips the mutation-apply block. Section J then creates `$PR_BRANCH` via `git checkout -b` (line 626) and the commit block at line 628-635 is gated on `CANARY_FAILED_MODE == false` — so the [CANARY-FAILED] branch points at HEAD with zero new commits. GitHub rejects PRs where head and base have no commit difference ("No commits between master and pel/code/xxxxxxx"). The simulation at `tests/pr-emitter-simulation.sh` uses a stubbed `gh` that always succeeds, so Scenario E passes hermetically but would fail against real `gh pr create` on the diagnostic path.

The phase context prompt notes: "canary-failed sandbox handling (must create on demand when Section G was skipped under set -u)" — this review surfaces the adjacent commit-on-canary-fail bug.

**Fix:** Commit an empty placeholder on the canary-failed branch so GitHub accepts the PR. The state.json + diff already live in the PR body; the commit just needs to exist:

```bash
if [[ "$CANARY_FAILED_MODE" == "true" ]]; then
  # Create a diagnostic-only commit with no files changed, so gh pr create accepts
  # a branch that differs from base. The substantive diff lives in the PR body.
  (
    cd "$EMITTER_SANDBOX"
    "$REAL_GIT" -c user.email=pel@co-evolve -c user.name=pel-emitter \
      commit --allow-empty -m "$PR_TITLE" --no-verify >/dev/null
  ) || die "failed to create diagnostic commit in canary-failed sandbox" 8
elif [[ "$CANARY_FAILED_MODE" == "false" ]]; then
  # existing commit block
fi
```

Or alternatively, include the state.json as a committed artifact (writes a file → genuine diff).

### WR-05: PR body fenced-diff block can be escaped by a `` ``` `` line in the diff content

**File:** `lab/pel/pr-emitter/pr-body-template.md:26-28` and `pr-emitter.sh:577`
**Issue:** The template wraps `{{diff}}` in a triple-backtick fence:

```
```diff
{{diff}}
```
```

Bash parameter expansion replaces `{{diff}}` verbatim, preserving any content including a literal `` ``` `` line. If a proposed diff contains a line with three backticks (possible for template/shell mutations that touch markdown or embed code samples — e.g., a template diff that modifies README text with fenced blocks), the rendered PR body would:
1. Close the `diff` fence early.
2. Render the rest of the "diff" content as live markdown (possibly with HTML for injected `<script>` tags, though GitHub sanitizes HTML).
3. Leave the outer template's closing ` ``` ` as an unterminated fence.

While not a code-execution vector (GitHub's markdown sanitizer is defense-in-depth), this breaks the PR body's visual contract and enables malicious proposers to inject arbitrary markdown into human reviewers' view.

**Fix:** Before rendering, scan the diff for fence lines and use a longer fence if any are present:

```bash
# Compute a fence length longer than any consecutive backtick run in the diff.
max_fence=$(printf '%s' "$diff_content" | grep -oE '`{3,}' | awk '{print length}' | sort -n | tail -1)
: "${max_fence:=2}"
fence=$(printf '%.0s`' $(seq 1 $((max_fence + 1))))
# Swap the template's fence markers for $fence before {{diff}} substitution.
```

Or simpler: sanitize the diff by prefixing any `^```` line with a zero-width space or HTML entity. Document this in the template comment.

### WR-06: Dry-run invocations pollute `refs/heads/pel/<tier>/<short-hash>` branches

**File:** `lab/pel/pr-emitter/pr-emitter.sh:626, 207-217`
**Issue:** The `git checkout -b "$PR_BRANCH"` at line 626 creates a real branch in the shared repo (worktrees share `.git/refs/`). The cleanup trap `emitter_cleanup_all` removes the worktree via `git worktree remove --force` but does NOT delete the branch. Under `--dry-run`, no `gh pr create` actually happens, so the branch is created and orphaned on every dry-run invocation. Over time this creates dozens of stale `pel/<tier>/<hash>` refs.

The simulation at `tests/pr-emitter-simulation.sh:54-57` handles this for `pel/sim-pr-emitter/*` branches explicitly, but real `--dry-run` invocations from users have no such cleanup.

**Fix:** Extend the cleanup trap to delete the created branch on dry-run:

```bash
BRANCH_CREATED=""  # set after successful checkout -b

emitter_cleanup_all() {
  if [[ -n "$EMITTER_SANDBOX" && -d "$EMITTER_SANDBOX" ]]; then
    "${REAL_GIT:-git}" -C "$REPO_ROOT" worktree remove --force "$EMITTER_SANDBOX" 2>/dev/null || true
    rm -rf "$EMITTER_SANDBOX" 2>/dev/null || true
  fi
  # Delete the created branch on dry-run (real runs kept the branch for gh pr create).
  if [[ -n "$BRANCH_CREATED" && "${CO_EVOLVE_DRY_RUN:-}" == "1" ]]; then
    "${REAL_GIT:-git}" -C "$REPO_ROOT" branch -D "$BRANCH_CREATED" 2>/dev/null || true
  fi
  # ... rest unchanged
}
```

Then after line 626: `BRANCH_CREATED="$PR_BRANCH"`.

### WR-07: Cache `scripts_hash` misses non-`.sh` eval dependencies

**File:** `lab/pel/pr-emitter/pr-emitter.sh:485-486`
**Issue:** The cache key's `scripts_hash` component hashes only `*.sh` files under `evals/` (maxdepth 2). But the eval harness also depends on:
- `evals/cases/*.yaml` (case definitions; edits here change scoring)
- `evals/cases/defaults.yaml` (shared thresholds)
- `evals/fixtures/*.md` and `evals/fixtures/*.json` (scorer fixtures)
- `schemas/review-verdict.json` (indirectly via scorer)

If any of these change, the scorer output changes, but `scripts_hash` does not, so the cache returns stale results. This makes cache invalidation incomplete for the documented "rebuilt when fixtures OR `evals/*.sh` change" contract (`evals/README.md:159`).

**Fix:** Broaden the hash inputs to cover the full eval-runtime surface:

```bash
scripts_hash=$(find "$scripts_dir" -maxdepth 3 -type f \
  \( -name '*.sh' -o -name '*.yaml' -o -name '*.json' -o -name '*.md' \) \
  -exec sha1sum {} + 2>/dev/null \
  | sort | sha1sum | awk '{print $1}')
```

Also consider including `$REPO_ROOT/schemas/review-verdict.json` if the scorer reads it.

### WR-08: `diff_lines=$(jq ... || echo 0)` can produce non-integer string that breaks `-eq` under `set -e`

**File:** `lab/pel/pr-emitter/pr-emitter.sh:407-408, 427`
**Issue:**

```bash
diff_lines=$(jq -r '.diff_lines // 0' "$STATE_SNAPSHOT" 2>/dev/null || echo 0)
# ...
if [[ "$diff_lines" -eq 0 ]] && [[ -n "$diff_content" ]]; then
```

`jq -r '.diff_lines // 0'` emits the raw string form of the value. If `diff_lines` is somehow a non-numeric value in `state.json` (e.g., corrupted by disk issues, race with proposer writing partial state), the `|| echo 0` fallback only fires on jq's non-zero exit, not on a non-numeric stdout. The arithmetic `-eq 0` comparison then errors under `set -e`:

```
[[: "null": syntax error: invalid arithmetic operator (error token is "null")
```

**Fix:** Normalize via a shell-level numeric check:

```bash
diff_lines_raw=$(jq -r '.diff_lines // 0' "$STATE_SNAPSHOT" 2>/dev/null || echo 0)
[[ "$diff_lines_raw" =~ ^[0-9]+$ ]] && diff_lines="$diff_lines_raw" || diff_lines=0
```

Apply similarly to `diff_budget` on line 408.

## Info

### IN-01: Documented tier-glob `tests/fixtures/templates/**.md` doesn't match bash case `*.md`

**File:** `lab/pel/pr-emitter/pr-emitter.sh:160` and `lab/pel/README.md:700-706`
**Issue:** The README's auto-detect rule table lists `tests/fixtures/templates/**.md` (recursive glob), but the bash `case` at line 160 uses `tests/fixtures/templates/*.md` (one level only). Bash `case` patterns do not interpret `**` as recursive. A template fixture at `tests/fixtures/templates/subdir/foo.md` would fall through to code-tier allowlist check and hard-error exit 10.

**Fix:** Either match the README's recursive promise by adding `| tests/fixtures/templates/*/*.md | tests/fixtures/templates/**/*.md` (with `shopt -s globstar nullglob` at top of the function), OR update the README to document the actual `*.md` one-level behavior. Current mismatch is a doc bug; flat glob is probably sufficient in practice.

### IN-02: `pr_url` captures stderr via `2>&1`, interleaving warnings with the URL

**File:** `lab/pel/pr-emitter/pr-emitter.sh:644-648`
**Issue:**

```bash
pr_url=$(gh pr create --draft --base master --head "$PR_BRANCH" \
  --title "$PR_TITLE" --body-file "$EMITTER_BODY_FILE" 2>&1) \
  || die "gh pr create failed post-scoring" 9

printf '%s\n' "$pr_url"
```

On gh success, `pr_url` receives the URL on stdout AND any warnings gh emitted to stderr (e.g., auth refresh hints, rate-limit soft warnings). The final `printf '%s\n'` then prints both to the emitter's stdout, violating the "stdout: Draft PR URL on success" contract (`lab/pel/README.md:714`). Downstream parsers expecting a clean URL line may break.

**Fix:** Redirect stderr to a temp file for the `die` path, not into `pr_url`:

```bash
gh_stderr=$(mktemp)
if ! pr_url=$(gh pr create --draft --base master --head "$PR_BRANCH" \
    --title "$PR_TITLE" --body-file "$EMITTER_BODY_FILE" 2>"$gh_stderr"); then
  log_stderr "gh stderr:"
  head -c 500 "$gh_stderr" >&2
  rm -f "$gh_stderr"
  die "gh pr create failed post-scoring" 9
fi
rm -f "$gh_stderr"
# Trim to first line only (defensive against gh emitting trailing whitespace).
pr_url=$(printf '%s' "$pr_url" | head -n1)
printf '%s\n' "$pr_url"
```

### IN-03: `run_scorer_cached` uses `-newer "$tmp_out"` which can race on fast filesystems

**File:** `lab/pel/pr-emitter/pr-emitter.sh:520-525`
**Issue:**

```bash
tmp_out=$(mktemp)
if ! (cd "$worktree_dir" && bash "$REPO_ROOT/evals/run-evals.sh" >"$tmp_out" 2>&1); then
  ...
fi
scores_file=$(find "$worktree_dir/evals/reports" -maxdepth 2 -name raw-scores.json -newer "$tmp_out" 2>/dev/null | head -1)
```

`find -newer "$tmp_out"` compares mtime at 1-second resolution on many filesystems (HFS+, some NTFS mounts). On a fast host, `run-evals.sh` could write `raw-scores.json` in the same second as `tmp_out` was created, and `-newer` may or may not match depending on mtime rounding. The `|| die "scorer did not produce raw-scores.json"` guard then fires falsely.

**Fix:** Record `tmp_out` mtime explicitly before invoking the scorer, or use a deterministic output path via an environment variable the scorer honors. Simplest: touch `tmp_out` AFTER capturing start time, then check `find ... -newer "$tmp_out"`:

```bash
# Option A: force tmp_out older than any scorer output
tmp_out=$(mktemp)
touch -d '1 second ago' "$tmp_out"  # GNU coreutils syntax; fall back per-platform if needed
```

Or bypass `-newer` entirely by asking the scorer to print the path it wrote:

```bash
scores_file=$(cd "$worktree_dir" && bash "$REPO_ROOT/evals/run-evals.sh" --print-output-path)
```

(Requires adding the flag to `run-evals.sh`.)

### IN-04: `normalize_path_for_bash` from dev-review unused in lab dispatch path

**File:** `dev-review/codex/dev-review.sh:1117-1128`
**Issue:** When `LAB_MODE == "pel-proposer"`, the dispatch rebuild copies `$TARGET` verbatim from user input into the argv tail. The normalization helper `normalize_path_for_bash` (used at line 1136 for WORKDIR and PLAN_SOURCE on the non-lab path) does not run. If a user invokes `bash dev-review.sh --lab pel-proposer --target 'C:\Users\alan\repo\lib\co-evolution.sh'` under WSL, the backslash path flows into pr-emitter.sh's `TARGET_ABS="$REPO_ROOT/$TARGET"` and fails `grep -Fxq` against the allowlist (which stores forward-slash repo-relative paths).

This is an ergonomic gap, not a bug — the documented contract is repo-relative forward-slash paths. Worth a comment clarifying the invariant for WSL users.

**Fix:** Either (a) run `normalize_path_for_bash "$TARGET"` before adding to `lab_tail`, or (b) document in the help text that `--target` requires a repo-relative forward-slash path. Option (b) matches the allowlist-format discipline.

### IN-05: `rationale_subject` truncation is byte-based, may mid-cut a UTF-8 character

**File:** `lab/pel/pr-emitter/pr-emitter.sh:617`
**Issue:**

```bash
rationale_subject=$(printf '%s' "$rationale" | head -c 50 | tr '\n' ' ' | sed 's/  */ /g')
```

`head -c 50` cuts at 50 bytes, not 50 characters. If the classifier rationale contains non-ASCII characters (unlikely but possible for localized prompts), the cut can land mid-codepoint, producing a partial UTF-8 sequence that may render as mojibake in the PR title or break `git commit -m` message parsing on some locales.

**Fix:** Use `cut -c` (character-count) instead:

```bash
rationale_subject=$(printf '%s' "$rationale" | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-50)
```

### IN-06: `canary_failed_at` jq fallback to `"none"` differs from accepted-path `"null"`

**File:** `lab/pel/pr-emitter/pr-emitter.sh:411`
**Issue:**

```bash
canary_failed_at=$(jq -r '.canary.failed_at // "none"' "$STATE_SNAPSHOT" 2>/dev/null || echo none)
```

When the proposer writes an accepted state.json, `canary.failed_at` is JSON `null`, which `jq -r` renders as the literal string `null` (not `"none"`). The `//` operator only applies when the left side is `null` OR `false`; for `null`, it would return `"none"`. So the output is actually `"none"` for accepted runs (`null` triggers the fallback) — which is fine. But the subsequent usage at line 415:

```bash
canary_result="FAIL at scenario: $canary_failed_at"
```

only fires when `$canary_passed != "true"`, so `canary_failed_at` is only read on actual failures where it holds a scenario name. The literal "none" vs "null" difference is never user-visible. OK — but the jq expression is confusingly written. Left as-is is fine; a cleanup comment would help future readers.

**Fix (optional):** Add a comment: `# jq's // applies when left is null|false, so accepted runs get "none" here, never displayed (guarded by $canary_passed check at line 412).`

---

_Reviewed: 2026-04-18T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
