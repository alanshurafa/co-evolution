# Co-Evolution

Tools for structured iterative refinement between AI agents and humans. Documents
bounce back and forth between agents using disagreement markers until they
converge, producing tighter and more precise output than any single agent would
alone.

## Default Usage

Start with the general Co-Evolution runner unless the task specifically needs
code execution:

```bash
bash ./co-evolve-bouncer.sh --vanilla "stress test this idea"
```

For an existing markdown document:

```bash
bash ./co-evolve-bouncer.sh --vanilla --bounce-only docs/plan.md
```

Use `dev-review` only when you want a code-focused compose -> bounce -> execute
-> verify workflow.

## Install On macOS/Linux

From the cloned repo:

```bash
mkdir -p ~/.claude/skills/co-evolution ~/.local/bin
cp -R skills/co-evolution/* ~/.claude/skills/co-evolution/

cat > ~/.local/bin/co-evolve <<EOF
#!/usr/bin/env bash
cd "$PWD" || exit 1
exec bash ./co-evolve-bouncer.sh "\$@"
EOF
chmod +x ~/.local/bin/co-evolve
```

Make sure `~/.local/bin` is on `PATH`. After that, the default command is:

```bash
co-evolve --vanilla "what should I do next?"
```

Optional code workflow:

```bash
mkdir -p ~/.claude/skills/dev-review
cp -R skills/dev-review/* ~/.claude/skills/dev-review/
```

## What's In This Repo

### [Co-Evolution Skill](skills/co-evolution/)

`/co-evolution` is the default Claude Code skill for general questions, ideas,
drafts, markdown files, plans, specs, and arguments. It routes to
`co-evolve-bouncer.sh` and does not execute repo changes.

```text
/co-evolution Stress test this launch plan
```

### [Co-Evolve Bouncer](co-evolve-bouncer.sh)

The primary standalone runner. It can compose from a question, bounce an
existing document, or run staged critique -> defend -> tighten passes.

```bash
bash ./co-evolve-bouncer.sh --vanilla "What is the strongest version of this argument?"
bash ./co-evolve-bouncer.sh --vanilla --chain "Should we ship this migration?"
```

When only one agent is available — or to A/B against a cross-model run — use
`--single-model` to pin both reviewer and composer onto the same agent. By
default this is **bare two-role mode**: same model, two role prompts (composer
and critic), nothing else. An A/B on a dense technical document (2026-05-24)
showed this beats the persona-discipline variant — the model preserves its
natural impulse to investigate the codebase and produces concrete, code-grounded
critique instead of abstract methodological objections.

```bash
bash ./co-evolve-bouncer.sh --vanilla --single-model "Stress test this argument"
bash ./co-evolve-bouncer.sh --vanilla --single-model codex --chain "Ship plan?"
```

If you want the divergence preface — which asks the model to deliberately read
against its own prior turn — enable it with `--persona-discipline`. This pairs
naturally with compose-then-bounce of your own draft, where there *is* a
shared-author bias to fight:

```bash
bash ./co-evolve-bouncer.sh --vanilla --single-model --persona-discipline "..."
```

Expect shallower diversity than cross-model bounces (shared weights share
blindspots), but most single-model runs still surface 1-2 real objections in
the first pass.

### [Agent Bouncer](agent-bouncer/)

A standalone bash script that bounces any markdown document between two agents.
Agent-agnostic: ships with Claude and Codex adapters, and new agents can be
added by writing one function. Runs from any terminal.

```bash
# Pass any document you want refined
bash ./agent-bouncer/agent-bouncer.sh your-document.md
```

### [Codex Runtime](dev-review/codex/)

A standalone Bash runtime for the full `dev-review` compose -> bounce -> execute
-> optional verify workflow. Use it when the task is a real repo change and you
want a bounced plan, an execution trail, or a verifier pass outside Claude Code.

```bash
# Produce a plan and stop
bash dev-review/codex/dev-review.sh --plan-only "Add docs for the Codex runtime"

# Execute an approved plan file
bash dev-review/codex/dev-review.sh --skip-plan --plan .planning/phases/04-docs-and-routing/04-01-PLAN.md
```

Start with [dev-review/codex/README.md](dev-review/codex/README.md) for usage
details and [dev-review/codex/instructions.md](dev-review/codex/instructions.md)
when you want Codex to route between the repo entrypoints automatically.

### [Dev-Review Skill](skills/dev-review/)

`/dev-review` is a Claude Code skill that wraps the bounce protocol in a
code-focused compose-bounce-execute-verify workflow. Use it inside Claude Code
when the intended deliverable is a repo change, not a general answer or document
refinement.

### [Lab](lab/)

First-class beta channel for experimental features that could break the core
runner if shipped prematurely. Opt-in only: users who never pass `--lab <mode>`
see zero behavior change. See [lab/README.md](lab/README.md) for the boundary
conventions, graduation criteria, anti-criteria, and sandbox guarantee.

```bash
# Invoke a lab mode
co-evolve --lab pel-proposer "task"
bash dev-review/codex/dev-review.sh --lab pel-proposer "task"
```

Unknown modes fail fast with a list of available modes. There is no silent
fallthrough.

### Picking The Right Entrypoint

| Task shape | Tool |
|------------|------|
| General question, idea, strategy, draft, or argument | `co-evolve-bouncer.sh` |
| Existing markdown document needs refinement | `co-evolve-bouncer.sh --bounce-only` |
| Small, low-risk repo edit in 1-2 files | Direct execution |
| Multi-file code change, medium/high risk, or plan/verify workflow | `dev-review/codex/dev-review.sh` |
| General co-evolution inside Claude Code | `skills/co-evolution/` |
| Code pipeline inside Claude Code | `skills/dev-review/` |

### The Bounce Protocol

The shared foundation. Two markers - `[CONTESTED]` and `[CLARIFY]` - coordinate
structured disagreement between agents. Both auto-expire after 2 passes,
guaranteeing convergence. The protocol is customizable: swap in domain-specific
markers, adjust convergence rules, change role lenses.

## Status

Early development. The Co-Evolution skill, Co-Evolve Bouncer, Agent Bouncer,
Dev-Review skill, and standalone Codex runtime are functional. Next steps:

- Additional agent adapters (Gemini CLI, Ollama, direct API calls)
- Standalone bounce protocol spec
- Proper CLI (`co-evolve bounce`, `co-evolve init`)

## License

MIT
