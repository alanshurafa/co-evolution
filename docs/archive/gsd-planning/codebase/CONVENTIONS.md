# Conventions

## Shell Coding Style

- `agent-bouncer/agent-bouncer.sh` starts with `set -euo pipefail` and relies on fail-fast shell semantics.
- Repository-wide shell style favors uppercase globals and lowercase helper/local names.
- Functions are short and single-purpose: adapter invocation, cleanup, and logging are separated.
- File-based orchestration is preferred over pipes between complex subprocess chains.
- Defensive cleanup is handled with `trap cleanup EXIT`.

## Prompt And Template Conventions

- Prompt templates use literal placeholder tokens such as `{TASK}` and `{PLAN_CONTENT}`.
- Both the bouncer and the skill embed plan content inline into prompts instead of handing Codex the canonical plan file path.
- The bounce protocol insists on editing the document directly rather than returning commentary or diffs.
- `[CONTESTED]` and `[CLARIFY]` are the shared coordination markers across the repo.
- A `## HUMAN SUMMARY` section is preserved as metadata for per-pass explanation and stripped from the clean canonical output by `agent-bouncer/agent-bouncer.sh`.

## Artifact Conventions

- Raw pass outputs are always preserved separately from the canonical working document.
- Clean outputs are named after the run label instead of a fixed filename.
- stderr is captured per pass in `runs/bouncer-*/pass-N-stderr.log`.
- Generated run artifacts are kept local and ignored through `.gitignore`.

## Documentation Conventions

- Behavior is documented close to the implementation: `agent-bouncer/README.md` for the script and `skill/README.md` for the skill.
- The repo uses markdown tables, command examples, and file trees heavily instead of typed interfaces or generated docs.
- `notesforhumans.md` carries concept and origin context that is intentionally hidden from agent ingestion via `.agentignore`.

## Workflow Conventions

- The bounce alternates reviewer on odd passes and composer on even passes.
- Most workflows assume two passes are the high-value default.
- The skill's verification phase expects JSON-only output matching `skill/schemas/review-verdict.json`.
- Recent git history uses imperative commit subjects such as `Fix Claude max-turns and Codex non-git-repo failures`.

## Error-Handling Conventions

- Empty agent output triggers a retry.
- Suspiciously short output triggers a retry because the agent may have returned a summary instead of the full document.
- Marker counting ignores fenced code blocks and inline backticks to reduce false positives when the docs discuss marker syntax itself.
- Adapter functions tolerate non-zero subprocess exits and rely on downstream file checks to decide whether a pass truly failed.

## What Is Not Standardized

- There is no formatter, linter, or automated style enforcement.
- There is no shared library enforcing consistency between `agent-bouncer/templates/` and `skill/templates/`.
- Process discipline is encoded mostly in docs, prompts, and human review rather than in tests or static analysis.
