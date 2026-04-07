# Co-Evolution

Tools for structured iterative refinement between AI agents and Humans. Documents bounce back and forth between agents using disagreement markers until they converge - producing tighter, more precise output than any single agent would alone. Humans can opt in to be a part of the co-evolution if they choose.

## What's in this repo

### [Agent Bouncer](agent-bouncer/)

A standalone bash script that bounces any markdown document between two agents. Agent-agnostic — ships with Claude and Codex adapters, add new agents by writing one function. Runs from any terminal.

```bash
# Pass any document you want refined
./agent-bouncer/agent-bouncer.sh your-document.md
```

### [Codex Runtime](dev-review/codex/)

A standalone Bash runtime for the full `dev-review` compose -> bounce -> execute -> optional verify workflow. Use it when the task is a real repo change and you want a bounced plan, an execution trail, or a verifier pass outside Claude Code.

```bash
# Produce a plan and stop
bash dev-review/codex/dev-review.sh --plan-only "Add docs for the Codex runtime"

# Execute an approved plan file
bash dev-review/codex/dev-review.sh --skip-plan --plan .planning/phases/04-docs-and-routing/04-01-PLAN.md
```

Start with [dev-review/codex/README.md](dev-review/codex/README.md) for usage details and [dev-review/codex/instructions.md](dev-review/codex/instructions.md) when you want Codex to route between the repo entrypoints automatically.

### [Claude Code Skill](skill/)

`/dev-review` - a Claude Code skill that wraps the bounce protocol in a full compose-bounce-execute-verify workflow. Use it inside Claude Code for end-to-end plan refinement and code generation.

### Picking the right entrypoint

| Task shape | Tool |
|------------|------|
| Small, low-risk repo edit in 1-2 files | Direct execution |
| Prompt, plan, spec, or other markdown refinement | `agent-bouncer/agent-bouncer.sh` |
| Multi-file code change, medium/high risk, or plan/verify workflow | `dev-review/codex/dev-review.sh` |
| Same pipeline inside Claude Code | `skill/` |

### The Bounce Protocol

The shared foundation. Two markers - `[CONTESTED]` and `[CLARIFY]` - coordinate structured disagreement between agents. Both auto-expire after 2 passes, guaranteeing convergence. The protocol is customizable: swap in domain-specific markers, adjust convergence rules, change role lenses.

## Status

Early development. The Agent Bouncer, Claude Code skill, and standalone Codex runtime are functional. Next steps:

- Additional agent adapters (Gemini CLI, Ollama, direct API calls)
- Standalone bounce protocol spec
- Proper CLI (`co-evolve bounce`, `co-evolve init`)

## License

MIT
