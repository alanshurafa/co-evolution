# The Lab

`lab/` is the first-class **beta channel** for opt-in experimental features in the Co-Evolution repo. Users who never pass `--lab <mode>` see zero behavior change — the default runner stays stable, boring, and backward-compatible. Everything that might *fundamentally* break the runner lives here instead.

## Why this exists

The co-evolution tool is used in live workflows. A broken core runner is not "an inconvenience" — it blocks real work. But waiting until every ambitious idea is 100% safe before building it means the most interesting experiments never happen.

The lab resolves this tension: ambitious things get built in a place where they *can* break without breaking anything that matters. Users reach the cutting edge by opting in explicitly; everyone else keeps a runner that still works.

## Boundary conventions

### Core runner (default `co-evolve`, `dev-review`)
- **Default.** Stable. Safe by construction.
- Backward-compatible within a major version.
- Has test coverage parity + documented rollback.
- What users invoke by default.

### Lab (`lab/` subdirectory)
- **Experimental, may break, never default.**
- Invoked explicitly via `--lab <mode>` (e.g., `co-evolve --lab pel-auto-promote`, `dev-review --lab explorer-mode`).
- Lower test bar — proof-of-concept acceptable.
- Features here may change API, be rewritten, or be removed without notice.

## What qualifies as "lab-worthy"

A feature belongs in the lab if ANY of these apply:

- It could brick the core runner if its logic is wrong (e.g., self-modifying code)
- Its correctness signal takes weeks to evaluate (e.g., protocol drift detection)
- It trades safety for power (e.g., autonomous mutation with auto-merge)
- It depends on infrastructure that doesn't exist yet (e.g., canary smoke-test suite)
- It's an architectural bet with real uncertainty (e.g., evolutionary population vs champion/challenger)

A feature does NOT belong in the lab if it's just "we haven't polished it yet" — that's normal pre-ship work. The lab is for features that are *fundamentally risky*, not *currently unfinished*.

## Graduation criteria — lab → core

A feature moves from `lab/` to core when ALL of these are true:

1. **Runtime signal.** Feature has run in the lab for ≥4 weeks on real workloads (not synthetic tests). Failures logged. Patterns observed.
2. **Test parity.** Feature has test coverage equivalent to analogous core features.
3. **Documented failure modes.** Known ways it can break + recovery paths written down.
4. **User signal.** User has explicitly opted into the lab version multiple times across different tasks — indicating real need, not novelty.
5. **Rollback path.** Clear story for "this regressed, how do we get back to the prior version."
6. **Name + API stable.** No more "I wonder if we should rename this" discussions.

Any missing criterion → stays in lab. Pushing something to core that doesn't meet all six is how the live runner gets poisoned.

## Anti-criteria — when to remove from lab (not graduate)

Sometimes a lab feature should be killed rather than promoted:

- User hasn't invoked it in months → nobody actually wants it
- Its fitness signal never stabilized → we don't know if it's helping
- A simpler pattern in core obviated it → redundant
- It breaks in a way we can't fix without a full rewrite → cut losses

Killing a lab feature is not a failure of the lab. The lab's job is to *find out*. Some experiments find out "no."

## What's NOT the lab

To avoid confusion with pre-existing scratch spaces:

- **`C:/Users/alan/Project/co-evolution-lab/`** (this workspace) is a pre-existing peer directory with auto-research, integrations, and older experiments. It is NOT the new `lab/`. It remains as-is; most of its content has already been folded into core or explicitly excluded.
- **`runners/codex-ps/`** is a read-only verbatim reference implementation, not a lab. Its purpose is historical preservation (see `runners/codex-ps/REFERENCE-STATUS.md`).
- **`experiments/`** holds design docs and exploration artifacts for features already shipped or cancelled. Not a runtime lab.

The new `lab/` is a *runtime area* — code that executes as part of invoking `co-evolve` or `dev-review` with a `--lab` flag.

## Sandbox guarantee

`--lab <mode>` runs cannot modify master directly. Core updates only ever happen via emitted PRs that a human reviews and merges. Each lab inhabitant ships its own enforcement mechanism (for example, the v1.2 PEL code-tier proposer will ship sandbox isolation + a canary smoke-test gate in Phase 7; other inhabitants will enforce this guarantee in ways appropriate to their surface).

This section is the Phase 3 *write* of the contract. Future phases that add lab inhabitants must honor it: no mutation paths to `master`, ever, that bypass the PR + human review gate.

## Invocation

Lab modes are opt-in via a single long-form flag. Both runners accept it with matching semantics:

```bash
# co-evolve runner
co-evolve --lab pel-proposer "task"

# dev-review runner
bash dev-review/codex/dev-review.sh --lab pel-proposer "task"
```

An unknown mode fails fast. The runner lists the available modes from the `lab/` directory and exits with a non-zero status, e.g.:

```
unknown --lab mode: foo. Available: pel-proposer, ...
```

No silent fallthrough to the default runner. Plan 02 of Phase 3 wires the parser; `--lab` is documented here as the invocation contract.

## First inhabitants

| Mode | Path | Status |
| --- | --- | --- |
| PEL Proposer-Only | `lab/pel/` | v1.2 current (machinery lands Phase 4+; directory NOT created by Phase 3) |
| PEL Auto-Promote | `lab/pel-auto/` | v1.3+ placeholder — NOT created in Phase 3 |
| PEL Explorer + Curator | `lab/pel-explorer/` | v1.3+ placeholder — NOT created in Phase 3 |

- **`lab/pel/`** is v1.2's first inhabitant. The PEL (Protocol Evolution Loop) Proposer-Only system — LLM-driven mutation proposals against templates, policy, and runner code — lands across Phases 4-8 of v1.2. See `.planning/notes/pel-design-decisions.md` for the design rationale.
- **`lab/pel-auto/`** will host PEL Auto-Promote (Option 2). Not created in Phase 3; its graduation prerequisites are tracked in [`.planning/seeds/pel-auto-promote-and-explorer.md`](../.planning/seeds/pel-auto-promote-and-explorer.md).
- **`lab/pel-explorer/`** will host PEL Explorer + Curator (Option 3). Not created in Phase 3; shares the same seed file for prereqs: [`.planning/seeds/pel-auto-promote-and-explorer.md`](../.planning/seeds/pel-auto-promote-and-explorer.md).

Placeholders are listed here so the namespace is reserved and future PEL work has an obvious home, but Phase 3 deliberately does NOT create those directories. They materialize only when their v1.3+ trigger conditions are met.

## How to add a new lab inhabitant

Short checklist for landing a new lab mode:

1. Create `lab/<name>/` directory.
2. Add an entry point (convention: `lab/<name>/entry.sh`).
3. Add a row under `## First inhabitants` in this README.
4. Add a simulation test under `tests/` if applicable (see `tests/worktree-management-simulation.sh` for style).
5. Document any required env vars, sandbox setup, or kill-switch in `lab/<name>/README.md`.

**Argv contract (v1.2):** Lab inhabitant entry points receive the full task string as `$1` (single argument). The runner concatenates multi-word task tokens into one string before dispatch, so an invocation like `co-evolve --lab pel-proposer one two three` resolves to `lab/pel-proposer/entry.sh "one two three"` with `$1 = "one two three"`. If your inhabitant needs multi-slot argv, split `$1` yourself (e.g., `read -ra parts <<< "$1"`) or define a fixed CLI surface like `lab/<mode>/entry.sh --flag value "$1"`. This is a v1.2 contract constraint — may relax in v1.3+.

## Further reading

- [`.planning/notes/co-evolution-lab-concept.md`](../.planning/notes/co-evolution-lab-concept.md) — the authoritative deep-why source. The 6 graduation criteria, 4 anti-criteria, 5 lab-worthy conditions, and 3 disambiguation items in this README are copied verbatim from that concept note. If this README and the concept note diverge, the concept note wins.
- [`.planning/seeds/pel-auto-promote-and-explorer.md`](../.planning/seeds/pel-auto-promote-and-explorer.md) — graduation prerequisites for the v1.3+ PEL Auto-Promote + Explorer inhabitants.
- [`.planning/REQUIREMENTS.md`](../.planning/REQUIREMENTS.md) — LAB-01 (this scaffold) plus PEL-01..PEL-05 (current + future inhabitants).
