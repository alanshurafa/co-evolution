# Rebuild — decision record

Working defaults adopted 2026-07-17 from proposal v1.1 §8 (`C:\Users\alan\Project\Admin\docs\rebuild-proposals\co-evolution.md`). Each is a default, not a ruling: Alan may override any of them at a gate, and an override becomes a TRACKER assumption-log entry plus an edit here.

## D1 — Naming and repo strategy
Tool name `co-evolve`; spec name "Bounce Protocol"; npm scope `@alanshurafa`. In-place migration: `packages/engine` on branch `rebuild/phase-0` in the existing repo. No fresh repo before parity — a fresh repo would split history, fixtures, and live maintenance while differential testing still needs both engines side by side (v1.1 §8.1, reversed from v1.0 under cross-AI review). Extraction to a separate repo is reconsidered only at publication (G2).

## D2 — Protocol scope and roles
The Bounce Protocol = marker grammar + loop semantics + termination rules. `review-verdict.json` is a separate, separately-versioned downstream contract. The orphaned `arbitrate` role (present only in the frozen `runners/codex-ps` reference tree) is retired; the spec's changelog records the retirement and the live role taxonomy (composer/reviewer ± light, chain critique/defend/tighten, executor, verifier).

## D3 — Single-model mode
Roadmap item for Phase 4, not built now. PR #30 closes in the housekeeping session (G1), with its idea credited in the roadmap.

## D4 — GSD integration
GSD remains a documented CLI consumer. No GSD-specific code paths in the engine.

## D5 — Housekeeping
Everything in proposal Appendix A is gated (G1). Nothing executed under this plan deletes, closes, edits, or retags anything in the main checkout, on origin, or on GitHub. The main checkout's dirty working tree (`.planning/` deletion, `AGENTS.md` half-edit, the salvageable lib fix) is preserved untouched for the G1 session.

## Gates in force

- **G1 housekeeping:** batched request delivered with WP-10's STOP B report unless needed earlier.
- **G2 publishing:** any public artifact (npm, MCP registry, marketplace, spec site). Dormant in Phase 0.
- **G3 metered spend:** paid direct-API calls. Subscription-CLI smoke calls at Haiku-class scale for WP-04/WP-06 are pre-authorized; anything beyond goes in a gate request.

## Standing constraints restated

Main checkout read-only except WP-02/WP-06 copy-out sources (`runs/`, `evals/reports/`); `runners/codex-ps/**` copy-only; workers never commit (orchestrator commits after verification); no real-model runs of the legacy Bash pipelines under this plan.
