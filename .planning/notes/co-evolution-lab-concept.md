---
title: Co-Evolution Lab — beta channel architecture
date: 2026-04-17
context: Architectural concept surfaced during PEL exploration. Generalizes beyond PEL to any ambitious experiment that could damage the live runner.
---

# The Lab

A first-class subdirectory inside the `co-evolution` repo: `lab/`. Serves as the **beta channel** for experimental features that could break the core runner if deployed prematurely.

## Why this exists

The co-evolution tool is used in live workflows. A broken core runner is not "an inconvenience" — it blocks real work. But waiting until every ambitious idea is 100% safe before building it means the most interesting experiments never happen.

The lab resolves this tension: ambitious things get built in a place where they *can* break without breaking anything that matters.

## Boundary conventions

### Core runner (default `co-evolve`, `dev-review`)
- Stable. Safe by construction.
- Backward-compatible within a major version.
- Has test coverage parity + documented rollback.
- What users invoke by default.

### Lab (`lab/` subdirectory)
- Experimental. May break. Never default.
- Invoked explicitly (e.g., `co-evolve --lab pel-auto-promote`, `dev-review --lab explorer-mode`).
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

## First inhabitants (from the PEL exploration)

Two features are explicitly targeted for the lab:

- **PEL Auto-Promote mode** (Option 2): mutations auto-merge when canary + eval tests pass. Risk: eval-gaming despite passing canary.
- **PEL Explorer + Curator mode** (Option 3): continuous sidecar exploration, graveyard logging, periodic human curation. Risk: curation never happens.

See seed: `.planning/seeds/pel-auto-promote-and-explorer.md` for graduation prerequisites specific to these.

## Why this pattern matters beyond PEL

Any future ambitious experiment in this codebase has the same choice: build it risky in core, or build it safe in the lab. The lab generalizes. Examples of things that would belong in the lab:

- Alternate bounce protocols (not the Claude↔Codex [CONTESTED]/[CLARIFY] pattern)
- A Bayesian search mode over protocol space (v1.4+ PEL ambition)
- Integration with new AI providers (Gemini, open-source models) before parity proven
- Cost-optimization modes that gamble on caching behavior

The lab protects the core. The core protects users. Users can still reach the cutting edge by explicitly opting in with `--lab`.

---

*Concept surfaced during PEL exploration. Any ambitious future experiment should route here by default unless it provably meets core's bar.*
