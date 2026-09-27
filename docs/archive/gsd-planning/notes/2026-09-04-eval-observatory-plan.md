# Eval observatory — public results website

User request: create a visually impressive public-facing eval website, inspired by LiveBench, Vellum, LLM Benchmarks and Artificial Analysis, preserving the existing website as an archive. Public readers should see clear scores and takeaways first.

## Workflow and preconditions

- Attempted `gsd-quick`; command not installed. Searched Codex/Claude commands, skills and plugin directories; no GSD entry point available. Use this local planning and verification record under Alan's project-root autonomous-work grant rather than stopping for a person gate.
- Work in the existing site worktree `C:/Users/alan/Project/co-ev-site`. Leave the original task checkout and unrelated work untouched.
- Site data is a `code-bench-site/2.0` export refreshed through the existing aggregator. No benchmark generation, model spend or new scoring/statistical algorithms.
- Existing `leaderboard.html`, `leaderboard-methodology.html`, `poc.html`, `poc-methodology.html` and JSON exports remain byte-identical. Archive them through navigation without moving their URLs.
- New root page consumes the existing scored data. Completed, publishable configurations are the default. Partial and flagged runs are explicitly labeled and excluded from headline results. Single-shot and agentic rows remain separate.
- Standardized benchmark policy remains in force; retired homegrown document results stay private.

## Implementation

1. Add a standalone, dependency-free observatory renderer and page templates: accessible responsive layout, scores with intervals, filterable configuration table, efficiency chart, paired comparison, task outcomes, upcoming registered experiments, methodology and archive links.
2. Add a suite catalog to accommodate future standardized benchmark exports without editing the interface. All figures derive from source JSON; missing scores remain missing.
3. Wire the new page into aggregate and Pages workflows without replacing legacy pages.
4. Validate export fidelity, archive checksums, incomplete-run handling, future-suite rendering, and desktop/mobile interaction. Preview on registered localhost port 3016.

## Verification

Completed 2026-09-04 local / 2026-09-05 UTC.

- New public entry point: `benchmarks/site/public/index.html`. Original pages keep their original URLs and bytes; current refreshes write `current-results.*`.
- Refreshed from `C:/Users/alan/Project/co-evolution-runtime/benchmarks/results/code` using the real `aggregate.sh --observatory` path, at `2026-09-05T02:34:50Z`. Completed light scores remain A 39/50, B 42/50, E 33/50. The refresh also includes two partial single-shot attempts; those never enter headline charts. Latest gold canary is 1/1.
- Existing aggregator/statistics/technical-renderer gate: 27/27 assertions passed.
- Observatory builder tests: 6/6 passed (exact export embedding, preserved archive hashes, non-recursive safe script embedding, additional suite registration, path boundaries, deterministic generated page).
- Browser-data tests: 6/6 passed (flagged/incomplete inclusion rules, zero versus missing, API-only timing placeholders, no-patch denominators, official known-answer totals, phase cohort boundaries).
- The immutable archive manifest verifies all seven original files. The `--observatory` refresh refuses an archived output filename before any writes; tested rejection against `leaderboard.json`.
- Browser checks passed: real search and empty state, cost sorting, configuration evidence, configuration selection/clear/select-all, paired statistics (+3 tasks and p=0.453), task repository filtering and evaluator records, flagged/partial run isolation, single-shot separation, zero-score partial records, CSV download, and navigation into the original leaderboard.
- Exported CSV parsed locally: exactly three rows, B=42/50 and rate=0.84, full numerical cost precision retained.
- Visual checks: desktop (default width and 1440px), mobile (390px), no page-wide horizontal overflow, no JavaScript console errors. Long tables have their own scroll regions. Improved chart text size after the mobile check.
- Screenshot evidence: `.co-evolve-cache/observatory-desktop.png`, `.co-evolve-cache/observatory-comparison.png`.
- Preview at `http://127.0.0.1:3016`; loopback-only server, port recorded in `C:/Users/alan/localhost.md`. Opened/queued in the Codex browser panel and retained in the browser session.
- CI now runs the observatory checks on Windows/macOS/Linux; local JavaScript syntax and `git diff --check` passed. Hosted CI itself has not run.
- Public deployment was not performed. The existing Pages workflow now stages the new `index.html` and preserves archive files; publishing remains a separate release action.
- Original task checkout and unrelated notes in this worktree were left untouched.

## Release to master

Alan explicitly requested merging and publishing the website. Release checks
found that the development branch included the unfinished phase orchestrator
from `8888cb0` and that the older Code Battery edition on `master` was not the
same as the development branch's archived pages.

- Exclude the unfinished orchestrator's five-file change from this release;
  its original branch remains on GitHub.
- Preserve all six public files from master `699be4a` plus its index alias in
  `archive/2026-09-04-code-battery/`; retain the frontier URLs at the root.
  The expanded archive manifest checks 16 preserved files.
- Fix the existing macOS CI failure in no-patch resume: Bash 3.2 treats an
  empty prediction-file array as unset under nounset. Guard its expansion and
  assert successful exit in the existing regression test.
- Run GitHub checks on a PR, merge the verified head into master, wait for the
  Pages deployment, and verify the deployed index and archive hashes.
