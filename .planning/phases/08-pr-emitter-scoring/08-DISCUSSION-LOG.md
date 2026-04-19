# Phase 8: PR Emission + Scoring Integration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `08-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-04-19
**Phase:** 08-pr-emitter-scoring
**Areas discussed:** Module layout, Scoring sandbox lifecycle, PR branch strategy, Plan decomposition

**Pre-session state:** `08-PRE-DISCUSS-BOUNCE.md` had already converged 5 decisions between Claude and Codex (SC-4 handling, `--dry-run` placement, DEF-07-01 fix placement, tier routing, scoring compute budget). Those entered the session as locked.

---

## Module layout for `lab/pel/pr-emitter/`

| Option | Description | Selected |
|--------|-------------|----------|
| A. Single-file | `pr-emitter.sh` only — simplest; no adapter needed; all logic in one file; diverges from `lab/pel/proposer/*` convention | |
| B. Two-file | `pr-emitter.sh` + `pr-body-template.md` — keeps template-placeholder pattern; body editable without shell changes; fits long PR-body content | ✓ |
| C. Full proposer-mirror | `pr-emitter.sh` + `adapter.sh` + `prompt.md` — full Phase 5/6/7 consistency; but adapter with no LLM = dead code; prompt filename misleading for non-LLM artifact | |

**User's choice:** B (accepted agent recommendation wholesale)
**Notes:** Heredoc-in-shell would be fragile for a long-form PR body; `{{placeholder}}` substitution matches how `prompt.md` already works in Phases 5/6/7.

---

## Scoring sandbox lifecycle

| Option | Description | Selected |
|--------|-------------|----------|
| A. Phase 7 gains `--hold-sandbox` | Phase 7 proposer skips cleanup when Phase 8 calls; Phase 8 consumes same worktree; requires retroactive edit to a closed phase; ownership boundary blurs | |
| B. Phase 8 owns its own sandbox | Phase 7 emits diff + state.json, cleans up normally. Phase 8 creates separate worktree, re-applies diff, scores, cleans up. Clean phase boundaries; Phase 7 untouched; explicit handoff contract | ✓ |
| C. Phase 8 re-runs proposer | Proposer invoked twice (canary / scoring) — no coordination but wasteful; re-invokes Opus 4.7 | |

**User's choice:** B
**Notes:** `git worktree add` is cheap (shared .git object store). Preserves Phase 7's closed status. Handoff contract = stdout diff + state.json (emitter reads state.json BEFORE proposer's EXIT trap cleanup fires).

---

## PR branch strategy

| Option | Description | Selected |
|--------|-------------|----------|
| A. Reuse v1.1 `--branch auto\|NAME` + `--worktree auto\|PATH` | User passes existing flags; zero new CLI surface; but "auto" naming not collision-free across parallel PEL runs; v1.1 flags designed for dev-review human workflow | |
| B. PEL-only auto-scheme always | `pel/<tier>/<short-hash>` with no user knob; predictable + collision-resistant; but no override for retry/dogfood edge cases | |
| C. Hybrid | Default `pel/<tier>/<short-hash>`; override via `--pr-branch NAME`; predictable defaults + escape hatch | ✓ |

**User's choice:** C
**Notes:** Matches v1.1 escape-hatch ergonomic (like `CLASSIFIER_MODEL`, `PROPOSER_MODEL`, `CODE_PROPOSER_MODEL`). `<short-hash>` = first 7 chars of `sha1sum`(diff) or `git hash-object`(diff) — exact tool choice is Claude's Discretion at plan time.

---

## Plan decomposition

| Option | Description | Selected |
|--------|-------------|----------|
| A. 2 plans (ROADMAP default) | 01: DEF-07-01 + wrapper + routing + scoring + cache + PR body + sim / 02: dogfood. Fewest artifacts but Plan 01 bundles 6 subsystems | |
| B. 3 plans | 01: DEF-07-01 + wrapper dispatch + tier routing / 02: scoring + cache + PR body + gh + sim gate / 03: dogfood (VERIFY-SC4.md). Matches Phase 5/6/7 sizing | ✓ |
| C. 4 plans | 01: DEF-07-01 / 02: wrapper+routing / 03: scoring+cache+PR+sim / 04: dogfood. One responsibility per plan but DEF-07-01 alone is ~1 line | |

**User's choice:** B
**Notes:** Plan 01 is the "foundation" commit (bugfix + plumbing); Plan 02 is "feature + simulation gate" (mirrors Phase 7's core + sim split); Plan 03 is the release tracker (non-code deliverable).

---

## Claude's Discretion (deferred decisions)

The following gray areas were NOT discussed — Alan accepted the agent's defaults wholesale. Captured as decisions D-15 through D-20 in `08-CONTEXT.md`:

- **Gray area #2 — PR body composition** → external `pr-body-template.md` with `{{placeholder}}` substitution (D-20)
- **Gray area #5 — Eval cache location** → `.co-evolve-cache/evals/<fixture-hash>-<script-hash>.json` (gitignored, per-repo; D-18, D-19)
- **Gray area #7 — Failure policy** → diagnostic draft PR marked `[CANARY-FAILED]` for proposer exit 7 only; all other proposer non-zero exits abort silently (D-15, D-16, D-17)

Additional Claude's-Discretion items — flexibility retained at plan time:

- Exact placeholder set in `pr-body-template.md`
- Tier routing implementation (bash case vs jq lookup vs `routing.yaml`)
- Hash tool for branch short-hash (`sha1sum` vs `git hash-object`)
- Preflight cost estimate table shape
- `gh pr create` failure handling (retry vs immediate abort)
- Simulation scenario count (≥5 per SC-3; targeting ≥10 for parity with Phase 7's sim density)
- Whether tier detection lives in `pr-emitter.sh` or a separate `router.sh` helper

---

## Deferred Ideas

Ideas mentioned during analysis that were noted for future phases (full list in `08-CONTEXT.md` `<deferred>` section):

- Automatic branch / worktree cleanup after PR merge/close — v1.2+ utility
- Multi-mutation stacked-PR emitter — triggered by SC-4 dogfood if review fatigue emerges
- Rendered-HTML PR body with collapsible diff — post-v1.2 UX iteration
- `co-evolve cost` subcommand — v1.3+ standalone query
- PEL Options 2 (auto-promote) + 3 (explorer+curator) — v1.3+, seeded in `.planning/seeds/pel-auto-promote-and-explorer.md`
- Classifier evolution (PEL-META-01) — v1.3+
- Workspace-agnostic PS port of lab integration scripts — v1.0 Phase 9 deferred, not blocking v1.2

---

## Session Meta

- **Advisor mode:** Detected active (USER-PROFILE.md present, calibration = standard per "pragmatic" vendor philosophy) but parallel research-agent spawning was skipped — the gray areas were deeply project-specific (module layout, sandbox lifecycle, branch naming, plan count) where external best-practice research would add noise over the in-repo pattern precedents. Comparison tables built from Phase 4-7 context instead.
- **Text-mode fallback:** `AskUserQuestion` tool was not loaded in this session; used plain-text numbered options and a comparison-table batch instead.
- **Trust-handoff flag (D-22):** Alan replied "go with your recommendations. They look good. Honestly a lot of this is above my head." This is a delegation signal, not a deferral. Planning agents should execute confidently within the locked decisions and surface only SIGNIFICANT deviations.
