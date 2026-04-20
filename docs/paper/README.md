# Paper: Convergence-Guaranteed LLM Debate via Expiring In-Document Markers

**Status:** First draft complete (2026-04-19) — **arxiv push deferred indefinitely** (2026-04-20)
**Format:** Markdown, read directly from [`sections/`](sections/) in order
**Companion artifacts:** [BOUNCE-PROTOCOL.md](../../BOUNCE-PROTOCOL.md), [CITATION.cff](../../CITATION.cff)

## Why this paper exists

The bounce protocol has a real claim to make: most multi-agent LLM debate frameworks (MAD, AutoGen, ChatEval) lack any convergence guarantee — debate can chain indefinitely until some external limit cuts it off. This paper formalizes the in-document marker approach with auto-expiry and proves convergence in a bounded number of passes.

The original strategic point was citability via arxiv preprint, which would unlock indexing in Semantic Scholar / Google Scholar / Perplexity. After honest review (2026-04-20), that goal was deferred indefinitely — see **Status note** below for rationale. The paper remains valuable as a markdown artifact: people can link to specific sections, the prose explains the protocol formally, and it complements the CC0 specification at the repo root.

## Status note (2026-04-20)

The paper exists as 7 drafted markdown sections in [`sections/`](sections/). It is **not** being polished for arxiv submission. Reasons for the deferral:

- No validated demand — nobody has asked for a PDF or formal preprint
- The audience we actually want to reach (tool maintainers like the [outreach targets](../../.planning/notes/post-v12-visibility-plan.md)) lives in markdown / GitHub, not in academic PDF
- [BOUNCE-PROTOCOL.md](../../BOUNCE-PROTOCOL.md) already does most of the citable-substrate work the paper was supposed to do
- arxiv submission carries real costs (trim pass, citation verification, author affiliation, ORCID, build pipeline maintenance) without obvious benefit at our current adoption stage

**Trigger to revive the arxiv push:** explicit external request for a PDF preprint, an outreach reply mentioning citation, or a downstream tool wanting to reference the protocol formally. At that point the markdown is already in good shape; the remaining work is editorial + build infrastructure (which is preserved — see [Build pipeline](#build-pipeline) below).

## Structure

```
docs/paper/
├── README.md          # this file
├── outline.md         # full structure + section-by-section plan
├── sections/
│   ├── 00-abstract.md       # drafted
│   ├── 01-introduction.md   # drafted
│   ├── 02-protocol.md       # drafted
│   ├── 03-convergence.md    # drafted
│   ├── 04-pilot-data.md     # drafted from runs/ retrospective (47 runs, 82.5% convergence)
│   ├── 05-comparison.md     # drafted
│   └── 06-limitations.md    # drafted
├── Makefile           # build pipeline — DORMANT, see "Build pipeline" below
├── metadata.yaml      # pandoc metadata stub — used by Makefile
├── refs.bib           # citation stubs — every entry needs verification before any submission
└── build/             # gitignored — pandoc output (PDF/LaTeX), populated only when pipeline is activated
```

## Reading the paper

Read the section files in order:

1. [`sections/00-abstract.md`](sections/00-abstract.md)
2. [`sections/01-introduction.md`](sections/01-introduction.md)
3. [`sections/02-protocol.md`](sections/02-protocol.md)
4. [`sections/03-convergence.md`](sections/03-convergence.md)
5. [`sections/04-pilot-data.md`](sections/04-pilot-data.md)
6. [`sections/05-comparison.md`](sections/05-comparison.md)
7. [`sections/06-limitations.md`](sections/06-limitations.md)

Or run `make` (after installing tools) to produce a single concatenated `build/paper.md`.

## Build pipeline

The [`Makefile`](Makefile) is **dormant**. It targets pandoc + Typst (or pandoc + LaTeX) to render the markdown sections to PDF or LaTeX. To activate:

1. Install tools — see prerequisites at the top of [`Makefile`](Makefile)
2. Run `make check-tools` to verify
3. Run `make` to concatenate sections into `build/paper.md`
4. Run `make paper` to render `build/paper.pdf`

The pipeline is committed but not exercised. We don't actively maintain it; revive when a PDF is genuinely needed.

## Open items if the arxiv push is ever revived

These would re-activate as work to do, in priority order:

1. **Trim pass** — every section is over its word budget; total cut needed is ~30-40% to hit a 4-6 page target
2. **Citation resolution** — every `[CITATION-NEEDED]` in the section files needs a real reference; every entry in [`refs.bib`](refs.bib) needs verification (titles, authors, venues, DOIs)
3. **Section 4 polish** — identify the commit hash where final-pass enforcement landed (`[HASH-NEEDED]` in §4.2); recompute convergence rate restricted to post-enforcement runs (`[HIGHER-FIGURE-NEEDED]`); write Appendix A sample bounce walkthrough
4. **Author affiliation + ORCID** — fill in [`metadata.yaml`](metadata.yaml)
5. **Confirm comparison table** — verify each row in §5.2 is still accurate at submission time
6. **License decision** — paper text proposed under CC-BY 4.0; [BOUNCE-PROTOCOL.md](../../BOUNCE-PROTOCOL.md) stays CC0

None of these are active work items today.
