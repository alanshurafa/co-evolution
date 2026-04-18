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
The classifier itself remains reachable directly via `bash lab/pel/classifier/classifier.sh`
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

## Further reading

- [`.planning/notes/pel-design-decisions.md`](../../.planning/notes/pel-design-decisions.md) — binding v1.2 design decisions; §1 "Multi-flavor fitness" is the authoritative source for the four flavor definitions that appear in `prompt.md`.
- [`.planning/phases/04-mode-classifier-frozen/04-CONTEXT.md`](../../.planning/phases/04-mode-classifier-frozen/04-CONTEXT.md) — Phase 4 context and the 11 locked decisions (D-01..D-11) that shape this inhabitant.
- [`lab/README.md`](../README.md) — the broader lab conventions this inhabitant honors (W-3 argv contract, L-05 sandbox guarantee, L-06 graduation criteria).
