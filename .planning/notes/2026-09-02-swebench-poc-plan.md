# SWE-bench proof-of-concept run: one task, every arm, published (2026-09-02)

Status: APPROVED (Alan, 2026-09-02). Execute from this file in a fresh Opus
session with Sonnet workers. Orientation: read `benchmarks/COMPLETE-SUITE-PLAN.md`
(on branch `codex/code-benchmark-battery`) and `benchmarks/code/README.md` first.

## Goal (Alan's words)

"Run just one task with the entire battery of co-evolution options, just to
get a proof of concept to see it works. We're not trying to get actual scores
here. We just want to prove the workflow: that we can do the tests, that the
tests pass, and that they can be published to GitHub with results."

Not in scope: scores anyone should cite, more than one task, other suites.

## Preconditions verified 2026-09-02

| Check | Result |
|---|---|
| Docker daemon | 29.6.2 running |
| `ZAI_API_KEY`, `KIMI_API_KEY` | present in `co-evolution-runtime/.env.local` (values never read) |
| `HF_TOKEN` | absent; evaluator works, only rate-limit warnings (plan issue 12) |
| Codex model | `codex exec -m gpt-5.6-sol -c model_reasoning_effort=xhigh` answers |
| Benchmark branch | `codex/code-benchmark-battery` @ 8339d52, unmerged; worktree `C:/Users/alan/Project/co-evolution-runtime` has 5 uncommitted files (adds the 50-task suite); last edit 2026-09-01 14:16, no session active |
| GitHub Pages | not enabled on `alanshurafa/co-evolution` (repo is public) |
| Prior runs | 5-task canary: all 7 arms graded. 50-task random subset: arm B only, 46/50 |

## Arms to run on the one task

| Arm | Label | Phases | Fable calls | Exists? |
|---|---|---|---|---|
| A | fable-solo | fable-implement | 1 | yes |
| B | cross-vendor-bounce | fable-implement, codex-repair | 1 | yes |
| C | fable-led-panel | fable-implement, codex+glm+kimi critique, fable-repair | 2 | yes |
| D | fable-self-bounce | fable-implement, fable-self-repair | 2 | yes |
| E | codex-solo | codex implement | 0 | yes |
| F | glm-solo-single-shot | one diff from GLM | 0 | yes |
| G | kimi-solo-single-shot | one diff from Kimi | 0 | yes |
| H | fable-glm-bounce | fable-implement, glm-critique, fable-repair | 2 | **new** |
| I | fable-kimi-bounce | fable-implement, kimi-critique, fable-repair | 2 | **new** |

Total: 10 Fable dispatches (~$15), 3 Codex cells (plan compute, inside the
codex-guard daily cap), GLM/Kimi in cents. Docker grading is local.

Task: `pallets__flask-5014` (from the frozen canary subset; smallest repo,
fastest image, already graded once per arm so infrastructure is known-good).

## Steps

### P0. Land the benchmark branch on master (no model spend)

1. In `co-evolution-runtime`, commit the 5 uncommitted files as
   "Add 50-task SWE-bench Verified suite definition" (they belong to that
   branch; the Codex session that wrote them is gone).
2. Merge `origin/master` (now includes PR #55 and the gpt-5.6-sol pin) into
   `codex/code-benchmark-battery`. Overlapping files: `tests/run-all.sh`,
   `.github/workflows/ci.yml`, `tests/{code-proposer,pr-emitter,policy-proposer,kimi-seat}-simulation.sh`.
   Keep both sides: #55's parallel/timeout/scratch-dir changes AND the
   branch's additions. `bash tests/run-all.sh --jobs 4` must be green.
3. Open a PR, merge on 3-OS CI green. Benchmark work continues on master
   afterwards (single worktree, no more branch drift).

### P1. Add arms H and I (no model spend)

- `benchmarks/code/conditions.json`: add H and I, tier `agentic`,
  dispatches `{claude:2, glm:1}` / `{claude:2, kimi:1}`, description must say
  "single-shot critic" (GLM/Kimi have no agent loop, plan issue 6).
- `benchmarks/code/drivers/run-workflow.sh`: phases
  `H) fable-implement,glm-critique,fable-repair`, `I) ...kimi-critique...`.
  Generalize the C repair prompt so it takes N reviewer files (C=3, H/I=1)
  instead of hardcoding three; reuse `run_direct_critic`.
- `benchmarks/code/tests/test-code-bench.sh`: add a stubbed scenario per new
  arm (phase list, manifest records the critic, repair prompt has exactly
  one reviewer section). Whole test file must pass.
- `benchmarks/code/README.md` conditions table: two rows.

### P2. Run (spend ~$15)

```bash
bash benchmarks/code/code-bench.sh run-canary \
  --run-id poc-flask-5014 --task pallets__flask-5014 \
  --conditions A,B,C,D,E,F,G,H,I --max-claude-dispatches 10 --dry-run
```
Dry run must show 10 declared Fable dispatches, then rerun without
`--dry-run`. The runner is resume-safe (per-cell `meta.json`); on any
provider failure, fix and rerun the same command. Then:

```bash
bash benchmarks/code/scripts/evaluate-swebench.sh --run-id poc-flask-5014
bash benchmarks/code/validate-predictions.sh --run-id poc-flask-5014
```
Exit: 9 prediction files validate; official evaluator report lists all 9
cells with resolved/unresolved and zero infrastructure failures. Record
Settings > Usage delta before/after as the cost line.

### P3. Publish to GitHub Pages

1. `bash benchmarks/site/aggregate.sh` -> `leaderboard.json`; render
   `leaderboard.html`. The page must carry, above the table: "Proof of
   concept: one SWE-bench Verified task, not a score. Frozen 50-task
   results for arm B are internal until the comparison arms run."
2. Commit the rendered outputs (JSON + HTML only, a few KB) to
   `benchmarks/site/public/`. Raw runs, workspaces, trajectories stay
   gitignored.
3. Add `.github/workflows/pages.yml`: on push to master touching
   `benchmarks/site/public/**`, `actions/upload-pages-artifact` +
   `actions/deploy-pages`. Enable Pages with source "GitHub Actions"
   (`gh api -X POST repos/alanshurafa/co-evolution/pages -f build_type=workflow`).
   This is the one outward-facing step; Alan asked for it explicitly on
   2026-09-02 ("published to GitHub with results").
4. Exit: page live at `https://alanshurafa.github.io/co-evolution/`, every
   number traceable to a file under `benchmarks/results/code/evaluation/`.

### P4. Report

Cost line, then: 9 arms, resolved yes/no each, wall time per arm, Fable
spend, page URL, and the list of anything that needed a manual retry.
Update memory `eval_suite_optimization_plan_2026_09_02` and this file's
Status line.

## Not decided yet (defaults chosen, change if Alan objects)

- Task choice `pallets__flask-5014` (fastest). Any canary ID works.
- Publish target GitHub Pages (repo already public; zero new accounts).
- Canary 5-task rows: not on the public page; only the POC row set.
