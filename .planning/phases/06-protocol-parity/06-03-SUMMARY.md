---
phase: 06-protocol-parity
plan: 03
subsystem: bounce-protocol
tags: [templates, reconciliation, upstream-parity, cxps-02-exception]
requires: [phase-05]
provides: [reconciled-bounce-protocol]
affects: [runners/codex-ps/templates/bounce-protocol.md]
tech-stack:
  added: []
  patterns: [byte-identical-overwrite]
key-files:
  created: []
  modified:
    - path: runners/codex-ps/templates/bounce-protocol.md
      what: overwritten byte-identical with skills/dev-review/templates/bounce-protocol.md
decisions:
  - Single atomic `cp` chosen over Read+Write reconstruction — guarantees byte-identical reproduction including trailing newline conventions
  - Prior content recoverable via `git show 438e435:runners/codex-ps/templates/bounce-protocol.md` (no local backup needed)
  - REFERENCE-STATUS.md language untouched — the read-only declaration is compatible with a one-time correction that predates it
metrics:
  duration: 3min
  completed: 2026-04-17
requirements: [PRTP-05]
---

# Phase 6 Plan 3: Bounce Protocol Reconciliation Summary

One-liner: Overwrite `runners/codex-ps/templates/bounce-protocol.md` byte-identical with `skills/dev-review/templates/bounce-protocol.md` — recovers the SCOPE CONTROL section and the "complete document" clause that the codex-co-evolution copy was missing.

## Reconciliation Command

```bash
cp skills/dev-review/templates/bounce-protocol.md runners/codex-ps/templates/bounce-protocol.md
```

## Line Counts

- Pre-reconciliation: `runners/codex-ps/templates/bounce-protocol.md` was 42 lines
- Post-reconciliation: 51 lines (matches `skills/dev-review/templates/bounce-protocol.md`)
- Delta: +9 lines (the "complete document" clause + the entire SCOPE CONTROL section)

## CXPS-02 Discipline Check

```
$ git status --porcelain runners/codex-ps/
 M runners/codex-ps/templates/bounce-protocol.md
```

Exactly one file modified under `runners/codex-ps/` — execution rule 6 satisfied. This reconciliation is the one-and-only write into the read-only reference tree, explicitly authorized by:
- `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` item 3 ("The unified repo should keep the main repo's stronger version; codex-co-evolution's version has nothing new to contribute to this file.")
- `.planning/phases/06-protocol-parity/06-CONTEXT.md` Decisions → "Bounce Protocol Reconciliation" section

Ancillary confirmations:
- `skills/dev-review/templates/bounce-protocol.md` — unchanged (source-of-truth untouched)
- `runners/codex-ps/REFERENCE-STATUS.md` — unchanged (read-only declaration preserved)

## Task Breakdown

| Task | Outcome | Commit |
|------|---------|--------|
| 1. Byte-identical overwrite + CXPS-02 scope check | `diff -q` exits 0; both new clauses grep to 1; exactly 1 file modified under runners/codex-ps/ | `7b76b3a` |

## Deviations from Plan

None. Single-task plan executed exactly as written.

## Audit Trail

- Landing commit (Phase 5 verbatim): `438e435`
- Reconciliation commit (Phase 6): `7b76b3a`
- Recovery command if ever needed: `git show 438e435:runners/codex-ps/templates/bounce-protocol.md`

## Known Stubs

None.

## Self-Check: PASSED

- `runners/codex-ps/templates/bounce-protocol.md` exists — FOUND
- `skills/dev-review/templates/bounce-protocol.md` exists (unchanged) — FOUND
- Commit `7b76b3a` — FOUND
- `diff -q skills/... runners/...` exit 0 — OK
- Both clauses grep to 1 — OK
