# Public evaluation observatory

`public/index.html` is the current results website. It is a standalone HTML
artifact with its CSS, JavaScript and exact source export embedded. It works
without a build server, package install or chart library. The two fonts have
local fallbacks if Google Fonts is unavailable.

The site prioritizes public readers: scores and sample sizes first, then
selectable repository/cost comparisons, paired gains and losses, individual
task evidence, planned experiments and methodology. Complete, publishable
configurations are the only source of headline charts. A flagged run may be
selected in the table, where partial denominators and provenance remain
visible. Coding agents and single-shot models are never pooled. Costs from
estimated token splits remain marked. Repository denominators include failed
no-patch attempts and exclude unattempted tasks, matching the exporter.
The schema currently records time for Claude/Codex phases only. API-only
zero-filled time fields display as unavailable, not zero-second execution.
Timing in workflows with external critics can omit those critics' time.

## Preview and rebuild

```bash
# Re-render the site from committed exports; no model calls or new evaluation.
python benchmarks/site/build-observatory.py

# Preview only public files on the registered frontend port.
python benchmarks/site/serve.py
# http://127.0.0.1:3016
```

Port 3016 is registered for this worktree in `C:/Users/alan/localhost.md`.
The server binds to loopback and serves only `benchmarks/site/public`.

Refresh from new official evaluator reports:

```bash
CODE_BENCH_RESULTS_ROOT=/path/to/results/code \
  bash benchmarks/site/aggregate.sh --suite swebench-verified-random50 \
    --output benchmarks/site/public/current-results.json --observatory \
    --also "Current observatory=index.html"
```

This updates `current-results.json`, its detailed technical pages, and the
observatory. It does not launch benchmarks or call models. The `--observatory`
preflight verifies that the output is the catalog's current export before
writing; archive filenames are rejected. Commit the generated public files
together. Pages deploys the committed directory verbatim, with `index.html`
as the entry point. A displayed snapshot date is the export date; there is no
background polling or automatic claim that an experiment is currently running.

## Future standardized suites

1. Add the suite and run to the benchmark registry and produce a
   `code-bench-site/2.0` export using its official evaluator.
2. Add an entry in `observatory-catalog.json`: unique suite `id`, public `name`,
   `subtitle`, `category`, export `data` filename, `methodology` filename and
   `default_run`. The suite identity and run must match the export. Set
   `default_suite` to make it the initial selection.
3. Rebuild. The benchmark selector, rows, charts, sample sizes and methodology
   switch to the selected suite without UI edits. Scores from different suites
   are never merged. Missing data displays as missing; a real zero stays zero.

The catalog accepts standardized exports in the existing schema. A benchmark
with a fundamentally different metric needs an explicit schema/renderer
extension, rather than labeling its result as a resolved-task percentage.

The research agenda derives progress from complete, publishable rows matching
each phase's suite and model tier. It intentionally does not reuse the old
`arms_measured` and `observed` summaries, which can describe another cohort.

## Preserved editions

The pre-redesign `leaderboard.html`, `leaderboard-methodology.html`,
`leaderboard.json`, `poc.html`, `poc-methodology.html`, `poc.json` and schema
are unchanged at their original addresses. `archive-manifest.json` pins their
original SHA-256 hashes. Future refreshes write `current-results.*`; the old
pages retain their original snapshots. Retired private document benchmarks
remain outside the public site.

## Verification

```bash
python benchmarks/site/tests/test_observatory.py
node --test benchmarks/site/tests/test-observatory-data.cjs
bash benchmarks/site/tests/test-site-build.sh
```

The first checks exact data embedding, deterministic output, old-page hashes,
future-suite registration and safe JSON embedding. The second checks the
score inclusion rules, zero/missing distinction, denominator fidelity and
phase cohort boundaries using the frozen original export as a known-answer
fixture. The existing site suite tests the aggregator, pricing, statistics and
technical renderer. The new checks run in CI on Windows, macOS and Linux.
