---
title: v1.4 addendum to the MCP server design (2026-04-19)
date: 2026-06-11
status: accepted — drives milestone v1.4
amends: 2026-04-19-mcp-server-design.md
---

# v1.4 addendum — reconciling the MCP design with the post-v1.3 toolkit

The 2026-04-19 spec predates milestone v1.3. Three decisions are amended;
everything not mentioned here stands as originally specified (architecture
shape, npm packaging, vendoring + version-pin, release pipeline, error
handling, README plan, success criteria).

## D-01 — Wrap `co-evolve-bouncer.sh`, not `agent-bouncer.sh`

The original spec wrapped `agent-bouncer.sh`. Two things changed in v1.3:

1. agent-bouncer is now explicitly **frozen legacy** (its README says so);
   co-evolve-bouncer is the development target.
2. co-evolve-bouncer runs now self-instrument: every run emits
   `state.json` (bounce-state/1.0), `bounce-scores.json` (deterministic
   behavior gate incl. the marker-fate ledger), and `HUMAN-REPORT.md` —
   for free, via the post-run hook.

The MCP server therefore spawns:

```
co-evolve-bouncer.sh --vanilla --bounce-only <doc> [--bounces N] [--agents A,B] [--output FILE]
```

Consequences:

- **Input safety improves over the original design.** agent-bouncer
  overwrites its input in place (the spec mitigated with copies);
  co-evolve-bouncer never touches the input. `in_place=true` is implemented
  as `output_path = document_path`.
- **Vendoring set grows** (build:vendor copies): `co-evolve-bouncer.sh`,
  `lib/co-evolution.sh`, `templates/co-evolve/`,
  `agent-bouncer/templates/bounce-protocol.md` (the canonical protocol the
  bouncer loads), and the receipts stack `evals/score-bounce.sh`,
  `evals/report-bounce.sh`, `evals/bounce-thresholds.yaml`.
- **Runs location**: co-evolve writes runs relative to its own script dir,
  which inside a global npm install may be read-only. v1.4 adds the
  `CO_EVOLVE_RUNS_DIR` env override upstream (default unchanged; pinned by
  `tests/bounce-state-simulation.sh` S6). The MCP server sets it to the
  caller's `runs_dir` (default `<document_dir>/.co-evolve/runs/`).

## D-02 — Tool output carries the receipts

This is the differentiator the npm pitch leans on ("agents improve your
doc — *and here's the receipt*"; evidence: Fable-5 blind judge 7/7 improved
on gate-passing historical runs). Output schema gains:

```ts
{
  // ... original fields (output_path, content, run_dir, passes_completed,
  //     reviewer_agent, composer_agent, duration_ms) ...
  scores: {                      // present when bounce-scores.json was produced
    overall_pass: boolean,
    marker_fates: Record<string, number>,   // resolved / deleted-with-section / ...
    dimensions: Record<string, boolean>
  } | null,
  report_path: string | null     // HUMAN-REPORT.md, when produced
}
```

`scores: null` is honest degradation, not an error (see D-03).

## D-03 — Preflight: doctor-style tiers; jq/yq optional for receipts

The original preflight checked bash/claude/codex as hard requirements.
Amended to match `scripts/doctor.sh` semantics:

- **Required:** `bash`, `claude` (authenticated — surfaced lazily via the
  v1.3 auth fail-fast, which returns a clear MCP error rather than garbage
  output).
- **Required only when selected:** `codex` — the default agent pair is
  claude+codex, but `reviewer_agent`/`composer_agent` set to claude-only
  must not demand codex.
- **Optional (receipts):** `jq` enables state.json + scores; `yq`
  (mikefarah) additionally enables the scorer. Missing → the bounce still
  runs, `scores`/`report_path` come back null, and the preflight result
  notes what to install for full receipts.

## Out of scope (unchanged from the original spec)

API-direct mode, a `dev_review` tool, PEL exposure, self-hosted CI runners,
`progress_verbosity` — all still deferred exactly as §11 lists them.
