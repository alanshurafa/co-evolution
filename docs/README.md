# docs/

Repository documentation. **Nothing under `docs/` deploys.** The Pages
workflow, `.github/workflows/pages.yml`, globs only
`benchmarks/site/public/**` and publishes those committed files as the site
root; it never reads this directory.

The published site is the SWE-bench Verified leaderboard, built by
`benchmarks/site/aggregate.sh` from evaluator reports and run logs into one
JSON, rendered as self-contained HTML, and committed under
`benchmarks/site/public/`. See the "Results site" section of
`benchmarks/code/README.md` for how to rebuild it.

## What is in here

| Path | What it is |
|---|---|
| `agent-seats.md` | Account, launcher and web-chat setup for the four agent seats. |
| `audits/` | Audit notes and their follow-ups. |
| `paper/` | Draft write-ups. |
| `superpowers/` | Notes on the interactive skill set. |

## The retired document-suite page

An earlier page for the judged bounce-protocol document benchmark lived here
(`index.html`, `assets/`, `data/`). That suite was retired from measurement
on 2026-09-01 under the standardized-only policy (see
`benchmarks/COMPLETE-SUITE-PLAN.md`), the page and its data were removed, and
its results stay archived under `benchmarks/results/` as internal evidence.
They are not published, linked, or summarized on any shared surface, and
`build-site-data.py` does not read them.
