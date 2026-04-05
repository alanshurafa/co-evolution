# Co-Evolution Agent Bouncer

A standalone bash script that bounces a document between two AI agents using structured disagreement markers until it converges.

## Quick Start

```bash
# Pass any markdown document you want refined
./agent-bouncer.sh your-document.md

# 4 passes instead of the default 2
./agent-bouncer.sh your-document.md 4 claude codex

# Reverse the roles: Codex reviews, Claude composes
./agent-bouncer.sh your-document.md 2 codex claude
```

Arguments: `<document> [max-bounces] [odd-agent] [even-agent]`

- Odd passes = reviewer role (flags problems)
- Even passes = composer role (resolves problems)
- Default: 2 passes, claude reviews, codex composes

## How It Works

1. The Agent Bouncer reads the plan file
2. Builds a prompt from the bounce protocol template + role preamble + plan content
3. Sends it to the reviewer agent
4. Captures the response, counts `[CONTESTED]` and `[CLARIFY]` markers
5. If zero markers: converged, stop. If markers remain: send to the composer
6. Composer resolves markers, bouncer checks again
7. Repeat until convergence or pass limit

```text
Agent Bouncer (agent-bouncer.sh)
    |
    +-- reads bounce-protocol.md template + role preamble
    +-- fills placeholders, writes prompt to temp file
    +-- invokes agent adapter (claude or codex)
    +-- reads response from output file
    +-- counts markers (skipping code blocks and inline backticks)
    +-- repeats or stops at convergence
```

## Run Artifacts

Each run creates a named directory under `runs/` at the repo root, prefixed with `bouncer-`:

```
runs/bouncer-adapter-contract-20260405-155633/
  original.md                      — input before bouncing
  pass-1-reviewer-claude-raw.md    — pass 1 output (with HUMAN SUMMARY)
  pass-2-composer-codex-raw.md     — pass 2 output (with HUMAN SUMMARY)
  adapter-contract.md              — clean output, named after the run
  run.log                          — console log
```

The Agent Bouncer generates a descriptive run name from the document content, falling back to a timestamp.

## Adapters

| Agent | Adapter | Command |
|-------|---------|---------|
| Claude | `invoke_claude` | `claude -p --output-format text --model claude-opus-4-6 --max-turns 5` |
| Codex | `invoke_codex` | `codex exec --full-auto -C <workdir> -o <output>` |

To add a new agent, define an `invoke_<name>` function in `agent-bouncer.sh` that takes three arguments: prompt file, output file, stderr file.

### Known Limitations

**Claude (`claude -p`)** struggles with long documents (~800+ words). It tends to return a summary of changes rather than the full edited document. The bouncer's size check catches this and retries, but the retry often fails the same way. Workarounds: use the Anthropic API directly as an adapter, or assign Claude the reviewer role where its output feeds into Codex (which reliably returns full documents) for resolution.

## Safety Checks

- **Size check**: If output is less than 30% of input word count, the bouncer treats it as a likely summary and retries once.
- **Empty check**: Empty outputs trigger a single retry before aborting.
- **Marker counting**: Skips fenced code blocks and inline backtick code to avoid false positives from documentation about markers.

## Customizing the Bounce Protocol

Edit `templates/bounce-protocol.md` directly. Changes take effect on the next run.

| What | How |
|------|-----|
| **Markers** | Add domain-specific markers like `[SECURITY]` or `[PERFORMANCE]`. Convergence checks for zero unresolved markers of any type. |
| **Convergence rules** | Default: no markers left means done. Tighten or loosen in the template. |
| **Staleness timeout** | Markers must resolve within 2 passes by default. |
| **Role lenses** | Edit `templates/role-composer.md` and `templates/role-reviewer.md` to change each agent's optimization lens. |
| **Guardrails** | The "what not to do" and "scope control" sections prevent common failure modes. |

## Files

```
agent-bouncer/
  agent-bouncer.sh             — the bouncer script
  templates/
    bounce-protocol.md         — core protocol (marker rules, convergence, scope control)
    role-composer.md            — composer role preamble (simplicity, scope reduction)
    role-reviewer.md            — reviewer role preamble (correctness, edge cases)
```
