# The PEL lab inhabitant

`lab/pel/` hosts the v1.2 Protocol Evolution Loop (PEL) proposer machinery. Phase 4
ships the **mode classifier** under `lab/pel/classifier/` — a frozen decision layer
that picks one of four fitness flavors (`bug-catcher`, `faster-converger`,
`blind-spot-surfacer`, `general`) per PEL invocation, emits transparent rationale,
and honors user overrides. The classifier is FROZEN in v1.2: its code, prompt,
and env var contract do not mutate. Phase 7's code-tier proposer excludes
`lab/pel/classifier/**` from its mutable-file allowlist (see `## Frozen surface`).

Phases 5-8 add template-tier, policy-tier, and code-tier proposers plus a PR emitter
— all under `lab/pel/` siblings — that consume this classifier's output. Until those
phases land, the classifier is reachable directly via `bash lab/pel/classifier/classifier.sh`
for debugging and for the Phase 4 Plan 02 simulation test.

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

## Further reading

- [`.planning/notes/pel-design-decisions.md`](../../.planning/notes/pel-design-decisions.md) — binding v1.2 design decisions; §1 "Multi-flavor fitness" is the authoritative source for the four flavor definitions that appear in `prompt.md`.
- [`.planning/phases/04-mode-classifier-frozen/04-CONTEXT.md`](../../.planning/phases/04-mode-classifier-frozen/04-CONTEXT.md) — Phase 4 context and the 11 locked decisions (D-01..D-11) that shape this inhabitant.
- [`lab/README.md`](../README.md) — the broader lab conventions this inhabitant honors (W-3 argv contract, L-05 sandbox guarantee, L-06 graduation criteria).
