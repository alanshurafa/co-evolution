# The PEL lab inhabitant

`lab/pel/` hosts the v1.2 Protocol Evolution Loop (PEL) proposer machinery. Phase 4
ships the **mode classifier** under `lab/pel/classifier/` — a frozen decision layer
that picks one of four fitness flavors (`bug-catcher`, `faster-converger`,
`blind-spot-surfacer`, `general`) per PEL invocation, emits transparent rationale,
and honors user overrides. The classifier is FROZEN in v1.2: its code, prompt,
and env var contract do not mutate. Phase 7's code-tier proposer excludes
`lab/pel/classifier/**` from its mutable-file allowlist (see `## Frozen surface`).

Phases 5-8 add template-tier, policy-tier, and code-tier proposers plus a PR emitter
— all under `lab/pel/` siblings — that consume this classifier's output. Phase 5
ships the **template-tier proposer** under `lab/pel/proposer/template/` — an Opus-4.7
mutation proposer that emits a single-file unified diff against one
`skills/dev-review/templates/*.md` file per invocation (see `## Template-tier proposer (v1.2)`).
Phase 7 ships the **code-tier proposer** under `lab/pel/proposer/code/` — an
Opus-4.7 mutation proposer targeting executable shell scripts with sandbox
isolation, canary smoke-test, and diff budget + allowlist enforcement (see
`## Code-tier proposer (v1.2)`). The classifier itself remains reachable directly
via `bash lab/pel/classifier/classifier.sh` for debugging and for the Phase 4
Plan 02 simulation test.

## Env-var contract (v1.2)

Callers (future Phases 5-8 proposers) MUST `export` the PEL_* variables explicitly
before invoking the classifier. **Never inherit from the user's shell.** A developer
running the classifier manually from a shell that happens to have
`PEL_BOUNCE_STEP=compose` left set will otherwise get stale context silently — the
classifier has no way to distinguish "caller intended this" from "residual
stickiness from the last session."

| Env var | Value domain | Default | Purpose |
|---------|--------------|---------|---------|
| `PEL_BOUNCE_STEP` | `compose`, `bounce`, `execute`, `verify`, `unknown` | `unknown` | Which step within a dev-review bounce this classification serves (specializes WITHIN a dev-review run) |
| `PEL_PHASE_TYPE` | `scoping`, `implementation`, `verification`, `unknown` | `unknown` | Which GSD phase type is active (specializes BETWEEN dev-review invocations) |
| `PEL_FLAVOR_OVERRIDE` | (optional) `bug-catcher`, `faster-converger`, `blind-spot-surfacer`, `general` | unset | Force a flavor pick, bypassing Haiku entirely |
| `CLASSIFIER_MODEL` | claude model ID matching `^[a-zA-Z0-9_.-]+$` | `claude-haiku-4-5-20251001` | Haiku model to invoke; override for debugging only |

**Unknown / missing context degrades gracefully.** Unset env vars default to
`unknown`; unexpected values emit a `WARNING: unexpected <var> value ..., treating
as unknown` to stderr and degrade to `unknown` rather than aborting the
classification. This aligns with the broader design distinction: structural-contract
violations die (invalid override token, missing task arg, shell metacharacters in
model ID), caller-input misspellings degrade.

## Output contract

Successful classification emits a single JSON object to stdout:

```json
{
  "flavor": "bug-catcher",
  "rationale": "one-to-three-sentence explanation of why this flavor",
  "override": false,
  "model": "claude-haiku-4-5-20251001",
  "inputs": {
    "task": "...",
    "bounce_step": "compose",
    "phase_type": "scoping"
  }
}
```

All diagnostic output (warnings, CLI progress, auth hints, errors) routes to
stderr. **stdout is pure JSON** — Phase 8's PR-body emitter will parse exactly
these fields.

Exit codes (fail-fast):

| Code | Meaning |
|------|---------|
| 0 | Success — JSON emitted |
| 1 | Input validation failure (bad `PEL_FLAVOR_OVERRIDE`, bad `CLASSIFIER_MODEL`, missing task arg) |
| 2 | `claude` CLI missing / auth failure / Haiku call non-zero |
| 3 | Malformed Haiku response (non-JSON, missing fields, invalid flavor value) |

Exit codes are load-bearing for callers — Phase 8's proposer will branch on
them to decide whether a classifier failure aborts the whole PEL run or falls
back to a documented default flavor. The classifier itself never masks signal
with silent fallbacks.

## Override mechanism

`PEL_FLAVOR_OVERRIDE=<flavor>` causes the classifier to emit the override flavor
directly without calling Haiku. The resulting JSON has `override: true` and
`rationale: "user override via PEL_FLAVOR_OVERRIDE"`. No Haiku call is made and
no network traffic is emitted — the override IS the trust signal.

Valid override values are exactly the four flavor tokens: `bug-catcher`,
`faster-converger`, `blind-spot-surfacer`, `general`. Invalid values die with
exit code 1 and message `invalid PEL_FLAVOR_OVERRIDE: <value>`.

Phase 8 will wire a user-facing override knob on `co-evolve --lab pel-proposer` that
sets `PEL_FLAVOR_OVERRIDE` before invoking this classifier. Phase 4 only commits
to accepting the env-var signal; the caller-level CLI surface lives one layer up.

## CLASSIFIER_MODEL escape hatch

`CLASSIFIER_MODEL` overrides the default Haiku 4.5 model ID. Use cases:

- **Debugging:** set `CLASSIFIER_MODEL=claude-opus-4-7` temporarily to compare
  Haiku vs Opus picks on a known task. The output JSON echoes back the model
  used in the `model` field so the caller always knows what answered.
- **Future model upgrades:** a new Haiku revision can be drop-in tested without
  editing `adapter.sh`. Once validated, update the default in the script.

The value is validated against `^[a-zA-Z0-9_.-]+$` before being passed to
`claude --model`. Shell metacharacters are rejected with exit 1 and the
message `invalid CLASSIFIER_MODEL: <value> (must match [A-Za-z0-9_.-]+)`.

**This is an escape hatch, not an everyday knob.** The classifier contract is
frozen in v1.2; a dedicated model-selection CLI surface is deferred to v1.3+
ergonomics.

## Frozen surface

`lab/pel/classifier/**` is FROZEN in v1.2. This is a path-based invariant,
not a banner comment. Phase 7's code-tier mutation proposer excludes the
glob `lab/pel/classifier/**` from its mutable-file allowlist. Comments can
be edited accidentally during refactors; a path-based allowlist cannot be
silently bypassed — the allowlist IS the enforcement mechanism.

**Why frozen:** attribution muddiness. If PEL is simultaneously evolving the
protocol AND the classifier that picks fitness flavors, it becomes impossible
to tell whether an eval-score improvement came from a better protocol or a
classifier that learned to pick whichever mode makes the current mutation
look good (Goodhart-adjacent). Freezing the classifier gives Phases 5-7 a
clean signal: the protocol changed, the flavor logic didn't.

Classifier evolution (PEL-META-01) is v1.3+. See
`.planning/notes/pel-design-decisions.md` §"Open risks" for the full
attribution argument.

## Invocation

Direct invocation (used by the Plan 02 simulation test at `tests/classifier-simulation.sh`
and by the future Phase 8 proposer entry point when it ships):

```bash
export PEL_BOUNCE_STEP=compose
export PEL_PHASE_TYPE=scoping
# Optional override:
# export PEL_FLAVOR_OVERRIDE=bug-catcher

bash lab/pel/classifier/classifier.sh "the task description as a single argv slot"
```

Output: single JSON object to stdout, warnings + progress to stderr.

Files involved:

- `lab/pel/classifier/classifier.sh` — public entry point (argv contract + env validation + override fast-path)
- `lab/pel/classifier/adapter.sh` — self-contained Haiku adapter (prompt composition + claude CLI invocation + JSON validation)
- `lab/pel/classifier/prompt.md` — frozen Haiku prompt (4 flavor defs + output schema; prompt-cache-friendly ordering)

All three live under `lab/pel/classifier/**` — the Phase 7 allowlist-exclusion
glob referenced in `## Frozen surface`.

## Template-tier proposer (v1.2)

Phase 5 adds `lab/pel/proposer/template/` — the template-tier mutation proposer.
A self-contained Opus-4.7 module that consumes a Phase-2-scorer JSON report plus
a target template path plus a classifier flavor pick, and emits a unified diff
targeting EXACTLY ONE `skills/dev-review/templates/*.md` file. Phase 8's PR
emitter calls this proposer internally; end users do not invoke it directly in
v1.2 (an optional manual invocation for debugging is documented below).

The proposer is self-contained per D-05: the only source statement in
`lab/pel/proposer/template/**` is `proposer.sh`'s sibling-only
`source "$SCRIPT_DIR/adapter.sh"`. Zero imports reach into
`lib/co-evolution.sh`, `lab/pel/classifier/**`, or runner internals.

### Env-var contract

Callers MUST set all three required env vars explicitly — unlike the classifier's
warn-don't-die posture, the template-tier proposer requires complete inputs and
dies exit 1 on any missing piece.

| Env var | Value domain | Default | Purpose |
|---------|--------------|---------|---------|
| `PEL_EVAL_REPORT` | readable path to a Phase-2-scorer JSON report (inside REPO_ROOT) | unset — REQUIRED | Eval-failure report that drives mutation targeting |
| `PEL_TEMPLATE_PATH` | readable `.md` file under `skills/dev-review/templates/` OR `tests/fixtures/templates/` | unset — REQUIRED | Template file to mutate (Phase 5 single-file constraint) |
| `PEL_FLAVOR` | `bug-catcher`, `faster-converger`, `blind-spot-surfacer`, `general` | unset — REQUIRED | Classifier flavor pick that biases mutation direction |
| `PROPOSER_MODEL` | claude model ID matching `^[a-zA-Z0-9_.-]+$` | `claude-opus-4-7` | Opus model to invoke; override for debugging only |

**Input strictness (D-03).** Missing or unreadable `PEL_EVAL_REPORT` /
`PEL_TEMPLATE_PATH` / `PEL_FLAVOR` die exit 1 with a specific message. Rationale:
the proposer is called internally by Phase 8's scoring loop, which always
provides all three — missing means the caller has a bug, not a user-shell
residue to degrade past.

**Optional task hint via `$1`.** The proposer accepts one optional positional
argument: a free-form task hint that biases mutation direction. Empty string is
allowed per D-04. When a hint is provided, it is a COARSE bias to the LLM, never
an override of the flavor pick. If the hint contradicts the flavor, the flavor
wins.

### Output contract

Stdout is a single well-formed unified diff with `---` / `+++` / `@@` headers
that passes `git apply --check` at REPO_ROOT. Stderr carries all diagnostics.

Example shape the proposer emits (indented, not fenced, so the README renders
cleanly when the diff is piped through a pretty-printer):

    --- a/skills/dev-review/templates/bounce-protocol.md
    +++ b/skills/dev-review/templates/bounce-protocol.md
    @@ -10,7 +10,9 @@
     Convergence:
     - If there are zero [CONTESTED] and zero [CLARIFY] notes remaining, the plan has converged. Focus on polish only.
     - If this is the final pass, you MUST resolve every remaining note and MUST NOT introduce new unresolved notes.
    +- Bug-catcher bias: before declaring convergence, enumerate at least one
    +  adversarial case the current plan does not address.

### Single-file invariant (D-09)

After Opus returns, the proposer parses the emitted diff's `---` / `+++`
headers and rejects with exit 4 any diff that touches more than one file OR
targets anything outside `skills/dev-review/templates/` and
`tests/fixtures/templates/` (the hermetic-testing alias per D-14). This is
belt-and-suspenders: the prompt instructs single-file, but the code check
catches prompt drift.

### Applyability invariant (D-10)

Before emitting the diff to stdout, the proposer runs
`printf '%s' "$diff" | git apply --check -` inside REPO_ROOT. If the dry-run
fails, the proposer dies exit 3 with a captured stderr snippet for debugging.
Phase 8's scoring loop gets either a guaranteed-applyable diff or a clean error.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success — unified diff emitted to stdout |
| 1 | Input validation failure (missing env var, invalid `PEL_FLAVOR`, invalid `PROPOSER_MODEL`, path traversal, out-of-prefix `PEL_TEMPLATE_PATH`) |
| 2 | `claude` CLI missing / auth failure / Opus call non-zero / empty response |
| 3 | Malformed diff — does not apply cleanly via `git apply --check` (D-10) |
| 4 | Single-file constraint violation — diff touches more than one file OR a non-template file (D-09) |

Exit codes are load-bearing for Phase 8's scoring loop: 1 = fix your invocation;
2 = retry after clearing the external issue; 3 / 4 = the proposer produced a
bad diff (log + move on, don't retry with the same inputs).

### PROPOSER_MODEL escape hatch

`PROPOSER_MODEL` overrides the default Opus 4.7 model ID. The value is validated
against `^[a-zA-Z0-9_.-]+$` before being passed to `claude --model` — shell
metacharacters are rejected with exit 1 and the message
`invalid PROPOSER_MODEL: <value> (must match [A-Za-z0-9_.-]+)`.

This is an escape hatch for debugging (swap in a cheaper or newer model for
benchmarking), not an everyday knob. Same posture as the classifier's
`CLASSIFIER_MODEL` escape hatch — a dedicated CLI flag is deferred to v1.3+
ergonomics.

### Invocation

Direct invocation (used by the Plan 02 simulation test at
`tests/template-proposer-simulation.sh` and by Phase 8's PR emitter in
production):

```bash
export PEL_EVAL_REPORT=$PWD/evals/reports/20260418-120000/scores.json
export PEL_TEMPLATE_PATH=skills/dev-review/templates/bounce-protocol.md
export PEL_FLAVOR=bug-catcher

bash lab/pel/proposer/template/proposer.sh "focus mutation on the bounce pass" \
  | git apply --stat -   # inspect the proposed mutation shape
```

Output: single unified diff to stdout, diagnostics to stderr.

Files involved:

- `lab/pel/proposer/template/proposer.sh` — public entry point (argv + env validation, path sandboxing, D-09/D-10 gates)
- `lab/pel/proposer/template/adapter.sh` — self-contained Opus adapter (prompt composition + claude CLI invocation + diff capture)
- `lab/pel/proposer/template/prompt.md` — mutation-proposer prompt (4 flavor bias riders + strict unified-diff output schema; prompt-cache-friendly ordering)

All three live under `lab/pel/proposer/template/**` — this is the Phase 7
allowlist-exclusion glob for the template-tier proposer.

## Policy proposer (Phase 6 PEL-03)

`lab/pel/proposer/policy/` is the **policy-tier mutation proposer** — Phase 6's
inhabitant. Given eval-failure feedback + a target policy YAML + a flavor pick,
it emits a **JSON delta** describing proposed mutations to `policy.yaml`. It does
NOT apply the delta (D-11 dry-run by construction); Phase 8's PR emitter applies
via `yq` after human review.

### Env-var contract

Callers MUST export these before invoking `bash lab/pel/proposer/policy/proposer.sh`:

| Env var | Value domain | Required | Purpose |
|---------|--------------|----------|---------|
| `PEL_FEEDBACK` | path to eval-failure JSON (readable file within repo) | yes (D-06) | Signal driving the mutation — e.g. `tests/fixtures/policy-feedback/retry-failure.json` |
| `PEL_POLICY_PATH` | path to target policy YAML (readable file within repo) | yes (D-06) | The file the proposed delta targets; typically `lab/pel/proposer/policy/policy.yaml` |
| `PEL_FLAVOR` | one of `bug-catcher`, `faster-converger`, `blind-spot-surfacer`, `general` | yes (D-06) | Classifier pick (normally fed by Phase 4's classifier JSON `.flavor` field) |
| `POLICY_PROPOSER_MODEL` | claude model ID matching `^[a-zA-Z0-9_.-]+$` | no (default `claude-haiku-4-5-20251001`) | Model override for debugging |

Task string via `$1` is optional — if passed, used as an additional hint. Empty
is legal. Single-argv slot per W-3 (`lab/README.md` §How to add).

### Output contract (D-10)

Successful invocation emits a single JSON delta object on stdout:

```json
{
  "mutations": [
    {"key": "retry_cap", "old": 3, "new": 5}
  ],
  "rationale": "eval feedback shows transient failures; raising retry cap",
  "flavor": "faster-converger",
  "policy_path": "lab/pel/proposer/policy/policy.yaml"
}
```

- `mutations[]` has 1-3 entries.
- Each `.key` is one of the 6 enumerated knobs from `policy.yaml` (validated by `bounds.jq`).
- Each `.new` value is within the knob's documented bound (also validated by `bounds.jq`).
- `.flavor` echoes the input `PEL_FLAVOR` verbatim.
- `.policy_path` echoes the input `PEL_POLICY_PATH` verbatim.

All diagnostics route to stderr; stdout stays pure JSON.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success — delta emitted |
| 1 | Input validation failure (missing env var, bad flavor token, shell-meta model, path traversal) |
| 2 | `claude` CLI missing / `jq` missing / `yq` missing / auth failure / Haiku call non-zero |
| 3 | Malformed response from Haiku (non-JSON, missing required fields) |
| 4 | bounds violation in proposed delta (`bounds.jq halt_error(4)`) — legal knob, illegal value |
| 5 | non-enumerated knob in proposed delta (`bounds.jq halt_error(5)`) — knob key not in D-03 allowlist |

Exit codes 4 (bounds violation) and 5 (non-enumerated knob) are distinct so Phase 8's
PR emitter can tell the difference between "LLM drifted on value" and "LLM tried
to mutate something not allowed."

### Mutable knobs (v1.2 frozen enumeration)

The 6 knobs in `lab/pel/proposer/policy/policy.yaml` are the ONLY fields the
proposer may mutate. `bounds.jq` enforces the enumeration AND bounds:

| Knob | Type | Bounds | Default |
|------|------|--------|---------|
| `retry_cap` | integer | [0, 10] | 3 |
| `marker_semantics` | enum | `strict` or `lax` | `strict` |
| `writable_phase_default` | boolean | `true` or `false` | `false` |
| `arbitrate_threshold` | float | [0.0, 1.0] | 0.7 |
| `max_passes` | integer | [1, 10] | 4 |
| `flavor_weights` | object | each sub-value in [0.0, 1.0], sum in [0.95, 1.05] | 0.25 each |

Adding new knobs is a new phase (bounds review, test coverage, prompt update).

### Dry-run by construction (D-11)

The proposer emits a delta; it NEVER modifies the live `policy.yaml`. This is
architectural, not policy — the proposer has zero `yq -i` invocations in its
code (verified by grep in `tests/policy-proposer-simulation.sh`). Applying the
delta is Phase 8's problem and always happens via PR review.

Humans may hand-edit `policy.yaml` between PEL runs. Both mechanisms coexist —
hand edits and PEL-proposed deltas land through the same PR review gate.

### Invocation example

```bash
export PEL_FEEDBACK=tests/fixtures/policy-feedback/retry-failure.json
export PEL_POLICY_PATH=lab/pel/proposer/policy/policy.yaml
export PEL_FLAVOR=bug-catcher

bash lab/pel/proposer/policy/proposer.sh "optional task hint"
```

### Files involved

- `lab/pel/proposer/policy/proposer.sh` — public entry (env validation, require_tools jq+yq, bounds enforcement)
- `lab/pel/proposer/policy/adapter.sh` — self-contained Haiku adapter (D-05)
- `lab/pel/proposer/policy/prompt.md` — frozen mutation prompt with flavor-bias guidance (D-15, D-16)
- `lab/pel/proposer/policy/policy.yaml` — the mutable 6-knob surface (D-03)
- `lab/pel/proposer/policy/bounds.jq` — single-source-of-truth bounds validator (D-13)

### Simulation gate

`tests/policy-proposer-simulation.sh` exercises all 8 SC-4 scenarios (4 flavor
paths + 4 adversarial rejections) hermetically via a PATH-injected stub `claude`
CLI. Final line `8/8 scenarios passed` on a clean proposer surface.

## Code-tier proposer (v1.2)

Phase 7 adds `lab/pel/proposer/code/` — the **code-tier mutation proposer**. The
hardest of the three proposer tiers because mutations target executable shell
code, not text templates or YAML config. A bad template mutation produces a
bad template; a bad policy mutation produces a bad knob value; a bad code
mutation breaks the runner itself. Phase 7 therefore ships three capabilities
absent from Phases 5/6:

1. **Sandbox isolation** — mutation applied in a `git worktree`, never the
   live checkout.
2. **Canary smoke-test suite** — runs AFTER mutation, BEFORE eval scoring;
   rejects broken runners at 5 scenarios.
3. **Diff budget + file allowlist** — caps blast radius; prevents mutation
   of frozen or protected paths.

The proposer is self-contained per D-12: the only source statement in
`lab/pel/proposer/code/**` is `proposer.sh`'s sibling-only
`source "$SCRIPT_DIR/adapter.sh"`. Zero imports reach into `lib/co-evolution.sh`,
`lab/pel/classifier/**`, `lab/pel/proposer/template/**`,
`lab/pel/proposer/policy/**`, or runner internals.

### Env-var contract

Callers MUST set all three required env vars explicitly — same die-on-missing
posture as template-tier and policy-tier. Missing inputs die exit 1.

| Env var | Value domain | Default | Purpose |
|---------|--------------|---------|---------|
| `PEL_CODE_FEEDBACK` | readable path to a Phase-2-scorer JSON report (inside REPO_ROOT) | unset — REQUIRED | Eval-failure report that drives mutation targeting |
| `PEL_CODE_TARGET` | relative path on `lab/pel/proposer/code/allowlist.txt` | unset — REQUIRED | Shell file to mutate (single-file constraint; only the 3 allowlisted paths) |
| `PEL_FLAVOR` | `bug-catcher`, `faster-converger`, `blind-spot-surfacer`, `general` | unset — REQUIRED | Classifier flavor pick that biases mutation direction |
| `CODE_PROPOSER_MODEL` | claude model ID matching `^[a-zA-Z0-9_.-]+$` | `claude-opus-4-7` | Opus model to invoke; override for debugging only |
| `DIFF_BUDGET` | positive integer (lines changed cap) | `20` | Per D-06 budget; mutations exceeding this die exit 6 |

**Input strictness (D-17).** Missing or unreadable `PEL_CODE_FEEDBACK` /
`PEL_CODE_TARGET` / `PEL_FLAVOR` die exit 1 with a specific message. Rationale:
the proposer is called internally by Phase 8's scoring loop, which always
provides all three — missing means the caller has a bug, not a user-shell
residue to degrade past.

**Optional task hint via `$1`.** The proposer accepts one optional positional
argument: a free-form task hint that biases mutation direction. Empty string is
allowed per D-18. When a hint is provided, it is a COARSE bias to the LLM, never
an override of the flavor pick. If the hint contradicts the flavor, the flavor
wins.

### Allowlist (D-04)

`lab/pel/proposer/code/allowlist.txt` enumerates the mutable surface. v1.2
ships exactly 3 paths:

    lib/co-evolution.sh
    dev-review/codex/dev-review.sh
    agent-bouncer/agent-bouncer.sh

Adding new files to the mutable surface is a deliberate act (edit the
allowlist file, commit, review). The allowlist IS the frozen-surface
enforcement mechanism — `lab/pel/classifier/**`, `.planning/**`, `tests/**`,
`.gitignore` are excluded by absence, not by a denylist. Each target is
validated via `grep -Fxq` for exact-line match; trailing slashes, absolute
forms, or `../` relative paths all fail the gate.

### Diff budget (D-06)

Default `DIFF_BUDGET=20`. Counts lines starting with `+` or `-` in the diff
body, EXCLUDING `---`, `+++`, and `@@` hunk headers. A rewrite counts as
2 (one `-` + one `+`). The budget is checked BEFORE sandbox creation, so an
oversized diff never triggers the expensive `git worktree add` + canary
cycle. Exceeding the budget dies exit 6.

### Output contract

Stdout is a single well-formed unified diff with `---` / `+++` / `@@` headers
that passed pre-flight gates AND canary. Stderr carries all diagnostics.

Example shape the proposer emits (indented, not fenced, so the README renders
cleanly when the diff is piped through a pretty-printer):

    --- a/lib/co-evolution.sh
    +++ b/lib/co-evolution.sh
    @@ -42,6 +42,8 @@
     validate_lab_mode() {
       local mode="$1"
    +  # Validate that mode name contains only allowed characters
    +  [[ "$mode" =~ ^[a-zA-Z0-9_-]+$ ]] || { log "ERROR: invalid mode name: $mode"; return 1; }
       case "$mode" in

### Sandbox isolation (D-01, D-02, D-03)

The mutation is applied inside a `git worktree` at
`$TMPDIR/pel-code-sandbox-XXXXXX`, not the live checkout. The live repo is
never `cd`'d into for mutation purposes. Sandbox lifecycle:

1. `SANDBOX_PATH=$(mktemp -d ...)` then `rmdir` (git worktree wants a
   non-existent target).
2. `git -C REPO_ROOT worktree add --detach "$SANDBOX_PATH" HEAD` — creates a
   detached-HEAD worktree from current state. Failure → exit 8.
3. `git apply` the diff inside the sandbox (`cd` into sandbox first).
4. Run `canary.sh "$SANDBOX_PATH"` — failure → exit 7 with state.json set.
5. Write `state.json` to the sandbox root.
6. Emit diff to stdout.
7. Trap EXIT cleans up via `git worktree remove --force` + `rm -rf` (defense
   in depth; either on its own is insufficient).

### Canary smoke-test suite (D-08, D-09, D-10)

`canary.sh` runs 5 scenarios sequentially inside the sandbox. PATH-injected
stub `claude` and `codex` binaries shadow the real CLIs so no network calls
happen during canary. Any scenario failure aborts the canary with a distinct
exit code 1-5; proposer translates to exit 7.

| Scenario | Canary exit | What it checks |
|----------|-------------|----------------|
| source-survives | 1 | `bash -n lib/co-evolution.sh` + `source lib/co-evolution.sh` |
| helper-signatures | 2 | grep for 4 function defs (`validate_lab_mode`, `dispatch_lab_mode`, `phase_is_writable`, `list_available_lab_modes`) |
| agent-bounce | 3 | `agent-bouncer.sh` e2e with stub agents |
| dev-review-plan-only | 4 | `dev-review.sh --plan-only` with stub agents |
| one-eval-case | 5 | simplest eval fixture present + `bash -n` of eval harness scripts |

The canary's job is "did the runner survive?", not "did scores improve?" —
full eval scoring is Phase 8's responsibility. Final success line is
`canary: 5/5 scenarios passed` to stderr.

### Pre-flight gate order (D-07)

After the LLM emits a diff and BEFORE sandbox creation, 5 gates run in order:

1. Parse diff headers → extract file targets.
2. Single-file check: count unique targets, must == 1 (exit 4).
3. Allowlist check: the single target must appear in `allowlist.txt` via
   `grep -Fxq` (exit 5).
4. Budget check: count `+`/`-` lines, must ≤ `DIFF_BUDGET` (exit 6).
5. `git apply --check` dry-run against REPO_ROOT (exit 3).

Only diffs surviving ALL five checks proceed to sandbox creation. The
sandbox is a second line of defense after these cheap syntactic gates.

### state.json (D-20)

Written to `$SANDBOX_PATH/state.json` with this schema:

    {
      "outcome": "accepted|canary-failed",
      "exit_code": 0,
      "target": "lib/co-evolution.sh",
      "flavor": "bug-catcher",
      "diff_lines": 14,
      "diff_budget": 20,
      "canary": {"passed": true, "scenarios": 5, "failed_at": null},
      "sandbox_path": "/tmp/pel-code-sandbox-XXXXXX",
      "timestamp": "2026-04-18T12:00:00Z"
    }

Phase 8's PR emitter reads this BEFORE cleanup. The proposer holds the
worktree alive until after `state.json` is written and the diff is emitted
to stdout; the trap EXIT handler then removes the worktree.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success — diff emitted to stdout, canary passed, state.json written |
| 1 | Input validation failure (missing env var, invalid `PEL_FLAVOR`, invalid `CODE_PROPOSER_MODEL`, path traversal, invalid `DIFF_BUDGET`, non-existent `PEL_CODE_TARGET`) |
| 2 | `claude` CLI missing / auth failure / Opus call non-zero / empty response |
| 3 | Malformed diff — does not apply cleanly via `git apply --check` |
| 4 | Single-file constraint violation — diff touches more than one file |
| 5 | Allowlist violation — diff targets a file not on `allowlist.txt` |
| 6 | Diff budget exceeded — mutation exceeds `DIFF_BUDGET` lines changed |
| 7 | Canary failed — mutation applied but runner broke (state.json has details) |
| 8 | Sandbox setup failed — `git worktree add` failed |

Exit codes 5/6/7/8 are new to Phase 7 (Phases 5/6 had 0-4). They are
load-bearing for Phase 8's PR emitter: 5/6 = pre-flight rejection (no
sandbox touched); 7 = mutation tested and rejected; 8 = infrastructure
failure.

### CODE_PROPOSER_MODEL escape hatch

`CODE_PROPOSER_MODEL` overrides the default Opus 4.7 model ID. The value is
validated against `^[a-zA-Z0-9_.-]+$` before being passed to `claude --model`
— shell metacharacters are rejected with exit 1 and the message
`invalid CODE_PROPOSER_MODEL: <value> (must match [A-Za-z0-9_.-]+)`.

This is an escape hatch for debugging (swap in a cheaper or newer model for
benchmarking), not an everyday knob. Same posture as the classifier's
`CLASSIFIER_MODEL escape hatch` and the template-tier's `PROPOSER_MODEL`
escape hatch — a dedicated CLI flag is deferred to v1.3+ ergonomics.

### Invocation

Direct invocation (used by the Plan 02 simulation test at
`tests/code-proposer-simulation.sh` and by Phase 8's PR emitter in production):

```bash
export PEL_CODE_FEEDBACK=$PWD/evals/reports/20260418-120000/scores.json
export PEL_CODE_TARGET=lib/co-evolution.sh
export PEL_FLAVOR=bug-catcher

bash lab/pel/proposer/code/proposer.sh "improve retry logic"
```

Output: single unified diff to stdout, diagnostics + canary progress to
stderr. The sandbox worktree is created, canary-validated, and cleaned up
automatically.

### Files involved

- `lab/pel/proposer/code/proposer.sh` — public entry point (argv + env validation, path sandboxing, allowlist gate, diff budget gate, sandbox setup, git apply, canary orchestration, state.json emission, cleanup)
- `lab/pel/proposer/code/adapter.sh` — self-contained Opus adapter (6-placeholder prompt composition + claude CLI invocation + diff capture)
- `lab/pel/proposer/code/prompt.md` — mutation-proposer prompt (shell-aware framing, 4 flavor bias riders, diff budget reminder)
- `lab/pel/proposer/code/canary.sh` — canary smoke-test suite (5 scenarios, distinct exit codes, PATH-injection stubs, trap cleanup)
- `lab/pel/proposer/code/allowlist.txt` — explicit file allowlist (3 mutable paths)

All 5 files live under `lab/pel/proposer/code/**` — this is the Phase 7
allowlist-exclusion glob for the code-tier proposer.

### Simulation gate

Plan 02 ships `tests/code-proposer-simulation.sh` — a hermetic simulation
covering SC-5 with **16 scenarios**:

- **A–D (4 flavor happy-paths):** one per flavor, each emits a valid diff,
  passes the 5 pre-flight gates, applies in sandbox, survives canary, and
  writes `state.json` with `outcome=accepted` + `canary.passed=true`.
- **E–I (5 text-pipeline edge cases)** from
  `.planning/notes/phase-7-simulation-lessons.md`: empty-line context
  marker (E), no-trailing-newline marker (F), CRLF-on-disk file (G),
  shell metacharacters `$VAR` + `` ` `` + `<<'EOF'` + `*.sh` (H), and
  `patch`-vs-`git apply` divergence (I, exits 3).
- **J–P (7 adversarial rejections):** allowlist violations targeting
  classifier frozen surface (J), `.planning/STATE.md` (K), and `tests/`
  (L) — each exits 5. Budget exceeded (M, exit 6), multi-file (N, exit 4),
  missing `PEL_CODE_FEEDBACK` (O, exit 1), canary-breaking mutation (P,
  exit 7 with `state.json.outcome=canary-failed`).

Final line on success: `16/16 scenarios passed`. The simulation is
hermetic — stub `claude` CLI via PATH injection, no network, no real Opus
invocation. The canary runs inside a real sandbox worktree with Plan 01's
own PATH-injected `claude`/`codex` stubs, so all 5 canary scenarios pass
against unmutated-surface happy-paths and fail deterministically on the
syntax-breaking mutation in scenario P.

The simulation lives at `tests/code-proposer-simulation.sh`. Fixtures used
by the simulation live at `tests/fixtures/code-feedback/*.json` (4 synthetic
Phase-2-scorer-shaped eval-failure reports, one per flavor).

### Cross-references

- [`.planning/phases/07-code-tier-proposer/07-CONTEXT.md`](../../.planning/phases/07-code-tier-proposer/07-CONTEXT.md) — Phase 7 CONTEXT with D-01..D-23 decisions.
- [`.planning/notes/pel-design-decisions.md`](../../.planning/notes/pel-design-decisions.md) §3 — "Mutable surface = templates + policy + code" — why code-tier is LLM-only (random mutation breaks shell).
- [`.planning/notes/pel-design-decisions.md`](../../.planning/notes/pel-design-decisions.md) §5 — "Option 2 and Option 3 → graduate via lab/" — human-review Goodhart mitigation rationale. Phase 7's canary is a safety net, not a replacement for human review.
- [`.planning/notes/phase-7-simulation-lessons.md`](../../.planning/notes/phase-7-simulation-lessons.md) — BINDING simulation + canary requirements distilled from Phase 5's red-simulation session.

## PR Emitter (v1.2)

The PR emitter (`lab/pel/pr-emitter/`) is the Phase 8 Option 1 ship: a
wrapper behind a single invocation `co-evolve --lab pel-proposer --target
<file>` that composes Phases 4–7 (classifier → tier proposer → sandbox +
scoring → PR draft) and emits a GitHub draft PR for human review. Humans
merge or close; there is no auto-merge path in v1.2.

### Invocation example

```bash
co-evolve --lab pel-proposer \
  --target lib/co-evolution.sh \
  --flavor bug-catcher \
  --budget 25 \
  "improve retry handling"
```

Under `--dry-run`, the emitter stubs `gh` via PATH shadow (no PR created,
body assembled and logged to stderr) so SC-3's hermetic simulation can
exercise the full pipeline without touching GitHub.

### Env-var contract

| Var                   | Required | Default                               | Purpose                                                                        |
|-----------------------|----------|---------------------------------------|--------------------------------------------------------------------------------|
| `PEL_BOUNCE_STEP`     | No       | `unknown`                             | Classifier input: current bounce phase (compose\|bounce\|execute\|verify)      |
| `PEL_PHASE_TYPE`      | No       | `unknown`                             | Classifier input: GSD phase type (scoping\|implementation\|verification)       |
| `PEL_FLAVOR_OVERRIDE` | No       | unset                                 | Classifier override; set by `--flavor` wrapper flag                            |
| `PEL_EVAL_REPORT`     | No       | latest `evals/reports/*/raw-scores.json` | Eval-failure JSON consumed by tier proposers                                |
| `CO_EVOLVE_DRY_RUN`   | No       | unset                                 | `1` = stub gh via PATH shadow; set by `--dry-run` wrapper flag                 |

Internal env (set by the emitter for downstream proposers): `PEL_TEMPLATE_PATH`,
`PEL_POLICY_PATH`, `PEL_CODE_TARGET`, `PEL_FLAVOR`, `PEL_FEEDBACK`, `PEL_CODE_FEEDBACK`.
Per `lab/pel/README.md`'s "never inherit from user shell" discipline, the emitter
sets these explicitly from parsed argv, never inherits from the calling shell.

### Wrapper CLI flags (both `co-evolve` and `dev-review`)

| Flag             | Type    | Default | Purpose                                                                     |
|------------------|---------|---------|-----------------------------------------------------------------------------|
| `--target FILE`  | string  | —       | File to mutate; tier auto-detected via D-04 rule table                      |
| `--tier TIER`    | enum    | —       | Override auto-detect (`template`\|`policy`\|`code`)                         |
| `--pr-branch N`  | string  | auto    | Override default `pel/<tier>/<short-hash>` branch name                      |
| `--dry-run`      | boolean | off     | Stub `gh` via `CO_EVOLVE_DRY_RUN=1` + PATH shadow                           |
| `--budget USD`   | integer | `25`    | Scoring budget hard cap; exit 6 on exhaustion                                |
| `--yes`          | boolean | off     | Skip interactive preflight cost-estimate prompt                             |
| `--flavor NAME`  | enum    | —       | Classifier override (one of bug-catcher\|faster-converger\|blind-spot-surfacer\|general) |

All seven flags default off / unset so non-PEL invocations (e.g., plain
`co-evolve "task"`) preserve byte-parity with v1.1 (SC-5).

### Tier auto-detect rule table (D-04)

| Path pattern                                                                    | Tier     |
|---------------------------------------------------------------------------------|----------|
| `skills/dev-review/templates/*.md` OR `tests/fixtures/templates/*.md`           | template |
| `lab/pel/proposer/policy/policy.yaml`                                           | policy   |
| Any exact-line match in `lab/pel/proposer/code/allowlist.txt`                   | code     |
| Anything else                                                                   | hard-error (exit 10) |

`--tier NAME` overrides auto-detect for a single invocation. Mixed-tier
globs hard-error. Ambiguous matches hard-error. Hard-errors exit 10.

### Output contract

- **stdout:** Draft PR URL on success (from `gh pr create --draft`). For
  `--dry-run`, the URL is `https://github.com/REPO/pull/0 (dry-run stub)`.
  For canary-failed the URL is the real `gh` URL, but the PR title is
  prefixed `[CANARY-FAILED]` (D-15).
- **stderr:** Progress log prefixed `INFO:`; errors prefixed `ERROR:`.

### Exit codes (D-17)

| Code | Meaning                                                                        |
|------|--------------------------------------------------------------------------------|
| 0    | PR draft created (or `[CANARY-FAILED]` diagnostic PR per D-15)                 |
| 1    | Input validation failure (bad `--target`, invalid `--tier`, etc.)              |
| 2    | Classifier or proposer propagated exit 2 (CLI / auth failure)                  |
| 3    | Malformed diff propagated from proposer                                        |
| 4    | Multi-file violation propagated from proposer                                  |
| 5    | Allowlist violation propagated from proposer                                   |
| 6    | **EMITTER** eval budget exhausted (distinct from Phase 7's DIFF_BUDGET exit 6) |
| 7    | Canary-failed surfaced as `[CANARY-FAILED]` PR (Phase 7 proposer's own code)   |
| 8    | Sandbox setup failed (proposer's or emitter's)                                 |
| 9    | `gh pr create` failed post-scoring (D-17)                                      |
| 10   | Tier auto-detect hard-error (ambiguous / no-match / mixed-tier glob)           |

Exit 6 log message distinguishes the emitter case from Phase 7's: the
emitter logs `ERROR: emitter eval budget exhausted ($25 cap; override with --budget)`.

### Failure policy

- **Canary-failed (proposer exit 7) → `[CANARY-FAILED]` diagnostic draft PR (D-15).**
  PR title prefixed `[CANARY-FAILED]`. Body includes the `state.json`
  snapshot and the mutation diff so humans can triage. Scoring is skipped
  (no point scoring a mutation that breaks the runner). Humans closing these
  PRs counts toward SC-4's "≥1 closed without merge".
- **All other non-zero proposer exits (1/2/3/4/5/6/8) → abort with propagation (D-16).**
  The emitter emits no PR and propagates the proposer's exit code so
  callers see the failure category.
- **Emitter's own exits (6/8/9/10):** see the table above.

### Branch naming (D-11)

- **Default:** `pel/<tier>/<short-hash>` where `<short-hash>` is the first
  7 chars of `sha1sum` of the diff content.
- **Override:** `--pr-branch NAME` — regex-validated against
  `^[A-Za-z0-9][A-Za-z0-9._/-]*$` before reaching `gh`.

### Eval cache (D-18 + D-19)

Scorer output is cached at
`.co-evolve-cache/evals/<fixture-hash>-<script-hash>-<worktree-hash>[-<dirty-hash>].json`.
The cache is:

- **Gitignored** (`.co-evolve-cache/` added to root `.gitignore` in Plan 01)
- **Hash-invalidated** — rebuilt when fixtures OR `evals/*.sh` OR worktree
  HEAD OR worktree dirty state change. No TTL.
- **Cost-attributed** — cache hits cost `$0.00`; cache misses bill against
  the emitter's `$BUDGET_USD` (default `$25`). Exceeding the cap exits 6.

The worktree and dirty components are load-bearing: before/after scoring
runs share `$REPO_ROOT` but have different applied state, so identical
keys are undesirable. Including them separates the two cache lines.

### Simulation gate

`tests/pr-emitter-simulation.sh` provides the hermetic SC-3 gate:
10 scenarios (A–J) covering happy-path per tier, `--dry-run`, canary-failed
PR, budget exceeded, tier hard-error, tier override, byte-parity (SC-5),
and eval cache hit. PATH-injected stubs (`claude`, `gh`, `codex`) make it
hermetic across Git Bash Windows + Linux + macOS. Final line on success:
`10/10 scenarios passed`.

### Files involved

- `lab/pel/pr-emitter/pr-emitter.sh` — public entry point (10 sections
  A–J: require_tools, classifier, PEL_EVAL_REPORT selection, proposer
  invoke + git-shim state.json capture, failure policy, state parse,
  emitter sandbox + apply, eval cache + scorer + budget, render_pr_body,
  branch + commit + gh pr create).
- `lab/pel/pr-emitter/pr-body-template.md` — 13-placeholder `{{KEY}}`
  double-brace template per D-20.
- `lab/pel/pr-emitter/entry.sh` — dispatch shim (one-line exec into
  `pr-emitter.sh`).
- `lab/pel-proposer/entry.sh` — flat-namespace dispatch resolver (Plan 01
  Rule-3 deviation; routes `--lab pel-proposer` → `lab/pel/pr-emitter/`).

### Cross-references

- [`.planning/phases/08-pr-emitter-scoring/08-CONTEXT.md`](../../.planning/phases/08-pr-emitter-scoring/08-CONTEXT.md)
  — Phase 8 CONTEXT with D-01..D-22 decisions.
- [`.planning/phases/08-pr-emitter-scoring/08-02-PLAN.md`](../../.planning/phases/08-pr-emitter-scoring/08-02-PLAN.md)
  — feature + simulation plan (this plan).
- `.planning/phases/08-pr-emitter-scoring/VERIFY-SC4.md` — post-ship human-review
  tracker for ≥3 real PEL PRs (blocks v1.2 git tag, NOT Phase 8 closure).

## Further reading

- [`.planning/notes/pel-design-decisions.md`](../../.planning/notes/pel-design-decisions.md) — binding v1.2 design decisions; §1 "Multi-flavor fitness" is the authoritative source for the four flavor definitions that appear in `prompt.md`.
- [`.planning/phases/04-mode-classifier-frozen/04-CONTEXT.md`](../../.planning/phases/04-mode-classifier-frozen/04-CONTEXT.md) — Phase 4 context and the 11 locked decisions (D-01..D-11) that shape this inhabitant.
- [`lab/README.md`](../README.md) — the broader lab conventions this inhabitant honors (W-3 argv contract, L-05 sandbox guarantee, L-06 graduation criteria).
