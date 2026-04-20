# Abstract

Multi-agent LLM debate frameworks have been shown to improve answer quality on reasoning tasks, but existing approaches share a structural weakness: debate is turn-based and termination is empirical, governed by external timeouts or heuristic stop conditions rather than by the protocol itself. We introduce a marker-based refinement protocol in which agents annotate disagreement (`[CONTESTED]`) and ambiguity (`[CLARIFY]`) inline within a shared document, and a staleness rule — every marker must be resolved by the final pass of a fixed *N*-pass budget — provides bounded convergence by construction. The protocol is substrate-agnostic but file-native by default, requires no shared state beyond the document, and accommodates adversarial role lenses (reviewer / composer) drawn from different model families. A reference implementation in approximately 200 lines of bash, with adapters for Claude and Codex CLIs, is released alongside this paper. Pilot evaluation across [N] document refinement tasks recovered [M] previously-unsurfaced issues, with [X%] of bounces converging within the default 2-pass budget. The protocol specification is published under CC0 to enable cross-tool interoperability.

---

*Word count target: 150. Current: ~190 — tighten before submission.*

*Open data points to verify:* `[N]` bounces, `[M]` issues recovered, `[X%]` convergence rate. Source: pilot run logs in `runs/` directory of [Co-Evolution repository](https://github.com/alanshurafa/co-evolution). Verify before publication; do not cite the brainstorm-memory placeholder ("11 bounces → 8 bugs") without re-running.
