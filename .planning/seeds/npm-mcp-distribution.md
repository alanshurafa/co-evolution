---
title: Adoption/distribution — npm packaging + MCP server for the bounce protocol
trigger_condition: >
  Bounce calibration (VERIFY-BOUNCE-CALIBRATION.md) shows a measurable lift:
  judge↔human agreement >=4/5 AND >=60% of judged runs verdict "improved".
  The pitch needs evidence before the packaging work is worth it.
planted_date: 2026-06-10
planted_during: v1.3 Reliability, Measurement & Cross-Platform — Phase 7
scope: medium (likely milestone v1.4)
status: dormant
---

# Seed: npm + MCP distribution of the bounce protocol

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
