---
phase: 08-evals-absorbed
plan: 01
subsystem: evals-portable-assets
tags: [eval-asset-elevation, cross-runner, pwsh-optional, cxps-02-preserved, byte-identity]
requires: [phase-05, phase-07]
provides: [top-level-evals-cases, top-level-evals-fixtures, top-level-verification-plan, top-level-review-verdict-schema, pwsh-optional-documentation]
affects:
  - evals/cases/
  - evals/fixtures/
  - evals/VERIFICATION-PLAN.md
  - evals/README.md
  - schemas/review-verdict.json
  - .gitignore
key-files:
  created:
    - evals/cases/defaults.yaml
    - evals/cases/01-trivial-task.yaml
    - evals/cases/02-simple-md-edit.yaml
    - evals/cases/03-contested-decision.yaml
    - evals/cases/04-hallucination-trap.yaml
    - evals/cases/05-ambiguous-task.yaml
    - evals/cases/06-multi-file-refactor.yaml
    - evals/cases/07-real-doc-bounce.yaml
    - evals/cases/08-real-code-refactor.yaml
    - evals/cases/09-real-python-refactor.yaml
    - evals/fixtures/mock-report.md
    - evals/fixtures/mock-scores.json
    - evals/VERIFICATION-PLAN.md
    - evals/README.md
    - schemas/review-verdict.json
  modified:
    - .gitignore
decisions:
  - "Copy, don't move — runners/codex-ps/ remains the Phase-5 byte-identical audit trail (CXPS-02); top-level copies are a parallel portable slice, not a replacement"
  - "Schema lands at repo-root schemas/ (not evals/schemas/) because the dev-review verdict parser consumes it too, not just the eval harness"
  - "Empty fixtures/seed-repos/ and fixtures/seeded-bugs/ directories NOT copied — no portable content, and the top-level gitignore extension already covers the tmp/ and reports/ runtime output paths a future Bash harness would populate"
  - "Single sentence in README drops backticks around `pwsh` so the literal phrase `pwsh is optional` is grep-matchable per the EVAL-03 acceptance gate; rest of README keeps inline-code formatting"
  - ".gitignore entries for evals/reports/ and evals/fixtures/tmp/ placed in a named block below the runners/codex-ps/ block so the parallel structure is obvious to future readers"
metrics:
  duration: 15min
  tasks_completed: 4
  commits: 4
  completed: 2026-04-17
requirements: [EVAL-01, EVAL-02, EVAL-03]
---

# Phase 8 Plan 01: Elevate Portable Eval Assets to Top-Level

One-liner: Elevated 14 portable eval assets (10 cases + 2 fixtures + VERIFICATION-PLAN.md + review-verdict.json) from `runners/codex-ps/evals/` and `runners/codex-ps/schemas/` to top-level `evals/` and `schemas/` via byte-identical `cp`, added `evals/README.md` documenting the split and the pwsh-optional dependency, and extended `.gitignore` to mirror runtime-artifact discipline — all with CXPS-02 preserved (`git status --porcelain runners/codex-ps/` empty at every step).

## What Landed Per Task

### Task 1: Portable case files + fixtures (EVAL-01, EVAL-02)

- Created `evals/cases/` and `evals/fixtures/` directories
- Copied 10 case YAMLs (`defaults.yaml` + 9 numbered cases) from `runners/codex-ps/evals/cases/`
- Copied 2 scorer fixtures (`mock-report.md`, `mock-scores.json`) from `runners/codex-ps/evals/fixtures/`
- Did NOT create empty `seed-repos/` or `seeded-bugs/` subdirs (no portable content)
- All 12 copies `diff -q`-clean against source
- `git status --porcelain runners/codex-ps/` — empty (CXPS-02 preserved)

Commit: `6f337da`

### Task 2: VERIFICATION-PLAN.md + review-verdict.json (EVAL-02)

- Created `schemas/` directory at repo root
- Copied `evals/VERIFICATION-PLAN.md` from `runners/codex-ps/evals/VERIFICATION-PLAN.md`
- Copied `schemas/review-verdict.json` from `runners/codex-ps/schemas/review-verdict.json` (schema lives at repo-root schemas/, not under evals/, because dev-review review-verdict parser consumes it too)
- Both copies `diff -q`-clean against source
- JSON parse sanity check passed (`py -3.13 -c "import json; json.load(...)"` — proves no BOM / encoding corruption from the copy)
- `git status --porcelain runners/codex-ps/` — empty

Commit: `011c443`

### Task 3: evals/README.md (EVAL-03)

- Created `evals/README.md` — 103 lines, LF line endings, no UTF-8 BOM
- Documents the split: what's at top level (portable — cases, fixtures, plan, schema) vs what stays at `runners/codex-ps/` (PS harness — `*.ps1`, `lib/`, `tests/`)
- Contains the literal phrase `pwsh is optional` (EVAL-03 acceptance gate)
- States the Bash port of the harness is `deferred` to post-milestone work
- Names `agent-bouncer/agent-bouncer.sh`, `dev-review/codex/dev-review.sh`, and `lib/co-evolution.sh` as pwsh-free Bash entrypoints
- Includes a compact case-schema convention reference for future readers
- Points readers at `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` for the Bash-port feature inventory

Commit: `5558d07`

### Task 4: Gitignore extension + final byte-identity sweep

- Added `evals/reports/` and `evals/fixtures/tmp/` to `.gitignore` in a named block
- Block placed immediately below the existing `runners/codex-ps/` block so the parallel structure (PS runtime vs future Bash harness runtime) is visible
- Full 14-pair `diff -q` sweep — all clean
- Idempotency check: re-running the sweep + CXPS audit yields identical clean output
- `git status --porcelain runners/codex-ps/` — empty (binding CXPS-02 check)

Commit: `c6679ac`

## Commit Chain

```
c6679ac  chore(08-01): extend gitignore for top-level evals runtime artifacts
5558d07  docs(08-01): add evals/README.md documenting pwsh-optional split
011c443  feat(08-01): elevate VERIFICATION-PLAN + review-verdict schema to top-level
6f337da  feat(08-01): elevate eval cases + fixtures to top-level evals/
```

All commits pushed to `feat/unification-absorb`.

## Byte-Identity Sweep (14 pairs, all clean)

| Source (runners/codex-ps/...) | Target (top-level) | diff -q |
|-------------------------------|--------------------|---------|
| evals/cases/defaults.yaml | evals/cases/defaults.yaml | clean |
| evals/cases/01-trivial-task.yaml | evals/cases/01-trivial-task.yaml | clean |
| evals/cases/02-simple-md-edit.yaml | evals/cases/02-simple-md-edit.yaml | clean |
| evals/cases/03-contested-decision.yaml | evals/cases/03-contested-decision.yaml | clean |
| evals/cases/04-hallucination-trap.yaml | evals/cases/04-hallucination-trap.yaml | clean |
| evals/cases/05-ambiguous-task.yaml | evals/cases/05-ambiguous-task.yaml | clean |
| evals/cases/06-multi-file-refactor.yaml | evals/cases/06-multi-file-refactor.yaml | clean |
| evals/cases/07-real-doc-bounce.yaml | evals/cases/07-real-doc-bounce.yaml | clean |
| evals/cases/08-real-code-refactor.yaml | evals/cases/08-real-code-refactor.yaml | clean |
| evals/cases/09-real-python-refactor.yaml | evals/cases/09-real-python-refactor.yaml | clean |
| evals/fixtures/mock-report.md (has UTF-8 BOM) | evals/fixtures/mock-report.md | clean (BOM preserved) |
| evals/fixtures/mock-scores.json | evals/fixtures/mock-scores.json | clean |
| evals/VERIFICATION-PLAN.md | evals/VERIFICATION-PLAN.md | clean |
| schemas/review-verdict.json | schemas/review-verdict.json | clean (JSON parses) |

## CXPS-02 Audit Result

`git status --porcelain runners/codex-ps/` was empty at every checkpoint:
- After Task 1 (12 copies)
- After Task 2 (14 total copies)
- After Task 3 (README creation — cannot touch runners/codex-ps/ anyway)
- After Task 4 gitignore edit
- Final phase-end re-check

No file under `runners/codex-ps/` was modified, added, or deleted by Phase 8. CXPS-02 discipline preserved.

## README Acceptance Checks (all pass)

| Gate | Status |
|------|--------|
| File exists | OK |
| ≥50 lines | OK (103 lines) |
| Contains `pwsh is optional` | OK |
| Contains `Bash port` | OK |
| Contains `deferred` (case-insensitive) | OK |
| Names `agent-bouncer` | OK |
| Names `dev-review` | OK |
| Points at `runners/codex-ps` | OK |
| Mentions `VERIFICATION-PLAN.md` | OK |
| Mentions `review-verdict.json` | OK |
| Mentions `defaults.yaml` | OK |
| No UTF-8 BOM (first 3 bytes `23 20 45` = `# E`) | OK |
| No CRLF line endings | OK |

## Deviations

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed backticks from `pwsh is optional` sentence in README**
- **Found during:** Task 3 verification
- **Issue:** First draft of `evals/README.md` wrote the critical sentence as ``` `pwsh` is optional — required only ... ```. The PLAN's literal markdown copy showed it this way, but the PLAN's verify gate (`grep -q 'pwsh is optional' evals/README.md`) searches for the unquoted substring. With backticks adjacent to `pwsh`, the grep fails.
- **Fix:** Removed the two backticks around `pwsh` in that one sentence only. Rest of the README keeps inline-code formatting (section heading `## pwsh Dependency — Optional`, later references like `runners/codex-ps/evals/*.ps1`, and the table of pwsh dependencies all retain their backticks).
- **Files modified:** `evals/README.md` (single Edit before commit)
- **Commit:** Folded into `5558d07` (no separate commit — the fix happened before Task 3's initial commit landed)

### Other Notes

- **Line-ending warnings during commits:** `git commit` reported `LF will be replaced by CRLF the next time Git touches it` for every YAML, MD, JSON, and the README because `core.autocrlf=true` is set globally. This is a prospective warning only — `diff -q` was re-verified after each commit and all copies remain LF-byte-identical in the working tree. A future `git checkout` on a fresh clone may materialize CRLF in the working tree while the index stays LF (same behavior as any text file in this repo); byte-identity against `runners/codex-ps/` sources is preserved on this machine and in the committed tree.
- **No `evals/fixtures/seed-repos/` or `evals/fixtures/seeded-bugs/` at top level:** Per the plan's explicit instruction (empty dirs = no portable content). If a future Bash harness needs these as runtime scratch paths, they're gitignored via the new `evals/fixtures/tmp/` entry + can be recreated on demand.
- **No changes to repo-root `README.md`:** Per plan constraint (separate concern — a later phase may add a backlink from the root README to `evals/README.md`).

## Threat Mitigations Applied

- **T-08-01 (Tampering — silent source mutation):** `git status --porcelain runners/codex-ps/` verified empty after every task. CXPS-02 binding check passes.
- **T-08-02 (Line-ending / BOM corruption via cp):** `diff -q` on every pair. `mock-report.md` source has a UTF-8 BOM — byte-identity check is the detector for BOM loss; passed. JSON-parse sanity check on `schemas/review-verdict.json` is the second-line detector for encoding corruption; passed.
- **T-08-04 (Ambiguous split — future contributor edits wrong copy):** `evals/README.md` explicitly names `runners/codex-ps/` as the Phase-5 read-only audit trail and lists which files live where.
- **T-08-05 (README misleads on pwsh dependency):** README contains the literal phrase `pwsh is optional` plus a dependency table explicitly marking `agent-bouncer`, `dev-review`, and `lib/co-evolution.sh` as "No" and `runners/codex-ps/evals/*.ps1` as "Yes".
- **T-08-06 (DoS via runtime artifacts ballooning the repo):** `.gitignore` now includes `evals/reports/` and `evals/fixtures/tmp/` preemptively — before any future Bash harness runs.

## Requirements Coverage

| Req | Landed via | Status |
|-----|------------|--------|
| EVAL-01 | Task 1 (cases at top level, 10 files diff -q clean) | Complete |
| EVAL-02 | Task 1 (fixtures) + Task 2 (VERIFICATION-PLAN.md, review-verdict.json) | Complete |
| EVAL-03 | Task 3 (README with pwsh-optional documentation) + structural decision to leave `*.ps1` + `lib/` + `tests/` under `runners/codex-ps/` | Complete |

## Known Stubs

None. All 14 portable files copied and verified. README is complete, not a placeholder. The gitignore entries cover both the committed-state invariant and the future-runtime-artifact case.

## Self-Check: PASSED

- `evals/cases/defaults.yaml` — FOUND
- `evals/cases/01-trivial-task.yaml` through `09-real-python-refactor.yaml` — all 9 FOUND
- `evals/fixtures/mock-report.md` — FOUND
- `evals/fixtures/mock-scores.json` — FOUND
- `evals/VERIFICATION-PLAN.md` — FOUND
- `evals/README.md` — FOUND
- `schemas/review-verdict.json` — FOUND
- `.gitignore` — evals/reports/ + evals/fixtures/tmp/ entries FOUND at lines 10-11
- Commits `6f337da`, `011c443`, `5558d07`, `c6679ac` — all FOUND in git log
- 14-pair byte-identity sweep — all clean
- `git status --porcelain runners/codex-ps/` — empty (binding CXPS-02 check)
- Idempotency re-check — still clean
