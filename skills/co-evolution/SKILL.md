---
name: co-evolution
description: >
  General-purpose co-evolution for questions, ideas, drafts, plans, specs,
  arguments, and markdown documents. Composes or bounces content between agents
  using [CONTESTED]/[CLARIFY] markers until it converges. Triggers on
  "co-evolution", "co-evolve", "co evolve", "bounce", "bounce document",
  "agent bouncer", "refine with another agent", "cross-AI refinement",
  "stress test this", "have two AIs review this", "adversarial review",
  and "red team this".
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

Run an adversarial review (structured falsification persona — premises,
assumptions, decisions, complexity, alternatives). Cross-AI by default; add
`--agents claude,claude` for an internal same-model review when the user wants
no Codex involvement:

```bash
repo=$(resolve_co_evolution_repo) || exit 1
bash -lc 'cd "$1" && bash ./co-evolve-bouncer.sh --vanilla --adversarial --bounce-only "$2"' bash "$repo" "path/to/document.md"
bash -lc 'cd "$1" && bash ./co-evolve-bouncer.sh --vanilla --adversarial --agents claude,claude --bounce-only "$2"' bash "$repo" "path/to/document.md"
```

On dense documents pair `--adversarial` with `--chain` or `--bounces 3` — an
aggressive critique pass can leave markers open at the default 2 passes.

## Routing

| User intent | Command |
|---|---|
| General question, idea, strategy, or draft | `bash ./co-evolve-bouncer.sh --vanilla "input"` |
| Existing markdown file needs refinement | `bash ./co-evolve-bouncer.sh --vanilla --bounce-only <file>` |
| High-stakes argument or decision needs adversarial passes | `bash ./co-evolve-bouncer.sh --vanilla --chain "input"` |
| Adversarial review of a document (cross-AI bounce) | `bash ./co-evolve-bouncer.sh --vanilla --adversarial --bounce-only <file>` |
| Internal adversarial review, same model, no Codex | `bash ./co-evolve-bouncer.sh --vanilla --adversarial --agents claude,claude --bounce-only <file>` |
| Low-cost third cross-vendor read | `bash ./co-evolve-bouncer.sh --vanilla --agents claude,glm "input"` |
| Bounce against Kimi instead of Codex | `bash ./co-evolve-bouncer.sh --vanilla --agents claude,kimi --bounce-only <file>` |
| Real repo change with code execution | `/dev-review` or `dev-review/codex/dev-review.sh` |

## Available agents

`--agents <first>,<second>` picks the ordered pair. The first seat creates the
initial draft and handles odd passes; the second handles even passes. Use
different vendors so the bounce can surface disagreement.

- **`claude`**: session default through the Claude CLI (`best` resolves to
  opus-4.8). Best suited to user-facing composition.
- **`codex`**: GPT-5.5 through the Codex CLI. A strong mechanical reviewer. It is
  cheap under the Codex plan but not free; the daily codex-guard cap applies.
- **`glm`**: GLM-5.3-Flash through Z.AI's direct Chat Completions API. Calls use
  the Z.AI account balance or resource package shared across machines. Use it
  for a low-cost extra cross-vendor critique.
- **`kimi`**: Kimi K3 through Moonshot's direct Chat Completions API, using the
  Kimi Platform balance shared across machines. It is a second low-cost
  cross-vendor composer or reviewer.

Setup for the `glm` and `kimi` seats (accounts, keys, launchers, web chat) lives in
[docs/agent-seats.md](../../docs/agent-seats.md). Document seats compose or review;
the full-context session Claude adjudicates.

## Output

Each run writes artifacts under `runs/co-evolve-{label}-{timestamp}/`, including
the original input, per-pass raw outputs, a clean final document, and `run.log`.
Read the final markdown output and summarize the result for the user.
