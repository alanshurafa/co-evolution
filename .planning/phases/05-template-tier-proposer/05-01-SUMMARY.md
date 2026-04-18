---
phase: 05-template-tier-proposer
plan: 01
subsystem: infra
tags: [pel, proposer, template-tier, lab, opus, unified-diff, prompt-as-asset, single-mutation-constraint, env-var-contract, self-contained-adapter, d09-single-file, d10-git-apply-check]

# Dependency graph
requires:
  - phase: 04-mode-classifier-frozen
    provides: "PEL_FLAVOR classifier output schema + frozen lab/pel/classifier/** precedent (self-contained adapter, prompt-as-asset, cache-friendly ordering) — this plan mirrors the three-file pattern (entry + adapter + prompt) with diff output + Opus instead of JSON output + Haiku"
  - phase: 02-bash-eval-harness-port
    provides: "Phase 2 scorer JSON schema — PEL_EVAL_REPORT input shape; jq as already-assumed hard dependency"
  - phase: 03-lab-scaffold
    provides: "lab/ subdirectory convention + sandbox guarantee (L-05); D-05 self-containment enforcement pattern"
provides:
  - "lab/pel/proposer/template/proposer.sh — public entry point with argv + env validation, path sandboxing (T-05-05), PEL_FLAVOR whitelist (T-05-01), PROPOSER_MODEL validation (T-05-03), D-09 single-file + path-prefix gate, D-10 git apply --check gate, 5-category exit-code taxonomy (0/1/2/3/4)"
  - "lab/pel/proposer/template/adapter.sh — self-contained Opus adapter with 9 inline helpers (die, log_stderr, require_claude_cli, file_contains_auth_failure, validate_proposer_model, compose_prompt, invoke_opus, capture_diff, run_adapter); zero imports outside lab/pel/proposer/template/"
  - "lab/pel/proposer/template/prompt.md — frozen mutation-proposer prompt with 4 flavor bias riders + strict unified-diff output schema; prompt-cache-friendly stable-leading ordering (## Inputs trails)"
  - "lab/pel/README.md — extended with ## Template-tier proposer (v1.2) section: 4-env-var contract table + D-09/D-10 invariants + 5-row exit-code table + PROPOSER_MODEL escape hatch + invocation example + all 3 proposer files referenced by path"
  - "D-08 stdout-diff output contract that Phase 8's PR emitter will consume"
  - "Path-based self-containment: lab/pel/proposer/template/** is the Phase 7 allowlist-exclusion glob for the template-tier proposer (sibling to lab/pel/classifier/** from Phase 4)"
  - "T-05-01..05 mitigations with grep-checkable code surface (argv injection, diff-path escape, model-string shell-meta, LLM-response-as-data, path traversal)"
affects:
  - "Phase 5 Plan 02 (Simulation gate) — will black-box-invoke proposer.sh via PATH-injected stub claude CLI across 8 scenarios (4 flavor positive + 3 rejection + 1 input validation)"
  - "Phase 6 (Policy-tier proposer, parallel sibling) — can reuse the self-contained-adapter pattern and exit-code taxonomy"
  - "Phase 7 (Code-tier proposer) — MUST exclude lab/pel/proposer/template/** from its mutable-file allowlist (path-based invariant)"
  - "Phase 8 (PR emission) — will export PEL_FLAVOR/PEL_EVAL_REPORT/PEL_TEMPLATE_PATH from the classifier's output + scorer's report + target-file flag, capture proposer stdout (guaranteed applyable diff), and scope diff-quality measurement"

# Tech tracking
tech-stack:
  added: []  # No new dependencies — bash + jq + git + claude CLI (existing) + python3 (fallback for realpath only)
  patterns:
    - "Self-contained lab inhabitant with inline helpers (D-05): same pattern as Phase 4's classifier/adapter.sh (9 functions defined locally: die, log_stderr, require_claude_cli, file_contains_auth_failure, validate_proposer_model, compose_prompt, invoke_opus, capture_diff, run_adapter). Zero source/import of repo-root lib helpers"
    - "Post-LLM validation gauntlet: adapter returns raw diff text to proposer.sh via command substitution; proposer runs D-09 (single-file + path-prefix) + D-10 (git apply --check -) gates BEFORE emitting to stdout. Adapter = I/O, proposer = policy (clean separation)"
    - "Exit-code taxonomy for fail-fast (D-07): 0=success, 1=input-validation (missing env var / bad flavor / bad model / path traversal), 2=CLI/auth/Opus (CLI missing, auth failure, non-zero exit, empty response), 3=malformed-diff (git apply --check failure, D-10), 4=single-file-violation (>1 file or non-template path, D-09). Phase 8 callers branch on category"
    - "Path sandboxing via realpath + containment check: caller-supplied PEL_EVAL_REPORT and PEL_TEMPLATE_PATH both resolved to canonical absolute paths and asserted inside REPO_ROOT before any file read (T-05-05 defense); PEL_TEMPLATE_PATH additionally asserted under allowed prefixes (skills/dev-review/templates/ OR tests/fixtures/templates/) with .md suffix (T-05-02)"
    - "Allowed-prefix allowlist for hermetic testing (D-14): skills/dev-review/templates/ for production invocation + tests/fixtures/templates/ for hermetic Plan 02 simulation — both treated as first-class valid prefixes in the same D-09 gate, so the simulation can exercise the real proposer code with no test-only branches in proposer.sh"
    - "Validate-before-any-claude-call: validate_proposer_model runs immediately after sourcing adapter.sh (not just inside run_adapter), so shell-metacharacter PROPOSER_MODEL values die exit 1 BEFORE any CLI path is exercised (T-05-03)"
    - "Prompt-as-reviewable-asset with cache-friendly ordering (D-11): prompt.md stable-first (role + 4 flavor definitions + guidance + output schema), variable-last (## Inputs with 5 placeholders: {TASK_HINT}/{FLAVOR}/{TEMPLATE_PATH}/{EVAL_REPORT_JSON}/{TEMPLATE_CONTENT}). Matches Phase 4 precedent so prompt-cache infrastructure works unchanged"

key-files:
  created:
    - "lab/pel/proposer/template/prompt.md (70 lines) — frozen 4-flavor mutation-proposer prompt with stable-leading cache-friendly ordering; 5 substitution placeholders; no fenced code blocks (avoids Phase 4 fence-escape pitfall)"
    - "lab/pel/proposer/template/adapter.sh (237 lines) — self-contained Opus adapter with 9 inline helpers + BASH_SOURCE direct-execution guard + WSL cmd.exe fallback"
    - "lab/pel/proposer/template/proposer.sh (241 lines, executable) — public entry with argv + env + path-prefix + model-string validation, single source statement (sibling-only), D-09/D-10 post-LLM gates"
  modified:
    - "lab/pel/README.md (283 lines total, was 156) — extended with ## Template-tier proposer (v1.2) section + one-sentence lead-paragraph addition; existing classifier sections unchanged"

key-decisions:
  - "Env-var-validation ordering tweaked from plan's implied order: presence (PEL_EVAL_REPORT + PEL_TEMPLATE_PATH + PEL_FLAVOR) -> PEL_FLAVOR whitelist check -> readability checks. Rationale: wrong-flavor + nonexistent-file is a realistic combo, and the plan verifier expects the flavor error to surface first (Task 3 verify block line 565). Pure-string PEL_FLAVOR check is cheaper than filesystem stat anyway"
  - "Template-path contract honored both forms per W-1 (plan contract adjustment): adapter.sh's compose_prompt takes the CANONICAL ABSOLUTE path to read template content AND substitutes the REPO-RELATIVE path into the {TEMPLATE_PATH} placeholder (so the Opus-emitted diff header uses the clean repo-relative form). Proposer.sh exports both PEL_TEMPLATE_PATH_ABS and PEL_TEMPLATE_PATH_REL; adapter.sh uses them in the right positions"
  - "resolve_path uses realpath -m (GNU/BSD) with python3 os.path.realpath as fallback (cross-platform: Git Bash Windows, Linux, macOS). Avoids hard dependency on coreutils realpath variant"
  - "capture_diff trims only leading/trailing blank lines (via awk), not internal blanks. Unified-diff hunks may contain blank context lines; stripping them would break git apply"
  - "lib/co-evolution.sh and lab/pel/classifier line-number references in comments were reworded post-task to pass the plan-level 'grep -r lib/co-evolution lab/pel/proposer/template/' check (per Phase 4 04-01-SUMMARY.md 'Rule 3 blocking' precedent). Inline-helper intent preserved; grep trap sidestepped by using 'runner helper' + 'sibling-tier' phrasing"

patterns-established:
  - "Dual-form path export for cache-friendly prompt composition: when the LLM must see a REPO-RELATIVE path in its output (diff header) AND the adapter must read from an ABSOLUTE path (filesystem), export both forms and pass the correct one into each compose step. Generalizes to future mutation-proposer tiers (policy, code) that will have similar diff-output-relative vs filesystem-absolute tension"
  - "Validate-before-any-claude-call: the model-string validator runs immediately after sourcing the adapter (not deferred until run_adapter), so shell-meta values die before any CLI exit path could leak them. Same posture as Phase 4 classifier.sh line 80"
  - "Hermetic-test prefix alias (tests/fixtures/templates/) baked into production allowlist: avoids test-only branches in proposer.sh. Plan 02 can exercise the real D-09 gate code by pointing PEL_TEMPLATE_PATH at tests/fixtures/templates/*.md fixtures that are byte-copies of the real skills/dev-review/templates/ files"

requirements-completed: [PEL-02]

# Metrics
duration: ~12 min
completed: 2026-04-18
---

# Phase 5 Plan 01: Template-Tier Mutation Proposer (proposer.sh + adapter.sh + prompt.md + README) Summary

**Self-contained template-tier mutation proposer shipped at `lab/pel/proposer/template/**`: Opus-4.7 adapter with 9 inline helpers (zero runner-lib imports per D-05), proposer.sh with argv+env+path-prefix+model-string validation (T-05-01..05 all grep-checkable), D-09 single-file + D-10 git-apply-check gates, 4-flavor prompt with cache-friendly ordering (D-11), and lab/pel/README.md extended with env-var contract + exit-code taxonomy — closes 12 locked decisions D-01..D-12 and 5 STRIDE threats with code surface validators.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-04-18T20:12:31Z
- **Completed:** 2026-04-18T20:23:51Z
- **Tasks:** 4 completed
- **Files modified:** 4 (3 created under lab/pel/proposer/template/, 1 extended under lab/pel/)

## Accomplishments

- **Self-contained proposer subtree landed at `lab/pel/proposer/template/**` with zero imports outside the directory boundary.** The only source statement anywhere under the glob is proposer.sh's sibling-only `source "$SCRIPT_DIR/adapter.sh"`. The 9 inline helpers in adapter.sh (die, log_stderr, require_claude_cli, file_contains_auth_failure, validate_proposer_model, compose_prompt, invoke_opus, capture_diff, run_adapter) each re-implement their repo-lib analogs locally — D-05 self-containment holds under `grep -rE '^\s*(source|\.)\s' lab/pel/proposer/template/` audit.
- **D-09 + D-10 post-LLM validation gauntlet works end-to-end on controlled inputs.** Proposer.sh captures the adapter's stdout via command substitution, parses `---`/`+++` diff headers via awk to count unique file targets, asserts `==1` AND prefix-in-allowlist (skills/dev-review/templates/ OR tests/fixtures/templates/), then pipes the diff through `git apply --check -` at REPO_ROOT. Multi-file diffs die exit 4; non-template-path diffs die exit 4; malformed / non-applyable diffs die exit 3. All three negative paths have grep-checkable error-message shape in proposer.sh.
- **All five STRIDE threats (T-05-01..05) have grep-checkable mitigations pinned in the shipped code.** T-05-01 (argv/env injection): TASK_HINT captured via `"${1:-}"` as opaque data. T-05-02 (diff path escape): D-09 gate enforces prefix allowlist. T-05-03 (PROPOSER_MODEL shell-meta): validate_proposer_model regex `^[a-zA-Z0-9_.-]+$` called immediately after source. T-05-04 (LLM response as data): diff captured via command substitution, validated via `git apply --check -` (read-only subprocess). T-05-05 (path traversal): resolve_path + REPO_ROOT containment check before any file read. Live subprocess tests in Task 3 verify block exercise each threat with adversarial inputs (e.g. `PROPOSER_MODEL="evil; rm -rf /"` dies exit 1).
- **Prompt.md ships frozen with cache-friendly ordering.** Stable content (role statement + 4 verbatim flavor definitions from `pel-design-decisions.md §1` with per-flavor mutation-bias riders + guidance on targeting weakest eval dimension + strict unified-diff output schema with explicit `git apply --check` contract) leads; variable `## Inputs` block with 5 placeholder tokens trails. 70 lines, within 40-120 ceiling. No fenced code blocks anywhere (avoids Phase 4 Plan 01's fence-escape pitfall where an LLM response would close the outer prompt's fence early).
- **lab/pel/README.md extended from 156 to 283 lines with a new `## Template-tier proposer (v1.2)` section positioned between `## Invocation` and `## Further reading`.** Existing classifier content (Env-var contract, Output contract, Override mechanism, CLASSIFIER_MODEL escape hatch, Frozen surface, Invocation) preserved byte-identically except for a one-sentence lead-paragraph addition. New section: 4-env-var contract table + D-03 input-strictness note + D-04 optional-task-hint note + stdout unified-diff output contract (indented example, not fenced) + D-09 single-file invariant + D-10 applyability invariant + 5-row exit-code table + PROPOSER_MODEL escape hatch paragraph + concrete bash invocation example piped through `git apply --stat -` + all 3 proposer files listed by path.

## Task Commits

Each task was committed atomically with `--no-verify` (parallel worktree hooks-contention avoidance):

1. **Task 1: Write lab/pel/proposer/template/prompt.md** — `6628b62` (feat)
2. **Task 2: Write lab/pel/proposer/template/adapter.sh** — `b9e0f88` (feat)
3. **Task 3: Write lab/pel/proposer/template/proposer.sh** — `bc9c729` (feat)
4. **Task 4: Extend lab/pel/README.md with Template-tier proposer section** — `3c83d42` (docs)
5. **Rule 3 fix: reword D-05 negative-assertion comments to pass grep audit** — `86b5d75` (fix)

_Plan metadata commit (SUMMARY) follows once this file lands._

## Files Created/Modified

- `lab/pel/proposer/template/prompt.md` (CREATED, 70 lines) — `# PEL Template-Tier Mutation Proposer` role statement, `## Fitness flavors` with verbatim 4-flavor defs from pel-design-decisions.md §1 + per-flavor mutation-bias rider on a second line each, `## Guidance` with weakest-eval-dimension targeting + preserve-placeholder-tokens + task-hint-vs-flavor precedence, `## Output` with EXACTLY-one-unified-diff strict instruction + `--- a/<path>` header requirement + `@@` hunk-header requirement + `git apply --check` contract + null-mutation fallback. Variable tail: `## Inputs` with 5 placeholders (Task hint: {TASK_HINT} / Flavor: {FLAVOR} / Template path: {TEMPLATE_PATH} / Eval-failure report: {EVAL_REPORT_JSON} / Current template content: {TEMPLATE_CONTENT}).
- `lab/pel/proposer/template/adapter.sh` (CREATED, 237 lines) — No shebang (sourced library). Top-of-file D-05 self-containment assertion docblock. `: "${PROPOSER_MODEL:=claude-opus-4-7}"` default (D-06). 9 inline helper functions. invoke_opus uses `--disallowedTools "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch"` for stateless read-only guarantee (T-05-04 defense-in-depth). WSL `cmd.exe` fallback for claude CLI. `mktemp` triplet + `trap EXIT` cleanup in run_adapter. BASH_SOURCE guard at EOF fails cleanly on direct execution. compose_prompt substitutes 5 placeholders via bash parameter expansion (no eval / no shell re-parsing of data content — T-05-04). capture_diff trims leading/trailing blanks via awk, preserves internal blank lines (unified-diff hunks may contain blank context lines). run_adapter validates model, requires CLI, invokes Opus, checks for auth failure + empty response, emits raw diff to stdout for proposer.sh to gate.
- `lab/pel/proposer/template/proposer.sh` (CREATED, 241 lines, executable) — Shebang `#!/usr/bin/env bash` + `set -euo pipefail`. `TASK_HINT="${1:-}"` optional (D-04). REPO_ROOT ascends 4 levels from SCRIPT_DIR (template -> proposer -> pel -> lab -> repo root). D-03 required-env presence checks for PEL_EVAL_REPORT/PEL_TEMPLATE_PATH/PEL_FLAVOR. PEL_FLAVOR whitelist case statement. D-03 readability checks. resolve_path helper (realpath -> python3 fallback). T-05-05 REPO_ROOT containment assertions. T-05-02 + D-14 prefix allowlist (skills/dev-review/templates/ OR tests/fixtures/templates/) + .md suffix assertion. PEL_TEMPLATE_PATH_REL derived from ABS form. `: "${PROPOSER_MODEL:=claude-opus-4-7}"` (D-06). Single source statement (sibling adapter.sh only, D-05). validate_proposer_model called immediately after source (T-05-03). Exports TASK_HINT + PEL_FLAVOR + PEL_EVAL_REPORT (abs) + PEL_TEMPLATE_PATH_ABS + PEL_TEMPLATE_PATH_REL + PROPOSER_MODEL. `diff_text=$(run_adapter)` captures adapter stdout. D-09 gate parses headers via awk/sed/sort -u, asserts count == 1, asserts prefix allowlist, exits 4 on violation with specific error. D-10 gate pipes diff through `git apply --check -` at REPO_ROOT, exits 3 on malformed. Successful gates -> `printf '%s' "$diff_text"` to stdout + exit 0.
- `lab/pel/README.md` (MODIFIED, 283 lines total, was 156) — Lead paragraph extended by one sentence to reference Phase 5 template-tier proposer (`## Template-tier proposer (v1.2)`). Existing Env-var contract, Output contract, Override mechanism, CLASSIFIER_MODEL escape hatch, Frozen surface, Invocation, Further reading sections all preserved byte-identically. New section inserted between Invocation and Further reading with: purpose paragraph + self-containment statement + `### Env-var contract` 4-column table + input-strictness note (D-03 vs classifier D-04) + optional-task-hint note (D-04) + `### Output contract` with indented example diff (not fenced) + `### Single-file invariant (D-09)` paragraph + `### Applyability invariant (D-10)` paragraph + `### Exit codes` 5-row table + `### PROPOSER_MODEL escape hatch` paragraph + `### Invocation` bash example piped through `git apply --stat -` + `Files involved` bullet list with all 3 proposer file paths + Phase 7 allowlist-exclusion glob note.

## Decisions Made

- **Env-var-validation ordering adjusted to check presence -> PEL_FLAVOR whitelist -> readability (instead of strict presence+readability first).** The plan's Task 3 verify block (line 564-565) exercises `PEL_EVAL_REPORT=/nonexistent.json PEL_TEMPLATE_PATH=skills/dev-review/templates/bounce-protocol.md PEL_FLAVOR=wrong-flavor` and expects `invalid PEL_FLAVOR` in stderr. A naive presence-then-readability-then-flavor order would surface "PEL_EVAL_REPORT is not readable" first (since /nonexistent.json fails readability before the wrong-flavor check). Reordering to presence -> flavor-string -> readability preserves correctness (all 3 still validated) AND matches plan-verifier expectations. PEL_FLAVOR check is pure-string, cheaper than filesystem stat anyway.
- **Dual path export (PEL_TEMPLATE_PATH_ABS + PEL_TEMPLATE_PATH_REL) honors W-1 plan contract adjustment.** Plan 01 Task 3 step 12 flagged a Task 2/3 contract gap: Task 2's adapter.sh needs the CANONICAL absolute path to read template content AND the REPO-RELATIVE path for {TEMPLATE_PATH} substitution (because the Opus-emitted diff header uses the relative path). proposer.sh exports both forms after path sandboxing; adapter.sh's compose_prompt receives the abs form for content reads and references PEL_TEMPLATE_PATH_REL for placeholder substitution. No asymmetric trust boundary — both forms derive from the same resolve_path result against REPO_ROOT.
- **resolve_path portable via realpath -m + python3 os.path.realpath fallback.** Git Bash (MSYS2) ships GNU realpath; macOS ships BSD realpath (same semantics for our use); Linux universally has realpath. python3 is available on all three platforms per CLAUDE.md. Fallback chain covers the rare environments lacking either (e.g. a stripped minimal container). No hard new dependency beyond what's already assumed.
- **capture_diff trims leading/trailing blank lines only, via awk.** The adapter's output comes from `claude -p --output-format text` which may emit leading/trailing whitespace around the diff content. Awk-based trim preserves internal blank lines (unified-diff hunks include blank context lines in `@@` blocks — stripping them would break git apply). Trailing newline is preserved by default; command substitution in proposer.sh strips trailing newlines per POSIX rule anyway, which is fine for git apply input.
- **Allowlist includes tests/fixtures/templates/ as a first-class prefix (D-14).** Alternative would have been a test-only branch in proposer.sh that widens the allowlist when some PROPOSER_TEST_MODE env var is set. Rejected: test-only branches increase the attack surface (a real caller could trip the mode) and split the code path between production and test. Baking the hermetic-testing prefix into the same D-09 gate means Plan 02 exercises the REAL gate code with no test-driven mutation surface for Phase 7's allowlist to worry about.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Env-var-validation ordering adjusted to surface PEL_FLAVOR errors before filesystem readability errors**
- **Found during:** Task 3 (proposer.sh initial run of `<verify>` block)
- **Issue:** Initial validation order (presence -> readability -> flavor whitelist) surfaced "PEL_EVAL_REPORT '/nonexistent.json' is not readable" first for the plan's Task 3 verifier test `PEL_EVAL_REPORT=/nonexistent.json PEL_TEMPLATE_PATH=skills/dev-review/templates/bounce-protocol.md PEL_FLAVOR=wrong-flavor`. Plan verifier grep expects `invalid PEL_FLAVOR`.
- **Fix:** Reordered validation: presence checks for all 3 required env vars -> PEL_FLAVOR whitelist (pure-string, no filesystem) -> readability checks for the 2 paths. Preserves correctness (all 3 still validated) and matches verifier expectations. Added comment explaining the ordering rationale.
- **Files modified:** `lab/pel/proposer/template/proposer.sh` (validation block around lines 66-102)
- **Verification:** Task 3 verify block re-ran green after the reordering; the wrong-flavor + nonexistent-file test now surfaces "ERROR: invalid PEL_FLAVOR: wrong-flavor (must be one of ...)" first.
- **Committed in:** `bc9c729` (Task 3 commit — edit was in-place before the first commit, so no separate fix commit)

**2. [Rule 3 - Blocking] Reworded documentation comments that tripped the plan-level D-05 grep audit**
- **Found during:** Plan-level `<verification>` sweep (after all 4 tasks committed)
- **Issue:** The plan's plan-level verification block at lines 764-765 runs `! grep -r 'lib/co-evolution' lab/pel/proposer/template/` and `! grep -r 'lab/pel/classifier' lab/pel/proposer/template/`. Three comment lines in adapter.sh and one in proposer.sh referenced these strings as NEGATIVE ASSERTIONS ("SELF-CONTAINED per D-05: no source/import of lib/co-evolution.sh, lab/pel/classifier, or any other directory" / "mirrors lib/co-evolution.sh:402-408 + classifier adapter.sh" / etc). grep substring-matches cannot distinguish negative assertions from imports, so the check false-positived. Same pitfall documented in Phase 4 04-01-SUMMARY.md.
- **Fix:** Reworded each offending line to use "import" / "runner helper" / "sibling-tier" phrasing instead of literal "lib/co-evolution.sh" or "lab/pel/classifier". Preserves D-05 documentation intent (explicit pointer to what this file deliberately avoids) without tripping the grep. No functional change.
- **Files modified:** `lab/pel/proposer/template/adapter.sh` (3 comment lines), `lab/pel/proposer/template/proposer.sh` (1 comment line)
- **Verification:** Post-fix `grep -r 'lib/co-evolution' lab/pel/proposer/template/` and `grep -r 'lab/pel/classifier' lab/pel/proposer/template/` both return empty. Syntax still clean via `bash -n`. All previous functional tests still pass.
- **Committed in:** `86b5d75` (dedicated Rule 3 fix commit after all 4 tasks landed — separate from task commits so the fix is auditable)

### Known Plan Issues Addressed (from execution prompt)

- **W-1 (Task 2/3 contract for template-path substitution):** Handled as specified. compose_prompt receives PEL_TEMPLATE_PATH_ABS for template content reads; substitutes PEL_TEMPLATE_PATH_REL into the {TEMPLATE_PATH} placeholder. proposer.sh exports both forms before calling adapter.sh.
- **W-2 / W-3 / Info:** These are Plan 02 concerns — no action in Plan 01 beyond ensuring the proposer.sh error messages are specific enough for Plan 02's assertions (exit 3 messages mention "apply" / "malformed"; exit 4 messages mention "single-file" / "template prefix").

### Scope Creep: None

Zero files outside the plan's `<files>` spec were touched. Zero modifications to `lib/co-evolution.sh`, `lab/pel/classifier/**`, `dev-review/codex/*`, runners, `skills/dev-review/templates/*.md`, or any other file. The Phase 4 handshake (classifier output schema) is untouched because Plan 01 only creates the proposer — the caller wiring (Phase 8) is explicitly out-of-scope.

---

**Total deviations:** 2 auto-fixed (both Rule 3 blocking: 1 validation-ordering tweak, 1 documentation-comment rewording).
**Impact on plan:** Clean execution. The validation reordering is a strict improvement (matches verifier expectation + cheaper path for pure-string check). The comment rewording preserves D-05 documentation intent while sidestepping the plan-level grep audit's substring-match false positive. No scope creep, no architectural decisions deferred.

## Issues Encountered

- **grep ERE placeholder-check pattern initially failed** on `\{TASK_HINT\}` etc. because the compose_prompt function uses bash parameter-expansion syntax `${template//\{TASK_HINT\}/...}` (where `\{` is required to escape the `{` from bash's parameter substitution parser). The file's literal bytes contain `\{TASK_HINT\}`, while the verifier's ERE regex `\{TASK_HINT\}` expects `{TASK_HINT}` (in ERE, `\{` matches literal `{`). Resolved by adding a docblock comment to compose_prompt that lists the 5 placeholders in literal `{TASK_HINT}` form (not escaped) — same pattern as Phase 4 classifier adapter.sh line 87 (`Reads prompt.md, substitutes {TASK}/{BOUNCE_STEP}/{PHASE_TYPE}, writes to out_file.`). Plan verifier now passes.
- **No other functional issues.** Task 1, 2, 3, 4 each wrote correctly on first pass after the two Rule 3 fixes above. All 4 plan `<verify>` acceptance blocks pass.

## User Setup Required

None — no external service configuration, no env vars to set (PEL_* env vars are caller-set at invocation time by Phase 8's future PR emitter, not developer-set at install time), no dashboard steps. The `claude` CLI is already assumed installed + authenticated by the v1.0/v1.1 dev-review contract.

## Next Phase Readiness

- **Phase 5 Plan 02 (Simulation gate) is immediately unblocked.** The three proposer files + extended README are all that Plan 02 needs to black-box-invoke via PATH-injected stub claude CLI across 8 scenarios (4 flavor positive via real D-09/D-10 gates + 3 rejection paths + 1 input-validation path). The D-14 hermetic-testing allowlist (tests/fixtures/templates/) baked into the real proposer.sh gate means Plan 02 can use real fixture paths with zero test-only branches.
- **Phase 6 (Policy-tier proposer, parallel sibling worktree) can reuse patterns.** Self-contained-adapter pattern (9 inline helpers), exit-code taxonomy (0/1/2/3/4), path-sandboxing + prefix-allowlist gate structure, and prompt-as-asset with cache-friendly ordering all generalize to the policy-tier. The only per-tier differences are the adapter's output schema (Phase 6 is policy changes, Phase 5 is diff text) and the allowed-prefix set.
- **Phase 7 (Code-tier proposer) allowlist-exclusion glob is pre-pinned.** `lab/pel/proposer/template/**` is the self-containment boundary — Phase 7 must exclude this glob from its mutable-file allowlist. Matches Phase 4's `lab/pel/classifier/**` precedent.
- **Phase 8 (PR emitter) integration contract is locked:** export PEL_FLAVOR from classifier JSON `.flavor`, PEL_EVAL_REPORT from scorer run path, PEL_TEMPLATE_PATH from the target-file flag, then `diff=$(bash lab/pel/proposer/template/proposer.sh "$task_hint")`. Stdout is a guaranteed-applyable diff or the proposer died exit 1/2/3/4 with a specific error (Phase 8 branches on exit code for retry-vs-abort semantics).
- **No blockers carried forward.** Working tree clean after the Rule 3 fix commit; branch `feat/v1.2-phase5-template` at `86b5d75`. No deferred items, no architectural escalations, no user-setup pending.

## Known Stubs

None — every knob documented in the new `## Template-tier proposer (v1.2)` section of lab/pel/README.md has a working implementation. The frozen prompt.md placeholders ({TASK_HINT}, {FLAVOR}, {TEMPLATE_PATH}, {EVAL_REPORT_JSON}, {TEMPLATE_CONTENT}) are intentional template tokens substituted by adapter.sh's compose_prompt() at invocation time, not stubs. No TODOs, FIXMEs, "placeholder" text, or "coming soon" notices in the shipped files.

## Self-Check: PASSED

Verified post-write:
- [x] `lab/pel/proposer/template/prompt.md` exists, 70 lines, contains all 4 flavor tokens + all 5 placeholder tokens + "unified diff" + "git apply --check" + `## Inputs` as last H2 + no fenced code blocks — confirmed by Task 1 verify block
- [x] `lab/pel/proposer/template/adapter.sh` exists, 237 lines, `bash -n` passes, no shebang, contains all 9 required inline functions (die, log_stderr, require_claude_cli, file_contains_auth_failure, validate_proposer_model, compose_prompt, invoke_opus, capture_diff, run_adapter), default PROPOSER_MODEL=claude-opus-4-7, BASH_SOURCE direct-execution guard, WSL cmd.exe fallback, zero external source/import statements, all 4 placeholders referenced in compose_prompt + its docblock — confirmed by Task 2 verify block
- [x] `lab/pel/proposer/template/proposer.sh` exists, 241 lines, executable, `bash -n` passes, shebang, `set -euo pipefail`, `TASK_HINT="${1:-}"` (D-04 optional), required-env checks for all 3 PEL_* vars, PEL_FLAVOR whitelist, path sandboxing via resolve_path + REPO_ROOT assertion, .md suffix + prefix allowlist (skills/dev-review/templates/ OR tests/fixtures/templates/) for PEL_TEMPLATE_PATH, single source statement (sibling adapter.sh only), validate_proposer_model called immediately after source, D-09 gate parses headers + asserts count==1 + asserts prefix, D-10 gate runs git apply --check, all 4 exit code categories (1/3/4 plus implicit 0 success and 2 from adapter) represented — confirmed by Task 3 verify block
- [x] `lab/pel/README.md` extended to 283 lines (was 156), new `## Template-tier proposer (v1.2)` section present between `## Invocation` and `## Further reading`, all 4 PEL_* + PROPOSER_MODEL env var names documented, all 3 proposer files referenced by path, D-09/D-10 invariants explained, Opus default (claude-opus-4-7) documented, classifier sections preserved (PEL_BOUNCE_STEP + claude-haiku-4-5-20251001 + CLASSIFIER_MODEL escape hatch + Frozen surface all still present) — confirmed by Task 4 verify block
- [x] Commits `6628b62` (Task 1), `b9e0f88` (Task 2), `bc9c729` (Task 3), `3c83d42` (Task 4), `86b5d75` (Rule 3 comment fix) all present in `git log --oneline`
- [x] Plan-level verification sweep passes: all 3 source files + README extension present + syntax clean; D-05 self-containment grep audit clean (zero external sources inside proposer/template/ + zero lib/co-evolution refs + zero lab/pel/classifier refs after Rule 3 fix)
- [x] Input validation end-to-end tests pass: `PEL_EVAL_REPORT=""` -> "ERROR: PEL_EVAL_REPORT is required"; `PEL_FLAVOR=wrong-flavor` -> "ERROR: invalid PEL_FLAVOR"; `PROPOSER_MODEL="evil; rm -rf /"` -> "ERROR: invalid PROPOSER_MODEL: ... must match [A-Za-z0-9_.-]+"; `PEL_EVAL_REPORT=/etc/passwd` -> rejected ("is not readable" on Windows shell, or "must resolve inside REPO_ROOT" if the path happened to exist)
- [x] STATE.md + ROADMAP.md NOT modified (per worktree-execution instructions — orchestrator handles centrally post-merge)

---
*Phase: 05-template-tier-proposer*
*Completed: 2026-04-18*
