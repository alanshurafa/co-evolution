# Codex Co-Evolution

Codex-first orchestration for the Co-Evolution bounce protocol.

This repository is intentionally separate from the Claude-oriented `co-evolution`
repo so the Codex implementation can evolve independently, stay local/private for
now, and later be merged or ported back selectively.

## What Is Here

- Shared protocol assets copied from the original project:
  - `templates/bounce-protocol.md`
  - `templates/dev-prompt-codex.md`
  - `templates/review-prompt-codex.md`
  - `schemas/review-verdict.json`
- Codex-first scaffolding:
  - `docs/architecture.md`
  - `scripts/run-co-evolution.ps1`

## Current Goal

Build a real runner where Codex owns the control loop:

1. Compose the initial plan
2. Bounce it between agents until convergence
3. Execute the refined plan
4. Verify the implementation
5. Optionally auto-fix review issues without stopping for a human

## Why This Is A Separate Repo

- It keeps the public Claude-facing repo stable.
- It avoids shared git history with the experimental Codex implementation.
- It lets you choose a separate git identity before the first commit.

## Safety For Pseudonymous Development

This repo is configured with `user.useConfigOnly=true`, which means git will not
let you commit until you explicitly set a local `user.name` and `user.email`.

Before the first commit, set a repo-local identity:

```powershell
git config user.name "Your Pseudonym"
git config user.email "your-alias@example.com"
```

If you later publish this repo and want stronger separation, also use a separate
GitHub account and separate SSH key for that account.

## Suggested Next Steps

1. Implement the adapter layer for `codex`, `claude`, and optional local models.
2. Flesh out `scripts/run-co-evolution.ps1` into the actual autonomous runner.
3. Store run artifacts under `.co-evolution/runs/<run-id>/`.
4. Add resume, retry, and verify/fix loop behavior.
5. Decide later whether this repo stays private, local-only, or gets a separate remote.
