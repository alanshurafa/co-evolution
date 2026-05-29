# Remediation Plan — Co-Evolution (converged v2)

> Status: converged via one critique→resolve co-evolution pass (no open
> [CONTESTED]/[CLARIFY] markers). Companion to `PERFORMANCE-AUDIT.md`.
> Intended next step: independent Codex review via the dev-review methodology.

**Pre-work (baseline):** record the current hermetic-suite state — 7 suites green;
`policy-proposer` + `scorer-verification` red on the yq variant; `worktree` +
`pr-emitter` red only under host git commit signing — so any regression is detectable.

## Phase 1 — Correctness & portability (low risk)

**1.1 F-1 — Reject the wrong `yq`.** In `evals/lib/co-evolution-evals.sh:47`
(`ensure_yq`) and the inline guards at `lab/pel/proposer/policy/proposer.sh:44` and
`lab/pel/pr-emitter/pr-emitter.sh:570`, add
`yq --version 2>&1 | grep -qi mikefarah || die "<actionable message>"`. Keep the
snippet byte-identical across all three sites and add a grep-pinned test asserting
they match (so this fix does not reintroduce the drift F-2 removes). Document the
Debian/Ubuntu `apt install yq` trap in `README.md`, `evals/README.md`,
`lab/pel/README.md`.
*Verify:* with mikefarah yq installed, `policy-proposer` and `scorer-verification`
reach 14/14; with python yq, a clear die (not a jq error). Any residual failure →
new finding.

**1.2 F-6 — `co-evolve-bouncer.sh:166`** drop the stray `1` arg to `die`.
*Verify:* `bash -n` + `--complexity bogus` exits 1 with the message.

**1.3 F-2 — Single canonical `review-verdict.json`.** First `git log -p` the skill
copy to learn whether the divergence was intentional; canonicalize toward the
deliberate shape and confirm it matches what `validate_review_verdict` enforces.
Add a `diff <(jq -S .) …` drift guard across all three copies.
*Verify:* drift guard clean; existing verdict fixtures still pass.

**1.4 F-5a — Make the Claude model overridable.** In `lib/co-evolution.sh:337-368`
add `CLAUDE_MODEL` (default = one named constant) mirroring `CODEX_MODEL`; expose
`--claude-model` in both runners. Do NOT change the default value here.
*Verify:* stubbed `claude` records the model under default and override.

## Phase 2 — Test hermeticity + CI gate (low–med risk; guards Phase 3)

**2.1 F-3 — Hermetic tests, production untouched.** In suites whose sandboxes commit
(`worktree-management`, `pr-emitter`, `code-proposer`, others as found), set
`GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null` + `user.email/name` +
`commit.gpgsign=false` for the script-under-test. Leave production git calls alone so
PEL's real PRs keep the user's signing.
*Verify:* all suites pass on a signing-enabled host with no manual flags.

**2.2 F-4 — Aggregate runner + CI.** Add `tests/run-all.sh` (runs every `tests/*.sh`
+ `evals/tests/*.sh` with 2.1's env, roll-up table, non-zero on any fail). Add
`.github/workflows/ci.yml` that installs `jq` + mikefarah/yq (explicit binary, not
apt) + `shellcheck`, runs `run-all.sh` + the drift guard. CI runs ONLY
hermetic/stubbed suites — never live `claude`/`codex`. shellcheck lands non-blocking
first (error-severity gate), fixed incrementally; repo-wide noise suppressed via
`.shellcheckrc`.
*Verify:* CI green on a fresh runner.

## Phase 3 — Performance (med risk; sequenced last, behind the Phase 2 gate)

**3.1 (Spike) — Prompt cost.** Investigate whether `claude -p` / `codex exec` expose
cache control. Deliverable = a written finding. The static protocol+role prefix is
resent every pass (`co-evolve-bouncer.sh:467-486`); only implement trimming if
measurement shows it is safe for convergence. No code change without that evidence.

**3.2 — Cheaper verify/critique model.** Building on 1.4, let the verify/critique step
and PEL scoring sub-runs select a cheaper model (e.g. Haiku) independent of compose —
that is where multi-bounce cost concentrates.
*Verify:* stubbed runs show the verify phase using the cheaper model; scorer tests
unaffected.

**3.3 — Smarter stop/retry.** Add a delta-based early stop (pass changes < N words AND
adds no new markers) and an absolute word floor on the `size_sanity_check` retry
(`lib/co-evolution.sh:663-682`) so terse-but-valid outputs do not pay an extra model
call.
*Verify:* new simulation cases "terse valid → no retry" and "tiny delta → early stop."

## Phase 4 — Hygiene (low risk)

**4.1 F-7 —** Do NOT relocate `.planning/` (GSD tooling depends on it). Add a header
marking `STATE.md` a dev journal and scrub `C:/Users/alan/...` absolute paths.
**4.2 F-5b —** Refresh the hardcoded Claude default model, verified against the
installed CLI's accepted values (separate from 1.4's override).
**4.3 Run-naming —** Port the main runner's local label-derivation to legacy
`agent-bouncer/agent-bouncer.sh:46-64` (or deprecate it) to drop the pre-pass Codex
call. *Verify:* legacy run dir created with zero pre-pass model calls.

## Sequencing

| PR | Contents | Risk |
|---|---|---|
| 1 | Phase 1 (F-1, F-6, F-2, F-5a) | Low |
| 2 | Phase 2 (F-3, F-4) | Low–Med |
| 3 | Phase 3.2, 3.3 + 3.1 spike finding | Med |
| 4 | Phase 4 cleanup | Low |
