# co-evolve.sh — General-Purpose Co-Evolution Tool

## What This Is

A single entry point for co-evolution: any input (question, draft, file, idea) gets composed, bounced between two AIs through structured disagreement, and returned as a converged output. It subsumes agent-bouncer (document refinement) and dev-review (code pipeline) as specialized flag combinations behind one shell entry point.

## Design Principles

1. No modes. The user never selects "question mode" vs "document mode." The tool detects the input and proceeds.
2. Minimal protocol. The only rigid structure: mark disagreements with `[CONTESTED]`, mark ambiguities with `[CLARIFY]`. Everything else is the AI's judgment.
3. Future-proof. As models improve, the system gets better automatically. The wrapper stays thin.
4. Private data requires consent. ExoCortex and personal knowledge are opt-in, never automatic.
5. Interview-first by default. The tool asks what you need before it starts working.

## User Flow

```text
co-evolve "What's my best argument for Thursday's hearing?"

Step 1: INTERVIEW (default ON, --skip-interview to bypass)
  → Questions read from the user's terminal, not stdin
  → Who is the audience?
  → Should I search your memory for relevant context? (ExoCortex opt-in)
  → Any specific files or evidence to include?
  → What kind of output do you want?

Step 2: COMPOSE (enriched by interview answers)
  → If ExoCortex opted in: search and pull relevant context
  → If files specified: read and include as background
  → Detect gaps in available information
  → Agent A produces the first answer with all context loaded
  → Bounce framing is shaped by interview answers unless --lens is set

Step 3: BOUNCE (light roles default, --chain for staged passes)
  Default: 2 passes with light roles
    → Pass 1 (reviewer): "Find what's wrong, missing, weak"
    → Pass 2 (composer): "Make it simpler, clearer, more actionable"
  Chain mode (--chain): fixed staged passes
    → Pass 1: CRITIQUE — "What's wrong, missing, weak, or unsupported?"
    → Pass 2: DEFEND — "Given those critiques, strengthen every weak point"
    → Pass 3: TIGHTEN — "Cut everything that doesn't earn its place"

Step 4: HUMAN CHECK (default ON, --auto to bypass, runs after each pass)
  → Show contested points remaining
  → Human can: resolve markers, add context, continue, or stop
  → Bounce continues with human input folded in

Step 5: OUTPUT
  → Clean converged result printed to stdout
  → Run artifacts saved to runs/ directory
```

## Flags

| Flag | Default | Effect |
|------|---------|--------|
| --skip-interview | Interview ON | Skip opening questions, go straight to compose |
| --auto | Human check ON | Skip human intervention, fully autonomous |
| --exocortex "query" | ExoCortex OFF | Search ExoCortex for relevant context |
| --context file.md | No files | Include a file as background context |
| --audience "judge" | Detected from interview | Prime agents for a specific reader |
| --lens legal-critic | Auto-shaped roles | Replace auto-shaped bounce framing with a named adversarial lens |
| --chain | Standard 2-pass | Use fixed staged prompts (critique → defend → tighten) |
| --bounces N | 2 | Set standard bounce passes; ignored by `--chain` |
| --agents A,B | claude,codex | Agent pair |
| --dev-review | No execution | Add execute + verify phases after bounce |
| --bounce-only | Full pipeline | Skip compose, bounce a file directly (legacy bouncer mode) |
| --vanilla | Full pipeline | Shorthand for `--skip-interview --auto` (compose + bounce, nothing else) |
| --output file.md | stdout | Write final output to file |

## Input Handling

Auto-detect input type:
- String argument: `co-evolve "question"` → treated as prompt, compose step generates an answer
- File argument: `co-evolve document.md` → file contents become input, compose step enriches or improves it
- Piped input with no positional argument: `cat notes.txt | co-evolve` → stdin becomes input
- `--bounce-only`: skip compose entirely, bounce the file as-is (agent-bouncer behavior)

Detection: if the positional argument resolves to an existing file path, read it; otherwise treat it as a string. Piped input is detected via `[ ! -t 0 ]`. Interactive prompts never read from stdin; they read from the user's terminal.

## Role System

Three tiers, determined by context:

1. Static light roles (default when interview is skipped or `--vanilla` is used): same generic preamble every time. "Find what's wrong" / "Make it simpler."
2. Interview-shaped roles (default with interview): interview answers shape the framing. "This is going to a judge" makes the reviewer skeptical in that frame. "This is an email to my co-parent" makes the reviewer check tone and defensiveness triggers.
3. Named lenses (`--lens`): explicit power-user override. The named lens replaces the auto-generated bounce framing while keeping the interview's factual context.

## Compose Step

The compose step is the key differentiator from the existing bouncer. It creates or enriches the first version before any bouncing happens.

For question inputs: Agent A answers the question with all available context.
For document inputs: Agent A reviews the document and identifies gaps, missing context, or weak points.
For both: interview answers and opted-in context (ExoCortex, files) are prepended so Agent A works from a richer foundation.

Without compose (`--bounce-only`): the file goes straight to the bounce loop. This is the legacy bouncer behavior.

## Chain Bounce Design

Standard bounce: same instruction every pass, just "improve it and mark disagreements." Standard bounce can stop early if there are zero markers remaining.

Chain bounce (`--chain`): fixed 3-pass structure.
- Pass 1 CRITIQUE: adversarial, find every weakness
- Pass 2 DEFEND: resolve critiques, strengthen weak points
- Pass 3 TIGHTEN: cut ruthlessly, ensure nothing unnecessary remains

Chain mode always runs all three passes. Marker counts still show what remains unresolved, but they do not short-circuit the staged sequence.

## Relationship to Existing Tools

`co-evolve.sh` subsumes both existing tools:
- `co-evolve --bounce-only doc.md` = agent-bouncer behavior
- `co-evolve --vanilla --dev-review "task"` = dev-review behavior
- `co-evolve "question"` = new general-purpose behavior

The agent-bouncer and dev-review scripts remain as-is for backward compatibility but are no longer the primary entry points.

## Implementation

Single bash script at repo root: `co-evolve.sh`
Sources `lib/co-evolution.sh` for shared functions.
Estimated size: 300-400 lines (interview + compose + bounce + human-check + output).

Interview step: series of prompts to the user's terminal (`/dev/tty`), not stdin.
Compose step: invoke Agent A via `invoke_claude` or `invoke_codex`.
Bounce step: reuse the existing bounce loop logic from `agent-bouncer`.
Human check: pause after each pass, show markers, wait for input or Enter to continue.
Output: same artifact structure as `agent-bouncer` (`runs/` directory + clean stdout).

## Verification

1. `co-evolve --help` shows usage and exits 0
2. `co-evolve --vanilla "What is 2+2?"` produces a bounced answer
3. `co-evolve "What's my best argument?"` triggers interview, then compose + bounce + human check
4. `co-evolve --bounce-only document.md` behaves like `agent-bouncer`
5. `co-evolve --chain "Stress test this argument"` uses the fixed 3 staged passes
6. `co-evolve --exocortex "child support" "What should I argue?"` pulls ExoCortex context
7. `co-evolve --vanilla --dev-review "Add error handling"` composes, bounces, executes, and verifies
8. `echo "draft text" | co-evolve --vanilla` captures stdin as input and completes end-to-end
9. `echo "draft text" | co-evolve` keeps interview and human prompts on the terminal instead of consuming the piped content

