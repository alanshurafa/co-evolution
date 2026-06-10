# Remediation Plan — Co-Evolution

> Status: synthesis of two independent critique passes (Claude empirical + Codex
> structural); all critique markers resolved into concrete actions. Companion to
> `PERFORMANCE-AUDIT.md`.
> Review gate: run an independent dev-review pass on each PR's diff before merge,
> not once for the whole series.

**Pre-work (baseline).** Record hermetic-suite state in a tracked note (committed
`BASELINE.md` or a pinned `runs/` artifact) with the exact reproduction command, so
any regression is detectable. Capture exit code + assertion counts per suite where
the harness emits them, and pass/fail-only where it emits a bare result. Name the
suites and the configurations under comparison:

- Expected: 7 suites green.
- `policy-proposer` + `scorer-verification` go red when the wrong (python) `yq` is on
  PATH instead of mikefarah/yq v4.
- `worktree-management` + `pr-emitter` go red only when the host sets
  `commit.gpgsign=true` (host git commit signing).

## Phase 1 — Correctness & portability (low–med risk)

The one-line fix (F-6) is low risk, but schema canonicalization (F-2) and model
plumbing (F-5a) touch runtime contracts, so the phase as a whole is low–med.

**1.1 F-1 — Reject the wrong `yq`.** Extract `require_mikefarah_yq` into
`lib/co-evolution.sh`; call it from `evals/lib/co-evolution-evals.sh` (`ensure_yq`)
and the inline guards in `lab/pel/proposer/policy/proposer.sh` and
`lab/pel/pr-emitter/pr-emitter.sh`. Centralizing in one sourced helper removes the
duplication rather than freezing three byte-identical copies; keep an inline guard
only where sourcing `lib/co-evolution.sh` is impossible. Prefer a functional probe
over a version-string grep: run a minimal `yq eval` whose output differs between
mikefarah v4 and python-yq, and on mismatch fail with an actionable message naming
the mikefarah binary. Preserve each caller's local exit convention at the call
boundary only. Add a test that asserts every guard site routes through the shared
helper and that the guard rejects a python-yq stub by its exit behavior (not just a
literal source grep).

Eliminating `yq` via a one-time YAML-to-JSON conversion is deferred unless
verification shows the mikefarah dependency remains the dominant failure mode.

Document the Debian/Ubuntu `apt install yq` trap in `README.md`, `evals/README.md`,
and `lab/pel/README.md`.

*Verify:* with mikefarah yq, `policy-proposer` and `scorer-verification` each reach
14/14 (residual failures filed as new findings distinct from F-1). With python yq,
the scripts die with the new message, not a downstream jq error.

**1.2 F-6 — `die()` ignores its exit-code argument.** Verified: `die()` in
`lib/co-evolution.sh` ignores any second argument and always `exit 1`. So the stray
`1` at `co-evolve-bouncer.sh:166` is cosmetic, but the same pattern at
`lab/pel/pr-emitter/pr-emitter.sh:570` — `die "<msg>" 2` — is a real latent bug: it
intends exit 2 and silently exits 1. Pick one fix and apply it consistently: either
give `die()` an optional code (`exit "${2:-1}"`) and keep the call sites, or drop the
bogus args so no call implies a code `die()` cannot honor.

*Verify:* `bash -n` clean; invoking the bouncer with `--complexity bogus` exits 1 and
prints the expected `invalid --complexity value` message. If `die()` gains the code
parameter, add an assertion that `pr-emitter`'s yq-missing path exits 2.

**1.3 F-2 — Single canonical `review-verdict.json`.** Three copies exist:
`schemas/review-verdict.json`, `skills/dev-review/schemas/review-verdict.json`, and
`runners/codex-ps/schemas/review-verdict.json`. `git log -p` them to learn whether the
divergence was intentional. Decision rule for the canonical shape: the runtime
validator contract wins — canonicalize toward whatever `validate_review_verdict`
enforces, then reconcile the other copies to it. Use one tracked file plus symlinks
where supported; otherwise keep generated copies with a `diff <(jq -S .)` drift guard
across all three. Pair the byte/schema drift guard with validator-based positive and
negative fixtures (a valid verdict passes, a malformed one is rejected), since
sorted-JSON equality does not prove semantic compatibility with the validator.

*Verify:* drift guard clean; validator accepts the positive fixture and rejects the
negative; existing verdict fixtures still pass (create fixtures if none exist).

**1.4 F-5a — Make the Claude model overridable.** In `lib/co-evolution.sh`, replace
the hardcoded model in `invoke_claude` with `CLAUDE_MODEL` (single default constant),
mirroring `CODEX_MODEL`; expose `--claude-model` in both runners
(`co-evolve-bouncer.sh` and `agent-bouncer/agent-bouncer.sh`). Precedence:
`--claude-model` flag > `CLAUDE_MODEL` env > default constant. Do not change the
default value here.

*Verify:* stubbed `claude` records the model under default, env, and flag override,
confirming precedence.

## Phase 2 — Test hermeticity + CI gate (low–med risk; guards Phase 3)

**2.1 F-3 — Hermetic tests, production untouched.** Set the hermetic git environment
(`GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`, local
`user.email`/`user.name`, `commit.gpgsign=false`) at **test-runner process scope** so
it covers any suite that commits, present or future. The subtlety the blanket
approach must respect: several suites drive *production* code that itself runs git
(`pr-emitter`, `worktree-management`). The hermetic env must reach those child
invocations during tests **without** changing how that same production code behaves
when a real user runs it. Achieve this by exporting the hermetic config only from the
test runner (and/or inside test-created throwaway repos), never baked into production
scripts. Add an explicit check that a normal runtime invocation outside the test
runner still inherits the user's git config and signing. Audit every suite for
git-committing behavior rather than fixing only the two known-red suites.

*Verify:* all suites pass on a signing-enabled host (`commit.gpgsign=true` set
globally) with no manual flags; a separate check confirms a production invocation
outside the test runner still signs.

**2.2 F-4 — Aggregate runner + CI.** Add `tests/run-all.sh` that runs an **explicit,
declared list** of CI-safe hermetic suites (each opts in by name or a `# ci-safe`
marker the runner greps for) rather than globbing `tests/*.sh` + `evals/tests/*.sh`
blindly, so a future non-hermetic suite cannot silently enter CI. It applies 2.1's
env, emits a roll-up table, and exits non-zero on any failure. Add
`.github/workflows/ci.yml` on `ubuntu-latest` that installs pinned `jq`, mikefarah
`yq` (explicit upstream binary, not `apt`), and `shellcheck`; runs `run-all.sh` + the
schema drift guard. CI prevents live model calls by placing PATH stubs for `claude`
and `codex` ahead of any real binary and asserting the stubs are hit — not by test
selection alone.

shellcheck: a **blocking** `--severity=error` gate from the start. (An error-severity
gate is blocking by definition; do not describe it as "non-blocking.") Suppress
findings with narrowly scoped inline `# shellcheck disable=` directives or a small
`.shellcheckrc` that lists each suppressed rule with a one-line rationale, rather than
blanket repo-wide silence that can hide real defects. macOS coverage is out of scope
for the first CI gate.

*Verify:* CI green on a fresh Ubuntu runner with pinned tool versions; introducing a
live `claude` call in a suite makes CI fail, proving the stub guard.

## Phase 3 — Performance (med risk; sequenced last, behind the Phase 2 gate)

**3.1 (Spike) — Prompt cost.** Investigate prompt caching and repeated-prefix cost for
`claude -p` and `codex exec`. Deliverable: a written finding committed to the repo
(e.g. `docs/spikes/prompt-cost.md`) answering whether `claude -p` uses an API path
that can benefit from Anthropic `cache_control`; whether this caller can influence
caching via flags, structured input, or environment; whether `codex exec` has any
equivalent; and whether trimming the static protocol+role prefix re-sent every pass
in `co-evolve-bouncer.sh`'s prompt-assembly path is safe. Define "safe" concretely: a
fixed before/after corpus of inputs must produce identical or explicitly-accepted
marker-resolution outcomes before any prefix trimming ships. No code change without
that evidence.

**3.2 — Cheaper verify/critique model.** Building on 1.4, let critique/resolve
verification and PEL scoring sub-runs select a cheaper model (e.g. Haiku for
Claude-backed steps; the cheapest acceptable model for Codex-backed steps),
independent of the compose model. This is **conditional on the 3.1 spike** confirming
that critique/verify and scoring actually dominate call count or cost — the
cost-concentration claim is an assumption until measured. Expose the selection via
explicit options/env (e.g. `--verify-model` / `VERIFY_MODEL`, plus the PEL scorer's
own knob). Target critique-loop calls first; include verify only where quality risk is
low and the prompt contract is schema-bound.

*Verify:* stubbed runs show critique/verify and scorer calls using the cheaper
configured model (proving plumbing), plus one non-CI manual smoke check that the real
CLI accepts the cheaper model ID and verifier verdict quality holds. Scorer tests
unaffected.

**3.3 — Smarter stop/retry.** Add a delta-based early stop and an absolute word floor
on `size_sanity_check` in `lib/co-evolution.sh`. **Guard against the inherited-marker
bug:** stopping on "pass-to-pass delta < N words AND no *new* markers added" is unsafe
— it can halt while *inherited* markers from a prior pass are still open. Require
**zero live markers** as a precondition for early stop (or restrict early stop to
flows that are not critique/resolve convergence). Compute the delta on normalized
text: strip `## HUMAN SUMMARY`, whitespace-only changes, and fenced code blocks before
counting. Starting constants: N = 25 words; retry word floor = 120 words or the
existing proportional threshold, whichever is lower, and the floor must not accept
truncated output (keep it paired with the existing marker/structure checks). Adjust
constants if fixtures show false convergence or missed truncation.

*Verify:* simulation cases — "terse valid, zero markers → no retry and early stop",
"tiny delta but markers still open → does NOT early stop", "truncated short output →
still retries". The early-stop case must assert zero existing markers so it cannot
encode the unsafe behavior.

## Phase 4 — Hygiene (low risk)

**4.1 F-7 —** Do not relocate `.planning/` (GSD tooling depends on it). Add a header
marking `STATE.md` a private dev journal. Scrub personal absolute paths: replace
`C:/Users/alan/...` home-directory paths with repo-relative paths, or redact where no
repo-relative form exists — the intent is to remove personal home paths, not every
absolute path. Confirm no operational doc or script depends on a personal path.

**4.2 F-5b —** Refresh the hardcoded Claude default model after 1.4. Verify by checking
current Anthropic model docs and making one stub-safe or low-cost real CLI call to
confirm the installed CLI accepts the new ID. Record the verified CLI version and date
next to the constant, and keep the 1.4 override as the durable fallback so future
model drift needs no source edit. Cover this with a separate real-CLI smoke check —
the 1.4 stub tests prove plumbing, not acceptance.

**4.3 Run-naming —** Decision: **port** the main runner's local label-derivation into
legacy `agent-bouncer/agent-bouncer.sh` (its run-dir setup) so the legacy runner stops
making a pre-pass Codex call for naming. Deprecation is the alternative only if that
runner is being retired this cycle; choose porting otherwise. Preserve the behavior
the pre-pass call provided: a task-derived, readable, collision-resistant run-dir
label.

*Verify:* legacy run dir created with zero pre-pass model calls and a label of the
same shape the main runner produces.

## Sequencing

| PR | Contents | Risk |
|---|---|---|
| 1 | Phase 1 (F-1, F-6, F-2, F-5a) | Low–Med |
| 2 | Phase 2 (F-3, F-4) | Low–Med |
| 3a | Phase 3.1 spike finding only (committed before any perf code) | Low |
| 3b | Phase 3 implementation (3.2, 3.3, any caching-safe prompt-cost change), gated by 3a | Med |
| 4 | Phase 4 cleanup | Low |

PR 1 is Low–Med, not Low: F-6 is a one-liner, but F-2 canonicalization and F-5a model
plumbing touch runtime contracts. The 3.1 spike finding lands as its own artifact
(PR 3a) before any performance code, honoring "no code change without evidence."

Rollback:

- Phase 2: `git revert` the CI commit (or disable `.github/workflows/ci.yml`) and
  remove `tests/run-all.sh`; the per-suite hermetic env is inert outside CI.
- Phase 3: each behavioral change sits behind a constant or flag — revert 3.3 by
  restoring the prior `size_sanity_check` constants, revert 3.2 by unsetting the
  verify-model option. Model-override support (1.4) stays.

## Synthesis log

Merged from two independent critique passes on the v2 plan. Claude (empirical):
verified `die()` arity, caught stale line-number citations, flagged the missing
rollback plan. Codex (structural): 19 [CONTESTED] / 24 [CLARIFY] across convergence
status, baseline durability, the yq functional probe, schema fixtures, the 2.1
hermetic-vs-production contradiction, CI shellcheck consistency, and the 3.3
inherited-marker early-stop hazard. Two must-fixes drove the largest edits: the 3.3
zero-live-markers early-stop guard and the 2.1 test-runner-scoped hermetic env with an
explicit production-still-signs check. Line-number citations were replaced with
function-name references because several numbers had already drifted from source.
