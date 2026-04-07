# Codex Runtime Routing Instructions

Use this file when you want Codex to choose the right Co-Evolution entrypoint before it starts work.

## Default Rule

Pick the lowest-ceremony path that still protects correctness:

- Direct execution for small, low-risk changes where Codex should just inspect the repo and edit.
- `agent-bouncer/agent-bouncer.sh` for document refinement where the output is a markdown artifact, not code changes.
- `dev-review/codex/dev-review.sh` for coding tasks that benefit from compose -> bounce -> execute -> optional verify.

## Route By Task Shape

| Task shape | Use | Why |
|------------|-----|-----|
| 1-2 files, low risk, obvious implementation | direct execution | Fastest path when planning overhead is not useful |
| Markdown plan, prompt, spec, ADR, or review text needs refinement | `bash agent-bouncer/agent-bouncer.sh <file>` | Bounces a document between agents without touching the repo |
| 2+ files, medium risk, ambiguous approach, or user wants a plan artifact | `bash dev-review/codex/dev-review.sh <task>` | Adds compose and bounce before execution |
| Existing approved plan should be executed as-is | `bash dev-review/codex/dev-review.sh --skip-plan --plan <file>` | Reuses the approved plan and skips compose/bounce |
| User wants a reviewed plan before any code changes | `bash dev-review/codex/dev-review.sh --plan-only <task>` | Produces the plan artifact and stops |
| User wants a final review against the plan and diff | `bash dev-review/codex/dev-review.sh --verify <task>` | Runs the optional verifier after execution |

## Distinguish Coding From Document Work

Use `agent-bouncer.sh` when the deliverable is the document itself:

- plan refinement
- prompt tuning
- design notes
- architecture docs
- review memos

Use `dev-review.sh` when the deliverable is code plus an execution trail:

- feature work
- bug fixes
- refactors with repo edits
- tasks where optional verification is worth the extra pass

Use direct execution when the task is too small to justify the pipeline:

- typo fixes
- single-line config edits
- obvious narrow updates in 1-2 files

## Risk Heuristics

- Low risk: isolated edit, clear fix, easy to inspect.
- Medium risk: multiple files, unclear implementation path, or repo instructions matter.
- High risk: behavior changes across subsystems, migrations, or tasks where you want `--plan-only` or `--verify` before trusting unattended execution.

When in doubt:

1. Start with `--plan-only` for medium/high-risk coding tasks.
2. Use `--skip-plan --plan <file>` once the plan is approved.
3. Add `--verify` when the diff should be checked against the plan.

## Common Command Shapes

```bash
# Produce a plan and stop
bash dev-review/codex/dev-review.sh --plan-only "Add a retry wrapper around the Codex adapter"

# Run the full Codex runtime with verification
bash dev-review/codex/dev-review.sh --verify "Add README coverage for the Codex runtime"

# Execute an existing approved plan
bash dev-review/codex/dev-review.sh --skip-plan --plan .planning/phases/04-docs-and-routing/04-01-PLAN.md

# Bounce a markdown file without code execution
bash agent-bouncer/agent-bouncer.sh docs/architecture-notes.md
```

## Routing Trace Format

When recommending a path, emit a short routing trace:

```text
+- WORKFLOW ROUTER --------------------------+
| Scope:      multi-file | Duration: one-session
| Artifact:   code       | Stakes:   medium
| Complexity: standard
|
| Recommendation: bash dev-review/codex/dev-review.sh
| Why: Multi-file code change with enough risk to benefit from a bounced plan
| Alternative: direct execution (if scope drops to 1-2 low-risk files)
+--------------------------------------------+
```

## Repo Paths

- Codex runtime: `dev-review/codex/dev-review.sh`
- Codex router doc: `dev-review/codex/instructions.md`
- Document-only bounce tool: `agent-bouncer/agent-bouncer.sh`
- Claude Code skill surface: `skills/dev-review/`
