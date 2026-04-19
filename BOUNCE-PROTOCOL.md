# Bounce Protocol

**Version:** 0.1 (2026-04-19)
**Status:** Draft — open for adoption
**Reference implementation:** [`agent-bouncer/`](agent-bouncer/) in this repo

A convention for structured iterative refinement between AI agents using in-document markers with auto-expiry. Two agents take turns editing the same document; structured disagreement is recorded inline; staleness rules guarantee convergence in a bounded number of passes.

## Markers

Two markers are defined. Both appear inline in the document, on a line immediately below the text they reference.

### `[CONTESTED]`

Used when an agent disagrees with the preceding text and proposes a concrete alternative.

```
The classifier should retry on transient errors with exponential backoff up to 5 attempts.
[CONTESTED] Five attempts is too aggressive for an LLM call costing $0.10/invocation.
Cap at 2 attempts and surface the failure; let the caller decide whether to retry.
```

A `[CONTESTED]` note must include both the disagreement and a specific alternative. Notes that only register dissent ("I disagree") are non-conforming.

### `[CLARIFY]`

Used when an agent finds the preceding text ambiguous and needs the next agent to disambiguate.

```
Rate-limit all endpoints.
[CLARIFY] Does "all endpoints" include /metrics and /health? (A) Yes, treat all paths
equally. (B) No, exempt observability endpoints.
```

A `[CLARIFY]` note must include either two concrete interpretations or a question with a finite answer space. Open-ended notes ("what does this mean?") are non-conforming.

## Convergence rule

The protocol guarantees termination in a bounded number of passes:

1. The bounce runs for at most `N` passes (typically 2). `N` is fixed before the bounce starts.
2. On every pass except the last, agents may add new `[CONTESTED]` / `[CLARIFY]` notes and may resolve inherited ones (resolving = deleting the note, not replying to it).
3. On the **final pass**, the agent **must not** introduce new notes and **must** resolve every remaining inherited note.
4. The document is converged when zero `[CONTESTED]` and zero `[CLARIFY]` notes remain.

Total wall-clock cost is capped: at most `N` passes × cost-per-pass. The number of unresolved notes is strictly bounded after the final pass — by rule 3, it is zero.

This is the protocol's load-bearing property. Without the final-pass rule, debate can chain indefinitely; with it, every bounce produces a converged artifact in finite time.

## Role lens (optional layer)

Implementations may assign each pass a **role lens** to bias the agent's perspective. The reference implementation uses two:

- **Reviewer** — looks for what's missing, wrong, or unclear. Adds notes liberally.
- **Composer** — integrates resolutions. Resolves notes liberally; adds new notes only when genuinely necessary.

Roles typically alternate by pass. The protocol does not require any specific role taxonomy — implementations may use domain-specific lenses (e.g., `security` / `performance` / `correctness`).

## Substrate

The protocol is substrate-agnostic. The reference implementation uses markdown files on the filesystem, but the markers are plain text and work in any text-editable document. JSON, source code, plain text, RFC drafts, and chat transcripts have all been demonstrated.

## Minimal conforming implementation

A conforming implementation must:

1. Accept a document and a fixed pass budget `N ≥ 1`
2. Run two agents alternately for `N` passes
3. Pass each agent a prompt that includes the current document, the pass number, and the agent's role
4. Enforce the final-pass resolution rule (count markers; reject output that violates rule 3)
5. Return the converged document

Optional but recommended: persist per-pass artifacts (the document state after each pass) for audit and debugging. The reference implementation writes these to `runs/bouncer-{name}-{timestamp}/`.

## Adoption

This protocol is published as an open convention. Tools that emit and resolve these markers can interoperate — a document refined by one tool can be picked up and refined further by another, as long as both honor the convergence rule.

To adopt:

1. Implement the marker format above
2. Wire it into your existing multi-agent pipeline as an in-document refinement layer
3. Honor rule 3 (final-pass resolution) — this is the only non-negotiable

The reference implementation in [`agent-bouncer/`](agent-bouncer/) is ~200 lines of bash, agent-agnostic, and ships with adapters for Claude and Codex CLIs. Adapters for additional agents are 5–10 lines each.

## License

This specification is published under [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) — no rights reserved. Adopt freely.

---

*Co-Evolution project: [github.com/alanshurafa/co-evolution](https://github.com/alanshurafa/co-evolution)*
