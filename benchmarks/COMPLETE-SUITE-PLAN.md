# Complete Testing Suite — Fix & Finish Plan

Drafted 2026-09-01 (Fable seat). Execute from this file in a fresh Opus session.
Scope: every benchmark surface in this repo, not just one pipeline. The two
surfaces measure different things and both ship on one results site:

| Surface | What it measures | State today |
|---|---|---|
| S1 Code (SWE-bench battery, `benchmarks/code/`) | Do bounce/panel pipelines produce patches that resolve real issues? | Partial: B 5/5 (repair arm inert), C 4/5. A, D, solos unrun |
| S2 Documents (bounce protocol, `benchmarks/`) | Do they produce better plans/documents? Pre-registered, 3-judge | Batch b1 complete: 8x4 cells, 48 verdicts/judge. B-vs-A: no evidence (4/8). 3 judge-defect cells |
| S3 Regression (tests/run-all.sh) | Harness stays trustworthy | 42/42 green |

## Issues ledger

Every problem hit so far, with disposition. Fixed items stay listed so the
executing session does not re-litigate them.

| # | Issue | Surface | Status |
|---|---|---|---|
| 1 | GLM/Kimi bill reasoning against `max_tokens`; capped critics returned empty content | S1 | FIXED `735722f` (bounded reasoning, retry+backoff) |
| 2 | kimi-seat test could not simulate a missing key on a machine with a real key | S3 | FIXED `5cf451c` (`CO_EVOLVE_ENV_FILE`) |
| 3 | Codex refuses all writes on Windows despite `--sandbox workspace-write`; B repair arm never engaged, Codex-solo blocked | S1 | OPEN — Phase 0.1 |
| 4 | Conditions A and D never run on code; solos never run | S1 | OPEN — Phase 1 |
| 5 | B scored with inert repair arm: 5/5 is really Fable-solo | S1 | OPEN — re-run after 0.1 |
| 6 | GLM/Kimi have no agent loop (chat seats only) — cannot run solo cells as-is | S1 | OPEN — Phase 1.5 |
| 7 | Judge `position_biased` verdicts discard t1/t7 primary-judge cells | S2 | OPEN — Phase 2.1 |
| 8 | `sanitize-leak` on t2 invalidates that task's comparisons | S2 | OPEN — Phase 2.1 |
| 9 | Codex judge favors B (codex-revised output) 7/0 while fable judge says 4/1 — self-preference confound | S2 | OPEN — report labeling, Phase 3 |
| 10 | Two orchestrators wrote one status file (b1 watchdog stamped `B_resolved=` into the SWE status) | S1/S2 | OPEN — Phase 0.2 |
| 11 | 5-task code subset: one task = 20 points; B/C gap is one task | S1 | OPEN — Phase 4 decides scale-up |
| 12 | HF Hub unauthenticated-rate-limit warnings during evaluation | S1 | OPEN — minor, Phase 0.3 |
| 13 | Evaluator leaves 5 images per run (`Unremoved images: 5`) | S1 | OPEN — hygiene, Phase 0.3; never auto-delete other projects' images |

## Phase 0 — Unblock the harness

**0.1 Codex writable workspace (the critical fix).**
Codex 0.144.5 on Windows degrades `workspace-write` to read-only (no
Landlock/Seatbelt on win32). Fix sequence, stop at the first that passes:
1. Probe `-s danger-full-access` with the existing 1-file throwaway-repo test
   (prompt: replace file contents; assert the file changed).
2. If refused, probe `--dangerously-bypass-approvals-and-sandbox`.
3. If neither, route codex through WSL against the same workspace path.

Guardrails: full access is acceptable ONLY because benchmark workspaces are
disposable clones under `benchmarks/results/code/runs/`; the driver already
diffs nothing outside the workspace. Gate the elevated flag behind
`CODE_BENCH_CODEX_SANDBOX` (default stays `workspace-write` so non-Windows
hosts keep real sandboxing). Record the mode in `run-manifest.json` — it is a
treatment-relevant fact.
Exit: driver-path probe edits a file; mode recorded in manifest.

**0.2 Status-file single-writer.**
The b1 orchestrator's `waiting-for-swe` watchdog wrote into
`full-bc-status.txt`. Rule: one writer per status file; observers write their
own files. Add a `writer=` tag to every status line both suites emit.
Exit: grep shows tagged lines; watchdog writes `full-b1-status.txt` only.

**0.3 Small hygiene.** Set `HF_TOKEN` via `.env.local` loader (never echo);
add a post-eval `docker image prune` scoped by the evaluator's image-name
prefix only, listed for approval as it deletes evidence-adjacent artifacts —
default OFF.

## Phase 1 — Complete the code matrix (frozen 5-task subset)

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
unified diff out → `git apply --check` gate → prediction. No tool loop, no
test execution. Label the tier "single-shot" on the site — it is a different
class of attempt and must not sit unlabeled beside agentic rows.
All cells scored by the official Docker evaluator; A reuses the existing
`prepare-instance` flow; keep `--max-claude-dispatches` caps (A=1, D=2).
Exit: every matrix row measured or explicitly marked blocked, zero
infrastructure failures, prediction files validate 5/5 unique frozen IDs.

## Phase 2 — Close out the document suite

**2.1 Repair the judge panel, not the generations.** Generations are frozen
and complete; only judging is defective. Fix sanitizer for the t2 leak;
re-judge t1/t2/t7 with position-counterbalanced double passes (both A/B
orders, verdict only when both orders agree; disagreement = non-decisive).
Re-emit `reports/b1.md`. Do NOT regenerate any cell — the pre-registration
forbids touching generation post-hoc.
**2.2 Judge self-preference (issue 9).** No re-run needed: the report already
never adjudicates across judges. Add the B-authorship note to the report and
site so codex-judge B-favoritism is read as a confound, not confirmation.
**2.3 Calibration baselines** for the blind judge (`evals/judge-bounce.sh`)
remain unrun — schedule as its own small batch; without them, judge scores
stay labeled uncalibrated.
Exit: 48/48 usable primary-judge pairs or documented non-decisives; report
regenerated with the same pre-registered decision rules.

## Phase 3 — One results site for the whole suite

Extend the published artifact (same URL) from code-only to three sections:
**Code** (the current leaderboard + new rows from Phase 1), **Documents**
(b1 pre-registered outcomes, per-judge tables, confound labels), **Harness**
(42-suite regression state, gold canary, adapter probes). One aggregator
script (`benchmarks/site/aggregate.sh`) emits a single JSON from: evaluator
report JSONs, `judge-matrix` outputs, `tests/.run-ledger`. The page reads
one data blob; no hand-edited numbers. Validity language: pre-registration
wording for S2; "frozen 5-task probe, not comparable to published SWE-bench
Verified" for S1.
Exit: site rebuilt from aggregator output alone; every number traceable to a
file on disk.

## Phase 4 — Decide on scale, then gate

With the full 7-row code matrix and repaired b1 report in hand, decide:
- Code: expand frozen subset (25-50 tasks) only if a pipeline-vs-solo gap
  survives the 5-task probe in either direction worth confirming.
- Documents: the pre-registered held-out replication batch (b2) only if any
  comparison leaves the "no evidence" band after Phase 2 re-judging.
Both are cost gates — present as go/no-go with dollar estimates, not run
autonomously.

## Budget & sequencing

Phase 0 is hours, no model spend beyond two codex probes. Phase 1 ≈ 20 Fable
dispatches (~$25-30 by observed per-phase costs), 10 codex cells inside the
daily guard cap, GLM/Kimi in cents. Phase 2 is judging-only (~$5-10 API).
Phases 1 and 2 run in parallel after Phase 0; Phase 3 after both; Phase 4 is
a decision, not a run. Throughout: `.env.local`, results, workspaces, and
trajectories stay uncommitted; no key values in logs; one writer per status
file; evidence never deleted.
