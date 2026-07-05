# Workflow Upgrade — Execution Progress

**Plan:** `.planning/notes/2026-07-05-workflow-upgrade-plan.md` (bounced/converged 2026-07-05) · **Orchestrator:** Fable session on `claude/vigilant-antonelli-32d5bc` · **Mode:** one-shot loop (self-paced), PR per phase to master.

## Gate interpretation (Alan approved one-shot 2026-07-05)
- Origin branch deletions: proceed, but **archive-tag every branch first** (`archive/<branch>` tag at tip) so deletion is recoverable. Manifest recorded below before push.
- Plugin install (P3): attempt non-interactive `claude plugin` CLI; on any failure, deliver the manual checklist instead — never force.
- P5 spend: bounded — one codex-build dogfood run + one calibration pass (inspect calibrate-bounce cost shape first; if >~6 judge calls, downgrade to single judge-bounce and note deviation).
- npm publish: NOT executed (Alan only). `runners/codex-ps/**`: no changes, ever.

## Waves
| Phase | Branch | Builder (model/thinking) | Reviewer | Status |
|-------|--------|--------------------------|----------|--------|
| P0 hygiene + auth gate | claude/wf-p0-hygiene | opus / think hard | adversarial-reviewer opus | launching |
| P0.2 branch manifest | (orchestrator ops) | sonnet scout (read-only) | orchestrator | launching |
| P1 model routing | claude/wf-p1-routing | opus / ultrathink | adversarial-reviewer opus | blocked by P0 merge |
| P2 token discipline | claude/wf-p2-discipline | opus / think hard | adversarial-reviewer sonnet | blocked by P1 merge |
| P3 boundary docs | claude/wf-p3-boundary | sonnet / default | adversarial-reviewer sonnet | blocked by P1 merge (∥ P2) |
| P4 convergence + port | claude/wf-p4-convergence | opus / ultrathink | adversarial-reviewer opus | blocked by P2+P3 merge |
| P5 live evidence | (orchestrator, 💰) | orchestrator | — | blocked by P4 merge |

## Contracts
- Builders: work ONLY in their isolated worktree; create branch from **master** (`git checkout -b <branch> master`); commit locally; never push, never open PRs, never touch `runners/codex-ps/**` or `.planning/notes/2026-07-05-*`; run `bash tests/run-all.sh` before reporting; build report ≤20 lines (files + line ranges, what ran, pass/fail, diffs only ≤30 lines).
- Claude CLI calls from scripts/smokes: use `C:/Users/alan/Project/ExoCortex/scripts/lib/claude_cli.sh` wrapper.
- Orchestrator owns: pushes, PRs (cite plan SHA), CI watch, merges, branch ops, P5 spend, this file.

## Decisions log
- 2026-07-05: plan + progress committed on claude/vigilant-antonelli-32d5bc; SHA cited in every phase PR.

## State
- Plan SHA: (pending first commit)
- PRs: none yet
- Last update: 2026-07-05 wave 1 launch
