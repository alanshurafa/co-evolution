---
phase: 05-codex-ps-preservation
plan: 01
subsystem: runners
tags: [preservation, audit-trail, codex-ps, reference-impl, unification-absorb]
requires:
  - phase: 04-docs-and-routing
    provides: discoverability for cross-AI runtime surfaces (satisfies predecessor constraint)
provides:
  - verbatim copy of codex-co-evolution reference runtime at runners/codex-ps/
  - immutable UPSTREAM-MESSAGE.md parity contract for phases 6-8
  - REFERENCE-STATUS.md read-only declaration for downstream phases
  - permission for archival of the private codex-co-evolution/ workspace
affects: [.gitignore, runners/]
tech-stack:
  added: []
  patterns: [verbatim subtree preservation as audit trail, runtime-artifact exclusion via .gitignore, read-only declaration as single dedicated file (preserves byte-level verbatim guarantee of upstream content)]
key-files:
  created:
    - runners/codex-ps/ (111 files, 12512 lines, 748K on disk)
    - runners/codex-ps/REFERENCE-STATUS.md
  modified:
    - .gitignore (pinned runners/codex-ps/ runtime-artifact exclusions)
key-decisions:
  - "Verbatim file copy rather than subtree merge (codex-co-evolution had zero commits, so no history to preserve)."
  - "Put the read-only declaration in its own REFERENCE-STATUS.md file rather than injecting it into the upstream README.md — preserves byte-level verbatim guarantee for CXPS-01."
  - "Exclude only runtime artifact directories (.co-evolution/, .git/, .playwright-mcp/, evals/fixtures/tmp/, evals/reports/); keep everything else including evals/fixtures/ (committed mock fixtures) and the upstream .gitignore."
  - "Restore empty .claude/ dir after copy to maintain byte-level diff -qr cleanliness against source; .gitignore already excludes it from git tracking."
  - "rsync unavailable in MINGW64 Git Bash environment — used cp -R + explicit prune, documented in the plan as the fallback."
patterns-established:
  - "When absorbing a zero-commit source tree, prefer verbatim file copy + separate read-only banner over subtree merge."
  - "Runtime-artifact exclusion belongs in both the local upstream .gitignore (already present) AND the repo root .gitignore (new pin) so both branches of future history stay clean."
  - "Single dedicated REFERENCE-STATUS.md file is the read-only policy surface; never inject policy into verbatim-preserved upstream files."
requirements-completed: [CXPS-01, CXPS-02]
duration: ~15min
completed: 2026-04-17
---

# Phase 5: Codex PS Preservation Summary

**Verbatim mirror of the private codex-co-evolution reference runtime at runners/codex-ps/, declared read-only as the stable parity contract for phases 6-8**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-17 (this execution pass)
- **Completed:** 2026-04-17
- **Tasks:** 2
- **Commits:** 2 (feat + docs)
- **Files added:** 112 (111 from upstream verbatim + 1 new REFERENCE-STATUS.md)
- **Files modified:** 1 (.gitignore)
- **Lines added:** ~12,517 (12,433 upstream + 84 REFERENCE-STATUS.md)

## Accomplishments

- Landed the full `codex-co-evolution/` source tree inside the public repo as `runners/codex-ps/`, byte-identical to the source for every file (verified via `diff -qr` across the entire subtree).
- Excluded only runtime artifacts — `.co-evolution/`, `.git/`, `.playwright-mcp/`, `evals/fixtures/tmp/`, `evals/reports/` — and preserved the committed `evals/fixtures/` mock data plus the upstream `.gitignore`.
- Pinned the three runtime-artifact paths in the repo root `.gitignore` so any future accidental commit of generated content inside `runners/codex-ps/` is blocked at the git layer.
- Added `runners/codex-ps/REFERENCE-STATUS.md` (84 lines) declaring the directory read-only, naming phases 6-8 as the downstream consumers, and pointing at `evals/UPSTREAM-MESSAGE.md` as the authoritative MUST/SHOULD/parity contract.
- Preserved the original upstream `README.md` byte-identical — the read-only policy is in a separate file rather than injected into upstream content, so CXPS-01's verbatim guarantee remains intact.

## Task Commits

- `438e435` — `feat(05): land codex-co-evolution verbatim as runners/codex-ps/` — Task 1 (111 files added, .gitignore updated)
- `ccc3418` — `docs(05): declare runners/codex-ps/ read-only reference` — Task 2 (REFERENCE-STATUS.md)

Both commits pushed to `origin/feat/unification-absorb`.

## Files Created/Modified

- `runners/codex-ps/` (new directory, 111 files) — verbatim upstream tree containing README.md, docs/ (architecture.md, thread-handoff.md), evals/ (cases/, fixtures/, lib/, tests/, harness + plan docs), schemas/review-verdict.json, scripts/run-co-evolution.ps1, templates/ (5 prompt-codex .md files), .gitignore (upstream).
- `runners/codex-ps/REFERENCE-STATUS.md` (net-new, 84 lines) — read-only declaration, parity contract pointer, policy rules for phases 6-9, archival note.
- `.gitignore` (root, modified) — added 3 pins under a new "Codex PS reference runner runtime artifacts" comment block, placed immediately after the existing `runs/` entry.

## Decisions Made

- **Verbatim file copy, not subtree merge.** `codex-co-evolution/` had zero commits, so there was no history to preserve via subtree merge. A pure file copy is simpler and fully sufficient.
- **REFERENCE-STATUS.md as a dedicated file, not injected into README.md.** Injecting read-only policy into the upstream README would have broken the byte-level verbatim guarantee that justifies keeping `runners/codex-ps/` separate in the first place. A one-file dedicated banner is the cleaner pattern.
- **Runtime-artifact exclusions pinned at both layers.** The upstream `.gitignore` already excluded `.co-evolution/` inside that subtree; I ALSO added the pins to the repo root `.gitignore` so future phases (which may operate outside this subtree context) still get the protection.
- **Empty .claude/ preserved.** The upstream tree contained an empty `.claude/` directory. Restoring it after the prune keeps the `diff -qr` verification pristine. The repo root `.gitignore` ignores `.claude/` globally, so git won't track it either way.

## Deviations from Plan

- **[Rule 3 — Blocking] rsync unavailable, used cp -R fallback.** The plan's preferred command was `rsync -av --exclude='...' ...`, but `rsync` is not installed in this MINGW64 Git Bash environment. The plan explicitly documented this fallback pattern (`cp -R <src>/. <dst>/ && rm -rf <excluded-paths>`), which I used instead. Byte-level `diff -qr` verification confirms this achieved the same result as rsync would have — no files transformed during the copy.
- **Minor: empty `.claude/` dir handling.** First prune pass deleted `.claude/` (not named in plan excludes but also not named in includes). I restored it after noticing so the source and destination are byte-identical at the directory level. Not a plan deviation in content, just a step the plan didn't spell out for an inherited empty directory. Tracked as a note rather than a Rule N fix.

## Issues Encountered

- Git emitted `warning: in the working copy of '<file>', LF will be replaced by CRLF the next time Git touches it` on most `.md`, `.ps1`, `.json`, and `.yaml` files during `git add`. This is standard Windows `core.autocrlf` behavior — it affects how the file is stored in the git object database, not the on-disk content. The byte-level `diff -qr` (which ran against the working-tree files before `git add`) confirmed verbatim identity, so the plan's CXPS-01 guarantee holds at the filesystem layer. If phases 6-9 ever need to diff the upstream workspace against this subtree on another platform, `core.autocrlf` may need to be normalized on checkout — worth noting but not blocking.
- No other issues.

## User Setup Required

None.

## Next Phase Readiness

- **Phase 6 (Protocol Parity) is unblocked.** The parity contract at `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` is now present and immutable. Phase 6 implements MUST-items 3-6 against this reference.
- **Phase 7 (Runner Parity) is unblocked.** `runners/codex-ps/scripts/run-co-evolution.ps1` is the reference implementation to diff the Bash runner against for the 5 missing features.
- **Phase 8 (Evals Absorbed) is unblocked.** The portable eval assets under `runners/codex-ps/evals/` are ready to elevate to top-level (cases, fixtures, VERIFICATION-PLAN.md, schemas/review-verdict.json) while the PS-specific harness stays in place per EVAL-03.
- **Archival safe.** The original `C:/Users/alan/Project/codex-co-evolution/` workspace can now be archived without content loss — every source file has a verbatim copy in this subtree, confirmed by recursive byte-level diff.

## Self-Check: PASSED

Verified before writing this section:
- `runners/codex-ps/README.md` exists (FOUND)
- `runners/codex-ps/REFERENCE-STATUS.md` exists (FOUND)
- `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` exists (FOUND)
- `runners/codex-ps/scripts/run-co-evolution.ps1` exists (FOUND)
- `runners/codex-ps/templates/bounce-protocol.md` exists (FOUND)
- `runners/codex-ps/.gitignore` exists (FOUND)
- Commit `438e435` present in git log (FOUND)
- Commit `ccc3418` present in git log (FOUND)
- `diff -qr C:/Users/alan/Project/codex-co-evolution/ runners/codex-ps/ --exclude='.co-evolution' --exclude='.git' --exclude='.playwright-mcp' --exclude='tmp' --exclude='reports'` produces no output (verbatim guarantee CONFIRMED)

---
*Phase: 05-codex-ps-preservation*
*Completed: 2026-04-17*
