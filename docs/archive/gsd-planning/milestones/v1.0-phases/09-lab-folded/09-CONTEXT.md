# Phase 9: Lab Folded - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning
**Mode:** Auto-generated (autonomous, infrastructure phase — minimal fold)

<domain>
## Phase Boundary

Final phase of the Unification Absorb milestone. Fold the small set of unique artifacts from `C:/Users/alan/Project/co-evolution-lab/` into the unified repo. Explicitly exclude Karpathy's `autoresearch` clone (unrelated ML training). Document what was folded, what was excluded, and why.

</domain>

<decisions>
## Implementation Decisions

### What Gets Folded (Portable, Useful)
- **`co-evolution-lab/mempalace.yaml`** → `integrations/mempalace.yaml` — 585-byte reference integration config (MempAlace is Alan's knowledge graph/memory tool; the YAML documents what a co-evolution integration with it looks like)

### What Gets Explicitly Excluded
- **`co-evolution-lab/auto-research/`** (Karpathy's clone, unmodified, zero of Alan's commits) — unrelated ML training domain. Decision documented in PROJECT.md Key Decisions table (already landed during milestone kickoff).
- **`co-evolution-lab/integrations/co-evolution/`** — contains PS integration scripts (`run-autoresearch.ps1`, `run-co-evolve.ps1`, `run-dev-review.ps1`, `sync-upstream.ps1`, plus schemas/templates/reports dirs). **Excluded rationale:** these are workspace-specific harness scripts tied to the lab's particular directory layout and cross-project paths. They reference autoresearch (which we're excluding) and duplicate harness logic that now lives in `runners/codex-ps/scripts/run-co-evolution.ps1`. Including them would add noise without clear value in the unified repo.
- **`co-evolution-lab/co-evolution/`** (untracked file snapshot of the public repo) — stale copy, not a git repo. Not folded; the canonical version is the current repo root.
- **`co-evolution-lab/archive/`** — historical snapshots (integration-lab-20260407, codex-co-evolution). Not folded; historical state is preserved in git history of the source repos.
- **`co-evolution-lab/auto-research-safe/`** — not investigated; presumed redundant with `auto-research/`. Not folded unless the planner discovers it's meaningfully different.

### Documentation
- Add `integrations/README.md` documenting:
  - What's here (`mempalace.yaml` as reference)
  - What was explicitly excluded from the lab absorb (autoresearch, lab-specific PS scripts)
  - Where the canonical PS harness lives (`runners/codex-ps/`)
- Update top-level `README.md` if needed (probably a one-liner pointing at `integrations/`)

### Claude's Discretion
- Whether to write a short exclusion-rationale note at the top of `integrations/README.md` or defer to PROJECT.md
- Whether to preserve any of the lab's PS scripts as illustrative examples (recommend: no)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `integrations/` directory does not yet exist in the unified repo — must be created
- `integrations/` in the lab is nearly-empty: just a `co-evolution/` subdir with PS scripts (which we're excluding)
- `mempalace.yaml` at the lab root is the only unique artifact

### Established Patterns
- Phase 8 just established the top-level `integrations/` adjacent pattern (`evals/`, `schemas/`, etc. at root)
- PROJECT.md already captured the "Karpathy autoresearch excluded" decision during milestone kickoff (2026-04-17)

### Integration Points
- `integrations/` at repo root for future integration configs
- `integrations/README.md` as the landing page

</code_context>

<specifics>
## Specific Ideas

**Minimum viable Phase 9:** one commit that creates `integrations/`, copies `mempalace.yaml`, and writes `integrations/README.md`. ~3-4 files touched total.

**Exclusion discipline:** Like CXPS-02 for Phase 5, be explicit about what was left behind. Future contributors should know what was intentionally NOT folded.

**After this phase:** the `co-evolution-lab/` directory at the workspace root can be archived/deleted — everything worth keeping is in the unified repo or was deliberately excluded.

</specifics>

<deferred>
## Deferred Ideas

- Porting any of the lab's PS integration scripts (`run-co-evolve.ps1`, `run-dev-review.ps1`, `sync-upstream.ps1`) — deferred; if useful, these can be cleaned up and added in a future phase
- Auto-research integration of any kind — deferred indefinitely (Karpathy domain)

</deferred>
