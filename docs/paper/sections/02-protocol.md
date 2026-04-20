# 2. The Bounce Protocol

We specify the protocol in four parts: substrate, markers, pass mechanics, and resolution semantics. The complete specification is also published as a standalone artifact under CC0 (`BOUNCE-PROTOCOL.md`); this section gives the formal version with the language tightened for citation.

## 2.1 Substrate

A *bounce* operates on a single editable document — typically a markdown file, but the protocol is substrate-agnostic and has been demonstrated on JSON, source code, plain text, and chat transcripts. The document is the only shared state. There is no separate dialog log, no agent memory across passes, and no out-of-band channel. This constraint is intentional: it forces all coordination to happen *in the artifact*, where it remains inspectable, auditable, and resumable from any point in time.

Concretely, the reference implementation uses the local filesystem as substrate: the input document path is passed to each agent, the agent reads it, edits it in place, and the next agent reads the updated file. Per-pass copies are written to a run directory for audit, but the canonical document is always the working file.

## 2.2 Markers

Two markers are defined. Both appear inline in the document, on a line immediately below the text they reference, with no surrounding decoration.

**`[CONTESTED]`** — used when an agent disagrees with the preceding text and proposes a concrete alternative:

```
The classifier should retry on transient errors with exponential backoff up to 5 attempts.
[CONTESTED] Five attempts is too aggressive for an LLM call costing $0.10/invocation.
Cap at 2 attempts and surface the failure; let the caller decide whether to retry.
```

A `[CONTESTED]` note must include both the disagreement and a specific alternative. Notes that only register dissent ("I disagree") are non-conforming and should be rejected by the implementation.

**`[CLARIFY]`** — used when an agent finds the preceding text ambiguous:

```
Rate-limit all endpoints.
[CLARIFY] Does "all endpoints" include /metrics and /health? (A) Yes, treat all
paths equally. (B) No, exempt observability endpoints.
```

A `[CLARIFY]` note must include either two concrete interpretations or a question with a finite answer space. Open-ended notes ("what does this mean?") are non-conforming.

The two markers cover the two failure modes of a debate: substantive disagreement (handled by `[CONTESTED]`) and unsharable understanding (handled by `[CLARIFY]`). We do not introduce additional markers because the protocol's load-bearing property — convergence by construction — relies on a small, well-defined marker vocabulary that every conforming implementation can parse uniformly.

## 2.3 Pass mechanics

A bounce consists of *N* passes, where *N ≥ 1* is fixed before the bounce begins. On each pass, exactly one agent operates on the document. Agents alternate by pass, so for *N = 2* — the default — agent A acts on pass 1 and agent B on pass 2. For *N > 2*, the alternation continues; agent identity is determined by `pass_number mod 2`.

Each agent receives a prompt that includes the current document, the pass number, the total pass budget, and the agent's role. The reference implementation uses two role lenses:

- **Reviewer** — looks for what is missing, wrong, or unclear; adds markers liberally
- **Composer** — integrates resolutions; resolves markers liberally; adds new markers only when genuinely necessary

Roles are an optional layer. The protocol does not require any specific role taxonomy; implementations may use domain-specific lenses (e.g., `security`, `performance`, `correctness`) or no roles at all. What the protocol does require is that the role assignment be communicated to the agent in the prompt, so the agent's behavior can be tuned per pass.

## 2.4 Resolution semantics

When an agent encounters an inherited marker (one added by a previous agent), it has two options:

1. **Resolve** — apply the alternative or disambiguation suggested by the marker, then *delete the marker*. The resolution is recorded in the document's text itself, not as a reply or comment to the marker.
2. **Leave** — do nothing. The marker passes through to the next agent.

The "delete, don't reply" rule is the second key constraint. Replying inflates the document with debate metadata that the next agent must then ignore; deletion keeps the document a clean artifact at every step. Anyone reading the document at the end of a bounce sees only converged content, with no trace of the disagreements that produced it. (Audit trails of the bounce are preserved in the run directory, separate from the canonical document.)

Convergence is defined precisely: a document is *converged* when it contains zero `[CONTESTED]` and zero `[CLARIFY]` markers. The next section shows that the protocol guarantees a converged document at the end of pass *N*.

## 2.5 Reference implementation

A minimal conforming implementation is approximately 30 lines of bash:

```bash
#!/usr/bin/env bash
# bounce.sh DOC N AGENT_A AGENT_B
set -euo pipefail
DOC="$1"; N="$2"; AGENT_A="$3"; AGENT_B="$4"

for ((pass=1; pass<=N; pass++)); do
  if (( pass % 2 == 1 )); then
    AGENT="$AGENT_A"; ROLE="reviewer"
  else
    AGENT="$AGENT_B"; ROLE="composer"
  fi

  # Pass the document plus role/pass context; agent edits DOC in place.
  PROMPT=$(render_prompt "$ROLE" "$pass" "$N" "$(cat "$DOC")")
  printf '%s' "$PROMPT" | "$AGENT" --output "$DOC"

  # Enforce the staleness rule on the final pass.
  if (( pass == N )); then
    if grep -q '\[CONTESTED\]\|\[CLARIFY\]' "$DOC"; then
      echo "FATAL: unresolved markers after final pass" >&2
      exit 1
    fi
  fi
done
```

The full reference implementation in `agent-bouncer.sh` (≈200 lines) adds run-directory management, per-pass artifact preservation, model-specific adapter functions, error handling for agent failures, and progress logging. None of these change the protocol; they are operational concerns of running the protocol in production.

Adapters for new agents are 5–10 lines each. The reference implementation ships with adapters for the Claude and Codex command-line interfaces; adding a new agent (Gemini, a local Ollama instance, an HTTP API) requires only writing a function that takes a prompt on stdin and writes the agent's response to a specified output path.

---

*Word count target: 600. Current: ~860 — significant trim needed before submission. Cut targets: §2.1 paragraph 2 can compress to one sentence; §2.3 last paragraph could be a footnote; §2.5 could lose the "full reference implementation" paragraph if space tight.*
