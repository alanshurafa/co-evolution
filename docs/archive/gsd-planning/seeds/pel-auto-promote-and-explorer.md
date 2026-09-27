---
title: PEL Auto-Promote + Explorer modes — graduate from lab to core
trigger_condition: >
  ALL of the following must hold before surfacing:
  (1) PEL Option 1 (Proposer Only) has run in production for ≥4 weeks on real mutations,
  (2) A canary smoke-test suite exists (separate from fitness evals) that proves the runner still works after any mutation,
  (3) Goodhart mitigation research (`.planning/research/questions.md`) has actionable findings,
  (4) The `lab/` directory structure and graduation conventions (`co-evolution-lab-concept.md`) are established.
planted_date: 2026-04-17
---

# Seed: PEL Auto-Promote (Option 2) + Explorer + Curator (Option 3)

## The ambition

The user's real goal for PEL is **Option 2 and Option 3 running in parallel** — an autonomous system that both (a) auto-promotes mutations that beat the champion, and (b) continuously explores in a sidecar that humans periodically curate. Together, these would let the protocol evolve faster than any human-in-the-loop system could.

Both are deferred from v1.2 for a single reason: **they could poison a live workflow before iteration has locked the system down.** The user's words: "I'm using this in a live environment. It would really hurt my workflow if we had something poisoned early on before it's really iterated."

The solution: build both in `co-evolution/lab/` first. Run them alongside Option 1 (core) for long enough to learn their actual failure modes. Graduate them to core only when they've earned trust.

## Why both modes, not one

Option 2 and Option 3 answer different questions:

- **Option 2 (Auto-Promote)** answers: *which small mutations are worth keeping?* Tight exploit loop, high iteration speed, Goodhart risk.
- **Option 3 (Explorer + Curator)** answers: *what wild directions are worth investigating?* Wide exploration, slow feedback, curation dependency.

Running only Option 2 → local maximum, protocol converges on gaming the evals.
Running only Option 3 → graveyard of interesting-looking mutations that never ship.
Running both → Option 3 generates wild variants, Option 2's eval regime keeps only the ones that actually work, human curation picks the patterns worth formalizing.

## Prerequisites before this seed activates

### 1. Option 1 signal (≥4 weeks of real mutations)

Before automating promotion, we need to understand what "good mutation" looks like in this codebase. Option 1's PR stream is the teacher. Things to learn from it:

- How often does the LLM proposer suggest actually-useful mutations vs. plausible-sounding noise?
- What's the base rate of "mutation improves one eval case but regresses three others"?
- Which tiers (template / policy / code) actually produce winning mutations?
- Does the mode classifier correctly identify what flavor a task calls for?

Without this data, Option 2's promotion thresholds are guesses.

### 2. Canary smoke-test suite

Option 2's safety relies on catching broken runners BEFORE eval scoring. The canary is not the fitness eval — it's a separate "does the runner still execute" check. Minimum scope:

- `lib/co-evolution.sh` sources cleanly (no syntax errors)
- `agent-bouncer.sh` completes a trivial bounce end-to-end
- `dev-review/codex/dev-review.sh --plan-only` produces valid output
- A basic eval case from `evals/cases/` runs to completion with non-error exit

Any mutation that fails the canary is rejected BEFORE its fitness is scored.

Estimated build: 2–3 days of engineering as its own phase.

### 3. Goodhart mitigation research findings

See `.planning/research/questions.md`. At minimum, we need answers to:

- Do we rotate held-out eval cases? On what schedule?
- Is there a practical way to generate adversarial eval cases automatically?
- What drift-detection signal flags "mutation passed evals but is actually worse"?
- Can we maintain a ground-truth anchor set that PEL is never scored against directly?

Without mitigations, Option 2 *will* eventually drift toward eval-gaming. It's not a hypothetical.

### 4. `lab/` directory + graduation conventions

From `co-evolution-lab-concept.md`. Feature must be invokable via `--lab <mode>` flag, must log clearly, must not leak state into core runs, must have a documented kill-switch.

## Implementation sketch (for when this activates)

### Option 2 (Auto-Promote) in lab

Code lives at `lab/pel-auto-promote/`. Invoked via `co-evolve --lab pel-auto-promote` or scheduled nightly via ScheduleWakeup / cron.

Loop:
1. LLM proposer generates N mutation candidates against current champion
2. For each candidate: apply in isolated sandbox, run canary suite
3. If canary passes: run fitness eval suite
4. If mutation beats champion on fitness (stat-sig): auto-merge to `lab/` champion
5. Log everything to protocol graveyard
6. NEVER auto-merge to core; lab champion stays in lab until human promotion

Kill-switch: `lab/pel-auto-promote/STOP` file blocks next run.

### Option 3 (Explorer + Curator) in lab

Code lives at `lab/pel-explorer/`. Runs continuously or on schedule. NEVER has a promotion threshold.

Loop:
1. LLM proposer generates wild mutations (higher diversity budget than Option 2)
2. For each: apply in sandbox, run canary + partial eval subset
3. All results logged to graveyard with metadata (mutation diff, scores, classifier's mode pick, timestamp)
4. No promotion. Ever. Pure logging.

Curation UX: a `lab/pel-explorer/curate.sh` command that browses the graveyard. Filters by score, date, mode. Shows mutation diffs. Human can `promote <mutation-id>` to move it into the Option 2 lab for proper auto-promotion evaluation, or `kill <mutation-id>` to mark it dead-end.

### Graduation path to core

Either option graduates to core when:

- Lab metrics show consistent improvement of lab champion over core champion on a held-out eval set
- Failure modes are documented
- Canary suite hasn't caught a real-runner-breaking mutation in the past 4 weeks
- The code is simpler than the original draft (complexity has converged)

At that point, plan a milestone to port the lab feature to core with proper test coverage.

## Why this seed vs. planning it now

Fresh data from Option 1 will change this design. Right now this seed captures:

- The target shape (both modes, in parallel, in lab)
- The prerequisites (so it doesn't activate prematurely)
- The reasoning (so future-us understands why Option 1 came first)

When the trigger conditions hit, revisit this seed, let the v1.2 lessons reshape the design, then plan it.

---

*The user flagged this as "the most powerful thing that's going to create super quickly." That energy is real. This seed protects that energy from being wasted on a premature implementation.*
