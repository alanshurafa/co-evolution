---
title: Adaptive co-evolve — complexity-aware model routing for PEL
date: 2026-04-21
status: design — pending implementation plan
related:
  - docs/superpowers/specs/2026-04-19-mcp-server-design.md (deferred sibling)
  - .planning/VERIFY-SC4.md (SC-4 dogfood blocked partly on Opus quota burn — adaptive routing addresses this)
  - ~/.claude/skills/adaptive/SKILL.md (design pattern reference)
inspired_by:
  - First SC-4 dogfood run (2026-04-20) surfaced silent hangs on Opus quota exhaustion + always-Opus invocation pattern wasting quota on simple template tweaks
---

# Adaptive co-evolve

A complexity-aware routing layer that picks the right model (Sonnet vs Opus) per PEL invocation, plus graceful handling of quota exhaustion via the Claude CLI's `--fallback-model` flag. Inspired by the `/adaptive` skill's design pattern but ported into PEL's runtime context.

## 1. Context & motivation

Today PEL hardcodes a single model per adapter (`opus` alias). This has two real problems observed during 2026-04-20 SC-4 dogfood:

1. **Opus is overkill for simple template tweaks.** Most template-tier mutations are small wording changes that Sonnet handles cleanly. Burning Opus quota on every invocation is wasteful — and we ran out of quota partway through the dogfood loop.
2. **Quota exhaustion presents as silent hang.** When Opus is overloaded or quota is exhausted, `claude -p` doesn't error; it stalls indefinitely. We mistook this for a model-availability bug initially.

**Goal:** ship a router layer in `lab/pel/router/` that picks Sonnet for NORMAL-complexity work, escalates to Opus + thinking budget for COMPLEX work, and wires `--fallback-model sonnet` into every `claude -p` call so quota-related stalls auto-degrade instead of hanging.

**Non-goal:** parity with the `/adaptive` skill's full feature set (5 tiers, hook-based interception, sticky session mode). PEL's runtime context is different from Claude Code skills; ports of those mechanics would be cargo-culting.

## 2. Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Scope | Model selection + `--fallback-model` quota fallback | Smallest scope that fixes both real issues observed today |
| 2 | Classifier location | New `lab/pel/router/` (separate from frozen Phase 4 flavor classifier) | Keeps Phase 4 D-11 frozen-surface invariant intact; decoupled iteration |
| 3 | Default behavior | On by default; `--no-adaptive` to disable | We're already inside opt-in lab boundary; wrong-pick risk is bounded by fallback flag |
| 4 | Tier mapping | 2-tier: NORMAL → Sonnet, COMPLEX → Opus + think harder | Haiku diff quality is unproven; conservative start, telemetry justifies expansion |
| 5 | Invocation point | Single call from `pr-emitter.sh`, NOT per-adapter | Avoids 3× duplication; pr-emitter is the natural orchestration point |
| 6 | Fallback strategy | Always pass `--fallback-model sonnet` | Simplest thing that works; covers silent-hang case directly |
| 7 | Telemetry | Aggregate JSONL at `.co-evolve/router-history.jsonl` | Append-only, gitignored, analysis-ready without external pipeline |
| 8 | User override | `--complexity SIMPLE\|NORMAL\|COMPLEX` flag | Covers "I know this is hard" case; raw `--model` adds confusion |

## 3. Architecture

```
┌──────────────────────────┐
│ co-evolve-bouncer.sh     │  entry point
│   --lab pel-proposer     │  --no-adaptive sets PEL_NO_ADAPTIVE=1
│   --complexity TIER      │  optional override → PEL_COMPLEXITY_OVERRIDE
└────────────┬─────────────┘
             ▼
┌──────────────────────────────────────────────┐
│ lab/pel/pr-emitter/pr-emitter.sh             │
│                                              │
│  1. tier auto-detect (template/policy/code)  │  existing
│  2. flavor classifier (Phase 4, frozen)      │  existing
│  3. ┌─────────────────────────────────┐     │
│     │ NEW: lab/pel/router/router.sh   │     │
│     │ (skipped if PEL_NO_ADAPTIVE=1)  │     │
│     │                                 │     │
│     │ Haiku call → emit routing JSON  │     │
│     └─────────────────────────────────┘     │
│  4. export PROPOSER_MODEL from routing JSON  │  NEW (4 lines)
│  5. invoke tier-specific proposer            │  existing
│  6. emit PR (existing flow)                  │  existing
│  7. append telemetry to JSONL                │  NEW (5 lines)
└──────────────────────────────────────────────┘
```

The router is a single Haiku call between flavor classification and proposer invocation. Output is structured JSON consumed by pr-emitter.sh to set env vars for the proposer. The router is best-effort — its job is to save quota when it can; PEL must keep working even if the router itself misbehaves.

## 4. Router contract

### Inputs (env vars set by pr-emitter.sh)

```bash
TARGET=...                   # target file path (already known to pr-emitter)
PEL_TIER=...                 # template/policy/code (already resolved)
PEL_FLAVOR=...               # bug-catcher/faster/blind-spot/general (from flavor classifier)
PEL_FEEDBACK=...             # path to eval feedback JSON
PEL_COMPLEXITY_OVERRIDE=...  # optional, from --complexity flag (skips Haiku if set)
```

### Output (single JSON object on stdout)

```json
{
  "complexity": "NORMAL" | "COMPLEX",
  "model": "sonnet" | "opus",
  "fallback_model": "sonnet",
  "thinking_budget": null | "harder",
  "rationale": "code-tier mutation always escalates to COMPLEX",
  "inputs": {
    "pel_tier": "code",
    "target": "lib/co-evolution.sh",
    "target_size_bytes": 35000,
    "flavor": "bug-catcher",
    "user_override": null
  }
}
```

### Tier-to-model mapping

| Complexity | Model | Thinking | Use cases |
|------------|-------|----------|-----------|
| NORMAL | `sonnet` | none | Most template + policy mutations |
| COMPLEX | `opus` | `--thinking-budget harder` if CLI supports; else append "think harder" to prompt | Code-tier always; large/risky template/policy changes |

### Heuristics passed to Haiku as bias

The Haiku call does the actual classification, but Haiku is given these hints in its prompt:

- `pel_tier == "code"` → strongly bias COMPLEX (shell mutations are too risky for Sonnet)
- `pel_tier == "template" && target_size_bytes < 2000` → bias NORMAL
- `pel_tier == "policy"` → bias NORMAL (bounded knob surface)
- Otherwise → Haiku decides from feedback content + flavor

Why use Haiku at all rather than pure heuristics (the C alternative we considered): file-size + tier rules are brittle. Haiku adds ~$0.001 per invocation and ~30 seconds — negligible against the 23-min total runtime measured during dogfood.

## 5. Repo layout

```
lab/pel/router/                      # NEW
├── README.md                        # contract, tier table, troubleshooting
├── router.sh                        # entry; reads inputs, invokes Haiku, emits JSON
├── prompt.md                        # Haiku classifier prompt
└── adapter.sh                       # inline-helpers Haiku invoker (mirrors classifier/adapter.sh)

lab/pel/pr-emitter/pr-emitter.sh     # MODIFIED (~10 lines added)
  - new section between flavor classifier + proposer invocation: invoke router, parse JSON, export PROPOSER_MODEL
  - new tail section: append telemetry record to .co-evolve/router-history.jsonl

co-evolve-bouncer.sh                 # MODIFIED (~10 lines added)
  - new flags: --no-adaptive, --complexity SIMPLE|NORMAL|COMPLEX
  - argv passthrough to PEL via existing pel-proposer dispatch

lab/pel/proposer/template/adapter.sh # MODIFIED (~2 lines)
lab/pel/proposer/code/adapter.sh     # MODIFIED (~2 lines)
  - claude -p invocation gains --fallback-model "${FALLBACK_MODEL:-sonnet}"

.co-evolve/                          # gitignored (already exists per Phase 8 D-18)
└── router-history.jsonl             # append-only telemetry; one line per PEL invocation

tests/router-simulation.sh           # NEW (~300 lines, mirrors classifier-simulation.sh pattern)
  - hermetic Haiku stub via PATH injection
  - 5 primary scenarios covering happy paths + error modes
```

## 6. Telemetry format

`.co-evolve/router-history.jsonl` — one JSON object per line per PEL invocation:

```json
{"ts": "2026-04-21T15:30:00Z", "run_id": "...", "target": "skills/dev-review/templates/review-prompt-opus.md", "pel_tier": "template", "flavor": "blind-spot-surfacer", "complexity": "NORMAL", "model_chosen": "sonnet", "fallback_fired": false, "router_duration_ms": 850, "total_pel_duration_ms": 1380000, "user_override": null}
```

Use cases:
- "Did the router pick NORMAL when it should have picked COMPLEX?" — `jq` + manual review
- "How often does fallback fire?" — quota signal over time
- Future: feed into a meta-router that learns from history (deferred — needs ≥100 records)

## 7. Error handling

| Failure | Behavior |
|---------|----------|
| Router script not found / unexecutable | pr-emitter.sh prints WARN, falls back to current hardcoded `opus` default, continues. Doesn't kill PEL. |
| Haiku call fails (auth, network, malformed response) | router.sh emits canonical JSON with `complexity: "COMPLEX"` (safe-side default) + `rationale: "router-failure-fallback"` and exit 0. Logs WARN. |
| Haiku returns invalid complexity value | Same as above (safe-side fallback). |
| `--complexity` override with invalid value | Hard fail at `co-evolve-bouncer.sh` argv parse — exit 1 with usage error. |
| `--no-adaptive` set | Router skipped entirely. PEL behaves as today (always Opus). |
| `--fallback-model sonnet` fires (Opus overloaded) | Telemetry records `fallback_fired: true`. Proposer continues with Sonnet output. |

**Principle:** the router is best-effort. Its job is to save quota when it can; PEL must keep working even if the router itself misbehaves. All failure modes degrade gracefully to a known-working baseline.

## 8. Testing

`tests/router-simulation.sh` — hermetic, follows the Phase 4 `tests/classifier-simulation.sh` pattern:

- PATH-injected `claude` stub returns canned routing JSON
- 5 primary scenarios:
  1. NORMAL pick (template-tier small file)
  2. COMPLEX pick (code-tier any size)
  3. `--complexity` user override (skip Haiku, emit canonical JSON with override flag set)
  4. `--no-adaptive` bypass (router not invoked at all; PEL_NO_ADAPTIVE=1 env var honored)
  5. Router-failure fallback (Haiku call fails → safe-side COMPLEX default with WARN; PEL doesn't die)

Plus an addition to existing `tests/pr-emitter-simulation.sh`: existing 10 scenarios should continue to pass with the router enabled (proves we didn't break the SC-3 hermetic gate).

## 9. Open / deferred

| Item | Status |
|------|--------|
| Haiku-tier proposer (SIMPLE → Haiku) | Deferred — Q4 chose 2-tier; revisit if telemetry shows lots of "wasted Sonnet on tiny tweaks" |
| Per-tier fallback chain (Opus→Sonnet→Haiku) | Deferred — Q6 chose flat sonnet fallback; revisit if Sonnet itself overloads in practice |
| Sticky session toggle (`/adaptive on`-style) | Deferred — Q3 chose default-on; sticky toggle is YAGNI for PEL since each invocation is independent |
| `--model <name>` override flag | Deferred — Q8 chose only `--complexity`; raw `--model` adds confusion (which level overrides which?) |
| Meta-router that learns from telemetry | Future — needs ≥100 telemetry records before any analysis is meaningful |
| Hook-based interception (Claude Code session-level) | Out of scope — PEL is a separate runtime; the `/adaptive` skill already handles Claude Code session-level routing |
| **Wire `thinking_budget` end-to-end** (I-1 from 2026-04-21 code review) | Deferred — router emits `thinking_budget: "harder"` in COMPLEX branch but no proposer consumes it; SC-2's implicit "Opus + thinking budget" is currently "Opus only." Either wire `--thinking-budget harder` into the proposer's `claude -p` invocation OR inject "Think harder before responding" into the prompt. Low-urgency because COMPLEX=Opus alone still produces the expected quality-over-cost tradeoff. |
| **Detect `fallback_fired` from proposer stderr** (I-2 from 2026-04-21 code review) | Deferred — telemetry hardcodes `fallback_fired: false`. SC-5 ("`--fallback-model sonnet` fires; verified via telemetry") is only verifiable by manually grepping the proposer's stderr for a known Claude CLI fallback signal. Proper fix: capture proposer stderr, detect the fallback marker, export `FALLBACK_FIRED` env var, read in Section K. |
| **Integration test proving router fires in production flow** (I-3 from 2026-04-21 code review) | Deferred — existing `tests/pr-emitter-simulation.sh` 10/10 passed despite a critical env-var wiring bug (C-1) because no scenario asserts the router actually ran. Add at least one scenario that injects a router stub returning `{complexity: "NORMAL"}` and asserts stderr contains `INFO: router picked complexity=NORMAL model=sonnet`. |
| **Rename Section C.5 → Section D.0** (M-1 from 2026-04-21 code review) | Nit — the name "C.5" ran BEFORE C in the first pass (bug fixed), and now runs AFTER C. Name is correct as-is but the "C.5" label invites re-confusion if someone swaps sections again. Optional rename to disambiguate. |

## 10. Success criteria

This work is done when:

1. `co-evolve-bouncer.sh --lab pel-proposer --target <template>` automatically picks Sonnet for small template mutations (verified via telemetry record showing `model_chosen: "sonnet"`)
2. `co-evolve-bouncer.sh --lab pel-proposer --target <code>` automatically picks Opus for code-tier mutations (verified via telemetry record showing `model_chosen: "opus"`)
3. `--no-adaptive` flag exits the router cleanly; PEL behaves as pre-router code (verified via telemetry record absence + same Opus model used)
4. `--complexity COMPLEX` flag forces Opus regardless of router opinion (verified via telemetry `user_override: "COMPLEX"`)
5. When Opus is overloaded, `--fallback-model sonnet` fires; PEL continues to PR emission (verified via telemetry `fallback_fired: true`)
6. `tests/router-simulation.sh` returns "5/5 scenarios passed"
7. Existing `tests/pr-emitter-simulation.sh` returns "10/10 scenarios passed" (no regression)
8. Cost on a sample 3-PR dogfood cycle drops from ~Opus×3 to a mix (expected ~Sonnet×2 + Opus×1 for template+policy+code), measurable as fewer Opus tokens via Anthropic console

---

*Spec authored 2026-04-21 via brainstorming dialogue. Decisions traceable to Q1–Q8 in session transcript. Ready for implementation plan via `superpowers:writing-plans`.*
