# Post-v1.2 Visibility Follow-Up Plan

**Created:** 2026-04-18
**Resume trigger:** After v1.2 Phases 5, 6, 7 complete (all three tier proposers shipped)
**Shipped alongside this file (2026-04-18):** GitHub topics set, CITATION.cff, llms.txt — see commits on master.

This captures visibility/distribution work deferred from the 2026-04-18 competitive analysis. The low-conflict items already shipped. The items below either touch GSD-managed files or are phase-sized engineering and should be picked up after the v1.2 tier proposers stabilize the runtime surface.

## Context for a fresh session

Read first:
- `~/.claude/projects/C--Users-alan-Project-co-evolution/memory/brainstorm_competitive_adoption.md` — full ranked adoption candidates and strategic picture (marker protocol as unprotected lead, distribution as biggest gap)
- `.planning/notes/pel-design-decisions.md` — what PEL is actually doing
- `.planning/notes/co-evolution-lab-concept.md` — origin of the split

Confirm state before picking up:
- v1.2 Phase 7 (code-tier proposer) is shipped and merged to master
- `lab/pel/` is functional
- Master has no uncommitted work

## Deferred items

### Item A (was #2): AGENTS.md rewrite as agent-facing protocol

**Problem:** Current `AGENTS.md` is GSD auto-generated (it transcludes `PROJECT.md` / `STACK.md` / `CONVENTIONS.md` via `<!-- GSD:*-start -->` markers). An agent visiting the repo reads GSD meta, not the bounce protocol. The emerging `agents.md` convention (Cursor, Aider, Cline, Jules) expects an agent-facing protocol spec at repo root.

**Target:** `AGENTS.md` becomes agent-facing: "This repo implements a bounce protocol. If you see `[CONTESTED]`, address it. If you see `[CLARIFY]`, answer it. Here are the role lenses and their responsibilities." Move the GSD meta to `.agents/gsd-context.md` (or keep in `AGENTS.md` but under a clearly-labeled `## Internal project context (GSD)` section after the protocol section).

**Conflict risk:** GSD auto-gen. Options:
- Opt out of `AGENTS.md` regeneration in `gsd-settings`
- Teach GSD to emit to `.agents/gsd-context.md` instead
- Preserve a non-GSD-managed section at the top of `AGENTS.md`, use GSD markers below

**Fold candidates:**
- v1.2 Phase 3 (`lab/` scaffold + README — conventions + promotion flow) is a plausible home, since "conventions" includes the agents.md convention
- Or: its own insert phase after v1.2 ships (7.5 or v1.3 Phase 1)

**Effort:** ~1–2 hours for the rewrite + GSD coordination.

### Item B (was #5): MCP server wrapper

**Problem:** co-evolution runs *inside* Claude Code via skill. External MCP clients (Claude Desktop, Cursor, Continue) can't reach it. Distribution is `git clone`-only — every competitor ships npm / pip / plugin marketplace.

**Target:** New `mcp/` directory with a thin Node MCP server exposing `co_evolve(document, agents)` as a callable tool. Wraps `agent-bouncer.sh`. Publish to the MCP registry. Ships as npm package.

**Design sketch:**
- Node MCP server using `@modelcontextprotocol/sdk`
- Single tool `co_evolve` with params: `document_path`, optional `roles`, `agents`, `max_passes`
- Shells to `agent-bouncer.sh`; streams stderr as MCP notifications; returns final doc path + bounce trail
- README explains install (`npm i -g <pkg>`) + Claude Desktop config snippet
- CI: smoke test that invokes the MCP server against a fixture doc

**Effort:** ~1–2 days real engineering. Phase-sized.

**Why after Phase 7:** MCP shim should wrap the stable bash runtime, not the lab/ PEL experiments. Once the code-tier proposer is in, runtime surface is stable enough to wrap without churn.

### Item C (was #4): Paper / arxiv anchor

**Problem:** No paper → no Semantic Scholar / Google Scholar / Perplexity / Claude-research-mode indexing. Without it, we're GitHub-only for agent discovery.

**Target:** 4–6 page technical report titled approximately *"Convergence-Guaranteed LLM Debate via Expiring In-Document Markers"*. Post to arxiv in cs.AI or cs.SE. Mint a Zenodo DOI via the CITATION.cff integration.

**Contents:**
1. Problem framing — multi-agent LLM debate, convergence as a correctness property
2. Bounce protocol formalization — marker semantics, staleness rule, role lens composition
3. Convergence argument — pass-by-pass: marker count strictly bounded, 2-pass auto-expiry forces resolution, max total passes = N (proof sketch)
4. Pilot data — 11 bounces → 8 bugs caught (re-verify before publishing); if v1.2 eval runs exist, include them
5. Comparison table — MAD / AutoGen / ChatEval / metaswarm / quorum-cli / co-evolution on: substrate, marker protocol, convergence guarantee, cross-model adversarial review, self-improvement
6. Limitations and future work — mutation surface, eval ceiling, PEL human-gate rationale

**Effort:** 3–5 days of writing.

**Why last:** benefits from v1.2 data (PEL eval results strengthen the evidence section). Also benefits from items A and B shipping — reviewers will look at the repo.

## Resumption prompt (paste into a fresh Claude session in `co-evolution-clean/` or equivalent worktree)

```
I'm resuming the post-v1.2 visibility work.

Read `.planning/notes/post-v12-visibility-plan.md` + the brainstorm memory at
`~/.claude/projects/C--Users-alan-Project-co-evolution/memory/brainstorm_competitive_adoption.md`
before proposing anything.

Preconditions to verify:
1. v1.2 Phase 7 (code-tier proposer) shipped and merged to master
2. `lab/pel/` machinery functional
3. No uncommitted work on master

Recommended execution order (based on the plan):
- B first (MCP wrapper) — biggest distribution multiplier, wraps stable runtime
- A second (AGENTS.md rewrite) — quick, raises agent-facing discoverability
- C third (paper) — slowest; benefits from post-v1.2 data + completed A/B

Propose whether to run these as v1.3 phases, as inserts, or as back-to-back
atomic changes. Ask me before starting any one of them.
```

## Not on this list (captured elsewhere)

- **BOUNCE-PROTOCOL.md spec + interop push** — the "get one competitor to emit `[CONTESTED]`" play. Lives in the brainstorm memory; needs its own discuss phase before planning.
- **Awesome-list PRs** — drafted in `.planning/notes/awesome-list-pr-drafts.md`. Submit ~1 week after llms.txt is live so maintainers see the discoverability signal.
- **llms-full.txt** — the fuller companion to `llms.txt`. Skipped for now; `llms.txt` alone covers the indexing need. Add if we see it referenced by crawlers.
