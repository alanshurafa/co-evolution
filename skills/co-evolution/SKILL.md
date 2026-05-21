---
name: co-evolution
description: >
  General-purpose co-evolution for questions, ideas, drafts, plans, specs,
  arguments, and markdown documents. Composes or bounces content between agents
  using [CONTESTED]/[CLARIFY] markers until it converges. Triggers on
  "co-evolution", "co-evolve", "co evolve", "bounce", "bounce document",
  "agent bouncer", "refine with another agent", "cross-AI refinement",
  "stress test this", and "have two AIs review this".
allowed-tools: Bash, Read, Write, Glob, AskUserQuestion
---

# /co-evolution - General-Purpose Co-Evolution

Use this as the default Co-Evolution entrypoint when the user wants to refine an
answer, draft, argument, plan, spec, prompt, or markdown document through
structured cross-AI disagreement.

Do not use this skill for code execution. If the user specifically wants repo
files changed, a bug fixed, or a feature implemented with an execution trail,
route them to `/dev-review` or `dev-review/codex/dev-review.sh`.

## Repository Resolution

Before running the bouncer, resolve the repository root. Prefer the current git
checkout, then `CO_EVOLUTION_HOME`, then common clone locations:

```bash
resolve_co_evolution_repo() {
  local top

  top=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$top" && -f "$top/co-evolve-bouncer.sh" ]]; then
    printf '%s\n' "$top"
    return 0
  fi

  if [[ -n "${CO_EVOLUTION_HOME:-}" && -f "$CO_EVOLUTION_HOME/co-evolve-bouncer.sh" ]]; then
    printf '%s\n' "$CO_EVOLUTION_HOME"
    return 0
  fi

  for candidate in "$PWD" "$HOME/co-evolution" "$HOME/Project/co-evolution" "$HOME/Projects/co-evolution"; do
    if [[ -f "$candidate/co-evolve-bouncer.sh" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}
```

If no repository is found, tell the user to run from the cloned
`co-evolution` repo or set `CO_EVOLUTION_HOME` to the clone path.

## Common Commands

Run general questions or ideas through compose + bounce:

```bash
repo=$(resolve_co_evolution_repo) || exit 1
bash -lc 'cd "$1" && bash ./co-evolve-bouncer.sh --vanilla "$2"' bash "$repo" "question or input"
```

Bounce an existing markdown document without a compose pass:

```bash
repo=$(resolve_co_evolution_repo) || exit 1
bash -lc 'cd "$1" && bash ./co-evolve-bouncer.sh --vanilla --bounce-only "$2"' bash "$repo" "path/to/document.md"
```

Use chain mode for high-stakes stress testing:

```bash
repo=$(resolve_co_evolution_repo) || exit 1
bash -lc 'cd "$1" && bash ./co-evolve-bouncer.sh --vanilla --chain "$2"' bash "$repo" "argument or decision to stress test"
```

## Routing

| User intent | Command |
|---|---|
| General question, idea, strategy, or draft | `bash ./co-evolve-bouncer.sh --vanilla "input"` |
| Existing markdown file needs refinement | `bash ./co-evolve-bouncer.sh --vanilla --bounce-only <file>` |
| High-stakes argument or decision needs adversarial passes | `bash ./co-evolve-bouncer.sh --vanilla --chain "input"` |
| Real repo change with code execution | `/dev-review` or `dev-review/codex/dev-review.sh` |

## Output

Each run writes artifacts under `runs/co-evolve-{label}-{timestamp}/`, including
the original input, per-pass raw outputs, a clean final document, and `run.log`.
Read the final markdown output and summarize the result for the user.
