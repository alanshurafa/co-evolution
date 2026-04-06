# Structure

## Top-Level Layout

- `agent-bouncer/` contains the standalone shell tool and its runtime templates.
- `skill/` contains the Claude Code skill definition, supporting templates, and verification schema.
- `runs/` is local working output for bounce runs and scratch documents.
- Root docs include `README.md`, `notesforhumans.md`, `.gitignore`, `.agentignore`, and `LICENSE`.

## Key Files

- `agent-bouncer/agent-bouncer.sh`: only tracked executable program.
- `agent-bouncer/README.md`: user-facing documentation for the standalone bouncer.
- `agent-bouncer/templates/bounce-protocol.md`: core marker protocol for the shell tool.
- `skill/SKILL.md`: large orchestration spec for `/dev-review`.
- `skill/README.md`: installation and usage guide for the skill.
- `skill/schemas/review-verdict.json`: structured verification contract.

## Template Organization

- `agent-bouncer/templates/` contains exactly three files:
- `bounce-protocol.md`
- `role-composer.md`
- `role-reviewer.md`
- `skill/templates/` contains protocol plus execution and review prompt variants:
- `bounce-prompt-portable.md`
- `bounce-protocol.md`
- `dev-prompt-codex.md`
- `dev-prompt-opus.md`
- `review-prompt-codex.md`
- `review-prompt-opus.md`

## Run Artifact Layout

- The naming pattern is `runs/bouncer-<topic>-<timestamp>/`.
- Each run directory typically contains `original.md`, one or more `pass-N-role-agent-raw.md` files, corresponding stderr logs, a clean final `<topic>.md`, and `run.log`.
- The current working tree contains many local run folders under `runs/`, but `git ls-files` confirms none of them are tracked.

## Naming Conventions

- Shell globals are uppercase in `agent-bouncer/agent-bouncer.sh`, for example `PLAN_FILE`, `MAX_BOUNCES`, `RUN_DIR`, and `LOG_FILE`.
- Helper functions use verb-style names such as `invoke_claude`, `invoke_codex`, `cleanup`, and `log`.
- Prompt placeholders use brace tokens such as `{TASK}`, `{PLAN_CONTENT}`, `{PASS_NUMBER}`, and `{YOUR_ROLE}`.
- Review schema fields use stable snake_case names such as `scope_creep_detected` and `iteration_notes`.

## Human Vs Agent Material

- `.agentignore` excludes `notesforhumans.md` from agent-facing context.
- `notesforhumans.md` is intended as narrative context for people rather than runtime instructions.
- `runs/` acts as a local sandbox for human-in-the-loop experiments and generated outputs.

## Practical Navigation Guidance

- Start in `README.md` for the product overview.
- Read `agent-bouncer/agent-bouncer.sh` first if you need executable behavior.
- Read `skill/SKILL.md` first if you need Claude Code workflow behavior.
- Use the `templates/` directories next; they are part of the behavior surface, not just reference material.
