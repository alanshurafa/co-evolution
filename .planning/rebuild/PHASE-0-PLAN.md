# Rebuild Phase 0 — execution plan

- **Derived from:** `C:\Users\alan\Project\Admin\docs\rebuild-proposals\co-evolution.md` (proposal v1.1, 2026-07-17) — the AUTHORITY doc. This plan operationalizes §6 Phase 0; consult §3.2(2), §3.3, §8, and Appendix A only as cited below.
- **Branch:** `rebuild/phase-0`, worktree `C:\Users\alan\Project\co-evolution\.claude\worktrees\rebuild-phase-0`. Never work on master. Never touch the main checkout's uncommitted state (that is gated Appendix A material).
- **Orchestrator:** fresh Opus session. Workers: Sonnet default, Haiku for mechanical sweeps, Opus for the vertical-slice design WPs (WP-04/05/06). Trivial single-file WPs done directly.
- **Phase goal:** prove the rebuild's riskiest assumptions cheaply (vertical slice), preserve the measurement corpus, extract the contract kit, and produce a grounded Phase 1 plan. The TypeScript decision is GATED on WP-05 — if the process-tree kill contract cannot be demonstrated, stop and report rather than proceeding to Phase 1.

## Decisions adopted as defaults (do not re-litigate; log overrides in TRACKER)

Per proposal §8, adopted as working defaults with Alan able to override at any gate:

| # | Decision | Default adopted |
|---|---|---|
| 1 | Naming / repo strategy | Tool `co-evolve`, spec "Bounce Protocol", npm scope `@alanshurafa`; in-place `packages/` migration on this branch (no fresh repo before parity) |
| 2 | Protocol scope | Markers + loop + termination = the protocol; `review-verdict.json` a separate versioned contract; `arbitrate` role retired (recorded in spec changelog) |
| 3 | Single-model mode | Phase 4 roadmap item; PR #30 closes in the (gated) housekeeping session, not here |
| 4 | GSD integration | Documented CLI consumer only |
| 5 | Housekeeping | Entirely gated — nothing in this plan deletes, closes, or edits anything in the main checkout or on GitHub |

## Hard gates (write ONE batched request in TRACKER when hit; keep working elsewhere)

- **G1 Housekeeping (Appendix A):** all destructive/prototype-repo actions — branch/worktree deletion, PR closures, the `dev-review.sh:482` patch, tag/doc corrections. Not part of Phase 0's WPs.
- **G2 Publishing:** any public artifact (npm, registry, marketplace, spec site). Far outside Phase 0.
- **G3 Metered spend:** any paid direct-API call. Subscription-CLI smoke calls at Haiku-class scale (WP-04/06, a handful of tiny prompts) are pre-authorized; anything larger goes in a gate request.

## Work packages

### WP-01 — Decision record and scaffold commit
Write `.planning/rebuild/DECISIONS.md` recording the five defaults above verbatim with their proposal-§8 rationale, plus the G1–G3 gate list. Ensure `.planning/rebuild/` is committed on this branch.
**Done-check:** file committed; TRACKER updated with any deviations. *(direct, no agent)*

### WP-02 — Corpus preservation (non-destructive copy-out)
Copy from the MAIN checkout (`C:\Users\alan\Project\co-evolution\runs\` — 302 run dirs, ~57MB — and `C:\Users\alan\Project\co-evolution\evals\reports\`, including `bounce-calibration-2026-07-06.md`) to `C:\Users\alan\Project\Admin\archives\co-evolution-corpus-20260717\`. Copy only — the sources are gitignored, exist on one disk, and are Phase 1's calibration inputs (AUTHORITY §6 Phase 0, Appendix A item 1). Write a manifest: per-top-level-dir file counts + total bytes + SHA-256 of the manifest body.
**Done-check:** `robocopy`/`cp -r` exit clean; source vs destination file count and byte totals match; manifest committed to `.planning/rebuild/corpus-manifest.md` (manifest only — never the corpus itself).
**Verify:** independent recount by the orchestrator (not the copying agent). *(Sonnet)*

### WP-03 — packages/engine scaffold
Create `packages/engine/`: `package.json` (name `@alanshurafa/co-evolve`, `private: true` for now, `engines.node >=20`, type module), `tsconfig.json` (strict), vitest, one placeholder unit test, npm-workspaces root `package.json` at repo root. Constraint: MUST NOT disturb `mcp/` (its CI job runs `cd mcp && npm ci && npm test` standalone — root workspaces must exclude or not break it; verify by running the mcp test suite once after scaffolding).
**Done-check:** `npm test` green inside `packages/engine` on Windows; `cd mcp && npm ci && npm test` still green.
*(Sonnet)*

### WP-04 — Vertical slice A: one real adapter call
Minimal `claude` CLI adapter in `packages/engine/src/adapters/`: arg-array spawn (never shell-string), RNPT-06 env strip (the six vars — AUTHORITY §3.5 / lib/co-evolution.sh:460–467 on master), read-phase tool restriction, `--output-format text`, deadline-wrapped, typed result `{kind: artifact|empty|fatal}`. Smoke: one real call, model `claude-haiku-4-5-20251001`, trivial prompt, subscription auth (CLI must be logged in as ithelast@hotmail.com).
**Done-check:** vitest integration test (tagged `smoke`, skippable in CI) returns `artifact` with non-empty text on this Windows machine; unit tests cover env-strip list and PRTP-03 (no schema flag ever passed).
*(Opus)*

### WP-05 — Vertical slice B: process-tree kill contract (THE LANGUAGE GATE)
Test: engine spawns a child that spawns a grandchild (e.g. node → node → node sleep); deadline fires; assert BOTH descendants are gone (poll by PID with a grace window). Implement the Windows strategy (`taskkill /PID <pid> /T /F` or a vetted tree-kill approach — decide in-WP, record rationale in TRACKER) and the POSIX strategy (detached process group, negative-PID signal). AUTHORITY §3.2(2).
**Done-check:** test green locally on Windows; test is OS-conditional so WP-08's CI can prove ubuntu/macos. If Windows cannot pass after two distinct strategies → `blocked(stuck)` and STOP: this gates the whole language decision.
*(Opus)*

### WP-06 — Vertical slice C: bounce-state serializer against the real scorer
Internal-model → `bounce-state/1.0` serializer. Input: one archived run from WP-02 whose `state.json` carries `"schema": "bounce-state/1.0"` (192/202 runs predate it — scan with jq; the 2026-07-06 report's contract-path runs qualify). Re-serialize through the TS model into a scratch copy of that run dir, then run master's `evals/score-bounce.sh` against it.
**Done-check:** scorer consumes the TS-emitted `state.json` via the state path (not the artifact-parsing fallback — confirm by the scorer's own mode output), scores computed, schema field validates. Evidence: command + trimmed scorer output in TRACKER.
*(Opus)*

### WP-07 — Contract kit extraction
Create `packages/engine/contracts/` with a `MANIFEST.md` (source path → dest path → SHA-256): templates (canonical `agent-bouncer/templates/bounce-protocol.md` + role templates, `templates/co-evolve/*`, `skills/dev-review/templates/*` executor/verifier prompts), `skills/dev-review/schemas/review-verdict.json`, `evals/RUNNER-CONTRACT.md` + `evals/BOUNCE-RUNNER-CONTRACT.md` (verbatim, marked upstream-locked), `evals/bounce-thresholds.yaml` (marked NON-GATING baseline), fixtures: `evals/cases/*.yaml`, the 4 bounce-run fixtures, and the 10 golden scorer fixtures COPIED out of `runners/codex-ps/evals/tests/fixtures/` (that tree is read-only — copying respects that; never edit it. AUTHORITY §3.3). Add a drift test asserting kit copies still hash-match their master sources.
**Done-check:** manifest complete; drift test green; `git status` in the read-only tree shows zero changes.
*(Sonnet)*

### WP-08 — CI for the engine package
New job in `.github/workflows/ci.yml` (or a new workflow file): 3-OS matrix running `packages/engine` unit tests + WP-05's kill test. Do not modify the existing `test`/`mcp` jobs. Push branch; CI run is an EXTERNAL WAIT — mark `pending-observation(until: run completes)` and continue; never poll in-loop.
**Done-check:** all three OS legs green on the pushed branch, including the kill test on ubuntu/macos/windows. This completes WP-05's 3-OS proof.
*(Sonnet; observation by orchestrator)*

### WP-09 — Spec v0.2 (protocol ambiguities resolved on paper)
Author `packages/engine/contracts/BOUNCE-PROTOCOL-v0.2-draft.md` from the root spec, applying AUTHORITY §3.3's fixes: single expiry rule (pass-budget; delete the phantom per-marker-age rule), conformance clause softened to match reality (runners signal violations; MUST-reject deferred to v1.0 with an implementation), verdict schema declared a separate downstream contract (Decision 2), role taxonomy table (composer/reviewer ± light, chain critique/defend/tighten, executor, verifier; `arbitrate` retired with rationale), reference-implementation pointer updated, changelog vs v0.1. Do NOT touch the root `BOUNCE-PROTOCOL.md` (that edit ships via G1/Phase C merge decisions).
**Done-check:** draft committed; a checklist in the doc maps each §3.3 fix to its section; adversarial-review pass by a second agent (document-review persona) with findings filed or dismissed in TRACKER.
*(Opus author, Sonnet reviewer)*

### WP-10 — Phase 0 gate review and Phase 1 plan
Verify every WP's done-check evidence is in TRACKER. Write `PHASE-1-PLAN.md` (same directory, same structure as this file) grounded in slice results: adapter architecture from WP-04, kill strategy from WP-05, serializer shape from WP-06, re-forecast session estimates (AUTHORITY §6 Phase 1 scope: engine primitives, both adapters, contract-test harness from recorded transcripts + fault injection, CLI verbs, corpus classification + labeling + threshold recalibration, bounce-scorer verification wiring). End with a STOP B report to Alan: slice verdict (language gate PASS/FAIL), what Phase 1 will cost, the G1 housekeeping request restated.
**Done-check:** PHASE-1-PLAN.md committed; TRACKER shows Phase 0 done with evidence links; STOP B report delivered.
*(Opus / orchestrator)*

## Dependencies

WP-01 → none. WP-02 → none (parallel with WP-01). WP-03 → WP-01. WP-04, WP-05 → WP-03 (parallel with each other). WP-06 → WP-02 + WP-03. WP-07 → WP-01 (parallel with 04–06). WP-08 → WP-03 + WP-05. WP-09 → WP-01 (parallel; needs no code). WP-10 → all.

Suggested waves: **Wave 1:** WP-01, WP-02. **Wave 2:** WP-03, WP-07, WP-09. **Wave 3:** WP-04, WP-05, WP-06. **Wave 4:** WP-08, then WP-10.

## Standing constraints

- Main checkout (`C:\Users\alan\Project\co-evolution` proper) is READ-ONLY for this plan except the two explicitly-read sources in WP-02/06/07 (reads and copy-outs only). Its dirty working tree is G1 material.
- `runners/codex-ps/**` is read-only: copy out, never modify.
- No paid metered-API calls (G3). CLI smoke calls: Haiku-class, minimal prompts only.
- Never run `co-evolve-bouncer.sh`/`dev-review.sh` with real models from this plan (cost + no need); hermetic invocations of `score-bounce.sh` on local artifacts are fine.
- Commits: imperative, <72 chars, why-not-what, after every verified WP.
- Review pass after each code wave: `/code-review` on the wave's diff; findings become fix-WPs.
