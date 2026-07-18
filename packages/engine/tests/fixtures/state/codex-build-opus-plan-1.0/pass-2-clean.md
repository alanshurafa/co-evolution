# Plan: Retire Fable as the codex-build default → `best` alias, currently Opus

## Context

The `codex-build` preset hardcodes **Fable** for its two Claude seats: composer
(plan) and verifier (review). Fable access was lost, so the preset default now
points at an unreachable model. The executor seat is Codex and is unaffected.

Change the preset to default the Claude seats to a `best` alias that currently
resolves to `claude-opus-4-8`. Keep an `opus` alias for the current Opus line and
retain `fable` only for backward compatibility. This centralizes model bumps in
`resolve_claude_model_alias()` instead of scattering model IDs across the runner
and docs.

Also document an opt-in for making the Claude seats follow the orchestrating
session's model through explicit environment overrides. Only the Claude seats
follow that override; Codex always executes.

This repo enforces code↔docs agreement via `tests/docs-sync-simulation.sh`, so the
runner default, skill prose, and drift-guard assertions must move together.

---

## Phase 0 — Co-evolve this plan

Run the plan bounce before code changes:

```bash
cp C:/Users/alan/.claude/plans/can-you-make-this-linked-walrus.md /tmp/codex-build-opus-plan.md
bash co-evolve-bouncer.sh --vanilla --bounce-only /tmp/codex-build-opus-plan.md
```

Resolve every marker before proceeding to Phase 1.

---

## Phase 1 — Runtime change: `dev-review/codex/dev-review.sh`

**1a. Add aliases** in `resolve_claude_model_alias()` and keep `fable`:

```bash
resolve_claude_model_alias() {
  case "$1" in
    best)  echo "claude-opus-4-8" ;;
    opus)  echo "claude-opus-4-8" ;;
    fable) echo "claude-fable-5" ;;   # retained for back-compat; currently unreachable
    *)     echo "$1" ;;
  esac
}
```

Meaning:
- `best`: strongest supported Claude default for this preset.
- `opus`: current Opus-line model.
- `fable`: legacy alias only; do not use it as a default.

**1b. Repoint the preset default** in the `apply_preset()` `codex-build` arm.
Keep fill-if-empty (`:=`) so environment overrides still win:

```bash
codex-build)   # best Claude seats, Codex executes.
  COMPOSER="opus"; EXECUTOR="codex"; VERIFIER_OVERRIDE="opus"
  VERIFY=true; BOUNCES=2; REVISE_LOOP_MAX=1
  : "${COMPOSER_MODEL:=best}";  : "${COMPOSER_EFFORT:=high}"
  : "${VERIFIER_MODEL:=best}";  : "${VERIFIER_EFFORT:=max}"
  : "${EXECUTOR_EFFORT:=xhigh}"
  ;;
```

**1c. Harden the cross-agent leak guard** at both sites:
- `apply_seat_env()` (~line 1382)
- `resolve_seat_model_string()` (~line 1416)

For Codex seats, drop Claude aliases and Claude model IDs before building Codex
argv. Include `best|opus|fable|claude-*` in the drop list. If the existing code
already has a compact helper or allowlist pattern, prefer that over duplicating
case arms.

**1d. Update help text and banner strings:**
- `--claude-model` help: list `best`, `opus`, and legacy `fable`.
- `--preset codex-build` description: say `best (currently Opus)` for plan/review
  seats, not bare `Fable` or bare `Opus`.

---

## Phase 2 — Operational docs

Replace Fable seat descriptions in live operational docs only:

- `skills/codex-build/SKILL.md`
  - Header, protocol prose, auth-probe, Step-3 default, preset-expansion table,
    troubleshooting, and notes.
  - Preset table must say `composer = Opus (high)` and `verifier = Opus (max)`
    because docs-sync asserts those lines.
  - Add the session opt-in as a concrete environment override example:

```bash
COMPOSER_MODEL=claude-opus-4-8 VERIFIER_MODEL=claude-opus-4-8 \
  bash dev-review/codex/dev-review.sh --preset codex-build ...
```

- `skills/dev-review/SKILL.md`: update `Fable plans at high ... Fable` to Opus.
- `CLAUDE.md`: update `session (typically Fable)` to `session (typically Opus)`.
- `dev-review/codex/instructions.md`: update routing table `Fable plans/reviews`
  to Opus plans/reviews.

Do not update historical records under `.planning/`, `evals/RUNNER-CONTRACT.md`,
or `docs/superpowers/specs/`.

---

## Phase 3 — Update tests and drift guards

Update tests that pin the old default:

- `tests/preset-expansion-simulation.sh`
  - Composer argv assert: `--model claude-fable-5` → `--model claude-opus-4-8`.
  - Add explicit alias assertions:
    - `resolve_claude_model_alias best` → `claude-opus-4-8`
    - `resolve_claude_model_alias opus` → `claude-opus-4-8`
    - `resolve_claude_model_alias fable` → `claude-fable-5`
  - Extend leak-guard assertions so neither `model=best` nor
    `model=claude-opus-4-8` reaches a Codex verify argv.
  - Reword PASS messages from Fable to Opus.

- `tests/docs-sync-simulation.sh`
  - Runner assertions: `COMPOSER_MODEL:=fable` / `VERIFIER_MODEL:=fable` → `:=best`.
  - Skill assertions: `composer = Fable (high)` / `verifier = Fable (max)` →
    `Opus`.
  - Dev-review skill assertion: `Fable plans at high` → `Opus plans at high`.

Leave `tests/claude-model-override-simulation.sh` behavior intact; it verifies
model override propagation and help text, not alias resolution.

---

## Verification

Run:

```bash
bash tests/preset-expansion-simulation.sh
bash tests/docs-sync-simulation.sh
bash tests/claude-model-override-simulation.sh
bash tests/run-all.sh
```

Expected result: all suites green.

Manual checks:
- `bash dev-review/codex/dev-review.sh --preset codex-build --help` shows
  `best (currently Opus)` in the preset description and lists `best`/`opus` in the
  `--claude-model` note.
- With `--preset codex-build --verifier codex`, the Codex verify argv carries no
  Claude model setting.
- `COMPOSER_MODEL=claude-opus-4-8 ... --preset codex-build` still overrides the
  default composer model.

## Critical files

- `dev-review/codex/dev-review.sh`
- `skills/codex-build/SKILL.md`
- `skills/dev-review/SKILL.md`
- `CLAUDE.md`
- `dev-review/codex/instructions.md`
- `tests/preset-expansion-simulation.sh`
- `tests/docs-sync-simulation.sh`

## Out of scope / risks

- Do not remove the `fable` alias.
- Do not rewrite historical `.planning/` docs.
- `best` is a manual alias, not auto-detection.
- Session-follow is explicit env override, not runtime introspection.
- The pending Windows status-reader fix is independent and not touched here.

