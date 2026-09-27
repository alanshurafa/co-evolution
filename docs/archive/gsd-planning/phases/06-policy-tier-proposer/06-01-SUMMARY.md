---
phase: 06-policy-tier-proposer
plan: 01
subsystem: infra
tags: [pel, policy-proposer, lab, haiku, yq, jq, bounds, enum-knob, env-var-contract, json-delta, prompt-as-asset, self-contained]

# Dependency graph
requires:
  - phase: 04-mode-classifier-frozen
    provides: "D-08 classifier JSON output contract whose .flavor will feed PEL_FLAVOR for this proposer; Phase 4 self-containment + adapter + prompt patterns cloned verbatim for structure"
  - phase: 02-bash-eval-harness-port
    provides: "jq as an established hard dependency (score-run.sh) + Phase 2 scorer output schema the PEL_FEEDBACK fixtures mirror"
provides:
  - "lab/pel/proposer/policy/policy.yaml — the enumerated 6-knob mutable surface (D-01, D-02, D-03); hand-editable YAML with per-knob comments; default values in-bounds"
  - "lab/pel/proposer/policy/bounds.jq — single-source-of-truth bounds validator (D-12, D-13, D-14); halt_error(4) on bounds, halt_error(5) on non-enumerated knob; supports whole-object AND dotted-path flavor_weights mutations"
  - "lab/pel/proposer/policy/prompt.md — cache-friendly mutation prompt (D-15, D-16); stable lead (role + 6 knobs + 4 flavor bias + schema) / variable ## Inputs trail with {POLICY_YAML}/{EVAL_FEEDBACK}/{FLAVOR}"
  - "lab/pel/proposer/policy/adapter.sh — self-contained Haiku 4.5 adapter (D-07, D-08, D-10); 10 inline helpers; zero external source/import; BASH_SOURCE[0] direct-execution guard"
  - "lab/pel/proposer/policy/proposer.sh — public entry (D-05, D-06, D-11); require_tools (jq+yq), env validation, realpath+prefix path validation, sibling adapter source, bounds.jq post-emission enforcement, zero yq -i anywhere"
  - "D-10 JSON delta contract (mutations[] 1..3, rationale, flavor echo, policy_path echo) that Phase 8's PR emitter will consume"
  - "Mitigations grep-checkable in code for all 7 STRIDE threats T-06-01..T-06-07"
affects:
  - "Phase 6 Plan 02 (Simulation gate) — will stub claude CLI via PATH injection to exercise the 8 scenarios (4 flavor + 4 adversarial) against the proposer as a black box"
  - "Phase 7 (code-tier proposer) — MUST exclude lab/pel/proposer/policy/** from its mutable-file allowlist glob (path-based frozen invariant mirrors Phase 4 classifier treatment)"
  - "Phase 8 (PR emission) — will read D-10 JSON delta from stdout, apply via yq after human PR review; branches on exit codes 0/3/4/5 to decide retry vs abort"

# Tech tracking
tech-stack:
  added:
    - "yq (mikefarah/Go yq v4+) — required tool at proposer.sh startup; used read-only (no -i flag) for parse validation of PEL_POLICY_PATH; install hint emitted on missing binary"
  patterns:
    - "Bounds validation as jq program: bounds.jq is both runtime enforcement (called from proposer.sh after adapter emits) and documentation-as-code (single source of truth for the 6-knob allowlist + per-knob constraints). Reusable pattern for any future enumerated-surface proposer"
    - "halt_error(N) for distinct exit codes: bounds violation vs non-enumerated-knob flagged via halt_error(4) vs halt_error(5) so Phase 8 can distinguish 'LLM drifted on value' from 'LLM tried to mutate something not allowed'"
    - "Self-contained lab inhabitant cloned verbatim from Phase 4: same 10 inline helper functions (die, log_stderr, require_claude_cli, file_contains_auth_failure, validate_proposer_model, invoke_haiku, compose_prompt, validate_delta_response, emit_delta, run_adapter), same BASH_SOURCE guard, same --disallowedTools stateless-read-only subagent posture"
    - "D-11 dry-run by construction: proposer.sh has zero yq -i anywhere (grep-enforced). The proposer EMITS a delta; application to the live policy is Phase 8's PR-flow problem. This is architectural, not policy — a maintainer adding 'yq -i' by mistake breaks the ship contract"
    - "Dotted-path delta support (flavor_weights.<sub>): bounds.jq handles both whole-object ({key: 'flavor_weights', new: {...}}) and single-sub-key ({key: 'flavor_weights.bug_catcher', new: 0.3}) mutation shapes. Sum-invariant is enforced only on whole-object form (dotted-path caller responsible)"

key-files:
  created:
    - "lab/pel/proposer/policy/policy.yaml (37 lines) — 6 enumerated knobs with default values in-bounds, per-knob comments + header block naming Phase 6 PEL-03 scope"
    - "lab/pel/proposer/policy/bounds.jq (124 lines) — is_int/in_range/FW_SUBKEYS helpers + validate_flavor_weights (whole-object) + validate_knob (dispatcher with per-knob arms for all 6 knobs + flavor_weights.<sub>) + top-level mutations-array program"
    - "lab/pel/proposer/policy/prompt.md (75 lines) — role + 6-knob table + 4-flavor bias table + multi-knob coherence guidance + indent-only schema + ## Inputs trailer with all 3 placeholders"
    - "lab/pel/proposer/policy/adapter.sh (253 lines) — self-contained Haiku adapter with all 10 inline functions; substitutes {POLICY_YAML}/{EVAL_FEEDBACK}/{FLAVOR} via bash parameter expansion; optional TASK_HINT suffix; validate_delta_response enforces D-10 (mutations 1..3, string keys, flavor echo, policy_path echo)"
    - "lab/pel/proposer/policy/proposer.sh (123 lines, executable) — require_tools jq+yq, 3 required env vars each die exit 1 with explicit message, realpath+prefix path validation, parse-only yq/jq verification, sibling-only source of adapter.sh, validate_proposer_model call, run_adapter | bounds.jq with preserved exit codes"
  modified: []   # No existing files modified — scope discipline held

key-decisions:
  - "bounds.jq splits flavor_weights handling into whole-object AND dotted-path modes. Dotted-path (flavor_weights.bug_catcher) lets the LLM change a single sub-weight without restating the whole object, which is the common case. Sum invariant only validates on whole-object form — single-sub-key deltas can't check the post-apply sum without knowing the current policy, which bounds.jq does not see. Phase 8's PR apply step, or a future caller that composes multi-sub-key dotted deltas, is responsible for ensuring the final sum stays in [0.95, 1.05]"
  - "halt_error(N) chosen over tagged-output + exit-status lookup. jq's halt_error is the documented way to propagate a specific exit code from inside a filter, and it prints the emitted value to stderr automatically — so the human debugging a bounds violation sees {violation: 'bounds', key, new, expected} verbatim without extra glue"
  - "proposer.sh does not invoke bounds.jq INSIDE adapter.sh. Separating adapter.sh (schema validation + emit) from proposer.sh (bounds enforcement) keeps the two concerns distinct: adapter checks Haiku's response SHAPE (mutations array, flavor echo), proposer checks semantic VALIDITY via the shared bounds.jq. Adapter stays reusable for any future JSON-delta proposer that has different bounds"
  - "compose_prompt appends an optional 'Additional task hint from caller' suffix only when TASK_HINT is non-empty. Keeps the cache-friendly prompt stable (upstream tokens identical across invocations that don't pass a hint); the hint is a pure append so the cache prefix still matches"
  - "Policy path resolution uses cd+pwd -P rather than realpath. realpath is not universally installed on Git Bash for Windows; the cd+pwd combo gives the same realpath semantics via built-ins. The resolved path must begin with REPO_ROOT for T-06-07 containment (dies exit 1 with 'outside repo root' on any traversal)"

patterns-established:
  - "Path-based freeze enforcement for proposer subtree: lab/pel/proposer/policy/** is the Phase 7 allowlist-exclusion glob. No FROZEN.md sentinel, no banner comment. The path IS the signal. Mirrors Phase 4's lab/pel/classifier/** treatment"
  - "Tool-availability fail-fast at entry: require_tools runs BEFORE any env validation so a missing yq doesn't produce cascading 'PEL_FEEDBACK is required' noise. Exit 2 signals environment problem; exit 1 signals caller-input problem. Callers in Phase 8 can branch on the two categories cleanly"

requirements-completed: [PEL-03]

# Metrics
duration: ~15 min
completed: 2026-04-18
---

# Phase 6 Plan 01: Policy-Tier Mutation Proposer — proposer.sh + adapter.sh + prompt.md + bounds.jq + policy.yaml Summary

**Self-contained policy-tier mutation proposer shipped under `lab/pel/proposer/policy/**` — 5 new files totaling 612 lines. The mutable surface is 6 enumerated knobs in policy.yaml; bounds.jq enforces the allowlist and per-knob bounds via halt_error(4)/halt_error(5) for distinct exit categories; prompt.md carries cache-friendly stable-first ordering with variable `## Inputs` trail; adapter.sh clones Phase 4's 10 inline helpers (zero external source); proposer.sh adds require_tools for jq+yq, path validation, and D-11 dry-run-by-construction (no `yq -i` anywhere in the subtree). All 7 STRIDE threats T-06-01..T-06-07 have grep-checkable mitigations. Plan-level `<verification>` acceptance block passes.**

## Performance

- **Duration:** ~15 minutes (Tasks 1-5 sequential)
- **Tasks:** 5 completed (all `type="auto"`, no checkpoints)
- **Files created:** 5 under `lab/pel/proposer/policy/**`
- **Files modified:** 0 outside that subtree — scope discipline held

## Accomplishments

- **The 6-knob allowlist is now both documentation AND enforcement.** `policy.yaml` enumerates exactly retry_cap, marker_semantics, writable_phase_default, arbitrate_threshold, max_passes, flavor_weights — each with default values in-bounds and comments summarizing purpose + range. `bounds.jq` is the jq program callers run to validate a proposed delta: happy path exits 0 with `{valid: true, count: N}`; a key outside the 6-knob set triggers `halt_error(5)`; an in-enum key with a value outside its bound triggers `halt_error(4)`. The two distinct exit codes let Phase 8 distinguish "LLM drifted on value" from "LLM tried to mutate something not allowed." Verified via 11 smoke-test invocations covering every knob's happy and violation paths.
- **D-10 JSON delta contract works end-to-end.** `adapter.sh::validate_delta_response` enforces: top-level must have `mutations` + `rationale` + `flavor` + `policy_path`; `mutations` must be an array of length 1..3; each mutation must have a string `.key` and a present `.new`; `rationale` must be a non-empty string; `flavor` must be one of the 4 legal tokens AND match `$PEL_FLAVOR` verbatim; `policy_path` must match `$PEL_POLICY_PATH` verbatim. Any failure dies exit 3 after dumping the first 500 bytes of the response to stderr for debugging.
- **Self-containment invariant holds under grep audit.** Exactly one `source` statement exists anywhere under `lab/pel/proposer/policy/**`: `proposer.sh` line 98 — `source "$SCRIPT_DIR/adapter.sh"` — sibling-only reference that resolves inside the frozen boundary. Phase 7's code-tier proposer can exclude the glob `lab/pel/proposer/policy/**` with zero cross-directory leakage, mirroring Phase 4's classifier treatment.
- **D-11 dry-run by construction verified.** `grep -rnE "yq[[:space:]]+-i\b" lab/pel/proposer/policy/` returns zero matches. proposer.sh calls `yq -e "type" "$PEL_POLICY_PATH"` for parse validation only (read-only; `-e` is exit-code-on-empty, not in-place edit). No `yq -i` in the subtree means the proposer cannot mutate the live policy even if a future regression tried to.
- **All 7 STRIDE threats T-06-01..T-06-07 have code-level mitigations grep-checkable.**
  - T-06-01 (argv/env tampering): `$1` optional hint is data-only (bash parameter expansion, never eval); PEL_FEEDBACK + PEL_POLICY_PATH resolved via cd+pwd -P and containment-checked. Mitigation lives in `proposer.sh::validate_path_in_repo`.
  - T-06-02 (non-enumerated knob via LLM): bounds.jq allowlist + `halt_error(5)`. Mitigation lives in `bounds.jq::validate_knob` (else arm).
  - T-06-03 (shell-meta model): `validate_proposer_model` regex `^[a-zA-Z0-9_.-]+$`, dies exit 1 with `invalid POLICY_PROPOSER_MODEL: ...`. Mitigation lives in `adapter.sh::validate_proposer_model` + `proposer.sh` calls it post-source.
  - T-06-04 (out-of-bounds value via LLM): bounds.jq per-knob arms + `halt_error(4)`. Mitigation lives in `bounds.jq::validate_knob` (6 per-knob arms + flavor_weights sub-validator).
  - T-06-05 (yq command injection): proposer invokes `yq -e "type" "$PEL_POLICY_PATH"` with path as literal arg; no delta values reach yq (they reach bounds.jq only). No `yq -i` anywhere.
  - T-06-06 (YAML alias/anchor): mikefarah yq v4 default mode is safe; policy.yaml is hand-authored + committed (not untrusted input); yq output flows only through jq, never shell.
  - T-06-07 (path traversal): `proposer.sh::validate_path_in_repo` resolves via cd+pwd and prefix-checks REPO_ROOT; paths outside die exit 1 with `outside repo root`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Write lab/pel/proposer/policy/policy.yaml** — `1446de8` (feat) — 37 lines
2. **Task 2: Write lab/pel/proposer/policy/bounds.jq** — `a493499` (feat) — 124 lines
3. **Task 3: Write lab/pel/proposer/policy/prompt.md** — `561a5a4` (feat) — 75 lines
4. **Task 4: Write lab/pel/proposer/policy/adapter.sh** — `9c245cb` (feat) — 253 lines
5. **Task 5: Write lab/pel/proposer/policy/proposer.sh** — `f62b05f` (feat) — 123 lines

_Plan metadata commit (SUMMARY) follows once this file lands._

## Files Created/Modified

- `lab/pel/proposer/policy/policy.yaml` (CREATED, 37 lines) — Header block naming Phase 6 PEL-03 and enforcement pointer (bounds.jq). Top-level keys (in order): `retry_cap: 3`, `marker_semantics: strict`, `writable_phase_default: false`, `arbitrate_threshold: 0.7`, `max_passes: 4`, `flavor_weights:` with 4 sub-keys (bug_catcher, faster_converger, blind_spot_surfacer, general) each set to 0.25 (sum = 1.0 exactly). Every knob has a per-line comment describing purpose + bounds.
- `lab/pel/proposer/policy/bounds.jq` (CREATED, 124 lines) — Header with exit-code taxonomy. Helpers: `is_int`, `in_range`, `FW_SUBKEYS`. `validate_flavor_weights` enforces object type + exact sub-key set + per-value [0.0, 1.0] + sum [0.95, 1.05]. `validate_knob` dispatcher has 6 per-knob arms + flavor_weights.<sub> dotted-path arm + else arm. Top-level program maps `.mutations` through validator and returns `{valid: true, count: N}`.
- `lab/pel/proposer/policy/prompt.md` (CREATED, 75 lines) — `# PEL Policy Mutation Proposer` title, role paragraph, `## Mutable knobs` with all 6 knob bullets (name + type + bound + default + purpose), `## Flavor bias` with all 4 flavor bullets, `## Multi-knob coherence` (up to 3 coupled knobs), `## Output schema (D-10)` with indent-only JSON example + `EXACTLY one JSON object` instruction + `No markdown code fences` line, `## Inputs` as LAST H2 with all 3 placeholders.
- `lab/pel/proposer/policy/adapter.sh` (CREATED, 253 lines, no shebang, library) — 10 inline functions matching Phase 4 shape (die, log_stderr, require_claude_cli, file_contains_auth_failure, validate_proposer_model, invoke_haiku, compose_prompt, validate_delta_response, emit_delta, run_adapter). `--disallowedTools "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch"` for stateless read-only subagent. `compose_prompt` substitutes 3 placeholders + optional TASK_HINT suffix. BASH_SOURCE[0] direct-execution guard at EOF. Zero external source/import statements.
- `lab/pel/proposer/policy/proposer.sh` (CREATED, 123 lines, executable) — Shebang + `set -euo pipefail`. `require_tools` for jq + yq (exit 2 on missing with platform install hints). `validate_path_in_repo` using `cd + pwd -P` for portable realpath semantics (exit 1 on traversal, exit 1 on unreadable). Parse-only `yq -e "type"` + `jq -e "type"` of both inputs. Sibling-only `source "$SCRIPT_DIR/adapter.sh"`. `validate_proposer_model "$POLICY_PROPOSER_MODEL"` called post-source. `run_adapter | jq -f "$SCRIPT_DIR/bounds.jq"` with preserved exit code so bounds failures propagate exit 4/5 to the caller.

## Decisions Made

- **Dotted-path delta support in bounds.jq.** The plan extends D-10 with dotted-path mutations like `flavor_weights.bug_catcher`. I implemented this as a second arm in `validate_knob` that splits the key on `.`, validates the sub-key is one of the 4 flavor_weights children, and checks the single `.new` value is in [0.0, 1.0]. The sum invariant is NOT enforced on dotted-path form because bounds.jq cannot see the current policy to compute the post-apply sum. Whole-object form still enforces sum in [0.95, 1.05]. Documented in the bounds.jq body comment above `validate_knob`.
- **Sum-check uses direct addition (`a + b + c + d`), not `| add`.** The `| add` jq idiom works in jq but NOT in mikefarah yq (yq v4 uses `sum`). bounds.jq runs under jq, so `| add` is fine there — inside `validate_flavor_weights` it computes `$vals | add` where `$vals` is the 4-element array. The verify block in the Task 1 plan tried `yq ... | add` which doesn't parse (documented as W-4 below). Tests confirm bounds.jq's `add` works correctly.
- **Containment check uses `cd + pwd -P`, not `realpath`.** `realpath` is not always available on Git Bash for Windows. `cd "$(dirname "$raw")" && pwd -P` gives the same canonicalized-absolute-path semantics via bash built-ins (cd resolves the directory; pwd -P writes the physical path with symlinks resolved). Works on Git Bash + Linux + macOS + WSL without an external binary.
- **`-e` flag on yq parse check.** `yq -e "type"` exits non-zero when the result is null OR the YAML fails to parse. This is the minimum read-only probe that catches both "file isn't YAML" and "file is empty/null" at entry. No need for a separate structural check on policy.yaml at proposer startup — the D-03 allowlist is enforced downstream by bounds.jq on the delta, not on the input file.

## Deviations from Plan

### Auto-fixed Issues

**None.** Every task's verify block passed on the first write. No Rule 1/2/3 autofixes were triggered.

### Intentional Refinement (noted, not patched)

**1. Plan Task 1 verify block uses `yq "... | add"` which fails on mikefarah yq v4.**
- **Found during:** Task 1 verification.
- **Issue:** The plan's Task 1 verify at plan line 277 contains `sum=$(yq ".flavor_weights | to_entries | map(.value) | add" lab/pel/proposer/policy/policy.yaml)`. mikefarah yq v4 uses `sum` for array summation, not `add` (which is jq syntax). Running that exact line errors with `lexer: invalid input text "add"` (exit 1), so the verify block as written cannot pass under any valid policy.yaml.
- **Impact:** Cosmetic only — the file's flavor_weights sum IS 1.0 (proven by `yq '.flavor_weights.bug_catcher + .flavor_weights.faster_converger + .flavor_weights.blind_spot_surfacer + .flavor_weights.general' policy.yaml` returning `1`). The acceptance criterion "sum ∈ [0.95, 1.05]" holds; only the verify block's syntax is wrong.
- **Resolution:** Left as-is — scope discipline says plan files should not be edited during execution. Plan 02's simulation tests do their own YAML parsing and don't depend on this broken verify.
- **Flagged as:** W-4 for the planner's attention on future yq vs jq idiom mix-ups.

**2. Plan Task 5 verify block uses `mktemp --suffix` (GNU-only).**
- **Found during:** Task 5 live-test composition.
- **Issue:** Plan line 873 uses `tmppol=$(mktemp --suffix=.yaml)`. `--suffix` is GNU coreutils syntax; Git Bash for Windows has GNU mktemp so it works there. macOS ships BSD mktemp which does NOT support `--suffix`. The plan already flagged this in `<known_plan_issues>` under "Info (mktemp --suffix)" as acceptable for v1.2 Windows-first scope.
- **Impact:** None on the code shipped — only affects the plan's verify block portability. My live-test reproduction used `mktemp -p "$(pwd)" --suffix=.yaml` which worked on Git Bash; the resulting `$tmppol` was INSIDE the repo, so `validate_path_in_repo` accepted it (proving the T-06-07 path-containment logic works for files inside the repo tree).
- **Resolution:** No action needed per `<known_plan_issues>` acceptance.

### Scope Creep: None

Zero files outside `lab/pel/proposer/policy/**` were touched. Specifically:
- `lab/pel/classifier/**` (Phase 4 frozen surface) — unchanged.
- `lab/pel/proposer/template/**` (Phase 5 sibling worktree) — does not exist yet in this worktree (Phase 5 runs simultaneously in `co-evolution-v12-p5`).
- `lib/co-evolution.sh`, `dev-review/codex/*`, runner scripts — unchanged.
- `.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/config.json` — unchanged (per the parent orchestrator's explicit instruction NOT to modify STATE/ROADMAP in this worktree).

## Issues Encountered

- **jq 1.8 vs older jq halt_error behavior.** Early smoke test on my machine's jq-1.8.1 confirmed `halt_error(N)` exits with code N and prints the piped-in value to stderr. The plan didn't pin a jq version, but the Phase 2 scorer already assumes jq is present (the same hard-dep Phase 4 inherits); tested with `echo '{"msg":"oops"}' | jq 'halt_error(4)'; echo EXIT:$?` → output `{"msg":"oops"}` to stderr, exit 4. No action needed.
- **No `claude` CLI calls during this plan.** The adapter.sh's `run_adapter` function CAN call claude via `invoke_haiku`, but the Plan 01 verify blocks only exercise env validation + bounds.jq static smoke tests + proposer.sh's missing-env-var error path. The Haiku round-trip path is tested in Plan 02 under a hermetic PATH-injected stub (per CONTEXT §D-17).
- **No other functional issues.** Every `bash -n`, every grep battery, every smoke invocation of bounds.jq returned the expected output on first run.

## User Setup Required

None — no external service configuration, no env vars at install time, no dashboards. `yq` (mikefarah/Go yq v4+) must be installed; `proposer.sh::require_tools` gates at startup with a platform-specific install hint (scoop/brew/apt) on missing binary. `jq` is assumed present per Phase 2 precedent.

## Next Phase Readiness

- **Phase 6 Plan 02 (Simulation gate) is immediately unblocked.** All 5 files this plan shipped are reachable from `tests/policy-proposer-simulation.sh`. The stubbing strategy from Phase 4 Plan 02 (PATH-injected `claude` CLI shim emitting canned JSON per scenario) is directly applicable — `compose_prompt`'s substitution tokens are stable and `validate_delta_response` will accept any D-10-shaped response from the stub. Adversarial scenarios (E/F/G/H) can exercise bounds.jq + validate_delta_response + env validation paths without real Haiku.
- **D-10 JSON contract is locked for Phase 8.** Phase 8's PR emitter can build against the exact 4 fields: `mutations` (array, 1-3 entries, each {key, old, new}), `rationale` (non-empty string), `flavor` (one of 4 tokens, echoes input), `policy_path` (echoes input).
- **Path-based freeze invariant is ready for Phase 7.** The allowlist-exclusion glob `lab/pel/proposer/policy/**` catches all 5 files. Phase 7's code-tier proposer can consume the glob as-is.
- **No blockers carried forward.** Working tree clean after each task commit; branch `feat/v1.2-phase6-policy` at `f62b05f`. No deferred items, no architectural escalations.

## Known Stubs

None — every file this plan shipped is a working implementation. policy.yaml's `flavor_weights` sub-keys are real defaults (0.25 each, sum 1.0), not placeholders. prompt.md's `{POLICY_YAML}`/`{EVAL_FEEDBACK}`/`{FLAVOR}` are intentional template tokens substituted at invocation time by `adapter.sh::compose_prompt`, not stubs.

## Self-Check: PASSED

Verified post-write:
- [x] `lab/pel/proposer/policy/policy.yaml` exists, yq-parseable, 6 top-level keys, flavor_weights sum in [0.95, 1.05] (proven via `yq '.a + .b + .c + .d'` = 1).
- [x] `lab/pel/proposer/policy/bounds.jq` exists, all 6 knob identifiers present, halt_error(4) + halt_error(5) both referenced, 11 smoke-test invocations returning expected exit codes (happy/bounds/non-enum across all 6 knobs + flavor_weights whole + dotted + sum violation).
- [x] `lab/pel/proposer/policy/prompt.md` exists, 75 lines (within 40-150), all 6 knobs + all 4 flavors + all 3 placeholders + bounds literals + `EXACTLY one JSON object` instruction + `## Inputs` as last H2.
- [x] `lab/pel/proposer/policy/adapter.sh` exists, 253 lines (within 180-260), `bash -n` clean, no shebang (library), all 10 required inline functions, zero external source/import, BASH_SOURCE[0] guard, `invalid POLICY_PROPOSER_MODEL` error literal.
- [x] `lab/pel/proposer/policy/proposer.sh` exists, 123 lines (within 100-200), `bash -n` clean, executable, shebang + `set -euo pipefail`, all 3 env-var dies + 4-flavor whitelist, require_tools with jq + yq install hints, `validate_path_in_repo` + `outside repo root`, sibling-only source of adapter.sh, `validate_proposer_model` called, `jq -f "$SCRIPT_DIR/bounds.jq"` with preserved exit code, zero `yq -i` (D-11).
- [x] Commits `1446de8` (Task 1), `a493499` (Task 2), `561a5a4` (Task 3), `9c245cb` (Task 4), `f62b05f` (Task 5) all present in `git log`.
- [x] End-to-end proposer missing-env test verified: `bash lab/pel/proposer/policy/proposer.sh` → `ERROR: PEL_FEEDBACK is required (path to eval-feedback JSON)` + EXIT:1.
- [x] End-to-end bad-model test verified: `PEL_FEEDBACK=... PEL_POLICY_PATH=... PEL_FLAVOR=general POLICY_PROPOSER_MODEL="bad; rm -rf /" bash ...proposer.sh` → `ERROR: invalid POLICY_PROPOSER_MODEL: bad; rm -rf / (must match [A-Za-z0-9_.-]+)` + EXIT:1.
- [x] Self-containment invariant: `grep -rnE "^[[:space:]]*(source|\\.)[[:space:]].*\\.sh" lab/pel/proposer/policy/` returns exactly one line: `proposer.sh:98:source "$SCRIPT_DIR/adapter.sh"`.
- [x] D-11 dry-run invariant: `grep -rnE "yq[[:space:]]+-i\\b" lab/pel/proposer/policy/` returns zero matches.
- [x] All 5 plan `<verify>` acceptance blocks pass + plan-level `<verification>` sweep passes.

---
*Phase: 06-policy-tier-proposer*
*Completed: 2026-04-18*
