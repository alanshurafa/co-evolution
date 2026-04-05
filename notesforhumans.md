---
audience: human
agent-ignore: true
---

# Co-Evolution — Notes for Humans

## What This Is Really About

Co-Evolution is a set of tools for agents and humans to refine ideas together.

The README describes the mechanics — bounce protocols, marker systems, adapters. But the deeper idea is that the best results come from structured tension between different perspectives. Not adversarial. Not competitive. Constructive pressure, applied iteratively, until the output is better than any single contributor could produce.

This applies to agents bouncing a plan between each other. It also applies to a human and an agent working together — the human provides intent, context, and judgment; the agent provides speed, consistency, and a different set of blind spots. Co-evolution isn't just agents refining documents. It's a pattern for collaborative refinement between any combination of agents and humans.

The tools in this repo are the first implementations of that pattern. More will follow.

## Origin

Co-Evolution started as clipboard labor.

Alan Shurafa was using two AI agents — Claude Code (Opus) and Codex — on the same tasks. One would draft a plan, he'd copy it to the other for review, wait for the response, copy the feedback back, wait again. The plans got better with each pass, but the process was painful. Every round trip meant switching windows, selecting text, pasting, and hoping you didn't lose something in transit.

The first version was a Claude Code skill called `/dev-review`. It automated the copy-paste loop: one command kicked off the compose, bounced the plan between agents, and handed the refined result to an executor. It worked, but it was wired specifically to Claude and Codex, and you had to be inside Claude Code to use it.

Co-Evolution extracts the core idea into a standalone tool called the Agent Bouncer (`agent-bouncer.sh`) that runs from any terminal. It ships with adapters for Claude and Codex; adding a new agent means adding one `invoke_<name>` function — no framework changes required. The Claude Code skill still exists alongside it for users who want the full compose-bounce-execute-verify workflow inside Claude Code.

## What is a Bounce?

A bounce is one pass of a document between agents. You send the plan to Agent A, it reads it, improves it, marks disagreements, and sends it back. That's one bounce. Then Agent B gets it, resolves the disagreements, tightens the language, and sends it back. That's two bounces.

The metaphor is literal — the document bounces back and forth between agents, like a ball in a rally. Each time it comes back, it's a little better. The agents aren't having a conversation about the plan. They're editing the plan itself, co-evolving it together through structured passes until they agree.

A bounce run is the full sequence: the Agent Bouncer sends the document out, gets it back, checks if there's still disagreement, and either sends it out again or declares convergence. Two bounces is usually enough. The first surfaces problems; the second resolves them.

## The Insight

Most of the value comes in the first two passes.

Pass 1: the reviewer reads fresh and catches things the composer missed — unstated assumptions, ambiguous specs, overly optimistic claims. This is the high-value pass. The reviewer isn't trying to be difficult; it's seeing the plan for the first time and asking the questions the composer forgot to ask.

Pass 2: the composer resolves the disagreements. It picks the simpler interpretation, cuts the scope that got contested, and tightens the language. The plan gets shorter and more precise.

Passes 3+: diminishing returns. The agents are polishing, not debating. The structural improvements happened in passes 1 and 2.

This is why the Agent Bouncer defaults to 2 passes with auto-convergence. The `/dev-review` skill defaults to auto-convergence up to 6 passes, which is appropriate for the more complex compose-bounce-execute workflow it orchestrates. In both cases, if the plan converges in 1, the loop stops early.

## Why Structured Disagreement

The natural way for AI agents to "review" each other's work is free-form conversation — one writes a plan, the other writes a paragraph of feedback, the first responds to the feedback. This produces conversation threads, not better plans. The feedback lives in the chat, not in the document. You end up with a clean plan plus a wall of commentary that you have to mentally merge.

Co-Evolution takes a different approach: there is no conversation. There is only the plan. Each agent edits the plan directly. When it disagrees, it puts a `[CONTESTED]` marker right below the line it has a problem with, along with a concrete alternative. The next agent either accepts the alternative (edits the line, removes the marker) or strengthens the counter-argument.

This means the plan is always the source of truth. After the bounce, the final artifact reads clean — as if one person wrote it. No tracked changes. No revision history. No "as discussed above." Just the document.

## Why Cross-Vendor Matters

When both agents are the same model, they agree too quickly. The role prompts create surface-level tension (one optimizes for simplicity, the other for correctness), but the underlying perspective is identical. Pass 2 looks a lot like pass 1 with slightly tighter wording.

When Claude reviews and Codex composes (or vice versa), the disagreements are real. Claude caught that the README claimed "frontier models handle this well" when only two models had actually been tested. Codex never flagged that — it shared the same blind spot. Claude noticed the architecture diagram showed a command that didn't exist in the implementation. Different models have different priors, different tendencies, and different failure modes. The bounce protocol surfaces those differences systematically.

The lesson: the protocol is agent-agnostic, but the value scales with cognitive diversity.

## What We Learned Building It

**Codex edits files it can see.** When Codex runs with `--full-auto`, it has filesystem write access. If the prompt references a file path, Codex might edit that file directly — even when you've told it to write output elsewhere. The fix: never expose the plan file path to the agent. Embed the plan content inline in the prompt, pipe via stdin, and capture output to a separate file. The Agent Bouncer is the sole owner of the canonical plan.

**Plans balloon without guardrails.** In early tests, a 100-word sketch grew to 1,200 words across 4 passes. The agents kept adding — more sections, more details, more edge cases. The fix: explicit scope control in the protocol ("Your job is to REFINE the plan, not to GROW it") and role prompts that tell the composer to cut, not add.

**Agents return summaries instead of full documents.** A related failure mode: the agent reads a 500-word plan and returns a 50-word description of what it would change. The Agent Bouncer now checks whether the output is significantly shorter than the input. If so, it rejects the output and retries the pass.

**Inline code triggers false positives.** The README discusses `[CONTESTED]` markers as content — explaining what they are. The marker counter originally counted these as real unresolved markers. The fix: strip inline backtick code before counting, and skip fenced code blocks entirely.

**The automation is the product.** The bounce protocol is a good idea. But without automation, you're just doing the clipboard labor in a more structured way. The protocol tells agents what to do; the Agent Bouncer makes it happen without human intervention.

**HUMAN SUMMARY is for the process, not the output.** During bouncing, each agent appends a one-line summary of what it changed. This helps humans follow the process. But it doesn't belong in the final document — it's metadata, not content. The Agent Bouncer strips it from the canonical plan and preserves it in per-pass artifacts.

## The Name

"Co-evolution" comes from biology. In nature, co-evolution is when two species adapt to each other over time — each change in one creates selective pressure on the other. The result is two organisms that are more fit than either would be alone.

That's what happens in the bounce. Each agent's review creates pressure on the plan. The plan adapts. Two passes later, it's tighter and more robust than either agent would have produced alone.
