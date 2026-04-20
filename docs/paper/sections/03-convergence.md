# 3. Convergence Argument

We claim that any conforming implementation of the bounce protocol terminates in at most *N* passes with zero unresolved markers. This section gives a proof sketch and discusses what the guarantee does and does not say.

## 3.1 Statement

Let *D* be a document, *N ≥ 1* a fixed pass budget, and let *m(D)* denote the number of `[CONTESTED]` and `[CLARIFY]` markers present in *D*. A conforming implementation of the bounce protocol, given (*D*, *N*) and a sequence of agents, halts after exactly *N* passes producing a document *D′* such that *m(D′) = 0*.

## 3.2 Proof sketch

The argument has three steps, each grounded in a structural property of the protocol.

**Step 1: bounded execution.** The protocol specifies *N* as fixed before the bounce begins. The main loop runs exactly *N* times; there is no condition that can extend or shorten the loop. Therefore the protocol halts after exactly *N* agent invocations.

**Step 2: monotone marker decay on the final pass.** The protocol's resolution rule states that on the final pass — pass *N* — agents must (a) not introduce new markers and (b) resolve all inherited markers. Resolving a marker means deleting it from *D*. Therefore, between the start and end of pass *N*, the marker count *m(D)* is constrained: the agent may only delete markers, never add. Combined with the requirement that all inherited markers be resolved, the post-pass-*N* marker count is *m(D′) = 0*.

**Step 3: rule enforcement.** For Step 2 to hold, the implementation must enforce the final-pass constraint. The reference implementation does this by checking `m(D)` after pass *N* completes; if any markers remain, the implementation halts with a non-zero exit code rather than returning a non-converged artifact. This is the only point at which the protocol can fail, and the failure is observable: the caller knows the bounce did not converge and can take corrective action (e.g., re-run with larger *N*, escalate to a human reviewer, reject the document).

Combining the three steps: the protocol always executes in bounded time (Step 1), and either produces *D′* with *m(D′) = 0* (Steps 2 + 3) or fails loudly with the precondition violation localized (Step 3). The "converged or failed-explicit" property is exactly the convergence guarantee we claim.

## 3.3 What this guarantee says

The guarantee is structural, not behavioral. It depends on three things — fixed *N*, the deletion-not-reply resolution rule, and final-pass enforcement — all of which are properties of the protocol itself, not of agent behavior. An adversarial agent that ignores the resolution rule cannot defeat the guarantee; it can only cause the loud failure in Step 3, which is an *observable* outcome rather than the silent non-termination that conventional debate frameworks risk.

This separation matters for composition. Because termination is a structural property, the bounce protocol can be embedded in larger pipelines without termination becoming a global concern. A caller can wrap a bounce in a wider workflow knowing that the bounce will return — converged or explicitly-failed — within a bounded wall-clock that depends only on *N* and per-pass cost. Frameworks without this property require the caller to add their own watchdogs, retry logic, and stagnation detectors.

## 3.4 What this guarantee does not say

The guarantee says nothing about the *quality* of the converged document. A bounce can converge to a document that is wrong, vague, or even worse than the input — convergence is a necessary but not sufficient condition for useful debate. We make no claim that the protocol produces good documents; we claim only that the protocol produces documents with zero unresolved markers, in bounded time, every time.

This is the right factoring. Quality is the joint responsibility of the agents, the prompts, the role lenses, and the document being refined — variables that span model selection, prompt engineering, and task framing, none of which the protocol can control. By separating *whether the bounce terminates* from *whether the result is good*, the protocol leaves quality concerns to where they belong (model and prompt design) while providing the structural guarantee that lower layers in a system stack typically expect: bounded resource consumption with a defined success/failure contract.

A useful analogy is type-checking. A type system guarantees that certain classes of error cannot occur at runtime; it does not guarantee that a well-typed program is correct. Convergence is the bounce-protocol analogue: a converged document cannot have unresolved disagreements; it can still be wrong about everything else.

## 3.5 Caveats

Two caveats are worth stating explicitly.

First, the guarantee assumes a conforming implementation. Implementations that omit the final-pass enforcement (Step 3) will produce non-converged documents under adversarial or simply-distracted agents; the guarantee is only as strong as the implementation's enforcement loop. We provide the reference implementation as the proof-of-concept that enforcement is straightforward to implement (the check is a single `grep` on the document).

Second, the guarantee is about marker presence, not semantic resolution. An agent could in principle "resolve" a `[CONTESTED]` marker by deleting it without addressing the underlying disagreement — i.e., conform to the protocol while violating its spirit. This failure mode is real but is a property of the agent, not the protocol, and is detectable by inspecting the per-pass artifacts in the run directory: a pass that deletes markers without changing the surrounding text is a strong signal of non-substantive resolution. Future work could automate this detection; the current implementation surfaces the artifacts and leaves judgment to the human reviewer.

---

*Word count target: 500. Current: ~770 — significant trim needed before submission. Cut targets: §3.4 paragraph 3 (the type-checking analogy) is dispensable if space-tight; §3.5 second caveat could compress to one sentence with a footnote.*
