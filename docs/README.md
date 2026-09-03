# The benchmark results site

A static page that presents a judged benchmark batch as a cost-versus-quality
scatter, a sortable leaderboard, and a per-task drill-down.

Live at **<https://alanshurafa.github.io/co-evolution/plans/>**.

The repository root of that Pages site is a different page — the SWE-bench
"Code Battery" leaderboard, built from `benchmarks/site/public/`. Both are
deployed by the same workflow, `.github/workflows/pages.yml`, from files
already committed to `master`.

## What is in here

| Path | Published | What it is |
|---|---|---|
| `index.html` | yes | The page. Loads `data/index.json`, then the selected batch's data file. |
| `assets/site.css` | yes | All styling. Light and dark themes, no framework. |
| `assets/site.js` | yes | All rendering, including the inline-SVG scatter. No charting library. |
| `data/<batch>.json` | yes | One judged batch, written by `benchmarks/export-site-data.sh`. |
| `data/index.json` | yes | The batch list the selector reads. Regenerated on every export. |
| `data/schema.json` | yes | The `bench-site/1.0` contract every batch file must satisfy. |
| everything else | **no** | `audits/`, `paper/`, `superpowers/`, `agent-seats.md` are repository documentation. The Pages workflow copies only the three published paths above. |

## Republishing

One command, from the main checkout:

```bash
bash benchmarks/export-site-data.sh --batch b1
```

That reads `benchmarks/results/b1/`, writes `docs/data/b1.json`, and
regenerates `docs/data/index.json` from every batch file in that folder. Commit
the result and push to `master`; the `pages` workflow redeploys on any change
under `docs/index.html`, `docs/assets/` or `docs/data/`.

Export a batch whose results live outside `benchmarks/results/` with
`--batch-dir`:

```bash
bash benchmarks/export-site-data.sh --batch-dir /path/to/results/b1
```

## Previewing locally

The page fetches its data over HTTP, so opening `index.html` from the
filesystem will not work — the `fetch` call is blocked on `file://`. Serve the
folder instead:

```bash
python3 -m http.server 8791 --directory docs
```

Then open <http://localhost:8791/>. Any static server does; there is no build
step and nothing to install.

## What the page may show

The export is limited to publishable fields by design: scores, costs, model and
condition names, judge tallies, and task ids and difficulty. Task prompts, the
generated plans, judge reasoning and verbatim evidence quotes are never read
into the data file.

Three things enforce that rather than leaving it to review:

1. `export-site-data.sh` reads a fixed list of fields out of each artifact and
   fails if an unexpected one appears in its output.
2. `data/schema.json` sets `additionalProperties: false` throughout, so a field
   added upstream fails validation instead of reaching the page.
3. `benchmarks/tests/test-site-export.sh` asserts that no prompt, plan or
   transcript text survives an export of the fixture batch.

## Reading the numbers

Every figure on the page is computed by the export using the accounting frozen
in `benchmarks/PREREGISTRATION.md` section 4 — a win scores 1, a tie or a
position-biased pair scores half a win to each side, and pairs dropped by
sanitization or invalid evidence leave both the numerator and the denominator.
The win-matrix and Bradley-Terry code is the same awk `benchmarks/report.sh`
runs, so the site and the markdown report cannot disagree.

Judges are shown separately everywhere and are never adjudicated into a single
score, as the pre-registration requires. The cost axis is labelled "captured
cost (floor)" because Codex has no token sidecar and the direct GLM and Kimi
sidecars report tokens without a price.
