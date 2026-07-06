# Bounce Runner Contract — `bounce-state/1.1`

The shared spec between the document bouncers (`co-evolve-bouncer.sh`,
`agent-bouncer/agent-bouncer.sh`) and the bounce scorer
(`evals/score-bounce.sh`). The dev-review code pipeline has its own contract
(`evals/RUNNER-CONTRACT.md`); this one covers document-bounce runs, which
historically wrote **no** machine-readable state.

**Version history.** `1.1` (v1.5 Phase 4) adds the optional
`convergence_status` field and, for a run whose markers survive the configured
passes, the `adjudication-report.md` artifact. `1.1` is a strict superset of
`1.0`: the field is additive, so a `1.0` consumer reads a `1.1` state
losslessly, and consumers MUST accept the whole `bounce-state/1.x` family
rather than an exact string match.

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
| `adjudication-report.md` | co-evolve, adjudicated runs only | one bullet per stripped marker: the chosen text + a one-line rationale (see `convergence_status` below). Absent on `converged` and `stuck` runs. |
| `run.log` | both bouncers | human-readable transcript |

Historical runs (pre-v1.3) used `.bounce-pass-N-clean.md` (dot-prefixed,
co-evolve) or no clean-pass files at all (agent-bouncer). The scorer's
artifact-parsing fallback MUST check the dotted legacy name before declaring
a pass artifact missing.

## `state.json` schema (`bounce-state/1.0`)

```json
{
  "schema": "bounce-state/1.1",
  "runner": "co-evolve-bouncer.sh",
  "mode": "compose | bounce-only | chain | agent-bouncer",
  "task": "<task string or input file path>",
  "input_type": "file | string | pipe",
  "baseline_file": "original-input.md",
  "final_file": "working.md",
  "status": "running | complete | aborted",
  "convergence_status": "converged | adjudicated | stuck | null",
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

- `schema` — a `"bounce-state/1.x"` string (currently `"bounce-state/1.1"`).
  Consumers MUST accept the whole `1.x` family (e.g. match `^bounce-state/1\.`)
  and MUST reject a `2.x` or malformed value. A `1.0` state (no
  `convergence_status` key) is still valid and MUST score without error.
- `baseline_file` is **mode-aware**: the scorer compares the final document
  against this file. In `compose` mode it is `compose-output.md` (the bounce
  loop's job is to improve the *composed draft*; comparing against the
  original question would conflate composition with bouncing). In
  `bounce-only`, `chain`, and `agent-bouncer` modes it is
  `original-input.md`.
- `status` — the **lifecycle** field: `running` at init; `complete` only when
  the loop finished all passes (and any adjudication); `aborted` on any fatal
  exit (auth failure, empty retry, user stop). A scorer MUST NOT issue a
  quality verdict for an `aborted` run. Orthogonal to `convergence_status`.
- `convergence_status` — the **convergence** field, distinct from `status` (a
  run can be `complete` yet `stuck`). The convergence decision counts markers
  **fence-agnostically** (`lib/co-evolution.sh::count_markers_raw`): a marker
  token inside a code fence or inline code still blocks convergence, unlike
  the per-pass `passes[].contested`/`clarify` counts, which stay fence-aware.
  One of:
  - `converged` — raw marker count reached 0 within the configured passes. No
    adjudication ran; the emitted document is byte-identical to what the
    pre-`1.1` bouncer produced on the same input (the byte-parity invariant).
  - `adjudicated` — markers survived the configured passes, so one forced
    adjudication pass resolved every one and wrote `adjudication-report.md`
    (>= one CHOSE/WHY bullet per surviving marker); the final document carries
    0 live markers.
  - `stuck` — the adjudication pass could not defensibly resolve every marker
    (no report, malformed report, or markers still live). The working document
    is preserved **with** its markers and is labeled `CO-EVOLVE:STUCK`; it is
    NOT a clean final. The scorer MUST fail its behavior gate on a `stuck` run.
  - `null` / absent — the runner did not record convergence (agent-bouncer, or
    a legacy `1.0` state). Consumers MUST treat this as "unknown" and MUST NOT
    fail a gate on it. Only an explicit `stuck` blocks.
  Only `co-evolve-bouncer.sh` writes this field today; `agent-bouncer.sh`
  leaves it `null`.
- `passes[].contested` / `clarify` — marker counts of the **clean** output,
  counted by `lib/co-evolution.sh::count_markers` (code-fence-aware). The
  scorer reuses the same function; counts must match.
- `passes[].word_count` — `wc -w` of the clean output.
- Timestamps are UTC ISO-8601 with a trailing `Z`, second precision.

## Writer helpers (lib/co-evolution.sh)

- `init_bounce_state <state_file> <runner> <mode> <task> <input_type> <baseline_file> <final_file>`
- `append_bounce_pass <state_file> <pass> <role> <agent> <raw_rel> <clean_rel> <contested> <clarify> <word_count>`
- `set_bounce_convergence_status <state_file> <converged|adjudicated|stuck>` — set the convergence outcome (co-evolve only; call before `finalize_bounce_state`).
- `finalize_bounce_state <state_file> <status>`

All are jq-backed. When jq is unavailable they log a warning and write
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
