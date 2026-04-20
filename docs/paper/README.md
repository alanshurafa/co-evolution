# Paper: Convergence-Guaranteed LLM Debate via Expiring In-Document Markers

**Status:** Drafting (started 2026-04-19)
**Target venue:** arxiv (cs.AI or cs.SE), preprint
**Target length:** 4–6 pages
**Companion artifacts:** [BOUNCE-PROTOCOL.md](../../BOUNCE-PROTOCOL.md), [CITATION.cff](../../CITATION.cff)

## Why this paper exists

The bounce protocol has a real claim to make: most multi-agent LLM debate frameworks (MAD, AutoGen, ChatEval) lack any convergence guarantee — debate can chain indefinitely until some external limit cuts it off. This paper formalizes the in-document marker approach with auto-expiry and proves convergence in a bounded number of passes.

The strategic point is interop: a paper makes the protocol citable. Adoption stories ("Tool X uses the bounce protocol [Shurafa, 2026]") become possible. Without the paper, the protocol stays repo-bound and can only be adopted via informal markdown reference.

## Structure

```
docs/paper/
├── README.md          # this file
├── outline.md         # full structure + section-by-section plan
├── sections/
│   ├── 00-abstract.md       # drafted (over word target, needs trim)
│   ├── 01-introduction.md   # drafted (over word target, needs trim)
│   ├── 02-protocol.md       # drafted (over word target, needs trim)
│   ├── 03-convergence.md    # drafted (over word target, needs trim)
│   ├── 04-pilot-data.md     # drafted from runs/ retrospective (47 runs, 82.5% convergence) — appendix A pending
│   ├── 05-comparison.md     # drafted (over word target, needs trim)
│   └── 06-limitations.md    # drafted (over word target, needs trim)
├── refs.bib           # not yet written
└── build/             # gitignored — pandoc output (PDF/LaTeX)
```

## Build

Eventually:
- `pandoc sections/*.md -o build/paper.pdf --bibliography refs.bib --citeproc`
- For arxiv: convert markdown → LaTeX via pandoc, then submit `.tex` + `refs.bib`

## Open items before submission

- [x] ~~Verify the "11 bounces → 8 bugs caught" pilot data~~ — superseded by retrospective analysis of 47 bouncer runs in `runs/` (see Section 4). 33/40 with finals converged (82.5%); 89 [CONTESTED] + 70 [CLARIFY] markers added across pass 1.
- [ ] Identify the commit hash where final-pass enforcement landed (referenced as `[HASH-NEEDED]` in §4.2)
- [ ] Recompute convergence rate restricted to post-enforcement runs (referenced as `[HIGHER-FIGURE-NEEDED]` in §4.2)
- [ ] Write Appendix A — sample bounce walkthrough referenced in §4.5
- [ ] Verify all citations resolve (no fabricated paper titles or authors); replace all `[CITATION-NEEDED]` placeholders
- [ ] Confirm comparison table claims (§5.2) are accurate as of submission date
- [ ] Trim pass — every section is over its word budget; total cut needed is ~30-40% to hit the 4-6 page target
- [ ] Pick author affiliation + ORCID for the arxiv submission
- [ ] License: paper itself under CC-BY 4.0 (matches arxiv defaults); BOUNCE-PROTOCOL.md stays CC0
- [ ] Build pipeline: `Makefile` + `refs.bib` skeleton + pandoc → LaTeX conversion verified
