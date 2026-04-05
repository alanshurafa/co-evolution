# Co-Evolution

Tools for structured iterative refinement between AI agents. Documents bounce back and forth between agents using disagreement markers until they converge — producing tighter, more precise output than any single agent would alone.

## What's in this repo

### [Agent Bouncer](agent-bouncer/)

A standalone bash script that bounces a document between two agents. Agent-agnostic — ships with Claude and Codex adapters, add new agents by writing one function. Runs from any terminal.

```bash
./agent-bouncer/agent-bouncer.sh plan.md
```

### [Claude Code Skill](skill/)

`/dev-review` — a Claude Code skill that wraps the bounce protocol in a full compose-bounce-execute-verify workflow. Use it inside Claude Code for end-to-end plan refinement and code generation.

### The Bounce Protocol

The shared foundation. Two markers — `[CONTESTED]` and `[CLARIFY]` — coordinate structured disagreement between agents. Both auto-expire after 2 passes, guaranteeing convergence. The protocol is customizable: swap in domain-specific markers, adjust convergence rules, change role lenses.

## Status

Early development. The Agent Bouncer and skill are functional. Next steps:

- Additional agent adapters (Gemini CLI, Ollama, direct API calls)
- Standalone bounce protocol spec
- Proper CLI (`co-evolve bounce`, `co-evolve init`)

## License

MIT
