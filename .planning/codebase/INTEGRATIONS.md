# Integrations

## Direct CLI Integrations

- `agent-bouncer/agent-bouncer.sh` integrates with the Claude CLI through `invoke_claude()`.
- `agent-bouncer/agent-bouncer.sh` integrates with the Codex CLI through `invoke_codex()`.
- The script also uses `codex exec` once before the bounce loop to generate a short run label from the document title and opening paragraph.

## Claude Integration Details

- Claude is invoked with pure text output expectations from `agent-bouncer/agent-bouncer.sh`.
- The adapter writes stdout to a file and stderr to `runs/bouncer-*/pass-N-stderr.log`.
- `skill/SKILL.md` is designed for Claude Code's native skill runtime, not as a standalone shell program.
- `skill/SKILL.md` declares Claude Code tool dependencies including `Bash`, `Read`, `Write`, `Edit`, `Grep`, `Glob`, `Agent`, `EnterWorktree`, and `ExitWorktree`.

## Codex Integration Details

- Codex is used in two ways across the repo:
- `agent-bouncer/agent-bouncer.sh` uses `codex exec` for run naming and for even-pass document rewrites.
- `skill/SKILL.md` describes `codex exec`, `codex review`, structured JSON output, and a Windows live-launch path for visible Codex sessions.
- `skill/templates/dev-prompt-codex.md` and `skill/templates/review-prompt-codex.md` hold the Codex-side prompt contracts.

## Git And Workspace Integration

- The tracked bouncer script does not require git to edit a document, but it assumes repository-relative paths for `runs/`.
- `skill/SKILL.md` is deeply integrated with git workflows: branch creation, diff capture, staging, commit flow, and optional worktree isolation.
- `skill/SKILL.md` also references `gh pr create` as the final PR step.

## Filesystem And Artifact Contracts

- The bouncer reads any markdown plan path supplied on the command line, including documents outside this repo.
- The canonical input document is overwritten in place after each pass.
- Raw outputs are preserved as `runs/bouncer-*/pass-N-role-agent-raw.md`.
- Clean outputs are preserved as `runs/bouncer-*/<run-label>.md`.
- `skill/schemas/review-verdict.json` is the machine-readable contract for verification verdicts.

## Local-Only Scratch Space

- `runs/` currently holds both generated run folders and local scratch documents such as `runs/codex-workflow-sync-plan.md` and `runs/x-post-draft.md`.
- Because `runs/` is ignored, these artifacts are part of the local workflow but not part of the reproducible tracked repo state.

## Not Present

- No database integration.
- No HTTP client or server implementation.
- No auth provider, webhook receiver, telemetry sink, or cloud deployment config.
- External behavior is almost entirely mediated through local CLIs and file I/O.
