# Codex Runtime Routing Instructions

Use this file when you want Codex to choose the right Co-Evolution entrypoint before it starts work.

## Default Rule

Pick the lowest-ceremony path that still protects correctness. **Start with `co-evolve-bouncer.sh` unless the task specifically needs code execution.**

## Route By Task Shape

| Task shape | Use | Why |
|------------|-----|-----|
| Any question, idea, or strategy that benefits from cross-AI refinement | `bash co-evolve-bouncer.sh --vanilla "question"` | General-purpose compose + bounce |
| Markdown plan, spec, RFC, or document needs refinement | `bash co-evolve-bouncer.sh --vanilla --bounce-only <file>` | Bounces existing doc without compose |
| High-stakes question or argument that needs deep stress-testing | `bash co-evolve-bouncer.sh --vanilla --chain "input"` | Staged: critique → defend → tighten |
| 1-2 files, low risk, obvious implementation | direct execution | Fastest path when planning overhead is not useful |
| 2+ files, medium risk, ambiguous approach, needs code execution | `bash dev-review/codex/dev-review.sh <task>` | Adds compose, bounce, AND code execution |
| Existing approved plan should be executed as-is | `bash dev-review/codex/dev-review.sh --skip-plan --plan <file>` | Reuses the approved plan |
| User wants a reviewed plan before any code changes | `bash co-evolve-bouncer.sh --vanilla "task"` or `dev-review.sh --plan-only` | Plan artifact only |
| User wants a final review against the plan and diff | `bash dev-review/codex/dev-review.sh --verify <task>` | Runs verifier after execution |

## Distinguish Coding From Everything Else

Use `co-evolve-bouncer.sh` when the deliverable is a refined answer, document, or plan:

- questions and strategy
- plan refinement
- prompt tuning
- design notes
- architecture docs
- legal arguments
- draft emails

Use `dev-review.sh` when the deliverable is code plus an execution trail:

- feature work
- bug fixes
- refactors with repo edits
- tasks where optional verification is worth the extra pass

Use direct execution when the task is too small to justify the pipeline:

- typo fixes
- single-line config edits
- obvious narrow updates in 1-2 files

## co-evolve-bouncer.sh Key Flags

```
--vanilla          Shorthand for --skip-interview --auto (most common from Codex)
--bounce-only      Skip compose, bounce file directly
--chain            Staged passes: critique -> defend -> tighten
--bounces N        Max bounce passes (default: 2, ignored with --chain)
--agents A,B       Agent pair (default: claude,codex)
--context FILE     Background context file (not bounced)
--audience WHO     Prime agents for specific reader
--lens NAME        Named adversarial lens
--output FILE      Write output to file instead of stdout
```

## Risk Heuristics

- Low risk: isolated edit, clear fix, easy to inspect.
- Medium risk: multiple files, unclear implementation path, or repo instructions matter.
- High risk: behavior changes across subsystems, migrations, or tasks where you want `--chain` or `--verify`.

When in doubt:

1. Start with `co-evolve-bouncer.sh --vanilla` for questions and plans.
2. Use `dev-review.sh --plan-only` for medium/high-risk coding tasks.
3. Use `dev-review.sh --skip-plan --plan <file>` once the plan is approved.
4. Add `--verify` when the diff should be checked against the plan.

## Common Command Shapes

```bash
# General question — compose + bounce
bash co-evolve-bouncer.sh --vanilla "What is the best approach to add retry logic?"

# Bounce an existing document
bash co-evolve-bouncer.sh --vanilla --bounce-only docs/architecture-notes.md

# Chain mode for high-stakes stress testing
bash co-evolve-bouncer.sh --vanilla --chain "Argument for why the income was triple-counted"

# Produce a code plan and stop
bash dev-review/codex/dev-review.sh --plan-only "Add a retry wrapper around the Codex adapter"

# Run the full code pipeline with verification
bash dev-review/codex/dev-review.sh --verify "Add README coverage for the Codex runtime"

# Execute an existing approved plan
bash dev-review/codex/dev-review.sh --skip-plan --plan .planning/phases/04-docs-and-routing/04-01-PLAN.md
```

## Repo Paths

- General-purpose entry point: `co-evolve-bouncer.sh` (NEW — primary tool)
- Codex code runtime: `dev-review/codex/dev-review.sh`
- Codex router doc: `dev-review/codex/instructions.md` (this file)
- Legacy document bouncer: `agent-bouncer/agent-bouncer.sh`
- Claude Code skill surface: `skills/dev-review/`
- Shared library: `lib/co-evolution.sh`
- Co-evolve templates: `templates/co-evolve/`
