# Bounce Runner Contract — `bounce-state/1.0`

The shared spec between the document bouncers (`co-evolve-bouncer.sh`,
`agent-bouncer/agent-bouncer.sh`) and the bounce scorer
(`evals/score-bounce.sh`). The dev-review code pipeline has its own contract
(`evals/RUNNER-CONTRACT.md`); this one covers document-bounce runs, which
historically wrote **no** machine-readable state.

## Files a conforming bounce run writes

All paths are **forward-slash, relative to the run directory** — a run
produced on Windows must score byte-identically on macOS/Linux.

| Artifact | Written by | Purpose |
|----------|-----------|---------|
| `state.json` | both bouncers | machine-readable run record (schema below) |
| `original-input.md` | both bouncers | verbatim input document/question |
| `compose-output.md` | co-evolve compose mode | composed draft (the baseline in compose mode) |
| `pass-N-clean.md` | both bouncers | post-pass document, HUMAN SUMMARY stripped — **plain name, not dot-prefixed** (dot-prefixed artifacts are invisible to `ls` and were repeatedly missed by humans and tools; same bug class as `.compose-prompt.md`) |
| `pass-N-<role>-<agent>-raw.md` | both bouncers | raw agent output before stripping |
| `working.md` / final named copy | both bouncers | the final document |
| `run.log` | both bouncers | human-readable transcript |

Historical runs (pre-v1.3) used `.bounce-pass-N-clean.md` (dot-prefixed,
co-evolve) or no clean-pass files at all (agent-bouncer). The scorer's
artifact-parsing fallback MUST check the dotted legacy name before declaring
a pass artifact missing.

## `state.json` schema (`bounce-state/1.0`)

```json
{
  "schema": "bounce-state/1.0",
  "runner": "co-evolve-bouncer.sh",
  "mode": "compose | bounce-only | chain | agent-bouncer",
  "task": "<task string or input file path>",
  "input_type": "file | string | pipe",
  "baseline_file": "original-input.md",
  "final_file": "working.md",
  "status": "running | complete | aborted",
  "started_at": "2026-06-10T22:00:00Z",
  "finished_at": "2026-06-10T22:06:30Z",
  "passes": [
    {
      "pass": 1,
      "role": "reviewer",
      "agent": "claude",
      "output_raw": "pass-1-reviewer-claude-raw.md",
      "output_clean": "pass-1-clean.md",
      "contested": 3,
      "clarify": 2,
      "total_markers": 5,
      "word_count": 1234
    }
  ]
}
```

Field rules:

- `schema` — literal `"bounce-state/1.0"`. Consumers MUST reject other values.
- `baseline_file` is **mode-aware**: the scorer compares the final document
  against this file. In `compose` mode it is `compose-output.md` (the bounce
  loop's job is to improve the *composed draft*; comparing against the
  original question would conflate composition with bouncing). In
  `bounce-only`, `chain`, and `agent-bouncer` modes it is
  `original-input.md`.
- `status` — `running` at init; `complete` only when the loop finished all
  passes (converged or expired); `aborted` on any fatal exit (auth failure,
  empty retry, user stop). A scorer MUST NOT issue a quality verdict for an
  `aborted` run.
- `passes[].contested` / `clarify` — marker counts of the **clean** output,
  counted by `lib/co-evolution.sh::count_markers` (code-fence-aware). The
  scorer reuses the same function; counts must match.
- `passes[].word_count` — `wc -w` of the clean output.
- Timestamps are UTC ISO-8601 with a trailing `Z`, second precision.

## Writer helpers (lib/co-evolution.sh)

- `init_bounce_state <state_file> <runner> <mode> <task> <input_type> <baseline_file> <final_file>`
- `append_bounce_pass <state_file> <pass> <role> <agent> <raw_rel> <clean_rel> <contested> <clarify> <word_count>`
- `finalize_bounce_state <state_file> <status>`

All three are jq-backed. When jq is unavailable they log a warning and write
nothing — the scorer's artifact-parsing fallback covers that case, and a
partial hand-rolled JSON writer is worse than an honest absence.

## Scorer obligations (evals/score-bounce.sh, v1.3 Phase 4)

1. Prefer `state.json` (validate `schema`); fall back to artifact parsing so
   historical runs score on day one.
2. Treat `delta`/marker math as derived from artifacts when state and
   artifacts disagree — artifacts win, and the disagreement is itself a
   reported defect.
3. Emit deterministic output: byte-identical for the same run dir (modulo a
   `scored_at` timestamp field).
