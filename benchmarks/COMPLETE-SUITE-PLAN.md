# Complete Testing Suite — Fix & Finish Plan

Drafted 2026-09-01 (Fable seat), amended same day for the standardized-only
measurement policy. Execute from this file in a fresh Opus session.

## Measurement policy (Alan, 2026-09-01 — supersedes prior scope)

All pipeline comparison and ALL shared or published reporting uses
standardized, publicly recognized benchmarks scored by their official
evaluators — currently SWE-bench Verified on the pinned official harness.
Homegrown corpora and judge panels (the bounce-protocol document benchmark,
its 3-judge protocol, blind-judge calibration) are RETIRED from measurement
and from every shared surface. Existing internal results are archived in
place and never published. Rationale: results on a benchmark nobody outside
this repo has seen are not comparable and not worth sharing; common tests
with common baselines are.

Boundary: the hermetic regression suite (`tests/run-all.sh`, 42 suites) is
engineering QA that gates harness correctness — it is not a benchmark, its
results are not comparison data, and it stays.

| Surface | Status under policy |
|---|---|
| S1 Code — SWE-bench Verified battery (`benchmarks/code/`) | The measurement surface. Partial: B 5/5 (repair arm inert), C 4/5. A, D, solos unrun |
| S2 Documents — bounce-protocol suite (`benchmarks/`) | RETIRED. Batch b1 complete on disk; archive as internal evidence, no further spend, never on the shared site |
| S3 Regression — `tests/run-all.sh` | QA gate, 42/42 green. Not reported as benchmark data |

## Issues ledger

| # | Issue | Status |
|---|---|---|
| 1 | GLM/Kimi bill reasoning against `max_tokens`; capped critics returned empty content | FIXED `735722f` |
| 2 | kimi-seat test could not simulate a missing key with a real key on disk | FIXED `5cf451c` |
| 3 | Codex refuses all writes on Windows despite `--sandbox workspace-write` | OPEN — Phase 0.1 |
| 4 | Conditions A and D never run on code; solos never run | OPEN — Phase 1 |
| 5 | B scored with inert repair arm: 5/5 is really Fable-solo | OPEN — re-run after 0.1 |
| 6 | GLM/Kimi have no agent loop — solo cells need a single-shot harness | OPEN — Phase 1.5 |
| 7 | Judge `position_biased` verdicts discard t1/t7 cells (doc suite) | CLOSED-RETIRED — surface withdrawn; no re-judging spend |
| 8 | `sanitize-leak` on t2 (doc suite) | CLOSED-RETIRED — same |
| 9 | Codex-judge self-preference confound (doc suite) | CLOSED-RETIRED — same |
| 10 | Two orchestrators wrote one status file (b1 watchdog stamped the SWE status) | OPEN — Phase 0.2 |
| 11 | 5-task subset: one task = 20 points; B/C gap is one task | OPEN — Phase 4 decides scale |
| 12 | HF Hub unauthenticated-rate-limit warnings during evaluation | OPEN — minor, Phase 0.3 |
| 13 | Evaluator leaves 5 images per run | OPEN — hygiene, Phase 0.3, default OFF; never delete other projects' images |

## Phase 0 — Unblock the harness

**0.1 Codex writable workspace (the critical fix).**
Codex 0.144.5 on Windows degrades `workspace-write` to read-only. Fix
sequence, stop at the first that passes:
1. Probe `-s danger-full-access` with the existing 1-file throwaway-repo test.
2. If refused, probe `--dangerously-bypass-approvals-and-sandbox`.
3. If neither, route codex through WSL against the same workspace path.

Guardrails: elevated access is acceptable ONLY because benchmark workspaces
are disposable clones under `benchmarks/results/code/runs/`. Gate behind
`CODE_BENCH_CODEX_SANDBOX` (default stays `workspace-write`); record the mode
in `run-manifest.json` — treatment-relevant fact.
Exit: driver-path probe edits a file; mode recorded in manifest.

**0.2 Status-file single-writer.** One writer per status file; observers get
their own files; every status line carries `writer=`.
Exit: tagged lines present; no cross-suite writes.

**0.3 Small hygiene.** `HF_TOKEN` via the `.env.local` loader (never echo).
Image-prune stays default OFF.

## Phase 1 — Complete the code matrix (SWE-bench Verified, frozen 5-task subset)

Order preserves pairing: never spend Fable dispatches on a condition whose
comparator cannot run.

| Cell set | Dispatches | Est. cost | Precondition |
|---|---|---|---|
| 1.1 A (Fable solo), 5 cells | 5 Fable | ~$5 | none |
| 1.2 D (self-bounce), 5 cells | 10 Fable | ~$15-20 | none |
| 1.3 B re-run (real repair), 5 cells | 5 Fable + 5 Codex | ~$5 + plan compute | 0.1 |
| 1.4 Codex solo, 5 cells | 5 Codex | plan compute | 0.1 |
| 1.5 GLM solo + Kimi solo, single-shot tier | 10 API calls | cents | new harness |

1.5 harness: issue text + `git grep`-selected file context in one prompt →
unified diff → `git apply --check` gate → prediction. Label the tier
"single-shot" everywhere — never unlabeled beside agentic rows.
All cells scored by the official Docker evaluator; caps A=1, D=2 on
`--max-claude-dispatches`.
Exit: every matrix row measured or explicitly blocked; zero infrastructure
failures; prediction files validate 5/5 unique frozen IDs.

## Phase 2 — Retire the homegrown document benchmark

No model spend. Archive-only:
1. Leave batch b1 results and `reports/b1.md` in place as internal evidence;
   they are never published, linked, or summarized on any shared surface.
2. Add a retirement note to `benchmarks/README.md` (doc-suite root): retired
   from measurement 2026-09-01 per standardized-only policy; direct readers
   to `benchmarks/code/` for the active benchmark.
3. Cancel outstanding doc-suite work: t1/t2/t7 re-judging, sanitizer fix for
   judging, blind-judge calibration baselines. Do not delete any code or
   results — retire, don't destroy.
Exit: retirement note committed; no doc-suite job scheduled anywhere.

## Phase 3 — Results site: standardized benchmarks only

Update the existing artifact (same URL). Two sections:
1. **Leaderboard** — SWE-bench Verified frozen-subset matrix, all Phase 1
   rows, coverage labels, per-task dots.
2. **Methodology & integrity** — evaluator pin + gold canary 1/1, dispatch
   counts, per-condition cost, harness commit, and the standing caveat:
   frozen 5-task probe, not comparable to published full-500 scores.
Remove nothing that is already standardized; add no homegrown-benchmark
content. One aggregator script (`benchmarks/site/aggregate.sh`) builds a
single JSON from evaluator reports + run logs; the page renders only that.
Exit: site rebuilt from aggregator output alone; every number traceable to a
file on disk; zero references to the retired suite.

## Phase 4 — Scale gate (go/no-go recommendation, never autonomous)

Present with dollar estimates, run nothing:
- Expand the SWE-bench Verified subset (25-50 tasks) if any pipeline-vs-solo
  gap from Phase 1 is worth confirming.
- Candidate additional suites — standardized public benchmarks only, each
  with an official pinned harness (e.g. SWE-bench Lite, Terminal-Bench,
  Aider Polyglot, LiveCodeBench). No internal corpus is ever proposed.
- Note for the document pipeline: it currently has NO standardized public
  benchmark. Until one exists and is adopted at this gate, document-pipeline
  quality claims stay unmeasured rather than internally measured.

## Budget & sequencing

Phase 0 is hours, two codex probes. Phase 1 ≈ 20 Fable dispatches (~$25-30),
10 codex cells inside the daily guard cap, GLM/Kimi in cents. Phase 2 is a
docs commit. Phase 3 after Phase 1. Phase 4 is a decision. Throughout:
`.env.local`, results, workspaces, trajectories stay uncommitted; no key
values in logs; one writer per status file; evidence never deleted.
