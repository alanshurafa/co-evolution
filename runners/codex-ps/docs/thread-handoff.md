# Thread Handoff

Use this in a new Codex thread to continue work on the new Codex-first repo.

## Paste This Into The New Thread

I want to continue work on the Codex-first version of Co-Evolution.

Workspace:
`C:\Users\alan\Project\codex-co-evolution`

Please start by reading:
- `README.md`
- `docs/architecture.md`
- `docs/thread-handoff.md`
- `scripts/run-co-evolution.ps1`
- `templates/bounce-protocol.md`
- `templates/dev-prompt-codex.md`
- `templates/review-prompt-codex.md`
- `schemas/review-verdict.json`

Context:
- This repo was created as a brand-new local git repo, separate from the Claude-oriented `co-evolution` repo.
- The goal is to build a Codex-first autonomous orchestrator for the Co-Evolution protocol.
- We intentionally did not use a worktree because I wanted stronger separation and the option for pseudonymous development later.
- The shared reusable assets were copied from the original repo:
  - `templates/bounce-protocol.md`
  - `templates/dev-prompt-codex.md`
  - `templates/review-prompt-codex.md`
  - `schemas/review-verdict.json`
- A starter scaffold already exists:
  - `README.md`
  - `docs/architecture.md`
  - `scripts/run-co-evolution.ps1`
- The runner currently only creates a run directory and `state.json`. It does not yet implement compose, bounce, execute, verify, adapters, or resume logic.
- Run artifacts are intended to live under `.co-evolution/runs/<run-id>/`.
- This repo has no remote yet.
- Git is configured with `user.useConfigOnly=true`, so do not commit until I explicitly set a local `user.name` and `user.email`.

What I want next:
- Implement the first working autonomous runner in `scripts/run-co-evolution.ps1`.
- Start with a Codex-only path first if that is the fastest way to get an end-to-end loop working.
- Then structure it so adapters for `claude` and `ollama` can be added cleanly afterward.

Priority order:
1. Implement run-state and artifact helpers.
2. Implement prompt rendering from the template files.
3. Implement a Codex adapter using `codex exec` and `codex review`.
4. Implement compose -> bounce -> execute -> verify flow.
5. Add convergence detection for `[CONTESTED]` and `[CLARIFY]`.
6. Add autonomous arbitration policy when max bounces are reached.
7. Add one verify/fix retry loop.

Constraints:
- Keep protocol logic in templates/prompts, not hardcoded into adapters.
- Prefer durable artifacts over temp files.
- Keep the repo cleanly separable from the Claude repo.
- Do not add a git remote or make commits unless I ask.

Suggested first implementation target:
- Make `scripts/run-co-evolution.ps1` able to:
  - create a run directory
  - render a compose prompt
  - invoke `codex exec`
  - save the resulting plan to `plan.md`
  - run at least one bounce pass with the bounce protocol
  - count markers
  - stop with a readable status summary

When you continue, inspect the actual files first, then implement the runner instead of just proposing it.
