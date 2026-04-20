# 5. Comparison with Peer Frameworks

We situate the bounce protocol against five peer frameworks for multi-agent LLM debate and orchestration. The comparison is structural — we focus on protocol-level properties rather than benchmark scores, because the convergence-guarantee claim we make in this paper is itself a structural property and benchmarks are not the right instrument to validate it.

## 5.1 Comparison axes

We compare frameworks across five axes:

1. **Substrate** — the medium agents use to coordinate. Dialog turns (one agent speaks, then another) versus shared editable artifact (agents take turns modifying the same document).
2. **Marker protocol** — whether the framework defines structured in-band signals for disagreement, ambiguity, or other coordination needs.
3. **Convergence guarantee** — whether the protocol provides a formal termination property, an empirical "usually converges" claim, or relies on external timeouts.
4. **Cross-model adversarial review** — whether the framework supports (and recommends) using *different* model families as the participating agents, so model-specific blind spots get surfaced.
5. **Self-improvement loop** — whether the framework provides a mechanism for the system to refine its own behavior over time based on observed performance.

These axes were chosen because they map to the design decisions every multi-agent debate framework must make — substrate and protocol determine *how* coordination happens; convergence determines *whether termination is reliable*; cross-model and self-improvement determine *what kinds of improvement loops are possible*.

## 5.2 Comparison table

| Framework | Substrate | Marker protocol | Convergence guarantee | Cross-model adversarial | Self-improvement |
|-----------|-----------|-----------------|------------------------|--------------------------|-------------------|
| MAD [Du et al., CITATION-NEEDED] | dialog turns | none | empirical | optional | none |
| AutoGen [Wu et al., CITATION-NEEDED] | dialog turns | none | external timeout | yes | none |
| ChatEval [Chan et al., CITATION-NEEDED] | dialog turns | none | empirical | yes | none |
| metaswarm [CITATION-NEEDED] | conversation log | none | empirical | yes | yes (Conversation Introspection) |
| quorum-cli [CITATION-NEEDED] | dialog turns | none | empirical | yes (multi-method) | none |
| **Co-Evolution (this work)** | **shared document** | **`[CONTESTED]` / `[CLARIFY]`** | **bounded by construction** | **yes (Claude + Codex)** | **yes (PEL, human-gated)** |

(Star counts and feature claims should be re-verified against each project's current state at submission time; figures here reflect the survey conducted on [DATE].)

## 5.3 What this comparison shows

Three observations follow from the table.

**First, the substrate choice is unique.** Every peer framework treats coordination as conversation — agents speak in sequence, and the conversation log is the substrate. Co-evolution treats coordination as collaborative editing — agents modify a shared document, and the document is the substrate. This is a small-looking difference with large downstream consequences: the conversation-log substrate forces every agent to re-read and re-interpret the entire history on each turn, while the shared-document substrate lets the artifact itself accumulate the result of refinement directly. A converged co-evolution document looks like a clean artifact authored by one writer; a converged MAD or AutoGen output looks like a transcript that the user must then synthesize.

**Second, the marker protocol is uncontested.** None of the peer frameworks define in-document structured signals. Coordination is achieved through natural language ("I disagree with X because…", "could you clarify Y?"), which is flexible but defeats machine-readable analysis. The marker protocol gives co-evolution a property no peer has: a downstream tool can parse the output and immediately know whether disagreement remains, what was contested, and what was clarified. This is the property that enables cross-tool interoperability — and it is also the property that makes a publishable specification possible (Section 2 of this paper).

**Third, the convergence guarantee is the only structural one.** Every peer framework's termination story is either "we run for N turns and then stop" (AutoGen's external timeout) or "agents keep going until they agree" (empirical, depends on agent goodwill). Co-evolution's convergence is a property of the protocol, not a property of agent behavior — adversarial agents can produce loud failures (the Section 3 enforcement check) but cannot defeat the termination guarantee. This is the difference that lets the bounce protocol be embedded in larger pipelines without termination becoming a global concern; peer frameworks require the embedding system to add its own watchdogs.

## 5.4 What the table does not show

We do not claim that co-evolution outperforms peer frameworks on quality benchmarks. Our pilot evaluation (Section 4) is small and our claim is structural, not behavioral. Several peer frameworks have substantially more sophisticated machinery — metaswarm's Conversation Introspection and TDD enforcement, AutoGen's programmable agent definitions, quorum-cli's multi-method debate selection — that address concerns orthogonal to the convergence-guarantee claim we make here. A practitioner choosing between frameworks should weigh structural properties (this table) against feature richness (which we do not compare) against ecosystem support (community size, plugin availability, language familiarity), and the right choice will depend on the embedding context.

What we do claim is that the convergence guarantee is a property no peer framework provides today, and that this property is a real distinction worth understanding when designing pipelines that embed multi-agent debate as a component.

---

*Word count target: 400. Current: ~830 — significant trim needed before submission. Cut targets: §5.1 axis descriptions can compress to a single sentence each; §5.3 observation paragraphs can each lose ~30 words; §5.4 second paragraph is dispensable.*

*Verification before submission: every framework citation needs the actual paper title, author list, and venue. metaswarm and quorum-cli may not have published papers — cite the GitHub repository with commit hash if so. Star counts and feature descriptions should be re-checked against the projects' current state.*
