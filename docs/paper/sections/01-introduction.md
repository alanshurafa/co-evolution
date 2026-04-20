# 1. Introduction

## 1.1 The convergence problem in multi-agent LLM debate

Multi-agent debate has emerged as a practical technique for improving the reliability of LLM outputs on reasoning, coding, and analysis tasks. The core intuition — that two or more model instances arguing for different positions surface errors that a single instance would miss — has been validated empirically across several frameworks. Multi-Agent Debate [Du et al., CITATION-NEEDED] established the basic pattern: agents generate, critique, and revise in alternating rounds until either a stop condition is met or a fixed turn limit is reached. AutoGen [Wu et al., CITATION-NEEDED] generalized this into a programmable conversation framework with role-based agents. ChatEval [Chan et al., CITATION-NEEDED] applied the pattern to evaluation tasks. Subsequent work — Society of Mind orchestration, debate-of-many configurations, and tool-augmented variants — has extended the surface area without changing the basic structural assumption: debate is a sequence of turns, and termination is something we hope for rather than guarantee.

This is a real limitation. In every existing framework, debate either:

1. **Runs to a fixed turn limit** (e.g., "stop after 5 rounds"), in which case the conversation may end mid-disagreement with no resolution; or
2. **Terminates on a heuristic** (e.g., "stop when both agents agree" or "stop when no new objections are raised"), in which case the stopping condition is a property of agent behavior, not the protocol — adversarial or stubborn agents can drive the conversation indefinitely; or
3. **Terminates on external timeout** (wall-clock or token budget), in which case the artifact reflects whatever state the debate happened to be in when the timer fired.

None of these provide what we will call a **convergence guarantee**: a protocol-level property stating that within a bounded number of operations, the artifact reaches a state with no unresolved disagreements. The absence of such a guarantee matters because it makes debate frameworks difficult to compose, hard to embed in larger pipelines, and impossible to reason about formally.

## 1.2 Our approach

We propose an alternative substrate. Rather than alternating dialog turns, agents share a single editable document, and they communicate disagreement and ambiguity through structured markers placed inline in the document text. Two markers are defined:

- `[CONTESTED]` — an agent disagrees with preceding text and proposes a concrete alternative
- `[CLARIFY]` — an agent finds preceding text ambiguous and offers two interpretations or asks a finite-answer question

A bounce consists of *N* passes, with agents alternating roles. On every pass, agents may add new markers and may resolve inherited markers (resolution = deletion, not reply). On the **final pass**, agents must not introduce new markers and must resolve every remaining inherited marker. This last constraint — the *staleness rule* — is the load-bearing piece of the protocol: it guarantees that after pass *N*, the marker count is zero.

Because *N* is fixed in advance and the staleness rule is enforced by the protocol (not by agent goodwill), termination becomes a structural property. The bounce always converges; what varies is *what* the converged document says. This separation of termination from quality is, we argue, the right factoring: the protocol guarantees you get an answer; whether that answer is right is a separate question evaluated separately.

## 1.3 Contributions

This paper makes three contributions:

1. **Specification.** We formalize the bounce protocol — markers, pass mechanics, staleness rule — as a substrate-agnostic specification published under CC0 to enable cross-tool adoption. The full spec is included as Section 2 of this paper and is also distributed as a standalone artifact (`BOUNCE-PROTOCOL.md`).

2. **Convergence argument.** We provide a proof sketch (Section 3) showing that any conforming implementation terminates in at most *N* passes with zero unresolved markers. The argument is intentionally simple — the protocol is designed to make termination obvious — and we discuss why this matters for composition with other systems.

3. **Reference implementation and pilot.** We release a reference implementation in approximately 200 lines of bash, with adapters for Claude and Codex command-line interfaces, and report a pilot evaluation (Section 4) on [N] real document-refinement tasks. Adapters for additional agents are 5–10 lines each.

## 1.4 Roadmap

Section 2 specifies the protocol formally. Section 3 develops the convergence argument. Section 4 reports the pilot evaluation. Section 5 compares co-evolution to peer multi-agent debate frameworks across substrate, marker support, convergence guarantees, cross-model adversarial review, and self-improvement loops. Section 6 discusses limitations — most importantly the distinction between convergence and correctness — and outlines directions for future work, including the Protocol Evolution Loop (PEL) currently under development and the cross-tool interoperability story.

---

*Word count target: 700. Current: ~770 — slight trim before submission. Cut targets: tighten §1.1 paragraph 3 (the three-failure-modes list could be a single sentence with the list inline).*

*Citations to verify before submission: Du et al. (MAD), Wu et al. (AutoGen), Chan et al. (ChatEval). Do not finalize until each is checked against the actual paper title, author list, and venue.*
