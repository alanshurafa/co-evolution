# Orchestrating a benchmark phase

A phase is the same six stages whoever supervises it. The stages live in one
headless, resumable script, `scripts/phase-runner.sh`, and every orchestrator
is a thin adapter over it. The orchestrator is whichever host the session runs
in, and the choice is recorded rather than inferred.

## Who orchestrates

| Session runs in | Orchestrator | Adapter |
|---|---|---|
| Claude Code (`CLAUDECODE` set) | `claude` | `skills/bench-phase/SKILL.md`: kick the runner as a background task, end the turn, get woken, run the next stage |
| Codex (`CODEX_SANDBOX` or `CODEX_CI` set) | `codex` | the "Orchestrating a benchmark phase" section of `AGENTS.md`: kick the runner, then poll `phase-status.sh` at each check-in, because Codex has no wake-on-exit |
| Plain shell or cron on the run host | `shell` | run the stages by hand in order |

`CODE_BENCH_ORCHESTRATOR=claude|codex|shell[:label]` overrides the default. The
value is written into `phase-state.json` and becomes the status file's writer
id, so a second orchestrator attaching to a running phase is refused with the
owner's name, the same one-writer rule every status file in the harness
follows.

The orchestrator only runs shell commands and reads status JSON. It never reads
a raw log, and it never judges a result: a Codex session can supervise a phase
in which Codex is a seat, and a Claude session one in which Claude is, because
the gate is numbers from the aggregator, not the orchestrator's opinion.

## The six stages

| Stage | What it does | Idempotent because |
|---|---|---|
| `preflight` | manifests check, CLIs and keys present for the seats the conditions use, public metadata cached, no `ANTHROPIC_API_KEY`, declared dispatches fit the cap, Codex sandbox probe result reported | pure checks |
| `dispatch` | launches `run-canary` shards detached under `nohup`; records their pids | a running dispatch is left alone; `run-canary` reuses finished cells |
| `watch` | counts finished cells per arm from the cells themselves; says whether shards are alive (exit 4), exited short (exit 5) or done (exit 0) | reads only |
| `evaluate` | merges shard prediction files per arm, validates, scores under the run label | an arm whose newest report already covers its predictions is skipped |
| `aggregate` | rebuilds the site JSON and pages | rebuild is deterministic |
| `gate` | mechanical checks: every cell ran, every arm scored, site rebuilt, every row complete and fully priced, gold canary 1/1; reports the pre-registered contrast if observed | reads only |

`--stage all` runs preflight and dispatch, then returns 4 while the shards run.
Re-invoke with `--stage watch`, then `evaluate`, `aggregate`, `gate` as they
finish, or `--stage all` again: it continues from where the phase stands.

## Two kinds of gate

**Mechanical gates** have a right answer and a rule decides them. The runner
decides; the orchestrator reports.

**Spend gates** are the two decisions with money attached: dispatching model
calls, and advancing to the next phase. Both need a human go, delivered the
same way in every host: the orchestrator presents the compute estimate and the
exact command, then stops. The go is passed as `--approve-spend` on the
dispatch stage and recorded with a timestamp in `phase-state.json`. No
orchestrator infers it from context, and the gate stage never grants it.

## Commands

```bash
export CODE_BENCH_SUITE=swebench-verified-random50
bash benchmarks/code/code-bench.sh phase --phase-id 1 --run-id base50-light \
  --models light --conditions D,C,H,I,J,K,L,F,G --shards 2 --max-claude-dispatches 550 \
  --stage preflight
bash benchmarks/code/code-bench.sh phase ... --stage dispatch --dry-run       # counts only
bash benchmarks/code/code-bench.sh phase ... --stage dispatch --approve-spend # the human go
bash benchmarks/code/code-bench.sh phase-status 1-base50-light --json
bash benchmarks/code/code-bench.sh phase ... --stage evaluate
bash benchmarks/code/code-bench.sh phase ... --stage aggregate --also "One-task proof of concept=poc.html"
bash benchmarks/code/code-bench.sh phase ... --stage gate
```

State and logs live under `benchmarks/results/code/phases/<phase>-<run>/`.
