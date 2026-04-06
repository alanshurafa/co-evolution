# Stack

## Snapshot

- Project type: tooling repo for cross-AI document refinement, not a deployable app or service.
- Primary executable: `agent-bouncer/agent-bouncer.sh`.
- Primary orchestrator spec: `skill/SKILL.md`.
- Supporting assets: markdown templates in `agent-bouncer/templates/` and `skill/templates/`, plus JSON schema in `skill/schemas/review-verdict.json`.
- Tracked source is small: one shell entrypoint, one large skill spec, supporting docs, prompts, and schema files.

## Languages And Formats

- Bash is the only tracked programming language, used in `agent-bouncer/agent-bouncer.sh`.
- Markdown is the dominant artifact format in `README.md`, `agent-bouncer/README.md`, `skill/README.md`, `notesforhumans.md`, and all prompt/template files.
- JSON Schema is used in `skill/schemas/review-verdict.json` to constrain verification output.
- Ignore metadata lives in `.gitignore` and `.agentignore`.

## Runtime Dependencies

- `agent-bouncer/agent-bouncer.sh` assumes a POSIX shell plus standard utilities such as `date`, `head`, `tr`, `cp`, `mv`, `rm`, `wc`, `awk`, `tee`, `mkdir`, and `cat`.
- The bouncer depends on authenticated AI CLIs: `claude` and `codex`.
- The Claude adapter is hard-coded to `claude -p --output-format text --model claude-opus-4-6 --tools ""`.
- The Codex adapter is hard-coded to `codex exec --full-auto --skip-git-repo-check`.
- `skill/SKILL.md` assumes Claude Code tooling, `git`, and optionally `gh` for PR creation.

## Build And Packaging

- There is no `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, or compiled build system.
- There is no dependency lockfile.
- There is no CI configuration in the tracked repository.
- Distribution today is file-copy based: users run `agent-bouncer/agent-bouncer.sh` directly or copy `skill/` into a Claude Code skills directory.

## Storage And Generated State

- Generated bounce artifacts are written under `runs/`.
- `.gitignore` marks `runs/` as generated output, so run logs and bounced documents stay local by default.
- The bouncer mutates the input plan file in place and also writes a clean final copy plus per-pass raw outputs into `runs/bouncer-*/`.

## Practical Takeaway

- The repo is best understood as a shell-based orchestrator plus a prompt/spec bundle.
- Operational correctness depends more on CLI behavior, prompt quality, and file contracts than on a compiled application runtime.
