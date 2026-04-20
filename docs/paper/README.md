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
│   ├── 04-pilot-data.md     # not yet written — blocked on pilot data verification
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

- [ ] Verify the "11 bounces → 8 bugs caught" pilot data from brainstorm memory — need to cite the actual run logs from `runs/` or rerun on a known fixture set
- [ ] Verify all citations resolve (no fabricated paper titles or authors)
- [ ] Confirm comparison table claims are accurate as of submission date
- [ ] Pick author affiliation + ORCID for the arxiv submission
- [ ] License: paper itself under CC-BY 4.0 (matches arxiv defaults); BOUNCE-PROTOCOL.md stays CC0
