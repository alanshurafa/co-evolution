---
phase: 08-pr-emitter-scoring
fixed_at: 2026-04-18T00:00:00Z
review_path: .planning/phases/08-pr-emitter-scoring/08-REVIEW.md
iteration: 1
findings_in_scope: 15
fixed: 15
skipped: 0
status: all_fixed
---

# Phase 8: Code Review Fix Report

**Fixed at:** 2026-04-18T00:00:00Z
**Source review:** .planning/phases/08-pr-emitter-scoring/08-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 15 (1 critical + 8 warnings + 6 info)
- Fixed: 15
- Skipped: 0

**Regression gates:**
- `tests/pr-emitter-simulation.sh`: 10/10 passed after every commit
- `tests/code-proposer-simulation.sh`: 16/16 passed at final (Phase 7 unchanged)
- Byte-parity SC-5 (Scenario I): stable — `co-evolve-bouncer.sh --help` carries all v1.1 + Phase 8 flags, no PEL leaks in stderr

**Note on commit count:** 14 commits for 15 findings. CR-01 and WR-03 were fixed in the same commit because they touch adjacent lines in the policy-tier mutation apply loop (the defense-in-depth enumeration + process-substitution rewrite are one refactor of that block). All other findings received individual atomic commits.

## Fixed Issues

### CR-01 + WR-03: Policy-tier yq interpolation defense + no-swallow loop

**Files modified:** `lab/pel/pr-emitter/pr-emitter.sh`
**Commit:** 3896d2b
**Applied fix:** Replaced the pipe-fed `while read` loop (which ran in a subshell, swallowing `yq -i` failures) with process substitution so failures propagate via `die`. Added a `case` statement re-asserting the 6-knob enumeration (retry_cap|marker_semantics|writable_phase_default|arbitrate_threshold|max_passes|flavor_weights) at the emitter trust boundary per CLAUDE.md "validate inputs at system boundaries." Added a `[[ =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]` belt-and-braces check on the key. Switched the string-value path from shell-interpolated `".$key = \"$new_val\""` to yq's safe-interpolation idiom `VAL="$new_val" yq -i ".$key = strenv(VAL)"` so the value can't break out of quoting. Both numeric and string paths now fail explicitly via `die "yq mutation failed for key=..." 3`.

### WR-04: [CANARY-FAILED] empty-branch PR rejection

**Files modified:** `lab/pel/pr-emitter/pr-emitter.sh`
**Commit:** fff1db1
**Applied fix:** Added an `else` branch after the normal `commit` block that creates an empty diagnostic commit (`git commit --allow-empty`) when `CANARY_FAILED_MODE=true`. GitHub otherwise rejects PRs with "No commits between master and pel/..." when head and base share HEAD. The substantive diff still lives in the PR body — the empty commit just gives `gh pr create` a valid head to point at.

### WR-01: `--yes` flag parsed but never consumed

**Files modified:** `lab/pel/pr-emitter/pr-emitter.sh`
**Commit:** 2362726
**Applied fix:** Added a `TODO(v1.3)` annotation above the `AUTO_YES=false` default explaining that the interactive preflight cost-estimate prompt is deferred. The flag stays plumbed through dev-review and co-evolve-bouncer so the v1.2 public surface remains stable; wiring the prompt is an explicit v1.3 task. Removing the flag would break the documented v1.2 surface already shipped in earlier commits.

### WR-02: `find -printf` macOS portability

**Files modified:** `lab/pel/pr-emitter/pr-emitter.sh`
**Commit:** 8f73017
**Applied fix:** Wrapped the default-report discovery in `if find --version 2>/dev/null | grep -q GNU` — matching the detection pattern already used in `lib/co-evolution.sh:list_available_lab_modes`. GNU path uses `-printf '%T@ %p\n'`; BSD fallback iterates with `stat -f %m` (BSD) or `stat -c %Y` (GNU) for hybrid environments.

### WR-05: PR body fenced-diff escape

**Files modified:** `lab/pel/pr-emitter/pr-emitter.sh`, `lab/pel/pr-emitter/pr-body-template.md`
**Commit:** 8b34adf
**Applied fix:** Replaced the hard-coded triple-backtick fences in the template with `{{fence}}` placeholders (open and close). `render_pr_body` now scans `$rendered_diff` for the longest run of consecutive backticks, uses `max(3, run+1)` backticks for the fence, and substitutes via bash parameter expansion. Default case (no backticks in diff) stays at 3 backticks so Scenario A's `grep -qF '` + triple-backtick + `diff'` still passes.

### WR-06: Dry-run branch-ref pollution

**Files modified:** `lab/pel/pr-emitter/pr-emitter.sh`
**Commit:** 078d366
**Applied fix:** Added a `BRANCH_CREATED=""` state variable that is set to `$PR_BRANCH` immediately after the `git checkout -b` succeeds. Extended `emitter_cleanup_all` to `git branch -D $BRANCH_CREATED` when `CO_EVOLVE_DRY_RUN=1` — real runs keep the branch so `gh pr create` has something to point at, dry-runs delete it.

### WR-07: Cache `scripts_hash` misses non-`.sh` deps

**Files modified:** `lab/pel/pr-emitter/pr-emitter.sh`, `tests/pr-emitter-simulation.sh`
**Commit:** 43f8ef3
**Applied fix:** Broadened the `find` inputs from `-name '*.sh'` to `\( -name '*.sh' -o -name '*.yaml' -o -name '*.json' -o -name '*.md' \)` and `-maxdepth` from 2 to 3 so the cache key covers `evals/cases/*.yaml`, `evals/fixtures/*.json|*.md`, and any deeper scorer artifacts. Updated `compute_emitter_cache_key` in the simulation to stay byte-identical with the emitter's production version.

### WR-08: `diff_lines` non-integer breaks `-eq` under `set -e`

**Files modified:** `lab/pel/pr-emitter/pr-emitter.sh`
**Commit:** 601e673
**Applied fix:** Split `diff_lines=$(jq ... || echo 0)` into a `_raw` capture + `[[ =~ ^[0-9]+$ ]]` regex check. Non-integer values (including the literal string `null`) fall back to 0 deterministically. Same treatment for `diff_budget`.

### IN-01: Tier-glob docs mismatch

**Files modified:** `lab/pel/README.md`
**Commit:** 2fb32bc
**Applied fix:** Changed the README's tier-rule-table entry from `tests/fixtures/templates/**.md` to `tests/fixtures/templates/*.md` to match the actual bash `case` one-level behavior. Recursive glob would have required `shopt -s globstar` and carried scope risk — documenting the one-level behavior is the safer path.

### IN-02: `pr_url` captures gh stderr via `2>&1`

**Files modified:** `lab/pel/pr-emitter/pr-emitter.sh`
**Commit:** 2e7b2f7
**Applied fix:** Replaced the single `pr_url=$(gh ... 2>&1)` capture with a temp-file routing: gh stderr → `$gh_stderr`, stdout → `pr_url`. On success, `cat "$gh_stderr" >&2` forwards it to our stderr (preserving DRY-RUN markers and any warnings); on failure, `head -c 500` caps the forward and then `die`. `pr_url=$(printf '%s' "$pr_url" | head -n1)` trims to the first line defensively. Scenario D (`grep 'DRY-RUN: gh'`) continues to pass because stderr is still forwarded.

### IN-03: `find -newer` 1-second filesystem race

**Files modified:** `lab/pel/pr-emitter/pr-emitter.sh`
**Commit:** 9ad6f71
**Applied fix:** Created a separate `marker` file alongside `tmp_out` and aged it by 1 second via `touch -d '1 second ago'` (GNU) or `touch -t $(date -v-1S ...)` (BSD) before invoking the scorer. The scorer's stdout still goes to `$tmp_out` (for error diagnosis); the marker is the `-newer` reference, so any `raw-scores.json` produced in the same second as the scorer start is now unambiguously newer.

### IN-04: `normalize_path_for_bash` unused in lab dispatch

**Files modified:** `co-evolve-bouncer.sh`, `dev-review/codex/dev-review.sh`
**Commit:** de734c2
**Applied fix:** Chose option (b) from the review. Updated `--target FILE` help text in both entry points to document "repo-relative forward-slash path, e.g. lib/co-evolution.sh" matching the allowlist.txt format invariant. Added an inline comment in `dev-review.sh`'s pel-proposer dispatch block explaining the path-format contract so future WSL users don't wonder why their `C:\...` path fails.

### IN-05: `rationale_subject` byte-based truncation

**Files modified:** `lab/pel/pr-emitter/pr-emitter.sh`
**Commit:** 5b33a4b
**Applied fix:** Swapped `head -c 50` (byte-based, can mid-cut UTF-8) for `cut -c1-50` (character-based). Reordered the pipeline so newline/whitespace collapse (`tr '\n' ' ' | sed 's/  */ /g'`) runs before `cut` so the character count operates on a single-line stream.

### IN-06: `canary_failed_at` jq fallback comment

**Files modified:** `lab/pel/pr-emitter/pr-emitter.sh`
**Commit:** 1555190
**Applied fix:** Added an explanatory comment above the `canary_failed_at=$(jq -r '.canary.failed_at // "none"' ...)` line noting that (a) jq's `//` applies on `null|false`, so accepted state.json returns "none", and (b) `$canary_failed_at` is only read when `$canary_passed != "true"` so the "none" vs "null" literal difference is never user-visible. Zero behavioral change — comment-only per the review's "Fix (optional)".

---

_Fixed: 2026-04-18T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
