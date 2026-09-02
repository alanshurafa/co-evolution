# Eval Suite Optimization Plan (2026-09-02)

Status: DRAFT, awaiting Alan's answers to the open questions at the bottom.
Branch: `claude/eval-suite-optimization-ae8364`.

## What "the eval suite" is

Three surfaces, all wired into one aggregate gate:

| Surface | Entry | Suites | Spend | Purpose |
|---|---|---|---|---|
| Hermetic simulations | `tests/run-all.sh` | 35 `*-simulation.sh` | none | Contract tests for bouncer, dev-review, seats, routing |
| Eval scorer pipeline | `evals/run-evals.sh`, `score-*.sh`, `judge-bounce.sh` | 3 verification scripts | judge only (opt-in) | Deterministic scoring of runs + optional blind LLM judge |
| Benchmark harness | `benchmarks/run-benchmark.sh`, `run-panel.sh`, `judge-matrix.sh` | 4 stubbed tests | real (A/B/C/D x 4 agents, 3 judges) | Standardized benchmark battery |

CI (`.github/workflows/ci.yml`) runs `tests/run-all.sh` serially on a 3-OS
matrix; 41 suites in total.

## Measured baseline

CI test job, last green master run (2026-08-30):

| Runner | Wall time |
|---|---|
| ubuntu | 1m 21s |
| macos | 2m 42s |
| windows | 17m 24s |

Windows gates every CI run at ~17 min. Script startup is not the cause
(`co-evolve-bouncer.sh --help` = 0.17s, `dev-review.sh --help` = 0.24s); the
cost is per-suite process churn (fork/exec of `jq`, `yq`, `git`, subshells;
`lib/co-evolution.sh` alone has 98 jq/yq call sites and 84 `$(...)`), which is
5-10x more expensive under MSYS than on Linux.

Local serial run on this Windows box: **41/41 green in 1555s (26 min)**.
Top 12 suites by wall time (sum of all 41 = 1547s, so the top 12 are ~75%):

| Suite | Elapsed |
|---|---|
| test-report.sh | 197s |
| code-proposer-simulation.sh | 150s |
| pr-emitter-simulation.sh | 129s |
| marker-lifecycle-simulation.sh | 109s |
| smoke.sh | 100s |
| preset-expansion-simulation.sh | 97s |
| dev-review-handoff-simulation.sh | 86s |
| scorer-verification.sh | 81s |
| test-judging.sh | 65s |
| doc-pipeline-seats-simulation.sh | 58s |
| bounce-scorer-verification.sh | 50s |
| bounce-state-simulation.sh | 42s |

Note `benchmarks/tests/test-report.sh`: it is the single slowest suite and
was not on anyone's slow list. It runs `report.sh` only 4 times, but
`report.sh` has 52 shell loops with per-cell jq/awk spawns, so each run costs
~50s on Windows. `benchmarks/tests/smoke.sh` (100s) is 2 full bouncer runs.

## Findings (glaring issues)

### A. Test harness (`tests/`)

1. **No shared helper library.** Zero of 35 suites source a common lib.
   32 reimplement `mktemp -d` + `trap cleanup EXIT`; 20 duplicate the
   `bin/claude` / `bin/codex` PATH-stub heredoc. Every fix to stubbing
   semantics has to be made up to 20 times.
2. **Scratch dirs inside the repo tree.** `code-proposer-simulation.sh:79`,
   `policy-proposer-simulation.sh:35`, `pr-emitter-simulation.sh:43` use
   `mktemp -d -p "$REPO_ROOT/tests"`. Dirties `git status` on a crash and is
   a collision hazard under `--jobs N`.
3. **Shared TMPDIR glob cleanup.** `code-proposer-simulation.sh:89` and
   `pr-emitter-simulation.sh:58` clean `pel-*-sandbox-*` by glob; two
   concurrent instances can delete each other's sandboxes.
4. **End-to-end spawns as unit tests.** `code-proposer` (1096 lines) and
   `reliability` (793) each launch the full `dev-review.sh` 8 times;
   `bounce-state` launches the full bouncer 3 times. These are the suites
   that dominate wall time on Windows.
5. **CI never uses `--jobs`.** `run-all.sh` already supports parallel
   suites (bash >= 4.3, so ubuntu + windows qualify; macOS 3.2 falls back to
   serial, which is fine at 2m42s). The 17-minute Windows job is serial by
   default.
6. **Assertion quality.** 157 raw `grep -q` checks and 15 exit-code-only
   checks; not yet triaged for trivially-true patterns.
7. **Hermetic HOME is only enforced by `run-all.sh`.** Suites run directly
   (`bash tests/foo-simulation.sh`) fall through to the host git config.

### B. Eval scorer pipeline (`evals/`)

1. **No per-case timeout.** `run-evals.sh:290-299` runs the runner in a
   plain subshell; one hung LLM call stalls the whole serial suite forever.
2. **Serial, no resume.** Nested `for iteration / for case` at
   `run-evals.sh:212-213`; results accumulate via read-modify-write jq
   (`:343`). A kill discards every completed case.
3. **No timing output anywhere** in `run-evals.sh`, `score-run.sh`,
   `score-bounce.sh`, `calibrate-bounce.sh`.
4. **Judge has no timeout and no stub mode.** `judge-bounce.sh` issues 2
   order-swapped trials per item, up to 4 calls with retries
   (`lib/judge-lib.sh:81-105`), no per-call timeout. Only `run-evals.sh` has
   a fake runner; `judge-bounce.sh` cannot be exercised offline except via
   `test-judge-lib-extraction.sh`.
5. **Stale doc.** `VERIFICATION-PLAN.md:166,176` tells the reader to run
   `powershell.exe -File evals/run-evals.ps1 -Cases ... -FakeRunner`; that
   file does not exist at that path and the flags are wrong.
6. Deterministic scorer is fine: pure jq/awk, byte-stable (Tier 3 proves it).

### C. Benchmark harness (`benchmarks/`)

1. **Judging spend is untracked.** `report.sh:637` says "Judging cost is not
   itemized here"; README claims `judge-matrix.sh` uses the ledger, but
   `grep ledger judge-matrix.sh` is empty. The most expensive phase has no
   cost record.
2. **No 429/5xx retry** in `invoke_glm` / `invoke_kimi`
   (`lib/co-evolution.sh:639,698`): one-shot curl, failure becomes a literal
   `"API Error: ..."` string with rc 0, caught later by heuristics.
3. **Serial cell loop** (`run-benchmark.sh:636-766`); cells are independent
   except for the GLM daily ledger. Resume works (`meta.json` per cell).
4. **Quota ledger is GLM-only.** Codex/Claude/Kimi have no call-count guard,
   despite the codex-guard daily cap being a hard limit.
5. **No progress file** for long batches; status requires polling
   `meta.json` by hand. `judge-matrix.sh` has no `--only-task` equivalent.
6. **Inconsistent missing-key behaviour.** Bare lib `die()`s; `run-panel.sh`
   converts to a retryable cell. Two code paths, two contracts.
7. **Bash-3 fix was partial.** `d83990e` replaced `mapfile` for macOS; the
   Windows CRLF / MAX_PATH workarounds in `run-benchmark.sh:472-479` and
   README remain inline hacks.

## Plan

Ordered by payoff per hour. Each wave is independently mergeable.

### Wave 1: cut CI wall time (target: windows 17m -> under 6m)

- W1.1 `ci.yml`: run `tests/run-all.sh --jobs 4` on ubuntu/windows; keep
  serial on macOS (bash 3.2). Needs W1.2/W1.3 first or parallel runs will
  collide.
- W1.2 Move the three in-repo scratch dirs to `mktemp -d` under system temp.
- W1.3 Namespace the `pel-*-sandbox-*` cleanup globs with a per-run id.
- W1.4 Add per-suite `timeout` in `run-all.sh` (default 600s, flag
  `--suite-timeout`) so a hung suite fails instead of eating the 45-min job.
- W1.5 Publish per-suite timings as a CI artifact (the `.result` files
  already carry elapsed seconds; just upload the ledger dir).
- Verify: three green CI runs with windows under the target.

### Wave 2: shared harness library

- W2.1 Create `tests/lib/harness.sh`: `harness_tmpdir`, `harness_stub_cli
  <name> <script>`, `harness_hermetic_git`, `harness_assert_*` (file
  contains / json path equals / exit code), scenario counter + summary line
  matching the current `N/N scenarios passed` contract.
- W2.2 Migrate suites in batches of ~8 (mechanical; Sonnet workers, one
  suite file per worker, diff-only report). Behaviour must be byte-identical
  on the PASS/FAIL summary line.
- W2.3 Move the hermetic git config from `run-all.sh` into the lib so a
  suite run directly is also hermetic.
- W2.4 Assertion triage: replace exit-code-only and trivially-true `grep -q`
  checks with `harness_assert_*` calls (report which ones were weak).

### Wave 3: make the slow suites cheap

- W3.1 `code-proposer` and `reliability`: identify which of the 8
  end-to-end runs share a fixture and collapse to one run + multiple
  assertions; unit-test the underlying lib functions (`lib/co-evolution.sh`)
  directly for the rest.
- W3.2 Same treatment for `pr-emitter` and `bounce-state`.
- W3.0 `benchmarks/report.sh`: rewrite the per-cell loops as a single jq
  program over the collected `meta.json`/verdict files (one spawn, not
  hundreds). Expected: `test-report.sh` from 197s to under 20s.
- W3.3 Reduce jq/yq process spawns in `lib/co-evolution.sh` hot paths
  (batch multiple `jq` reads into one call; cache `yq` YAML->JSON once per
  run). This helps production runs too, not only tests.

### Wave 4: eval pipeline robustness (`evals/`)

- W4.1 Per-case `timeout` around the runner invocation
  (`run-evals.sh:290`), default from `defaults.yaml`.
- W4.2 Incremental persistence: write one `<case>.json` per completed case,
  `--resume` skips cases already scored (mirror `run-all.sh --resume`).
- W4.3 `--jobs N` for the case loop; cases are independent.
- W4.4 Timing: `elapsed_secs` per case in `raw-scores.json` and a total in
  the report footer.
- W4.5 `judge-bounce.sh --stub` (deterministic fake judge) + per-call
  timeout in `judge_invoke_trial`; add a hermetic test for the retry path.
- W4.6 Fix `VERIFICATION-PLAN.md` PowerShell references; delete or redirect
  to `runners/codex-ps/`.

### Wave 5: benchmark harness robustness (`benchmarks/`)

- W5.1 Retry with backoff on 429/5xx (and connection errors) in
  `invoke_glm` / `invoke_kimi`; surface HTTP status as a structured field,
  not a string in the output file.
- W5.2 Judge cost ledger: record model, calls, tokens (where the API returns
  them) per verdict; itemize in `report.sh`; fix the README claim.
- W5.3 Generalize the GLM ledger into a per-provider daily call cap (codex
  needs it most because of codex-guard).
- W5.4 `progress.json` per batch (cells done / pending / failed, ETA from
  mean `wall_secs`), updated after every cell; `judge-matrix.sh` gets
  `--only-task` and the same progress file.
- W5.5 Unify missing-key handling: lib returns a typed exit code, panel and
  batch both map it to `retryable`.
- W5.6 Optional: `--jobs N` for non-GLM cells.

### Things Alan did not ask about but should be in scope

- **Flake detection.** Nothing records whether a suite has ever flaked.
  Add `--repeat N` to `run-all.sh` and a nightly scheduled run (cheap, no
  spend) that reports suites with <100% pass rate.
- **CI path filtering.** A docs-only PR still runs the full 17-min matrix.
  Add `paths-ignore` for `docs/**`, `*.md` (keep the `docs-sync` suite
  reachable via a small separate job).
- **Cache the yq download** in CI (`actions/cache` keyed on yq version) and
  pin the version instead of `releases/latest` (a yq release can break CI
  with no code change).
- **Live-seat smoke on a schedule, not on PR.** `live-glm-seat-simulation`
  skips in CI; a weekly scheduled job with `CO_EVOLVE_LIVE_GLM_TEST=1` and
  the secret would catch provider drift (Kimi/GLM API changes) before a
  benchmark batch burns money on it.
- **One place for timings.** `run-all.sh` ledger, `evals` raw-scores, and
  `benchmarks` `wall_secs` should all emit the same `{name, elapsed_secs,
  status}` shape so a single script can chart them.

## Open questions for Alan

1. **CI target.** Is "windows under 6 min, ubuntu under 1 min" the right
   bar, or do you want to drop Windows from the PR matrix and run it only
   on master/nightly? (Windows is the project's home platform, so I lean
   toward keeping it and parallelizing.)
2. **Suite refactor risk appetite.** Wave 2 touches all 35 suites. Do you
   want that as one PR per batch of ~8 suites (reviewable), or one big PR
   after a full green run? I recommend batches.
3. **Benchmark harness priority.** Memory says the full batch is blocked on
   the `ZAI_API_KEY` paste and a ~$80-100 go/no-go. Should Wave 5 (retry,
   judge cost ledger, per-provider cap) land *before* that batch runs? I
   would not spend $80 through a harness with no 429 retry and no judge
   cost record.
4. **Parallel benchmark cells.** W5.6 would hit Codex/Claude rate limits
   faster. Skip it, or cap at 2?
5. **Flake nightly.** OK to add a scheduled GitHub Actions job (no LLM
   spend) for `run-all.sh --repeat 3`? It costs Actions minutes only.
6. **Assertion triage scope.** Should weak assertions be fixed in-place
   during the Wave 2 migration (slower, riskier) or listed in a report and
   fixed in a follow-up?

## Execution model

Orchestrator (this session or an Opus session from this file) fans out
Sonnet workers per file; Opus for W3.3 (`lib/co-evolution.sh` hot path) and
W5.1 (provider retry). Every wave ends with `bash tests/run-all.sh --jobs 4`
green locally and CI green on all three OSes before the next wave starts.
