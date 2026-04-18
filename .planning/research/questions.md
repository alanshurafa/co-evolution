# Open Research Questions

Questions that need deeper investigation before downstream work can commit to specific designs. Append new questions as they surface. Remove or archive when answered.

---

## RQ-001 — Goodhart mitigation in eval-driven prompt evolution

**Surfaced:** 2026-04-17, PEL exploration
**Relevance:** PEL v1.2 (limited — Option 1 has human review as Goodhart backstop); PEL v1.3+ (critical — Auto-Promote and Explorer modes rely on automated fitness signals with no human gate)

### Core question

How do we prevent a self-improving prompt-evolution system from learning to exploit the eval suite instead of actually improving the protocol? Fitness signal = eval pass rate ⇒ gradient descent finds eval-gamers that pass checks without producing better real outputs. What are the practical mitigations?

### Sub-questions

- **Prior art.** What does Anthropic's work on specification gaming recommend? OpenAI's reward hacking research? DeepMind's safety team publications? Are there known patterns that transfer to prompt-evolution contexts (as opposed to RL agents)?
- **Held-out rotation.** If a subset of eval cases is held out and rotated on a schedule (e.g., 20% rotated weekly), does that prevent over-fitting? What's the right rotation frequency vs. eval suite size?
- **Adversarial eval generation.** Can we use a separate LLM (different model family, different prompt) to automatically generate new eval cases each cycle, specifically targeted at surfacing ways the current champion might be gaming existing evals?
- **Semantic drift detection.** Is there a measurable signal for "this mutation passes evals but the outputs have drifted semantically from prior good outputs"? Embedding distance? Distribution shift on lexical features? Human spot-check sampling?
- **Multi-fitness blending.** If we combine 3+ fitness signals with different gameable surfaces (e.g., eval pass rate + convergence speed + agreement with held-out human judgments), does the combined fitness resist gaming better than any single signal? Or does it just find mutations that game all three?
- **Ground-truth anchors.** Can we maintain a corpus of "known good outputs" and "known bad outputs" that the evolution system is never scored against directly, but which we periodically use to audit whether the fitness signal has diverged from actual quality?
- **Canary-via-regression.** If we hold a fixed "quality regression" test set (distinct from evolving fitness evals), does monitoring for unexpected regressions on it provide a kill-switch signal?

### Why this matters

The user's founding observation for PEL is *"11 pilot bounces missed 8 real bugs that evals caught."* This means evals are already capturing real signal. But it also means **evals are the entire bottleneck** — if the protocol learns to pass them without catching real bugs, PEL not only stops improving, it actively regresses into a confident bug-misser.

Goodhart's law is not a hypothetical here. It's the default outcome of optimizing any proxy metric hard enough. Any Option 2 or Option 3 design without explicit mitigations will drift.

### Suggested research approach

1. **Literature scan** (1–2 hours). Look for: Anthropic spec-gaming papers, Krakovna et al. specification-gaming examples, work on "reward tampering" in LLMs, Constitutional AI-style anti-gaming techniques. Capture 5–10 relevant patterns.
2. **Pattern evaluation** (2–4 hours). For each pattern, assess: does it apply to prompt evolution (vs. RL)? What infrastructure does it require? What's the cost per eval cycle?
3. **Mitigation bundle design** (1 hour). Pick 2–3 mitigations that compose well and fit the project's Bash + eval harness constraints. Document as `.planning/notes/pel-goodhart-mitigations.md`.
4. **Revisit the seed** (`.planning/seeds/pel-auto-promote-and-explorer.md`). Update the prerequisite on "Goodhart mitigation research has actionable findings" with specific mitigations to implement.

### Who owns this

Unassigned. Needs to be picked up before Option 2 or Option 3 planning begins. Estimated: one afternoon of research + writeup.

---

*Next RQ numbering: RQ-002*
