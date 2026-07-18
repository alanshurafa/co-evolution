# Plan: Retire Fable as the codex-build default → Opus, with `best` alias + session opt-in

## Context

The `codex-build` preset (the "session plans + reviews, Codex executes detached"
model ladder) hardcodes **Fable** for its two Claude seats — composer (plan) and
verifier (review). Fable access was just lost, so the preset's default now points
at an unreachable model. The executor seat is Codex and is unaffected.

We want the preset to default to **Opus 4.8** via a future-proof `best`/`opus`
alias (so the next model bump is a one-line edit), keep the seats on a *strong*
model regardless of the driving session, and additionally **document** an opt-in
that lets the orchestrating session push its own model into the seats when it
wants them to follow the session (Option A + C from the design discussion).

This repo enforces code↔docs agreement via `tests/docs-sync-simulation.sh`, so the
runner default, the skill prose, and the drift-guard assertions must all move in
lockstep. The `fable` alias stays (back-compat; `evals/` and historical docs still
name `claude-fable-5` directly) — we are changing the *default*, not removing Fable.

**Before any implementation, this plan is co-evolved** (Claude composes, Codex
critiques with `[CONTESTED]`/`[CLARIFY]` markers) and the markers resolved.

---

## Phase 0 — Co-evolve this plan (FIRST, before code)

Harden this plan against Codex before touching code:

```bash
cp C:/Users/alan/.claude/plans/can-you-make-this-linked-walrus.md /tmp/codex-build-opus-plan.md
bash co-evolve-bouncer.sh --vanilla --bounce-only /tmp/codex-build-opus-plan.md
```

- Codex critiques with `[CONTESTED]` (disagreement + counter-argument) and
  `[CLARIFY]` (ambiguity + two interpretations) markers.
- Resolve EVERY marker before proceeding; apply the 2-pass expiry rule (any marker
  still open after 2 passes — decide here or ask Alan).
- Fold accepted critiques back into this plan, then proceed to Phase 1.

---

## Phase 1 — Runtime change: `dev-review/codex/dev-review.sh`

**1a. Add the alias** in `resolve_claude_model_alias()` (~line 134), keep `fable`:
```bash
resolve_claude_model_alias() {
  case "$1" in
    best|opus) echo "claude-opus-4-8" ;;
    fable)     echo "claude-fable-5" ;;   # retained for back-compat; Fable now unreachable
    *)         echo "$1" ;;
  esac
}
```

**1b. Repoint the preset default** in `apply_preset()` `codex-build` arm (~line 150),
keep fill-if-empty (`:=`) so env overrides still win:
```bash
codex-build)   # "build with codex": Opus plans/reviews, Codex executes.
  COMPOSER="opus"; EXECUTOR="codex"; VERIFIER_OVERRIDE="opus"
  VERIFY=true; BOUNCES=2; REVISE_LOOP_MAX=1
  : "${COMPOSER_MODEL:=best}";  : "${COMPOSER_EFFORT:=high}"
  : "${VERIFIER_MODEL:=best}";  : "${VERIFIER_EFFORT:=max}"
  : "${EXECUTOR_EFFORT:=xhigh}"
  ;;
```

**1c. Extend the cross-agent leak guard** so the new alias is recognized as
claude-kind and never leaks to the Codex seat. Two sites, identical edit:
- `apply_seat_env()` (~line 1382)
- `resolve_seat_model_string()` (~line 1416)

```bash
if [[ "$agent" == "codex" ]]; then
  case "$model" in
    fable|best|opus|claude-*) model=""; effort="" ;;   # add best|opus
  esac
else
  ...
fi
```
Without this, `--verifier codex` after `--preset codex-build` would export
`CODEX_MODEL=best` → live HTTP 400 "model not supported" (same class as the
v1.5 Phase 6 `fable` leak). This is the load-bearing correctness edit.

**1d. Help text / banner strings:**
- Line ~89 `--claude-model` help: note `best`/`opus` alias alongside `fable`.
- Line ~91 `--preset` description: "Fable plans (high) + Codex executes (xhigh) +
  Fable reviews (max)" → "Opus plans (high) + Codex executes (xhigh) + Opus
  reviews (max)".

---

## Phase 2 — Operational docs (kept in sync with the drift guard)

Replace the Fable→Opus *seat* descriptions in live/operational docs only:

- `skills/codex-build/SKILL.md` — header (~5), protocol prose (~19-20), auth-probe
  (~70, 72), Step-3 default (~187), **preset-expansion table (~192-193)** must read
  `composer = Opus (high)` … `verifier = Opus (max)` (asserted by docs-sync 99/103),
  troubleshooting (~326), Notes (~365-370). **Add the session opt-in** here:
  > To make the plan/review seats follow this session's model instead of the
  > `best` default, prepend `COMPOSER_MODEL=$SESSION_MODEL VERIFIER_MODEL=$SESSION_MODEL`
  > to the kick command. Only the Claude seats follow; Codex always executes.
- `skills/dev-review/SKILL.md` (~32) — "Fable plans at high … Fable" → "Opus …".
- `CLAUDE.md` (repo, ~67) — "session (typically Fable)" → "(typically Opus)".
- `dev-review/codex/instructions.md` (~21) — routing table "Fable plans/reviews"
  → "Opus plans/reviews".

**Explicitly NOT changed (historical records):** everything under `.planning/`
(v1.5-DESIGN.md, ROADMAP.md, token-evidence.md, VERIFY-*, milestones/),
`evals/RUNNER-CONTRACT.md` examples, `docs/superpowers/specs/`. These document what
was designed/built at the time. docs-sync asserts none of these, so leaving them is
safe and correct.

---

## Phase 3 — Update the drift-guard / preset assertions

These tests deliberately pin the old default and MUST move with the code:

- `tests/preset-expansion-simulation.sh`
  - ~246: composer argv assert `--model claude-fable-5` → `--model claude-opus-4-8`
    (the `best` alias resolves to opus-4-8 in argv).
  - ~425: leak-guard assert — extend so neither `-c model=best` nor
    `-c model=claude-opus-4-8` leaks into the codex verify argv (verifies 1c).
  - PASS-message strings (~254, ~438) reworded fable→opus for accuracy.
- `tests/docs-sync-simulation.sh`
  - ~73/77: runner asserts `COMPOSER_MODEL:=fable` / `VERIFIER_MODEL:=fable`
    → `:=best`.
  - ~99/103: skill asserts `composer = Fable (high)` / `verifier = Fable (max)`
    → `Opus`.
  - ~113: dev-review skill assert `Fable plans at high` → `Opus plans at high`.

Leave `tests/claude-model-override-simulation.sh` logic intact; confirm it still
passes (it exercises the alias resolver — the new `best` arm must not regress
existing `fable`/passthrough cases).

---

## Verification (end-to-end)

```bash
bash tests/preset-expansion-simulation.sh        # expect 8/8
bash tests/docs-sync-simulation.sh               # expect 17/17
bash tests/claude-model-override-simulation.sh   # expect 4/4
bash tests/run-all.sh                            # expect 25/25
```

Manual checks:
- `bash dev-review/codex/dev-review.sh --preset codex-build --help` shows Opus in
  the preset description and `best`/`opus` in the `--claude-model` note.
- Dry-confirm no leak: with `--preset codex-build --verifier codex`, the resolved
  codex verify argv carries **no** `model=best` / `model=claude-opus-4-8`
  (covered by the extended sim assertion at 1c/Phase 3).
- Confirm env override still wins: `COMPOSER_MODEL=claude-opus-4-8 ... --preset
  codex-build` resolves the composer seat to that explicit id (fill-if-empty).

## Critical files
- `dev-review/codex/dev-review.sh` (alias, preset, 2× leak guard, help)
- `skills/codex-build/SKILL.md`, `skills/dev-review/SKILL.md`, `CLAUDE.md`,
  `dev-review/codex/instructions.md`
- `tests/preset-expansion-simulation.sh`, `tests/docs-sync-simulation.sh`

## Out of scope / risks
- Not removing the `fable` alias or rewriting historical `.planning/` docs.
- "Current best" can't be auto-detected — the `best` alias is a manual one-line
  pin; next Opus = update `resolve_claude_model_alias` only.
- Session-follow is documentation + an env override, not runtime introspection
  (the runner can't see the orchestrating session's model).
- The pending Windows status-reader fix (uncommitted, separate change) is
  independent of this and not touched here.