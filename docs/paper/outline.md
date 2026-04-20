# Paper Outline

**Working title:** Convergence-Guaranteed LLM Debate via Expiring In-Document Markers

**Target length:** 4–6 pages, single-column, 11pt. Approximately 4,000–6,000 words.

## Section 0 — Abstract (~150 words)

Multi-agent LLM debate frameworks improve answer quality but lack convergence guarantees. We introduce a marker-based refinement protocol where agents annotate disagreement (`[CONTESTED]`) and ambiguity (`[CLARIFY]`) inline within a shared document, and a staleness rule (markers must be resolved by pass *N*) provides bounded termination. Reference implementation: ~200 lines of bash, agent-agnostic, with adapters for Claude and Codex CLIs. Pilot evaluation: *(N bounces, M bugs caught — pending verification)*. The protocol is published as a CC0 specification suitable for cross-tool interop.

## Section 1 — Introduction (~600–800 words)

- The problem: multi-agent LLM debate works but can chain indefinitely
- Existing approaches: MAD, AutoGen, ChatEval, Society of Mind, debate-of-many — all use turn-based debate; convergence is empirical, not guaranteed
- Our contribution: (1) a marker-based protocol with explicit staleness rule, (2) reference implementation, (3) interop spec
- Roadmap of paper

## Section 2 — The Bounce Protocol (~600 words)

- Substrate: shared editable document (filesystem-native, but substrate-agnostic)
- Two markers with formal semantics:
  - `[CONTESTED]` = structured disagreement requiring concrete alternative
  - `[CLARIFY]` = ambiguity requiring finite-answer disambiguation
- Pass mechanics: alternation, role lens, prompt template
- Resolution rule: delete (don't reply); convergence = zero markers
- Code listing: minimal conforming implementation (~30 lines, distilled from `agent-bouncer.sh`)

## Section 3 — Convergence Argument (~500 words)

- Claim: protocol terminates in ≤ *N* passes with zero unresolved markers
- Proof sketch:
  1. Pass budget *N* is fixed and finite
  2. Final-pass rule: zero new markers admitted, all inherited markers must be resolved
  3. Therefore at end of pass *N*, marker count = 0 (converged) by construction
- Discussion: why this matters (compare to debate frameworks where termination is empirical / heuristic / external-timeout-based)
- Caveat: protocol guarantees *termination*, not *correctness*. The agents can still produce a wrong but converged document; convergence is a necessary but not sufficient condition for usable debate.

## Section 4 — Pilot Data (~600 words)

- Setup: bounces against [TARGET corpus — e.g., real PR plans, drafted specs]
- Method: Claude as reviewer, Codex as composer; *N=2* passes; evaluate per-pass
- Metrics:
  - Bug-catch rate (bugs surfaced by `[CONTESTED]` markers / total bugs in target)
  - Convergence rate (% bounces reaching zero markers within budget)
  - Per-pass marker count (delta as evidence of staleness rule working)
- Result: *(N bounces → M bugs caught; convergence rate X%)* — **DATA TO VERIFY**
- Sample bounce: full transcript of one bounce showing markers being added and resolved across passes

## Section 5 — Comparison (~400 words)

Table comparing co-evolution to peer frameworks across:

| Framework | Substrate | Marker protocol | Convergence guarantee | Cross-model adversarial review | Self-improvement loop |
|-----------|-----------|-----------------|------------------------|--------------------------------|----------------------|
| MAD (Du et al.) | dialog turns | none | empirical | optional | none |
| AutoGen | dialog turns | none | external timeout | yes | none |
| ChatEval | dialog turns | none | empirical | yes | none |
| metaswarm | conversation log | none | empirical | yes | yes (Conversation Introspection) |
| quorum-cli | dialog turns | none | empirical | yes (multi-method) | none |
| **Co-Evolution** | **shared document** | **`[CONTESTED]` / `[CLARIFY]`** | **bounded by construction** | **yes (Claude + Codex)** | **yes (PEL, human-gated)** |

(Verify each row before publication; star counts and feature claims may have shifted.)

## Section 6 — Limitations and Future Work (~400 words)

- Limitations:
  - Convergence ≠ correctness (caveat from §3)
  - Pilot is small; broader eval needed
  - Marker semantics rely on agent compliance — adversarial agents can ignore them
  - Protocol assumes textual substrate; non-text artifacts (images, audio) need extension
- Future work:
  - Mutation surface: PEL extends the protocol from "agents refine the doc" to "agents refine the protocol itself"
  - Cross-tool interop: standardize marker format so different debate tools can hand artifacts back and forth
  - Formal verification: convergence argument is a sketch; a mechanized proof would strengthen the claim
  - Goodhart resistance: when proxy metrics drive the proposer, mitigations beyond human gating

## References

Compiled in `refs.bib`. Key citations to verify:
- Du et al. — Multi-Agent Debate
- Wu et al. — AutoGen
- Chan et al. — ChatEval
- Minsky — Society of Mind (background)
- Park et al. — Generative Agents (background)

**Do not invent citations.** If a paper title or author is uncertain, mark with `[CITATION-NEEDED]` and resolve before submission.

## Length budget

| Section | Target words |
|---------|--------------|
| 0. Abstract | 150 |
| 1. Introduction | 700 |
| 2. Protocol | 600 |
| 3. Convergence | 500 |
| 4. Pilot Data | 600 |
| 5. Comparison | 400 |
| 6. Limitations | 400 |
| **Total** | **~3,350** + figures + references → ~5 pages |

Aim for tight, declarative prose. No filler. Cut anything that doesn't advance the convergence-guarantee argument or the interop case.
