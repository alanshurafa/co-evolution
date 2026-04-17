# Architecture

## Intent

Codex should act as the orchestrator, not just one participant in the bounce.
The orchestration layer should be a scriptable, resumable runner instead of a
large prompt embedded in another agent's skill system.

## Core Components

### Runner

`scripts/run-co-evolution.ps1`

Owns:

- argument parsing
- workspace checks
- run directory creation
- phase transitions
- convergence checks
- retry and timeout policy
- autonomous arbitration policy
- verify and auto-fix loops

### Adapters

Each agent gets a thin adapter that only knows how to turn text input into text
output.

Examples:

- `codex exec`
- `claude -p`
- `ollama run`

The bounce protocol stays in prompt templates, not in the adapters.

### Artifacts

Each run should write durable artifacts to:

```text
.co-evolution/
  runs/
    <run-id>/
      state.json
      plan.md
      prompts/
      outputs/
      verdict.json
```

This allows interruption, resume, inspection, and later replay.

## Initial Execution Model

1. Compose
2. Bounce until zero unresolved markers or max passes reached
3. If unresolved markers remain:
   - autonomous mode: Codex arbitrates per policy
   - interactive mode: stop and ask the user
4. Execute
5. Verify
6. If verify fails and auto-fix budget remains, loop once more

## Design Constraints

- Keep protocol assets portable across orchestrators.
- Avoid shared git history with the Claude repo.
- Prefer local run artifacts over transient temp files.
- Keep adapters replaceable so new agents can be added later.
