# Phase 8: Evals Absorbed - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning
**Mode:** Auto-generated (autonomous, infrastructure phase — asset elevation)

<domain>
## Phase Boundary

Make evals cross-runner by elevating portable assets from `runners/codex-ps/evals/` (and `schemas/`) to the repo top level, while leaving the runner-specific PS harness under `runners/codex-ps/`. After this phase, any runner (including the newly-parity'd Bash runner from Phase 7) can consume the cases, fixtures, schema, and verification plan.

</domain>

<decisions>
## Implementation Decisions

### Asset Routing
- **Portable → top level:**
  - `runners/codex-ps/evals/cases/` → `evals/cases/` (with `defaults.yaml`)
  - `runners/codex-ps/evals/fixtures/` → `evals/fixtures/`
  - `runners/codex-ps/evals/VERIFICATION-PLAN.md` → `evals/VERIFICATION-PLAN.md`
  - `runners/codex-ps/schemas/review-verdict.json` → `schemas/review-verdict.json`
- **Stays under runners/codex-ps/ (PS-specific harness):**
  - `run-evals.ps1`, `score-run.ps1`, `compare-reports.ps1`
  - `evals/lib/`, `evals/tests/` (PS test infrastructure)
  - All other `evals/*.md` support files (BASELINE-SUMMARY, NEXT, PLAN, ROLL-UP-TO-MAIN, SEEDED-REGRESSION-REPORT, VARIANCE-REPORT, report-template, UPSTREAM-MESSAGE)

### Copy vs Move
- **Copy** portable assets to top level, **keep** the source under `runners/codex-ps/` untouched. Rationale: `runners/codex-ps/` is the verbatim reference impl (CXPS-01, CXPS-02) — byte-level diff with the original must remain clean.
- This means the two locations will diverge only if the top-level `evals/` is edited in future work. For now they're byte-identical.

### Structure of Top-Level evals/
```
evals/
├── cases/
│   ├── defaults.yaml
│   └── *.yaml (9 cases)
├── fixtures/
│   ├── mock-report.md
│   ├── mock-scores.json
│   └── ... (remaining portable fixtures)
└── VERIFICATION-PLAN.md
schemas/
└── review-verdict.json
```

### Documentation
- Add top-level `evals/README.md` explaining:
  - What's here (cases, fixtures, verification plan, schema) + what's elsewhere (PS harness at `runners/codex-ps/`)
  - How to run evals today (only PS harness; Bash port deferred)
  - The `pwsh` dependency — optional, only needed to run evals
- Update root `README.md` if it references evals (probably doesn't — evals are new to this repo).

### pwsh Dependency
- PS harness requires PowerShell (`pwsh` on Linux/Mac or `powershell.exe` on Windows) — document as optional
- The Bash runner itself (dev-review.sh, agent-bouncer.sh) does NOT depend on pwsh
- Document in `evals/README.md`: "Running the eval harness currently requires PowerShell. A Bash port of the harness is deferred to post-milestone work."

### Claude's Discretion
- Whether to include `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` at top-level (leaning no — it's historical context, not a portable artifact)
- Whether top-level `evals/` README should include running instructions for the PS harness or link to `runners/codex-ps/evals/`

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `runners/codex-ps/evals/` already exists from Phase 5 (verbatim copy)
- `runners/codex-ps/evals/cases/*.yaml` — 9 case YAMLs + `defaults.yaml`
- `runners/codex-ps/evals/fixtures/` — scorer unit fixtures (mock-report.md, mock-scores.json, plus the tmp/ and reports/ dirs already .gitignored)
- `runners/codex-ps/evals/VERIFICATION-PLAN.md` — the five-tier verification strategy document
- `runners/codex-ps/schemas/review-verdict.json` — JSON schema for verdict parsing

### Established Patterns
- Phase 5 established the "copy verbatim, preserve upstream byte-identity" discipline — this phase is the second "asset movement" phase
- `evals/fixtures/tmp/` and `evals/reports/` are already gitignored under `runners/codex-ps/` — extend same pattern to top-level if needed

### Integration Points
- Top-level `evals/` will be consumed by:
  - PS harness (already works via `runners/codex-ps/evals/*.ps1` — they read paths relative to runners/codex-ps/evals/)
  - Future Bash eval harness (deferred)
  - Eval scorers that read `schemas/review-verdict.json` (the newly-elevated one)

</code_context>

<specifics>
## Specific Ideas

**Byte-level diff on copies:** Every file copied to top-level should `diff -q` match its source under `runners/codex-ps/`. This proves the elevation was lossless.

**CXPS-02 discipline preserved:** Phase 8 does NOT modify any file under `runners/codex-ps/` — all changes are at top-level. Git status should show 0 modifications under `runners/codex-ps/`.

**pwsh optional:** Add clear note in top-level README + evals/README that pwsh is only required for running the eval harness, not for using the bouncer/dev-review runners.

</specifics>

<deferred>
## Deferred Ideas

- Bash port of PS eval harness — ~2 days, deferred post-milestone (would satisfy "no pwsh dependency to run evals")
- Cross-runner eval report format — deferred to Phase 8.1 (post-this-phase) or future work
- Automated eval runs in CI — deferred; manual invocation is sufficient for now

</deferred>
