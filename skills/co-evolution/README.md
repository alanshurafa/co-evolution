# Co-Evolution Claude Code Skill

`/co-evolution` is the default skill for general-purpose co-evolution. Use it for
questions, ideas, drafts, plans, specs, arguments, prompts, and markdown
documents that should be refined through cross-AI disagreement.

For repo code changes, use `skills/dev-review/` instead.

## Installation

From the cloned repo:

```bash
mkdir -p ~/.claude/skills/co-evolution
cp -R skills/co-evolution/* ~/.claude/skills/co-evolution/
```

The skill resolves the repo from the current checkout, `CO_EVOLUTION_HOME`, or
common clone locations.

## Usage

Inside Claude Code:

```text
/co-evolution Stress test this argument
/co-evolution Bounce docs/plan.md
```

Standalone:

```bash
bash ./co-evolve-bouncer.sh --vanilla "What is the best framing?"
bash ./co-evolve-bouncer.sh --vanilla --bounce-only docs/plan.md
bash ./co-evolve-bouncer.sh --vanilla --chain "Should we ship this migration?"
```
