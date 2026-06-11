---
title: Adoption/distribution — npm packaging + MCP server for the bounce protocol
trigger_condition: >
  MET 2026-06-10. Strongest-model judge (per owner delegation decision in
  VERIFY-BOUNCE-CALIBRATION.md) verdicts: 6/7 improved, 0 regressed, all
  evidence quotes verified. The agreement half was superseded by the owner's
  delegation ruling. Ready to spin up as milestone v1.4 on request.
planted_date: 2026-06-10
planted_during: v1.3 Reliability, Measurement & Cross-Platform — Phase 7
scope: medium (likely milestone v1.4)
status: fulfilled
---

# Seed (FULFILLED 2026-06-11): npm + MCP distribution of the bounce protocol

Graduated to **milestone v1.4** — see ROADMAP.md Active Milestone. Retained
as the trigger-evidence record.

## What

Make the bounce protocol invocable without `git clone`:

1. **MCP server** (`@alanshurafa/co-evolution-mcp`) wrapping the bouncer so
   Claude Desktop / Cursor / any MCP client can run bounces. Full design
   already captured (no re-design needed):
   `docs/superpowers/specs/2026-04-19-mcp-server-design.md`.
2. **npm packaging** for the CLI runner.

Also queued behind this trigger: the third-family judge via OpenRouter if
calibration shows self-preference bias (see VERIFY-BOUNCE-CALIBRATION.md).

## Why gated

The April competitive brainstorm concluded the cheap interop play
(BOUNCE-PROTOCOL.md) ships first, and distribution waits for either external
pull or evidence. v1.3 built the measurement stack (deterministic scorer,
blind judge, calibration harness) precisely so this decision can be made on
data: "bounce your doc, it measurably improves" is the pitch, and the
calibration numbers either back it or they don't.

## Trigger check (do this when calibration closes)

- [ ] VERIFY-BOUNCE-CALIBRATION.md closed with agreement stats
- [ ] >=60% "improved" verdicts on judged runs (threshold negotiable —
      the point is a defensible number in the README)
- [ ] If both hold: spin up milestone v1.4 from this seed + the MCP design doc
