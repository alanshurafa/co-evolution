---
name: bench-phase
description: >
  Supervise one SWE-bench benchmark phase from a Claude Code session without
  babysitting it. The session runs preflight, presents the compute estimate and
  waits for the user's explicit go, kicks the phase runner detached as a
  background task, ENDS ITS TURN, and on wake runs watch, evaluate, aggregate
  and the mechanical gate, then presents the numbers for the next spend
  decision. Use when the user says "run phase N", "dispatch the benchmark",
  "start the light matrix", "check the phase", or "how far is the run".
allowed-tools: Bash, Read, Grep, Glob
---

# /bench-phase - Claude Code adapter for `phase-runner.sh`

The protocol is `benchmarks/code/ORCHESTRATION.md`; this file is the Claude
Code adapter and adds nothing to it. The orchestrator id is `claude`
(`CLAUDECODE` is set in this host); set `CODE_BENCH_ORCHESTRATOR` only when
continuing a phase another orchestrator started, and say so.

The defining rule, shared with `/codex-build`: **the session is never kept busy
while the shards run.** Kick, end the turn, get woken.

## Step 1: PREFLIGHT (first turn)

```bash
export CODE_BENCH_SUITE=<suite>
bash benchmarks/code/code-bench.sh phase --phase-id <N> --run-id <run> --models <tier> \
  --conditions <list> --shards <M> --max-claude-dispatches <cap> --stage preflight
bash benchmarks/code/code-bench.sh phase ... --stage dispatch --dry-run
```

If preflight lists problems, fix or report them and stop. Otherwise present the
dry-run dispatch counts and the dollar estimate (Claude at the CLI's list
figure, Codex at the pricing-file rate with its total-only caveat, GLM and Kimi
pay-as-you-go), and the exact dispatch command. Then **stop and wait for the
user's go.** A go is the user's words in chat; nothing else counts.

## Step 2: DISPATCH (only after a go)

```bash
bash benchmarks/code/code-bench.sh phase ... --stage dispatch --approve-spend
```

Run this as a background Bash task and end the turn. The runner records the
approval with a timestamp and launches the shards under `nohup`; the task
returns as soon as they are running. Do not poll.

## Step 3: ON WAKE, or when the user asks how far the run is

```bash
bash benchmarks/code/code-bench.sh phase-status <N>-<run> --json
```

Exit 4 means shards are still alive: report progress in one line and end the
turn. Exit 0 with `watch` not yet complete means run `--stage watch`; if it
exits 5 (shards exited short), rerun `--stage dispatch` to retry only the
failed cells, again as a background task. When `watch` is complete:

```bash
bash benchmarks/code/code-bench.sh phase ... --stage evaluate    # Docker; long
bash benchmarks/code/code-bench.sh phase ... --stage aggregate --also "<label>=<href>"
bash benchmarks/code/code-bench.sh phase ... --stage gate
```

Evaluate is long; run it as a background task too and end the turn.

## Step 4: REPORT

Read the gate JSON (`.gate` in `phase-state.json`, or the `phase-status` output)
and the rebuilt `leaderboard.json`. Report, in the TL;DR / plain English /
technical format: the mechanical verdict and any failed check, the
pre-registered contrast's numbers if observed, the cost the arms actually
booked, and the go/no-go question for the next phase with its estimate and
command. Commit `benchmarks/site/public/` when the user says to publish.

The gate never approves spend and never advances a phase. Neither do you.
