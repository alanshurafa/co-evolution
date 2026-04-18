---
title: PEL design decisions — v1.2 foundation
date: 2026-04-17
context: Exploration session (/gsd-explore) before v1.2 kickoff. Binding decisions referenced by v1.2 planning.
---

# Protocol Evolution Loop — Design Decisions

Produced by a Socratic exploration session on 2026-04-17 before committing to a v1.2 milestone shape. Captures the binding decisions, the reasoning, and the explicit trade-offs surfaced.

## Founding observation

From `v1.0-SUMMARY.md`: **11 pilot bounces missed 8 real bugs plus 1 scorer blindness that evals caught.** Bouncing alone has structural blind spots; evals surface them. PEL exists to evolve the bounce protocol toward catching more of what evals detect — with Goodhart's law as a first-class risk to mitigate, not an afterthought.

## Binding decisions

### 1. Multi-flavor fitness, auto-selected with override

PEL is not a single-mode optimizer. It supports distinct fitness flavors:

- **Better bug-catcher** — protocol variants that catch more eval-known bugs. Fitness = eval pass rate.
- **Faster / cheaper converger** — variants that reach "good enough" in fewer bounce passes or less compute. Fitness = convergence time × cost at a fixed quality bar.
- **Blind-spot surfacer** — variants that catch real bugs the evals DON'T know yet. Fitness = agreement with a held-out ground truth or adversarial set.
- **General** — a principled blend for tasks that don't fit a single flavor. NOT a neutral default — treat as "one fitness function with extra steps."

Selection is automated (a small classifier, likely Haiku 4.5) with the classifier's reasoning shown transparently in each run. Users can override the auto-selection per invocation.

**Trade-off surfaced:** If the classifier itself is mutable, PEL gets meta-meta-learning (powerful, dangerous — classifier can learn to pick whichever mode makes the current mutation look good). **Decision: freeze the classifier for v1.2.** Evolving it is a v1.3+ question.

### 2. Specialization across BOTH layers (bounce-step × GSD-phase)

Two independent context axes specialize PEL's fitness function:

- **Bounce step** — compose vs bounce-pass vs execute vs verify. Specializes WITHIN a dev-review run.
- **GSD phase type** — scoping vs implementation vs verification. Specializes BETWEEN invocations.

This yields roughly a 3×3 matrix of mode combinations before flavors stack on top. Explicit implication: **the eval harness can no longer run isolated fixtures.** It must run bounces *in the context of a phase type*, because the same compose prompt may score differently in "scoping a refactor" vs "shipping a bug fix." The PS harness today does not do this — the new Bash harness must.

### 3. Mutable surface = templates + policy + code

PEL can propose changes to three tiers:

- **Templates** — compose / bounce / review / arbitrate `.md` files.
- **Policy** — marker-semantics definitions, retry caps, writable-phase defaults, arbitrate thresholds, max-passes, flavor weights (YAML/JSON config).
- **Code** — runtime paths in `lib/co-evolution.sh`, phase chaining logic, arbitration triggers.

**Locked-in consequence:** Random mutation of shell code always produces syntax errors. Mutating the code tier **requires an LLM proposer** (Claude or Codex). Evolutionary random search is off the table for the code surface — not a choice, a constraint.

### 4. v1.2 production = Option 1 (Proposer Only)

PEL proposes mutations as draft PRs / branches. A human reviews and merges every mutation like a normal PR. Eval scores are shown in the PR body.

**Why this over Option 2 (Auto-Promote) or Option 3 (Explorer + Curator):**

- Novel territory — we don't yet know what "good mutation" looks like in context. Seeing every proposal teaches us what to trust before automating trust.
- Option 2 requires an airtight canary suite to exist first. It doesn't. Building the canary is ~half the engineering of Option 2 on its own.
- Option 3's failure mode is human (curation never gets done). Don't bet on future-you having more discipline than current-you.
- PRs already integrate with `/gsd:ship --review`. Zero new infrastructure for the review loop.
- Core architectural principle: **every version of the system leaves you with a runner that still works.** Proposer-only is the only option where that's guaranteed by construction.

### 5. Option 2 and Option 3 → graduate via `co-evolution/lab/`

A new first-class subdirectory inside the main repo: `lab/`. Serves as a beta channel for experimental modes that could damage the live runner if deployed prematurely. Auto-Promote and Explorer+Curator live there until they meet graduation criteria. See separate note: `co-evolution-lab-concept.md`.

## Platform upgrades assumed

Not "nice to haves" — PEL's economics depend on them:

- **Haiku 4.5** (`claude-haiku-4-5-20251001`) as the eval verifier. Opus 4.7 is overkill for verify-at-scale; Haiku cuts cost ~10× for eval runs where latency compounds.
- **Prompt caching** on stable bounce prompts + templates. With caching, identical system prompts across 100+ eval runs hit cache at ~10% token cost. Without it, PEL is economically impractical.
- **Opus 4.7 (1M context)** for compose/bounce. Whole-codebase bounces now feasible; previous context ceilings forced piecemeal embeds.
- **ScheduleWakeup / cron** for autonomous nightly eval runs (relevant starting at Option 2).
- **`/compute-guard`** paired with any autonomous mode. Unbounded eval loops will burn a day of API budget fast.

See `.claude/projects/.../memory/future_tools.md` for the full queue.

## Open risks tracked as research questions

- **Goodhart's law / specification gaming.** Fitness = eval pass rate ⇒ PEL eventually learns to hit eval checks without producing actually-better outputs. Captured in `.planning/research/questions.md` for ongoing investigation. Critical for Option 2.
- **Attribution muddiness.** When PEL promotes a mutation, was it because the protocol got better or the classifier changed modes? Requires clean separation between protocol-evolution and classifier-evolution, which is why the classifier is frozen in v1.2.
- **"General" flavor trap.** A blend fitness function is not neutral — it's one fitness function with extra steps. Treat as a distinct flavor, not a default.

## Immediate next step

`/gsd:new-milestone v1.2` to commit the above into a roadmap shape. Likely phases:

1. Bash port of PS eval harness (~2 days — prerequisite)
2. Create `lab/` scaffold + README (graduation conventions)
3. Mode classifier (frozen, shown transparently)
4. Template-tier mutation proposer (safest first cut)
5. Policy-tier mutation proposer
6. Code-tier mutation proposer (LLM-only)
7. PR emission + scoring integration

Code-tier work likely spans multiple sub-phases given the safety surface.

---

*Decisions captured from one exploration session. Revisit if v1.2 planning surfaces conflicts with anything here — but flag the conflict explicitly; don't silently drift.*
