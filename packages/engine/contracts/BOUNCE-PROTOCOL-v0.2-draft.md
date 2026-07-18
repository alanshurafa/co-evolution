# Bounce Protocol

**Version:** 0.2 (2026-07-17)
**Status:** Draft v0.2 (internal)
**Reference implementation:** the co-evolve runtime in this repository — see [Reference implementation](#reference-implementation).

A convention for structured iterative refinement between AI agents using
in-document markers. Two agents take turns editing the same document; structured
disagreement is recorded inline; a fixed pass budget bounds the number of turns
and yields an explicit terminal outcome.

The keywords MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY in this document are to
be read as normative requirement levels.

## Scope

The Bounce Protocol comprises exactly three things:

1. The **marker grammar** — the inline `[CONTESTED]` and `[CLARIFY]` notes.
2. The **loop semantics** — how agents alternate and edit the shared document.
3. The **termination rules** — the pass budget, adjudication, and terminal
   outcomes.

Everything else is out of scope. In particular, the `review-verdict` JSON schema
(`skills/dev-review/schemas/review-verdict.json`) is a downstream contract
consumed by the verifier role. It is versioned separately and is NOT part of this
protocol (see `.planning/rebuild/DECISIONS.md`, D2). A change to that schema does
not change the protocol version, and vice versa.

## Markers

Two markers are defined. Both appear inline in the document, on a line
immediately below the text they reference.

### `[CONTESTED]`

Used when an agent disagrees with the preceding text and proposes a concrete
alternative.

```
The classifier should retry on transient errors with exponential backoff up to 5 attempts.
[CONTESTED] Five attempts is too aggressive for an LLM call costing $0.10/invocation.
Cap at 2 attempts and surface the failure; let the caller decide whether to retry.
```

A `[CONTESTED]` note MUST include both the disagreement and a specific
alternative. Notes that only register dissent ("I disagree") are non-conforming.

### `[CLARIFY]`

Used when an agent finds the preceding text ambiguous and needs the next agent to
disambiguate.

```
Rate-limit all endpoints.
[CLARIFY] Does "all endpoints" include /metrics and /health? (A) Yes, treat all paths
equally. (B) No, exempt observability endpoints.
```

A `[CLARIFY]` note MUST include either two concrete interpretations or a question
with a finite answer space. Open-ended notes ("what does this mean?") are
non-conforming.

## Loop semantics

An implementation runs two agents alternately over a shared document. Each pass,
the acting agent:

1. Reads the document as the current version.
2. Edits the text in place. It MUST NOT use diff syntax, strikethroughs, tracked
   changes, or a separate review block; the document MUST always read as a single
   clean artifact.
3. MAY improve text it agrees with directly, without commentary.
4. MAY add a `[CONTESTED]` or `[CLARIFY]` note below text it disagrees with or
   finds ambiguous, subject to the termination rules below.
5. MAY resolve an inherited note. Resolution means deleting the note after acting
   on it, not replying to it.

Agents are assigned a role each pass (see [Roles](#roles)). Roles bias the
agent's behavior but do not change the marker grammar or the termination rules.

## Termination rules

### The pass-budget rule (the single expiry mechanism)

There is exactly one marker-expiry mechanism: the pass budget.

1. A bounce MUST run for a fixed pass budget `N ≥ 1`, chosen before the first
   pass. The reference implementation defaults to `N = 2`.
2. On every pass before the final pass, an agent MAY introduce new notes and MAY
   resolve inherited notes.
3. On the **final pass**, an agent MUST NOT introduce new notes and MUST resolve
   every remaining inherited note.

At most `N` passes run, so wall-clock cost is bounded by `N × cost-per-pass`. Item
3 above is the final-pass clause of the pass-budget rule (hereafter: the
final-pass clause).

> **Deprecated framing — "per-marker 2-pass staleness."** Earlier prose
> (`skills/dev-review/SKILL.md`, `agent-bouncer/README.md`, `llms.txt`) described
> a rule where an individual marker "expires" after surviving 2 passes,
> independent of `N`. That framing is a documentation error and is DEPRECATED. It
> was never present in the operative prompt template — which exists as two
> byte-identical copies, `agent-bouncer/templates/bounce-protocol.md` and
> `skills/dev-review/templates/bounce-protocol.md` — and was never implemented in
> any runner; `skills/dev-review/SKILL.md` additionally mis-attributes it to the
> template. The number 2 entered the prose only because the default budget is
> `N = 2`. The pass-budget rule above is the sole expiry mechanism.

### Adjudication

The final-pass clause is a requirement on agent behavior, not a guarantee that
agents comply. When notes survive the pass budget, a conforming runner SHOULD run
at most one **adjudication** pass: a single forced-resolution pass whose only job
is to resolve every surviving note and to record, per marker, the text it chose
and a one-line rationale. Adjudication adds at most one pass to the budget.

The reference implementation renders this pass from
`templates/co-evolve/adjudicate.md` via `run_adjudication()` in the co-evolve
runtime (`co-evolve-bouncer.sh`).

### Terminal outcomes

A run reports two independent fields.

- **`run_status`** — the operational lifecycle of the run process (for example
  `running`, `completed`, `aborted`, `error`). It answers "did the run execute to
  completion?" Exact values are implementation-defined.
- **`protocol_outcome`** — the marker-resolution terminal state, one of:
  - **`converged`** — markers reached zero within the pass budget. No
    adjudication ran; the artifact is byte-identical to the pre-adjudication
    document.
  - **`adjudicated`** — markers survived the budget, and one adjudication pass
    resolved each while recording a per-marker rationale report.
  - **`stuck`** — adjudication could not defensibly resolve every marker. The
    document is preserved WITH its markers, labeled non-final, and MUST fail the
    behavior gate (`evals/score-bounce.sh`'s term for this check).

The two fields are independent: a run MAY report `run_status = completed` while
`protocol_outcome = stuck`. Implementations SHOULD persist both fields in run
state.

The protocol does **not** guarantee convergence. It guarantees a bounded number
of protocol turns (at most `N` passes plus at most one adjudication pass) and an
explicit terminal signal. Non-convergence MUST be signaled through
`protocol_outcome`, never hidden by silently stripping or forcing markers.

> **Note (serialization).** This spec names the terminal-outcome field
> `protocol_outcome`. The co-evolve reference runtime currently serializes it in
> `state.json` as `convergence_status` with the same three values. Aligning the
> serialized field name to `protocol_outcome` is a forward-compatibility item;
> the concept is normative, the field name is not.

## Roles

Role **alternation** is structural and REQUIRED: a conforming implementation
MUST assign each pass to one of two alternating seats — reviewer-seat and
composer-seat — taken in alternation by pass parity, so the two agents take
turns. Role **lensing** — biasing an agent's perspective with a persona template
or domain focus (for example `security` / `performance` / `correctness`,
adversarial, light/heavy) — is an OPTIONAL layer on top of alternation. A
conforming implementation MAY run without any lens differentiation: two agents
alternating seats with no persona text still conforms. The protocol does not
mandate a specific lens taxonomy. The reference implementation uses the
following live taxonomy.

| Role | Template variant(s) | Adds markers? | Stage | Notes |
|------|---------------------|---------------|-------|-------|
| composer | heavy, light | Sparingly | bounce loop | Integrates resolutions; adds notes only when genuinely necessary. Light variant for smaller inputs. |
| reviewer | heavy, light | Liberally | bounce loop | Looks for what is missing, wrong, or unclear. A structured adversarial reviewer variant also ships (`role-reviewer-adversarial.md`). |
| chain: critique | critique, critique-adversarial | Liberally | bounce loop (chain mode) | Opens disagreement on the composed draft. |
| chain: defend | defend | Resolves | bounce loop (chain mode) | Steelmans or rebuts contested text. |
| chain: tighten | tighten | Resolves | bounce loop (chain mode) | Consolidates and trims to a final draft. |
| executor | dev-prompt | No | downstream pipeline | Obedience-only: executes the converged plan with **no disagreement channel**. The absence of a marker path here is deliberate — execution must not re-litigate a converged plan. |
| verifier | review-prompt | No | downstream pipeline | Emits schema-bound output against the downstream `review-verdict` contract (out of protocol scope; see [Scope](#scope)). |

Per-runner defaults differ. The co-evolve runtime's preamble builders
(`build_reviewer_preamble`, `build_composer_preamble` in `co-evolve-bouncer.sh`)
load only the light variants by default, or `role-reviewer-adversarial.md` under
`--adversarial` — never the heavy variants. The legacy `agent-bouncer/` runner
and dev-review's bounce step (`dev-review/codex/dev-review.sh`) default to the
heavy variants (`agent-bouncer/templates/role-composer.md`,
`agent-bouncer/templates/role-reviewer.md`).

The `executor` and `verifier` roles operate on the code pipeline that consumes a
converged plan; they are outside the bounce loop itself and are listed here only
to fix the full role vocabulary.

**Retired role.** The `arbitrate` role is RETIRED (`DECISIONS.md`, D2). It named a
forced-resolution pass that exists only in the frozen `runners/codex-ps`
reference tree; the live protocol expresses that same function as the
adjudication step producing `protocol_outcome = adjudicated`, so a distinct
`arbitrate` role would be a second name for one mechanism.

## Conformance

A conforming implementation MUST:

1. Accept a document and a fixed pass budget `N ≥ 1`.
2. Run two agents alternately for at most `N` passes, plus at most one
   adjudication pass.
3. Pass each agent a prompt that includes the current document, the pass number,
   and which seat — reviewer-seat or composer-seat — the agent occupies this
   pass. A persona lens MAY additionally be included; it is not required for
   conformance.
4. **Detect** final-pass clause violations — markers remaining after the final
   pass — and **signal** them: emit a warning and record the condition in run
   state (for example `protocol_outcome = stuck`).
5. Return the document together with its `run_status` and `protocol_outcome`.

A conforming implementation SHOULD reject or quarantine output that violates the
final-pass clause. In the base document-bounce path — the bounce loop itself,
prior to any downstream consumer — no current runner performs hard rejection:
runners detect the violation, signal it, and preserve the marked document
labeled non-final. Automatic in-loop rejection, and a reference enforcement
implementation for it, are DEFERRED to v1.0.

> **Partial enforcement today.** A hard-rejection implementation already exists
> at a downstream consumption boundary, not in the loop: `co-evolve-bouncer.sh`'s
> `--execute` flag refuses (exit 1) to hand a `protocol_outcome = stuck` document
> to the code-execution pipeline. This is consumer-side enforcement; the bounce
> loop that produced the stuck document still terminates without rejecting its
> own output, which is what remains deferred to v1.0.

(v0.1 stated that implementations must "reject output that violates rule 3"; no
runner enforces that inside the base bounce loop, so this clause is rewritten to
match reality.)

Implementations SHOULD persist per-pass artifacts (the document state after each
pass) for audit and debugging. For example, the co-evolve reference runtime
writes these under `$RUNS_ROOT/co-evolve-{label}-{timestamp}/` (default `runs/`,
overridable via `CO_EVOLVE_RUNS_DIR`).

## Substrate

The protocol is substrate-agnostic. The markers are plain text and work in any
text-editable document. Markdown files on the filesystem, JSON, source code,
plain text, RFC drafts, and chat transcripts have all been demonstrated.

## Reference implementation

The current reference implementation is the **co-evolve runtime** in this
repository: the runner plus the shared `templates/` and `schemas/` prompt
contract. It emits and resolves the markers above, runs the pass-budget and
adjudication rules, and records `run_status` and `protocol_outcome` in run state.

The legacy `agent-bouncer/` runner still operates but is **pending
deprecation**; new adopters SHOULD target the co-evolve runtime.

Reference pointers name a runtime, not a language or a substrate. Any
implementation that honors the marker grammar, the loop semantics, and the
termination rules conforms, regardless of how it is built.

## Adoption

This protocol is published as an open convention. Tools that emit and resolve
these markers can interoperate: a document refined by one tool can be picked up
and refined further by another, as long as both honor the termination rules.

To adopt:

1. Implement the marker grammar. **(non-negotiable core)**
2. Wire it into your multi-agent pipeline as an in-document refinement layer.
   *(recommended)*
3. Honor the pass-budget rule, including the final-pass clause. **(non-negotiable
   core)**
4. Report both `run_status` and `protocol_outcome`, and signal `stuck` rather
   than forcing a false convergence. *(recommended)*

Items 1 and 3 together are the non-negotiable core: the marker grammar
implemented and the pass-budget rule honored end to end. Items 2 and 4 are
recommended integration and observability practice — valuable, but not required
for a document to interoperate with tools that honor the core.

## Changelog — v0.1 → v0.2

This draft applies eight changes to v0.1: six substantive fixes to the protocol
text (1–6) and two additions to this deliverable's own apparatus (7–8).

**Provenance.** Fixes 1–5 implement AUTHORITY rebuild-proposal §3.3
(`Admin/docs/rebuild-proposals/co-evolution.md`), as scoped into this draft by
`.planning/rebuild/PHASE-0-PLAN.md` WP-09. Fix 6 is not a §3.3 item — it is an
author-initiated correction of v0.1's false convergence guarantee, sourced from
the rebuild proposal's §1 Non-goals and the §3.1 C-7 correction. Fixes 7–8
originate with this deliverable and have no §3.3 source.

1. **Single expiry rule.** Consolidated to one mechanism — the pass-budget rule.
   Explicitly deprecated the "per-marker 2-pass staleness" framing as a
   documentation error that was never in the operative template nor implemented
   in any runner.
2. **Honest conformance clause.** v0.1 required implementations to "reject output
   that violates rule 3," which no runner does. Rewrote to: conforming runners
   MUST detect and signal violations; output rejection is a SHOULD, deferred to
   v1.0 with a reference enforcement implementation. v0.2 additionally records
   the one partial enforcement implementation that already exists at a
   downstream consumption boundary (`--execute`'s stuck-refusal).
3. **Scope boundary.** Stated the protocol as marker grammar + loop semantics +
   termination rules, and put the `review-verdict` JSON schema explicitly out of
   scope as a separately-versioned downstream contract (D2).
4. **Role taxonomy.** Added a single table for composer, reviewer (heavy/light),
   chain critique/defend/tighten, executor (obedience-only), and verifier
   (schema-bound). Recorded that `arbitrate` is retired (D2). Distinguished
   required role alternation from optional role lensing, and recorded each
   runner's actual default template variant.
5. **Reference implementation pointer.** Moved the pointer from `agent-bouncer/`
   to the co-evolve runtime, and noted agent-bouncer's pending deprecation. Kept
   the pointer substrate-agnostic.
6. **Terminal outcomes.** Replaced "guarantees convergence" with a two-field
   model — `run_status` (operational lifecycle) versus `protocol_outcome`
   (`converged` | `adjudicated` | `stuck`) — bounded protocol turns, and explicit
   non-convergence signaling. Author-initiated; see Provenance above — not a
   §3.3 item.
7. **Normative-keyword convention.** Adopted RFC 2119 MUST / MUST NOT / SHOULD /
   SHOULD NOT / MAY as defined normative requirement levels (see the note under
   the title block). v0.1 used these words informally, with no defined meaning.
   This convention itself is new in v0.2.
8. **Changelog and fix-mapping table.** This changelog section and the
   fix-mapping checklist below are new structural additions in v0.2; v0.1 had
   neither.

## Fix-mapping checklist

| Fix | Summary | Section(s) applied | Source |
|-----|---------|--------------------|--------|
| 1 | One expiry rule; deprecate per-marker 2-pass staleness | Termination rules → The pass-budget rule | §3.3 |
| 2 | Honest conformance: MUST detect+signal, SHOULD reject (v1.0); partial enforcement noted | Conformance | §3.3 |
| 3 | Scope boundary; review-verdict schema out of scope (D2) | Scope | §3.3 |
| 4 | Role taxonomy table; arbitrate retired (D2); alternation vs. lensing; per-runner defaults | Roles | §3.3 |
| 5 | Reference pointer → co-evolve runtime; agent-bouncer deprecating | Reference implementation | §3.3 |
| 6 | Terminal outcomes: run_status vs protocol_outcome; no guaranteed convergence | Termination rules → Terminal outcomes | §1 Non-goals / §3.1 (C-7); author-initiated |
| 7 | Normative-keyword (RFC 2119) convention disclosed | Title block; Changelog | This deliverable |
| 8 | Changelog + fix-mapping table are new structural additions | Changelog; Fix-mapping checklist | This deliverable |

## License

This specification is published under [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) — no rights reserved. Adopt freely.

---

*Co-Evolution project: [github.com/alanshurafa/co-evolution](https://github.com/alanshurafa/co-evolution)*
