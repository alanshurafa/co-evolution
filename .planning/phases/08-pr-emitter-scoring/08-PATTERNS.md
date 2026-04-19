# Phase 8: PR Emitter + Scoring Integration - Pattern Map

**Mapped:** 2026-04-19
**Files analyzed:** 12 new/modified files
**Analogs found:** 12 / 12

All analogs exist in the codebase. Phase 8 is a compositional layer atop Phases 3-7 — every pattern it needs is already established in a sibling Phase inhabitant.

---

## File Classification

### Files to CREATE

| New File | Role | Data Flow | Closest Analog | Match Quality |
|----------|------|-----------|----------------|---------------|
| `lab/pel/pr-emitter/pr-emitter.sh` | orchestrator/controller | pipeline (classify → propose → score → PR) | `lab/pel/proposer/code/proposer.sh` | role + lifecycle + sandbox match (exact) |
| `lab/pel/pr-emitter/pr-body-template.md` | template (no-LLM) | placeholder substitution | `lab/pel/proposer/code/prompt.md` (structural) + `dev-review.sh build_bounce_prompt` (substitution pattern) | partial (new artifact type — template for non-LLM PR body, uses `{{placeholder}}` instead of `{placeholder}`) |
| `tests/pr-emitter-simulation.sh` | simulation gate | hermetic test | `tests/code-proposer-simulation.sh` | exact (16-scenario structure, PATH-injected stubs, final-line gate convention) |
| `VERIFY-SC4.md` | release-gate doc | human-review tracker | (no exact analog; dogfood tracker is new artifact type) | no analog (use RESEARCH.md patterns; closest shape = `.planning/notes/phase-7-simulation-lessons.md` structured-notes format) |
| `tests/fixtures/pr-emitter/*.json` | fixtures | eval-report fixtures | `tests/fixtures/code-feedback/*.json` | exact (Phase 2 scorer JSON shape) |

### Files to MODIFY

| File | Role | Change | Analog for the Change |
|------|------|--------|------------------------|
| `co-evolve-bouncer.sh` | CLI entry | Add 7 flags (`--target`, `--tier`, `--pr-branch`, `--dry-run`, `--budget`, `--yes`, `--flavor`); gate each with default-off behavior | Existing `--lab` parsing arm (lines 93-97) + `--bounces` arg-validation arm (lines 77-81) |
| `dev-review/codex/dev-review.sh` | CLI entry | Same 7 flags (mirrored), preserving argv-position invariant (arms before `--`) | Existing `--lab` arm (lines 1012-1019) — argv invariant documented in STATE.md |
| `lib/co-evolution.sh` | shared helpers | Possibly extend `dispatch_lab_mode` (no change expected per D-07 self-containment); ensure `pel-proposer` mode routes cleanly | Existing `dispatch_lab_mode` (lines 117-132) |
| `.gitignore` | repo config | Add `.co-evolve-cache/` line | (trivial; no analog needed) |
| `lab/pel/README.md` | lab contract doc | Add "PR Emitter (v1.2)" section | Existing "Code-tier proposer (v1.2)" section (lab/pel/README.md:393-646) |
| `evals/README.md` | docs | Brief note on scorer-cache | (trivial; no analog needed) |
| `lab/pel/proposer/code/proposer.sh` | code proposer (DEF-07-01 fix) | Suppress "HEAD is now at..." stdout leak from `git worktree add` | Same file, line 306 — redirect stdout to stderr or `/dev/null` |

---

## Pattern Assignments

### `lab/pel/pr-emitter/pr-emitter.sh` (orchestrator / pipeline)

**Analog:** `lab/pel/proposer/code/proposer.sh` (best match for self-contained lab inhabitant owning a sandbox + exit-code taxonomy + state.json handoff)

**Secondary analogs:**
- `dev-review/codex/dev-review.sh` — multi-phase orchestration (compose → bounce → execute → verify); directly parallels pr-emitter's (classify → propose → score → PR) pipeline
- `agent-bouncer/agent-bouncer.sh` — single-entry-point shape + trap EXIT cleanup + simple per-invocation RUN_DIR

#### Header + strict mode (copy from `lab/pel/proposer/code/proposer.sh` lines 76-85)

```bash
#!/usr/bin/env bash
# lab/pel/pr-emitter/pr-emitter.sh
# ... header doc block (usage, argv, env vars, output, exit codes) ...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# REPO_ROOT ascends: pr-emitter -> pel -> lab -> repo root (3 levels).
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
```

**Note the depth difference:** code proposer ascends 4 levels (`code -> proposer -> pel -> lab -> root`); pr-emitter ascends 3 (`pr-emitter -> pel -> lab -> root`). Verify with a `pwd` check early in the script.

#### Self-containment invariant (D-07 — copy pattern from `lab/pel/proposer/code/proposer.sh` lines 51-54 + 181-186)

```bash
# Self-contained per D-07: NO source/import of lib/co-evolution.sh, classifier,
# or any proposer's internals. Cross-module communication happens via:
#   - documented stdout contracts (proposer diff -> emitter)
#   - filesystem handoffs (proposer state.json -> emitter reads before cleanup)

# The ONLY source statement in this module is sibling-only (if any helper
# extractions happen at plan time). Per D-06, the two-file module is
# pr-emitter.sh + pr-body-template.md — no sibling adapter is required
# because there is NO LLM call.
```

**Key divergence from proposer pattern:** No `source "$SCRIPT_DIR/adapter.sh"` — the emitter has no LLM call. `pr-body-template.md` is a text-substitution template, not a prompt.

#### Tier auto-detect rule table (D-04 — new code; no direct analog)

Closest shape: the allowlist-exact-match pattern from code proposer (`lab/pel/proposer/code/proposer.sh` lines 120-123 + 237-240). Use `grep -Fxq` semantics for the code-tier allowlist case; use bash `case` globs for the template and policy cases:

```bash
# Pattern: Bash case statement with explicit globs (D-04 rule table).
# Fail-closed on ambiguous / no-match / mixed-tier globs (exit 10).
detect_tier() {
  local target="$1"
  case "$target" in
    skills/dev-review/templates/*.md|tests/fixtures/templates/*.md)
      printf 'template' ;;
    lab/pel/proposer/policy/policy.yaml)
      printf 'policy' ;;
    *)
      # Code-tier: exact-line match in allowlist.txt
      if grep -Fxq "$target" "$REPO_ROOT/lab/pel/proposer/code/allowlist.txt"; then
        printf 'code'
      else
        die "tier auto-detect: no rule matches '$target' (D-04 hard-error)" 10
      fi
      ;;
  esac
}
```

**Grep pattern reference:** `lab/pel/proposer/code/proposer.sh:120`
**Case glob reference:** `lab/pel/proposer/template/proposer.sh:161-167`

#### Classifier invocation pattern (copy from `lab/pel/README.md` lines 139-146 — the documented direct-invocation example)

The classifier is a sibling lab inhabitant. Copy this exact pattern, adapted to export required env:

```bash
# Invoke the Phase 4 classifier. Contract is documented at:
#   lab/pel/classifier/classifier.sh (header)
#   lab/pel/README.md §Env-var contract (v1.2)
#
# Emitter sets env explicitly — never inherits from user shell (see
# lab/pel/README.md:27-30 "Never inherit from the user's shell").
export PEL_BOUNCE_STEP="${PEL_BOUNCE_STEP:-unknown}"
export PEL_PHASE_TYPE="${PEL_PHASE_TYPE:-unknown}"
if [[ -n "${FLAVOR_OVERRIDE:-}" ]]; then
  export PEL_FLAVOR_OVERRIDE="$FLAVOR_OVERRIDE"
fi

classifier_json=$(bash "$REPO_ROOT/lab/pel/classifier/classifier.sh" "$TASK_HINT") \
  || die "classifier failed; see stderr" $?

# Parse via jq (classifier output schema from lab/pel/README.md:49-62).
flavor=$(printf '%s' "$classifier_json" | jq -r '.flavor')
rationale=$(printf '%s' "$classifier_json" | jq -r '.rationale')
override_flag=$(printf '%s' "$classifier_json" | jq -r '.override')
```

#### Proposer invocation pattern (copy from `tests/code-proposer-simulation.sh` lines 319-326 — the simulation's env-export-then-bash pattern is the canonical invocation shape)

```bash
# Invoke the tier-appropriate proposer. Env-var contract is the same pattern
# across all three tiers (template/policy/code): export required vars, bash
# the proposer.sh, capture stdout (diff or JSON delta), stderr routes to the
# emitter's own log.
#
# Reference: tests/code-proposer-simulation.sh:319-326 for the exact shape.
rc=0
case "$tier" in
  template)
    export PEL_EVAL_REPORT="$feedback_path"
    export PEL_TEMPLATE_PATH="$target"
    export PEL_FLAVOR="$flavor"
    diff_text=$(bash "$REPO_ROOT/lab/pel/proposer/template/proposer.sh" "$TASK_HINT") \
      || rc=$?
    ;;
  policy)
    export PEL_FEEDBACK="$feedback_path"
    export PEL_POLICY_PATH="$target"
    export PEL_FLAVOR="$flavor"
    delta_json=$(bash "$REPO_ROOT/lab/pel/proposer/policy/proposer.sh" "$TASK_HINT") \
      || rc=$?
    ;;
  code)
    export PEL_CODE_FEEDBACK="$feedback_path"
    export PEL_CODE_TARGET="$target"
    export PEL_FLAVOR="$flavor"
    diff_text=$(bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "$TASK_HINT") \
      || rc=$?
    ;;
esac
```

#### state.json read BEFORE proposer cleanup (D-09 — this is NEW; synthesize from the git-shim pattern at `tests/code-proposer-simulation.sh` lines 229-287)

The simulation's git-shim is the exact precedent. Phase 8 does NOT use a git-shim at runtime — instead, it runs the proposer via `bash -c` that reads `state.json` from `$SANDBOX_PATH` as the LAST ACTION before returning, letting the proposer's trap EXIT handler fire AFTER emitter has captured the state:

**Option A (architectural):** Because the code proposer writes `state.json` BEFORE it emits `printf "%s\n" "$diff_text"` (proposer.sh lines 376-393), and emits diff to stdout AFTER state.json exists on disk — the emitter can:
1. Capture stdout (= diff).
2. Capture proposer exit code.
3. At this point trap EXIT has already fired and removed the worktree.

**Option B (simpler, preferred):** Discover sandbox path via the proposer writing its sandbox path to a pre-agreed file the emitter specifies, OR use the same git-shim approach the simulation uses (lines 229-287 of `tests/code-proposer-simulation.sh`):

```bash
# Install a PATH-shim for `git` that snapshots state.json BEFORE `git worktree
# remove --force` tears the sandbox down. Identical to the simulation pattern
# at tests/code-proposer-simulation.sh:239-287.
REAL_GIT=$(PATH="/usr/bin:/bin:/mingw64/bin:/c/Program Files/Git/cmd" command -v git)
export REAL_GIT STATE_SNAPSHOT="$EMITTER_WORKDIR/proposer-state.json"
cat > "$EMITTER_BIN/git" <<'GITSHIM'
#!/usr/bin/env bash
# Pre-intercept worktree-remove to copy state.json out.
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[i]}" == "worktree" ]] && [[ "${args[i+1]:-}" == "remove" ]]; then
    last_idx=$((${#args[@]} - 1))
    sbox="${args[last_idx]}"
    [[ -f "$sbox/state.json" ]] && cp "$sbox/state.json" "$STATE_SNAPSHOT" 2>/dev/null || true
    break
  fi
done
exec "$REAL_GIT" "$@"
GITSHIM
chmod +x "$EMITTER_BIN/git"
PATH="$EMITTER_BIN:$PATH" bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "$TASK_HINT"
```

**Planning-time decision:** Pick between Option A (emitter cooperates with proposer contract) vs Option B (git-shim at runtime — note that this would introduce a shim to the production runtime which is a posture departure). **Prefer Option A** at plan time; reserve Option B as a simulation-only pattern.

#### Sandbox creation for scoring (D-08 — copy from `lab/pel/proposer/code/proposer.sh` lines 282-312)

```bash
# Phase 8 owns its OWN sandbox — Phase 7 has already cleaned up its sandbox
# by this point. This is a fresh worktree for scoring.
EMITTER_SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/pel-score-sandbox-XXXXXX")
rmdir "$EMITTER_SANDBOX"  # git worktree wants non-existent target

cleanup_emitter_sandbox() {
  git -C "$REPO_ROOT" worktree remove --force "$EMITTER_SANDBOX" 2>/dev/null || true
  rm -rf "$EMITTER_SANDBOX" 2>/dev/null || true
}
trap "cleanup_emitter_sandbox" EXIT

# Create detached-HEAD worktree from current state. Shared .git object store
# makes this near-instant (D-10).
if ! git -C "$REPO_ROOT" worktree add --detach "$EMITTER_SANDBOX" HEAD; then
  die "emitter sandbox setup failed: git worktree add returned non-zero" 8
fi
```

**Reference:** `lab/pel/proposer/code/proposer.sh` lines 282-312 — copy nearly verbatim, changing sandbox-prefix name to `pel-score-sandbox-` and adjusting the die exit code per D-17.

#### Exit-code taxonomy (D-17 — extend Phase 7's taxonomy from `lab/pel/proposer/code/proposer.sh` lines 37-49)

```bash
# Exit codes (D-17 taxonomy — extends Phase 7's 0-8 with 9 and 10):
#   0  success (PR draft created)
#   1  input validation failure (bad --target, bad --tier override)
#   2  classifier or proposer propagated exit 2 (CLI/auth)
#   3  malformed diff propagated from proposer
#   4  multi-file violation propagated from proposer
#   5  allowlist violation propagated from proposer
#   6  EMITTER eval budget exhausted during scoring (distinct from proposer's
#      DIFF_BUDGET exit 6 — log message disambiguates)
#   7  canary-failed PR created as [CANARY-FAILED] diagnostic (D-15;
#      this is exit 0 from the USER perspective — PR was drafted — but exit 7
#      is preserved from Phase 7 when no retry happens)
#   8  sandbox setup failed (either proposer's or emitter's)
#   9  NEW: gh pr create failed post-scoring (D-17)
#  10  NEW: tier auto-detect hard-error — ambiguous, no-match, or mixed-tier
#      glob (D-17)
```

#### PR body composition (copy placeholder-substitution pattern from `lib/co-evolution.sh` lines 726-743 `fill_template()`)

```bash
# {{placeholder}} substitution (D-20). Uses bash parameter expansion — NO
# external tool. Matches the pattern at lib/co-evolution.sh:726-743 but with
# {{ }} delimiters (vs { }) to avoid collision with legitimate `{` in diff
# hunk headers (`@@ -X,Y +A,B @@`).
#
# SECURITY: Diff content is substituted via ${template//\{\{diff\}\}/$diff_content}
# (bash parameter expansion) — NO eval, NO shell re-parsing. This is the same
# defense pattern used in lab/pel/proposer/code/adapter.sh:87-110 compose_prompt.

render_pr_body() {
  local template_path="$1"
  local rendered
  rendered=$(cat "$template_path")
  rendered="${rendered//\{\{tier\}\}/$tier}"
  rendered="${rendered//\{\{target\}\}/$target}"
  rendered="${rendered//\{\{flavor\}\}/$flavor}"
  rendered="${rendered//\{\{classifier_rationale\}\}/$rationale}"
  rendered="${rendered//\{\{diff\}\}/$diff_content}"
  rendered="${rendered//\{\{diff_lines\}\}/$diff_lines}"
  rendered="${rendered//\{\{diff_budget\}\}/$diff_budget}"
  rendered="${rendered//\{\{eval_before\}\}/$eval_before_text}"
  rendered="${rendered//\{\{eval_after\}\}/$eval_after_text}"
  rendered="${rendered//\{\{eval_delta\}\}/$eval_delta_text}"
  rendered="${rendered//\{\{canary_result\}\}/$canary_result}"
  rendered="${rendered//\{\{timestamp\}\}/$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
  rendered="${rendered//\{\{def_07_01_ref\}\}/$def_ref}"
  printf '%s' "$rendered"
}
```

**Reference `fill_template`:** `lib/co-evolution.sh:726-743` (uses `{KEY}` — Phase 8 switches to `{{KEY}}` per D-20 to avoid collision with diff hunk-header braces).
**Reference `compose_prompt` security argument (parameter-expansion, no eval):** `lab/pel/proposer/code/adapter.sh:87-110`.

#### `gh pr create --draft` invocation + `CO_EVOLVE_DRY_RUN` PATH-stub (D-02)

No existing codebase analog for `gh pr create` invocation. Pattern shape mirrors the PATH-injected stub pattern used by canary:

```bash
# D-02: CO_EVOLVE_DRY_RUN=1 + PATH-shadowed gh stub. The wrapper (co-evolve /
# dev-review top-level) sets the env var + prepends a stub bin dir earlier in
# PATH, then runs the normal emitter flow. Proposers don't parse --dry-run;
# they check CO_EVOLVE_DRY_RUN before any external side effect.
#
# Reference for PATH-stub pattern: lab/pel/proposer/code/canary.sh:44-78
# (stub_dir with executable stubs, prepended to PATH).

# In the wrapper:
if [[ "$DRY_RUN" == "true" ]]; then
  export CO_EVOLVE_DRY_RUN=1
  DRY_STUB_BIN=$(mktemp -d -t co-evolve-dry-XXXXXX)
  cat > "$DRY_STUB_BIN/gh" <<'DRYSTUB'
#!/usr/bin/env bash
# PATH-shadowed gh stub for --dry-run.
# Captures argv + stdin to stderr for visibility, exits 0 pretending success.
printf 'DRY-RUN: gh %s\n' "$*" >&2
if [[ ! -t 0 ]]; then cat >&2; fi
# Fake success — print a fake PR URL for the caller to parse.
printf 'https://github.com/REPO/pull/0 (dry-run stub)\n'
DRYSTUB
  chmod +x "$DRY_STUB_BIN/gh"
  export PATH="$DRY_STUB_BIN:$PATH"
fi

# Actual invocation (unchanged across dry-run and real). The stub resolves
# first when DRY_RUN is set; real gh otherwise.
pr_url=$(gh pr create --draft --base master --head "$PR_BRANCH" \
  --title "$PR_TITLE" --body "$PR_BODY" 2>&1) \
  || die "gh pr create failed: $pr_url" 9
```

**SC-3 verification:** Under Git Bash / MINGW64, assert that `$DRY_STUB_BIN/gh` resolves before any system-installed `gh`. Test with `type gh` in the stubbed env.

---

### `lab/pel/pr-emitter/pr-body-template.md` (template, placeholder substitution)

**Analog:** `lab/pel/proposer/code/prompt.md` (structural shape — placeholder slots in Markdown) + the `fill_template` convention (`lib/co-evolution.sh:726-743`).

**Pattern to adopt:** `{{placeholder}}` (double-brace) to avoid collision with Markdown/diff content.

**Illustrative structure:**

```markdown
## PEL Mutation: {{tier}} tier

**Target:** `{{target}}`
**Flavor:** {{flavor}}
**Classifier rationale:** {{classifier_rationale}}

## Eval Delta

| Metric | Before | After | Δ |
|--------|--------|-------|---|
{{eval_delta}}

## Mutation ({{diff_lines}} / {{diff_budget}} lines)

```diff
{{diff}}
```

## Canary

{{canary_result}}

---

Generated by co-evolve --lab pel-proposer at {{timestamp}}
{{def_07_01_ref}}
```

**Security note:** Placeholders with diff-shaped content (`{{diff}}`) are substituted via bash parameter expansion — no eval, no shell re-parsing. Same defense as `lab/pel/proposer/code/adapter.sh:87-110` `compose_prompt`.

---

### `tests/pr-emitter-simulation.sh` (hermetic simulation gate)

**Analog:** `tests/code-proposer-simulation.sh` (exact match — 16-scenario structure, PATH-injected stubs, state.json assertion via git-shim, final-line-gate convention)

#### Simulation harness skeleton (copy from `tests/code-proposer-simulation.sh` lines 1-97)

```bash
#!/usr/bin/env bash
# tests/pr-emitter-simulation.sh
# Phase 8 SC-3: Hermetic simulation of lab/pel/pr-emitter/ behavior.
#
# Scenarios (≥10, target 10/10 final-line gate):
#   A: Happy-path, template tier  — classifier stub + template-proposer
#                                    stub + eval-report fixtures + gh stub;
#                                    PR body must include eval delta + diff
#                                    + rationale.
#   B: Happy-path, policy tier    — same shape; PR body renders JSON delta
#                                    in a fenced json block (not diff block).
#   C: Happy-path, code tier      — classifier + code proposer (with
#                                    canary-passing stub) + gh stub.
#   D: --dry-run wrapper           — CO_EVOLVE_DRY_RUN=1 + PATH-shadowed gh
#                                    stub resolves first; real gh never called.
#   E: Canary-failed PR            — code proposer returns exit 7; PR title
#                                    prefixed [CANARY-FAILED]; body includes
#                                    state.json snapshot.
#   F: Budget exceeded during      — scorer runs exceed $25; emitter exits 6.
#      scoring
#   G: Tier auto-detect            — target path matches no rule -> exit 10.
#      hard-error
#   H: --tier override wins        — target would auto-detect as X, --tier Y
#                                    forces Y.
#   I: Byte-parity (SC-5)          — co-evolve "task" WITHOUT --lab pel-proposer
#                                    produces byte-identical output to v1.1.
#   J: Eval cache hit              — run twice with same diff; second run
#                                    billed $0.00 (cache hit).
#
# Final line: "10/10 scenarios passed" (v1.2 gate convention).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

# TEST_DIR must be INSIDE REPO_ROOT for path containment checks (mirrors
# pattern from tests/code-proposer-simulation.sh:79-82).
TEST_DIR=$(mktemp -d -p "$REPO_ROOT/tests" ".sim-pr-emitter-XXXXXX")
export TEST_DIR

cleanup() {
  # Belt-and-suspenders: clean orphan pel-score-sandbox-* worktrees.
  local orphan
  for orphan in "${TMPDIR:-/tmp}"/pel-score-sandbox-*; do
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
```

#### PATH-injected stubs for `claude`, `codex`, `gh` (copy from `tests/code-proposer-simulation.sh` lines 113-136 for claude; adapt for gh)

```bash
mkdir -p "$TEST_DIR/bin"

# Stub gh — captures argv to marker file, emits fake PR URL.
cat > "$TEST_DIR/bin/gh" <<'GHSTUB'
#!/usr/bin/env bash
# PATH-injected stub for hermetic pr-emitter simulation.
if [[ -n "${GH_STUB_MARKER:-}" ]]; then
  printf 'called: %s\n' "$*" >> "$GH_STUB_MARKER"
fi
# Drain stdin; capture body if --body-file was passed.
if [[ "$*" == *"--body-file"* ]]; then
  # Extract file path after --body-file, copy its contents to marker.
  for (( i=1; i<=$#; i++)); do
    if [[ "${!i}" == "--body-file" ]]; then
      next=$((i+1))
      [[ -n "${GH_BODY_SINK:-}" ]] && cp "${!next}" "$GH_BODY_SINK" || true
    fi
  done
fi
# Fake success.
printf 'https://github.com/test/repo/pull/1\n'
exit 0
GHSTUB
chmod +x "$TEST_DIR/bin/gh"

# Stub claude — echoes canned JSON (classifier) or canned diff (proposer).
# Same shape as tests/code-proposer-simulation.sh:114-136.
# ... (copy pattern) ...
```

#### Scenario asserting PR body content (pattern new; closest analog is the state.json jq-assertion pattern at `tests/code-proposer-simulation.sh` lines 349-358)

```bash
# After the emitter succeeds, assert PR body has the required sections.
# Body was captured to $TEST_DIR/body-A.md by the gh stub.
grep -qE '^## Eval Delta' "$TEST_DIR/body-A.md" \
  || { echo "A: body missing Eval Delta section" >&2; exit 1; }
grep -qF '```diff' "$TEST_DIR/body-A.md" \
  || { echo "A: body missing fenced diff block" >&2; exit 1; }
grep -qF "$flavor" "$TEST_DIR/body-A.md" \
  || { echo "A: body missing flavor identifier" >&2; exit 1; }
```

#### Final summary footer (copy from `tests/code-proposer-simulation.sh` lines 1063-1074)

```bash
passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
```

---

### `co-evolve-bouncer.sh` modifications (7 new flags)

**Analog for each flag:** Existing `--lab` arm (lines 93-97) has the cleanest shape:

```bash
# Pattern from co-evolve-bouncer.sh:93-97 — copy verbatim for each new flag.
--target)
  [[ $# -gt 1 ]] || die "--target requires a value"
  TARGET="$2"
  shift 2
  ;;
--tier)
  [[ $# -gt 1 ]] || die "--tier requires a value"
  case "$2" in
    template|policy|code) TIER="$2" ;;
    *) die "--tier must be template|policy|code (got: $2)" ;;
  esac
  shift 2
  ;;
--pr-branch)
  [[ $# -gt 1 ]] || die "--pr-branch requires a value"
  PR_BRANCH="$2"
  shift 2
  ;;
--dry-run)
  DRY_RUN=true
  shift
  ;;
--budget)
  [[ $# -gt 1 ]] || die "--budget requires a value"
  [[ "$2" =~ ^[0-9]+$ ]] || die "--budget must be a positive integer (got: $2)"
  BUDGET_USD="$2"
  shift 2
  ;;
--yes)
  AUTO_YES=true
  shift
  ;;
--flavor)
  [[ $# -gt 1 ]] || die "--flavor requires a value"
  case "$2" in
    bug-catcher|faster-converger|blind-spot-surfacer|general) FLAVOR_OVERRIDE="$2" ;;
    *) die "--flavor must be one of bug-catcher|faster-converger|blind-spot-surfacer|general (got: $2)" ;;
  esac
  shift 2
  ;;
```

**Default initialization pattern** (match lines 7-24): new variables default off / unset so byte-parity holds:

```bash
# Phase 8 flags — default off / unset so v1.1 invocations remain byte-parity.
TARGET=""
TIER=""
PR_BRANCH=""
DRY_RUN=false
BUDGET_USD="25"
AUTO_YES=false
FLAVOR_OVERRIDE=""
```

**Argv-position invariant** (from STATE.md line 78): Place all new arms BEFORE the `--)` argv-terminator (currently at line 98-102). Phase 8 simulation must assert this via `grep -n | cut` (mirror Phase 3's argv-position test from `tests/lab-routing-simulation.sh`).

---

### `dev-review/codex/dev-review.sh` modifications (mirror the 7 flags)

**Analog:** Exact mirror of the `co-evolve-bouncer.sh` changes. `dev-review.sh:929-1041` is the existing arg-parser; the `--lab` arm at lines 1012-1019 is the template. Same arms, same positions (before `--)` at line 1024).

**Symmetry requirement** (from STATE.md line 79 — "Argv-position invariant pinned by line-number comparison"): both runners must place new arms before `--)` AND in the same relative order. Plan verifier should include a `grep -n | cut` symmetry check.

---

### `lab/pel/proposer/code/proposer.sh` modification (DEF-07-01 fix)

**Analog:** The bug is at line 306:

```bash
if ! git -C "$REPO_ROOT" worktree add --detach "$SANDBOX_PATH" HEAD 2>"$apply_err"; then
```

`git worktree add` emits "HEAD is now at..." to STDOUT (not stderr). Current code redirects only stderr. Fix is one character:

```bash
# Before:
if ! git -C "$REPO_ROOT" worktree add --detach "$SANDBOX_PATH" HEAD 2>"$apply_err"; then
# After:
if ! git -C "$REPO_ROOT" worktree add --detach "$SANDBOX_PATH" HEAD >/dev/null 2>"$apply_err"; then
```

**Reference to leak:** `tests/code-proposer-simulation.sh:332-336` — the simulation already has the comment:
> "Proposer leaks git worktree's 'HEAD is now at...' on stdout (Plan 01 known issue — see 07-02-SUMMARY.md deferred issues); grep for the diff content ignores leading lines."

After the fix, Phase 8 Plan 01 should rerun the Phase 7 16-scenario simulation (expected 16/16 still green — the sim's grep-based matching was lenient; fixing the leak tightens the contract).

---

## Shared Patterns

### Authentication / CLI-availability check

**Source:** `lab/pel/proposer/code/adapter.sh:47-55` `require_claude_cli()` + `lib/co-evolution.sh:154-163` `require_agent_cli`

**Apply to:** Any subprocess that calls `gh`, `claude`, `codex`, `jq`, `yq`.

```bash
# Inline require_tool pattern — copy from lab/pel/proposer/policy/proposer.sh:41-46
require_tools() {
  command -v gh >/dev/null 2>&1 \
    || { echo "ERROR: gh is required. Install: https://cli.github.com" >&2; exit 2; }
  command -v jq >/dev/null 2>&1 \
    || { echo "ERROR: jq is required." >&2; exit 2; }
}
```

### Error handling

**Source:** `lab/pel/proposer/code/adapter.sh:33-42` (`die()` + `log_stderr()` inline per self-containment invariant)

**Apply to:** `pr-emitter.sh` (D-07 self-contained = no `source lib/co-evolution.sh`; inline die).

```bash
die() {
  printf "ERROR: %s\n" "${1:-Fatal error}" >&2
  exit "${2:-1}"
}
log_stderr() {
  printf "%s\n" "$1" >&2
}
```

### Trap EXIT cleanup (defense in depth)

**Source:** `lab/pel/proposer/code/proposer.sh:292-301` (`cleanup_sandbox` with `git worktree remove --force` + `rm -rf`)

**Apply to:** `pr-emitter.sh` — the emitter owns a separate scoring sandbox (D-08). Copy the pattern verbatim, rename function + variable.

### Path sandboxing (T-07-05 mitigation)

**Source:** `lab/pel/proposer/code/proposer.sh:134-159` (`resolve_path()` + REPO_ROOT containment check)

**Apply to:** Any caller-supplied path in `pr-emitter.sh` (`--target`, `--pr-branch` if it becomes a file path, eval-report paths consumed by scoring). Copy the `resolve_path` helper + the `case "$abs" in "$REPO_ROOT"/*) ;; *) die ;; esac` pattern.

### Hermetic simulation via PATH-injected stubs

**Source:** `tests/code-proposer-simulation.sh:113-136` (claude stub) + `lab/pel/proposer/code/canary.sh:44-78` (claude + codex stubs).

**Apply to:** `tests/pr-emitter-simulation.sh` — stub `claude` (classifier + proposers), `codex` (if any proposer calls it), `gh` (PR creation), and optionally `git` (for state.json snapshot via the shim at lines 239-287).

### Final-line simulation gate convention

**Source:** Every phase simulation uses `"N/N scenarios passed"` as final stdout line:
- `tests/code-proposer-simulation.sh:1063-1074` — 16/16
- `tests/policy-proposer-simulation.sh` — 8/8
- `tests/template-proposer-simulation.sh` — 8/8
- `tests/classifier-simulation.sh` — 6/6

**Apply to:** `tests/pr-emitter-simulation.sh` — target `10/10 scenarios passed` (CONTEXT.md D-14 says "≥5" but illustrative scenario list expands to 10; plan at planning time).

### Env-var "never inherit from user shell" discipline

**Source:** `lab/pel/README.md:27-30` + proposer pattern at `proposer.sh:195-202` (explicit `export` of each PEL_* var).

**Apply to:** `pr-emitter.sh` when invoking classifier + proposer. Emitter sets env explicitly from the CLI flags it parsed, never trusts the user's shell to have set PEL_* vars.

### Exit-code-as-contract

**Source:** Every lab inhabitant preserves Phase 7's exit taxonomy (D-17 extension in Phase 8):
- `lab/pel/proposer/code/proposer.sh:37-49` (canonical 0-8 taxonomy).
- `lab/pel/README.md:552-568` (documented taxonomy).

**Apply to:** `pr-emitter.sh` — propagate proposer exit codes upward, add 9 (gh pr create failure) and 10 (tier auto-detect hard-error) without renumbering existing codes.

### `{{placeholder}}` vs `{placeholder}` substitution

**Source A (single-brace):** `lib/co-evolution.sh:726-743` (`fill_template`) + all proposer `prompt.md` files.
**Source B (double-brace, NEW for Phase 8):** Introduced in D-20 to avoid collision with diff hunk-header braces.

**Apply to:** `pr-body-template.md` exclusively — double-brace. Do NOT switch `prompt.md` files or other templates to double-brace (byte-parity invariant).

### `.gitignore` entry pattern

**Source:** Existing gitignore patterns in repo — brief one-liner `.co-evolve-cache/` addition.

**Apply to:** Root `.gitignore`. Plan notes the exact line to add.

---

## No Analog Found

| File | Role | Reason | Mitigation |
|------|------|--------|------------|
| `VERIFY-SC4.md` | release-gate tracker (human-review count + merged/closed PR log) | New artifact type — no existing "tracked by humans post-ship" document in the repo | Use the structured-notes shape of `.planning/notes/phase-7-simulation-lessons.md` (headings, tables, binding-decision anchors). Plan 03 decides exact rubric format. |
| Eval cache layer (`.co-evolve-cache/evals/<hash>.json`) | cache | No existing in-repo cache subsystem | Pattern is trivially inventable: `hash(fixture) + hash(script)` → cache key; `jq` for I/O. Reference `evals/reports/<timestamp>/scores.json` for the output shape to preserve. |
| Preflight cost estimate (interactive prompt) | UX | No existing interactive prompt in the repo — all v1.0-v1.2 work is non-interactive by design | New surface; `--yes` skips it. Plan 02 specifies the tabular format inline. |

---

## Metadata

**Analog search scope:**
- `lab/pel/**` (all inhabitants — classifier + 3 proposer tiers)
- `dev-review/codex/**` + `agent-bouncer/**` (runners)
- `lib/co-evolution.sh` (shared library)
- `tests/**` (simulation gates)
- `evals/**` (scorer invocation target)
- `.planning/phases/0[4-7]*/**-CONTEXT.md` (phase precedents)
- `co-evolve-bouncer.sh` (CLI entry)

**Files scanned:** 24 (proposer.sh × 3, adapter.sh × 3, canary.sh, classifier.sh, allowlist.txt, prompt.md × 3, README.md × 2, dev-review.sh, agent-bouncer.sh, co-evolve-bouncer.sh, co-evolution.sh, 4 simulation scripts, 4 phase CONTEXT docs)

**Pattern extraction date:** 2026-04-19

**Key signal for planner:** Phase 8 is ~90% pattern-reuse from Phases 3-7. The genuinely new mechanics are: (1) the tier-auto-detect rule table (D-04), (2) the PR-body templating layer (D-20), (3) the `gh pr create` + `--dry-run` PATH-stub posture (D-02), and (4) the emitter-owned scoring sandbox (D-08/D-09). Everything else — self-containment invariant, exit-code taxonomy, simulation harness, env-var discipline, trap EXIT cleanup — has an exact-match analog.
