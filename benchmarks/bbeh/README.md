# BBEH compact calibration

Executed the approved [September 14 plan](../../docs/plans/2026-09-14-bbeh-low-compute-plan.md)
with Sonnet 5 and Terra at medium effort. The calibration gate rejected the main
phase: 22 of 36 answers received, seven original Sonnet timeouts, seven dependent
revisions blocked. Terra scored 3/12; Sonnet originals and revisions each had one
correct among five received. Missing answers are not scored as wrong.

Eight official failures match the reference except for angle brackets. This
formatting diagnostic does not modify the official score. No Co-Evolution
effectiveness comparison ran. The run is closed; do not resume it or change its
settings based on these results.

The runner freezes selected questions, runtime sources and outputs; reuses the
PlanBench subscription transport and transactional call ledger; and applies the
pinned official BBEH scorer. `vendor/evaluate.py` is unchanged from Google
DeepMind BBEH commit `80d12ca916b7158f22293fcf3144f4d3d854d4be`, licensed under
Apache 2.0 (see `vendor/LICENSE`).

`report.py` creates the immutable local report. `publish.py --root RUN_ROOT`
adds the reviewed assessment and original report hash for this terminal run.
Then run `python benchmarks/site/build-evaluations.py` and
`python benchmarks/site/validate-publication.py`. Publication checks replay the
official scorer against published response bytes. These commands make no model
calls. Runtime artifacts remain local under `runs/bbeh-compact-20260914`.

Public result: https://alanshurafa.github.io/co-evolution/bbeh.html
