# Co-Evolution — Software Performance Audit

**Date:** 2026-05-28
**Scope:** Full repository — runners (`co-evolve-bouncer.sh`, `dev-review/codex/dev-review.sh`),
shared library (`lib/co-evolution.sh`), the PEL self-improvement lab (`lab/pel/**`),
the eval/scoring harness (`evals/**`), prompt templates, and the test suites (`tests/**`).
**Method:** Static reading of all primary shell sources + executing every hermetic test
suite + dependency/tooling probing on a clean Linux host (bash 5.2, jq present, Python `yq`,
`claude` CLI present, `codex` CLI absent).

---

## 1. Executive Summary

Co-Evolution is a **Bash orchestration layer** that bounces documents, plans, and code
between two AI CLIs (`claude` and `codex`) using `[CONTESTED]`/`[CLARIFY]` markers until
convergence. The engineering quality of the *orchestration* is genuinely high: defensive
error handling, timeout wrapping, fail-safe permission gating, marker auto-expiry for
guaranteed termination, and a large hermetic test suite (10 simulation harnesses + a scorer
verifier).

The weaknesses are **not in the happy-path logic** — they are in **portability, dependency
coupling, artifact drift, and the absence of an aggregated test/CI gate**. The single
highest-impact defect found is a hard, undetected dependency on one specific `yq`
implementation that disables an entire tier of the product and the whole scoring harness on
common Linux installs.

"Performance" for this tool is dominated almost entirely by the **external model calls**
(2–N sequential blocking subprocesses per run, each with a 30-minute ceiling). The Bash
overhead itself is negligible. So the performance levers that matter are **latency
(sequential calls), token cost (no prompt caching, full-document resend each pass), and
convergence efficiency (bounded but not adaptive)** — covered in §4.

**Overall grade: B.** Solid core, production-blocking portability gap, and a maintenance
surface (drift + planning weight) that will erode quality without automation.

---

## 2. What Was Measured

| Test suite | Result (clean host) | Result (signing disabled) | Verdict |
|---|---|---|---|
| `tests/classifier-simulation.sh` | 6/6 ✅ | 6/6 ✅ | Pass |
| `tests/code-proposer-simulation.sh` | 16/16 ✅ | 16/16 ✅ | Pass |
| `tests/lab-routing-simulation.sh` | 4/4 ✅ | 4/4 ✅ | Pass |
| `tests/live-mode-simulation.sh` | ✅ | ✅ | Pass |
| `tests/revise-loop-simulation.sh` | ✅ | ✅ | Pass |
| `tests/router-simulation.sh` | 5/5 ✅ | 5/5 ✅ | Pass |
| `tests/template-proposer-simulation.sh` | 8/8 ✅ | 8/8 ✅ | Pass |
| `tests/worktree-management-simulation.sh` | ❌ 1 fail | ✅ all pass | **Env: git signing** |
| `tests/pr-emitter-simulation.sh` | 4/12 ❌ | 11/12 ❌ | **Env: signing + yq** |
| `tests/policy-proposer-simulation.sh` | 4/8 ❌ | 4/8 ❌ | **Real: yq variant** |
| `evals/tests/scorer-verification.sh` | 0/14 ❌ | 0/14 ❌ | **Real: yq variant** |

Two distinct failure causes, separated by experiment:

1. **Git commit signing** (sandbox-only): suites that `git commit` failed with
   `signing server returned status 400`. Disabling `commit.gpgsign` fixed worktree (→ all
   pass) and pr-emitter (4 → 11/12). This is an *environment* artifact, **but** it exposes a
   real test-hygiene gap (tests should be hermetic against host git config — see F-3).

2. **`yq` implementation mismatch** (real, host-independent): the policy proposer and the
   entire eval/scorer harness call **mikefarah/yq** syntax (`yq -o=json`, `yq -i`). The host
   had **kislyuk/yq** (the Python jq-wrapper, `version 0.0.0`), which rejects those flags:
   `yq: -i/--in-place can only be used with -y/-Y` and `jq: Unknown option -o=json`. This is
   F-1 below — the top finding.

---

## 3. Findings (ranked by impact)

### F-1 — HIGH: Hard, undetected dependency on mikefarah/yq

- **Evidence:** `lab/pel/proposer/policy/proposer.sh` uses `yq -i`; `evals/lib/co-evolution-evals.sh:66`
  uses `yq -o=json`. Under the Python `yq` both hard-fail. Policy-tier tests drop to 4/8 and
  the scorer verifier to **0/14**.
- **Why it matters:** `apt install yq` on many Debian/Ubuntu boxes installs the *Python*
  variant. A user who follows the README's `apt install yq` hint silently loses the policy
  mutation tier **and** the scoring harness — i.e. half of the v1.2 PEL value proposition —
  with a cryptic jq error, not a clear diagnostic.
- **Contrast:** `jq` usage is everywhere paired with a hand-rolled grep/sed fallback
  (`validate_review_verdict`, `init_state_json`, `compute_execute_delta`). `yq` has **no
  such guard** — `ensure_yq` only checks `command -v yq`, not the *variant*.
- **Fix:** In `ensure_yq`, probe the variant (`yq --version` / a `yq -o=json` smoke test) and
  `die` with an actionable message if it's the Python wrapper. Better: replace `yq` calls
  with `jq` over a one-time `yq`→JSON conversion done by whichever yq is present, or vendor a
  tiny YAML-read shim. Document the exact required binary in README + `evals/README.md`.

### F-2 — MEDIUM: Schema drift between canonical and skill copies

- **Evidence:** `schemas/review-verdict.json` and `runners/codex-ps/schemas/review-verdict.json`
  are identical (`1e35707a`), but `skills/dev-review/schemas/review-verdict.json` (`69476deb`)
  has **semantically diverged**: it dropped `additionalProperties:false`, dropped
  `file`/`line_range`/`suggestion` from required issue fields, and dropped
  `scope_creep_detected`/`iteration_notes` from the top-level required set.
- **Why it matters:** `lib/co-evolution.sh:validate_review_verdict` enforces the *stricter*
  rules at runtime while the skill ships the *looser* schema — a verifier can accept a
  verdict the runtime contract rejects (or vice-versa). This is exactly the drift the repo's
  own `CONCERNS.md §5` warns about, now realized.
- **Fix:** Make one schema canonical and symlink/copy-with-checksum-gate the rest. Add a
  drift test (`diff` the copies) to the aggregate suite (see F-4).

### F-3 — MEDIUM: Tests are not hermetic against host git config

- **Evidence:** Multiple suites `git commit` inside fixtures and inherit the host's
  `commit.gpgsign=true` / `gpg.format=ssh`, producing `failed to write commit object` and
  false failures.
- **Fix:** Have test fixtures create repos with `git -c commit.gpgsign=false -c user.name=… -c user.email=…`,
  or export `GIT_CONFIG_GLOBAL=/dev/null` per fixture. Cheap, removes a whole class of
  false negatives.

### F-4 — MEDIUM: No aggregate test runner and no CI

- **Evidence:** No `Makefile`, no `.github/workflows/`. The 11 suites must be invoked one by
  one; nothing fails the build on regression. `CONCERNS.md §1` flagged this at v1.0 and it is
  still open at v1.2.
- **Why it matters:** A repo whose core logic is string substitution + prompt assembly + CLI
  glue is *exactly* the kind that breaks silently. The tests already exist and are good —
  they're just not wired to a gate.
- **Fix:** Add `tests/run-all.sh` that runs every `tests/*.sh` + `evals/tests/*.sh` (with
  signing disabled per F-3), prints a roll-up, and exits non-zero on any failure. Wire it to
  a GitHub Actions workflow installing `jq` + **mikefarah/yq** explicitly (closes F-1's
  detection gap in CI too). `shellcheck` is also absent — add it; it would catch a class of
  quoting/portability bugs across 13.6k LOC of shell.

### F-5 — LOW/MEDIUM: Stale, hardcoded, non-overridable Claude model

- **Evidence:** `lib/co-evolution.sh:365,367` pin `--model claude-opus-4-6`. The Codex model
  is overridable (`--model`/`CODEX_MODEL`), but the **Claude model is not** — no flag, no env
  var. Per this environment's own context the current family is Opus 4.8 / Sonnet 4.6.
- **Why it matters:** Pinning is defensible for reproducibility, but (a) it's stale, and
  (b) the asymmetry (Codex tunable, Claude frozen) is surprising and undocumented. A model
  rename upstream silently degrades every run with no compile-time signal (`CONCERNS.md §3`).
- **Fix:** Add `CLAUDE_MODEL` env var + `--claude-model` flag mirroring the Codex path; keep
  the current value as the default. Centralize the default in one constant.

### F-6 — LOW: Minor `die` arity bug

- **Evidence:** `co-evolve-bouncer.sh:166` — `die "invalid --complexity value: $2 …" 1`.
  `die()` takes one argument; the `1` is silently ignored. Harmless today, but signals a
  copy-paste from a different `die` signature.
- **Fix:** Drop the trailing `1`.

### F-7 — INFO: Planning/doc weight dwarfs code (drift amplifier)

- **Evidence:** ~13,631 lines of shell vs **~39,027 lines of `.planning` markdown** across
  242 markdown files. Behavior is described in README, per-component READMEs, SKILL.md,
  templates, and dozens of phase summaries.
- **Why it matters:** Not wrong per se (this is a research-grade, heavily-journaled repo),
  but it multiplies the doc↔code drift surface (`CONCERNS.md §2`). `STATE.md` still points at
  `C:/Users/alan/Project/...` Windows paths and "Active PR: None yet," i.e. it's a personal
  working journal shipped in the repo.
- **Fix:** Move the live working journal (`.planning/STATE.md`, handoff notes) out of the
  shipped tree or into a clearly-marked `dev-journal/`, and keep user-facing docs lean.

---

## 4. Performance Evaluation (latency / cost / convergence)

Because every meaningful unit of work is an **external AI CLI subprocess**, wall-clock and
dollar cost are set by the model calls, not the Bash. Profile of a standard `co-evolve` run:

- **Call count:** 1 compose + `MAX_BOUNCES` (default 2) bounce passes = **3 sequential
  blocking calls**, +1 retry per phase on empty/short output. `--chain` is fixed at 3 passes.
  `dev-review` adds execute + verify phases. The PEL emitter adds classifier + proposer +
  a full scoring sub-run.
- **Concurrency:** **None.** Calls are strictly serial (`invoke_agent` → wait → next).
  Inherent to the bounce protocol (each pass consumes the previous output), so this is
  *correct*, not a defect — but it caps best-case latency at the sum of per-call latencies.
- **Timeout posture:** Good. `invoke_agent_with_timeout` wraps calls in `timeout --foreground
  1800s`, surfaces exit 124, and degrades gracefully if `timeout(1)` is missing. This
  directly addresses the documented upstream "1h 39min hang."
- **Token cost:** Each bounce pass rebuilds the prompt as `role preamble + full protocol +
  full TASK + full working document` and re-sends it (`run_bounce_phase`,
  `co-evolve-bouncer.sh:467-486`). The **stable prefix (protocol + role) is re-sent every
  pass with no prompt caching.** The project's own `STATE.md` blockers list flags prompt
  caching as *assumed-but-absent* infrastructure. This is the single biggest cost lever.
- **Convergence efficiency:** Markers auto-expire after 2 passes and standard mode
  early-exits at zero open markers (`total_markers -eq 0`) — termination is **guaranteed and
  cheap**. Good. But the pass count is static; there's no "converged early, stop" signal
  feeding back to reduce calls beyond the zero-marker check, and no confidence-based stop.
- **Run-naming cost:** `CONCERNS.md §8` notes an extra Codex call just to name a run; the
  current `co-evolve-bouncer.sh` derives `RUN_LABEL` locally from the task string
  (`head -c 60 | tr …`) — so **this concern appears already resolved** in the main runner.
  Verify the legacy `agent-bouncer/agent-bouncer.sh` doesn't still pay it.

**Performance recommendations (highest leverage first):**

1. **Adopt prompt caching** on the stable bounce-protocol/role prefix. On a 2–3 pass run that
   re-sends a multi-KB protocol each time, this is a direct, large token saving for zero
   behavior change. (Aligns with the repo's own roadmap.)
2. **Cheaper reviewer model for verify-at-scale.** The PEL scoring harness runs many bounces;
   `STATE.md` already identifies Haiku for verify (~10× cheaper). Make the verify/critique
   step model-selectable (ties into F-5).
3. **Confidence-/delta-based early stop.** Beyond the zero-marker check, stop when a pass
   changes < N words *and* introduces no new markers (size delta is already computed by
   `size_sanity_check`/`compute_execute_delta` — the signal exists).
4. **Don't retry blindly on "short" output** for legitimately short answers; the
   `size_sanity_check` 30% threshold can trigger a full second model call on a correct terse
   reply. Gate the retry on an *absolute* floor too, not just the ratio.

---

## 5. What's Genuinely Good (keep these)

- **Fail-safe security posture:** `phase_is_writable` defaults unknown phases to read-only;
  `validate_lab_mode` rejects path-traversal/shell-meta before any FS op; write phases use an
  explicit allow-list + scoped `--add-dir`. This is careful, correct design.
- **Robust error handling:** retry-on-empty, output size sanity checks, `|| true` on agent
  calls so model errors are *data* not crashes, `mktemp` cleanup on jq failure paths.
- **Graceful degradation:** jq-absent fallbacks throughout; `timeout`-absent fallback;
  macOS/GNU `find` feature detection; WSL/cmd.exe bridging for cross-auth.
- **Strong hermetic tests** where they exist — PATH-injected CLI stubs, fixture-driven,
  deterministic. The *pattern* is excellent; it just needs the F-1/F-3/F-4 gaps closed.
- **Guaranteed convergence** via marker auto-expiry — no infinite-bounce risk.

---

## 6. Prioritized Action List

| # | Action | Impact | Effort |
|---|---|---|---|
| 1 | F-1: detect yq variant in `ensure_yq` + die with guidance; document required binary | **High** | Low |
| 2 | F-4: add `tests/run-all.sh` roll-up + GitHub Actions CI (jq + mikefarah/yq + shellcheck) | **High** | Low–Med |
| 3 | Perf #1: prompt-cache the stable protocol/role prefix | **High** (cost) | Med |
| 4 | F-3: make test fixtures hermetic against host git signing config | Med | Low |
| 5 | F-2: single canonical `review-verdict.json` + drift test | Med | Low |
| 6 | F-5: `CLAUDE_MODEL`/`--claude-model` override; un-stale the default | Med | Low |
| 7 | Perf #3/#4: confidence/delta early-stop + absolute-floor retry gate | Med | Med |
| 8 | F-7: relocate the live working journal out of the shipped tree | Low | Low |
| 9 | F-6: drop stray `1` arg in `die` call | Low | Trivial |

---

*Audit produced from a clean-host read + full hermetic test execution. No production runs
(`claude`/`codex`) were invoked; `codex` is not installed in the audit environment, so
end-to-end live latency/cost figures are projected from the call graph, not measured.*
