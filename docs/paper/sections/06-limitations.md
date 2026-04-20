# 6. Limitations and Future Work

We close by stating four limitations of the work as presented and four directions for future work that the protocol naturally enables.

## 6.1 Limitations

**Convergence is not correctness.** The convergence guarantee proven in Section 3 establishes that bounces terminate in bounded time with zero unresolved markers — it says nothing about whether the converged document is true, useful, or better than the input. Agents can converge to a bad answer just as reliably as they can converge to a good one. Quality remains the joint responsibility of the agents, the prompts, the role lenses, and the document being refined; the protocol provides only the structural envelope within which those quality concerns operate. This is the right factoring (we argue in Section 3.4), but it means the protocol cannot be evaluated by quality benchmarks alone — its contribution is a property that quality-focused evaluations are not designed to measure.

**Pilot evaluation is small.** The pilot reported in Section 4 covers [N] document-refinement tasks across a single domain. We make no claim that the bug-catch and convergence rates generalize to other domains, longer documents, or different agent populations. A larger evaluation — across academic writing, code review, legal drafting, and policy analysis — would strengthen the empirical case substantially. We have deliberately scoped this paper to the protocol specification and convergence argument, leaving broader evaluation as future work.

**Marker semantics depend on agent compliance.** A `[CONTESTED]` marker is well-formed only if it includes a concrete alternative; a `[CLARIFY]` marker is well-formed only if it includes finite-answer disambiguation. The protocol relies on the agent producing well-formed markers in the first place. An adversarial or distracted agent can produce malformed markers ("I disagree" with no alternative) that conform to the syntax but violate the spirit of the protocol. The current implementation does not validate marker well-formedness; this is a meaningful gap that production deployments should close.

**Substrate assumes textual artifacts.** The protocol as specified assumes a markdown-or-similar text substrate. Non-textual artifacts — images, audio, video, binary files — would require an extension (perhaps a sidecar metadata file containing markers that reference regions of the binary). We have not attempted this extension and do not currently know whether the convergence properties carry over cleanly. A multimodal version of the protocol is plausible but not specified here.

## 6.2 Future work

**Mutation surface — the Protocol Evolution Loop (PEL).** The current implementation includes an experimental subsystem that extends the protocol from "agents refine the document" to "agents refine the protocol itself." A PEL invocation classifies the type of weakness an evaluation surfaces (template-tier, policy-tier, or code-tier), runs a tier-specific proposer that generates a candidate mutation to the corresponding repository surface, scores the mutation against an evaluation harness, and emits a draft pull request for human review. The human-review gate is the load-bearing safety constraint — autonomous mutation merging is explicitly out of scope until further mitigations for Goodhart-style metric gaming are in place. We see PEL as a path toward a self-improving multi-agent debate framework that retains the convergence-guarantee property of the underlying protocol.

**Cross-tool interoperability.** Because the marker protocol is a CC0 specification with conformance rules, multiple tools can adopt it independently and produce artifacts that interoperate. A document refined by tool A could be picked up and further refined by tool B if both honor the conformance rules; the staleness rule guarantees both will produce a converged artifact in bounded time. This is the standardization play that motivates the spec's separate publication. Active outreach to peer-framework maintainers is underway; whether the markers achieve adoption beyond the reference implementation is the open question that the next several quarters will answer.

**Mechanized convergence proof.** The proof sketch in Section 3 is informal — three numbered steps in prose. The protocol is simple enough that a mechanized proof in a theorem prover (Coq, Lean, or similar) would be tractable, and would let the convergence claim be verified rather than reviewed. We have not attempted this mechanization and welcome contributions from the formal-methods community.

**Goodhart resistance for autonomous proposers.** PEL's current mitigation against metric gaming is the human review gate — every mutation surfaces as a draft pull request that a human accepts or rejects. This works at low volume but does not scale. Higher-volume autonomous proposing (without mandatory human gating) would require deeper Goodhart mitigations: ensemble fitness functions, adversarial evaluation, holdout sets, or canary-style production-traffic validation. We treat this as a research question that gates the move from "proposer with human gate" to "auto-promoter" in the PEL roadmap.

## 6.3 Closing observation

Multi-agent LLM debate has rapidly accumulated useful techniques but has not, until now, accumulated structural guarantees. We have argued that the convergence-guarantee property is worth pursuing as a protocol-level property — not because it solves the quality problem (it does not) but because it factors out termination as a concern that can be reasoned about independently. The bounce protocol is one realization of this property; we hope it is not the last.

---

*Word count target: 400. Current: ~720 — significant trim needed before submission. Cut targets: §6.1 last two limitations could compress to one paragraph each; §6.2 last two future-work items could merge; §6.3 closing observation is dispensable if space-tight.*
