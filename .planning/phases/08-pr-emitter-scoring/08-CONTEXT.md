# Phase 8: PR Emission + Scoring Integration - Context

**Gathered:** 2026-04-19
**Status:** Ready for planning
**Source:** 08-PRE-DISCUSS-BOUNCE.md (5 Claude/Codex convergences) + /gsd-discuss-phase interactive session (4 additional gray areas resolved)

<domain>
## Phase Boundary

Ship v1.2 Option 1. Build `lab/pel/pr-emitter/` — a wrapper behind a single invocation `co-evolve --lab pel-proposer --target <file-or-pattern>` that:

1. Auto-detects tier from `--target` path (template / policy / code), honoring optional `--tier` override
2. Calls the Phase 4 classifier to pick a flavor (with `PEL_FLAVOR_OVERRIDE` escape hatch preserved)
3. Invokes the appropriate proposer (Phase 5 / 6 / 7) with classifier output + eval-failure report
4. Runs before/after eval scoring against the mutation in its own sandbox, with cached evals + `$25` hard budget cap
5. Drafts a PR against master via `gh pr create --draft` with eval deltas + diff + flavor rationale + canary result (code tier) in the body
6. Exits. Humans review and merge or close. No auto-merge path in v1.2.

Also in scope:
- DEF-07-01 bugfix (Phase 7 stdout redirect — blocking for PR-body markdown)
- `--dry-run` wrapper flag (top-level only, via `CO_EVOLVE_DRY_RUN=1` + PATH-shadowed `gh` stub)
- Tier auto-detect rule table
- Eval cache (fixture-content-hash + eval-script-hash keyed, gitignored)
- Byte-parity preservation: default `co-evolve` / `dev-review` invocations unchanged vs v1.1

Out of scope (explicit):
- Template / policy / code proposer internals (Phases 5, 6, 7 — shipped or closed; consumed via stdout + state.json contracts)
- Classifier logic (Phase 4 — frozen)
- SC-4 dogfood merge/close outcomes (tracked post-ship in `VERIFY-SC4.md`, release gate for v1.2 tag — not Phase 8 closure)
- Auto-merge / Options 2 / Options 3 (v1.3+)
- Evolving the classifier, proposers, or eval harness
- Workspace-agnostic PS port of lab integration scripts

</domain>

<decisions>
## Implementation Decisions

### Pre-locked (from 08-PRE-DISCUSS-BOUNCE.md — Claude/Codex convergence)

- **D-01 — SC-4 scope separation.** SC-4 is post-ship verification for Phase 8 closure AND a release gate for the v1.2 git tag. Phase 8 closes when SC-1, SC-2, SC-3, SC-5 pass. SC-4 blocks `git tag v1.2` until ≥3 real PEL-emitted PRs are reviewed (≥1 merged, ≥1 closed without merge). Tracked in `VERIFY-SC4.md`.
- **D-02 — `--dry-run` is top-level wrapper flag only.** The `co-evolve` wrapper sets `CO_EVOLVE_DRY_RUN=1`, prepends a stub `gh` binary earlier in `PATH`, then runs the normal proposer flow. Proposers do NOT parse `--dry-run` themselves — they honor the env var anywhere they would trigger external side effects beyond assembling the PR body. SC-3 must verify the stub resolves first under Git Bash / MINGW64.
- **D-03 — DEF-07-01 fix in Plan 01 first commit.** The Phase 7 stdout-redirect bug becomes blocking because PR-body markdown requires clean stdout from the code-tier proposer. Fix in Plan 01 as the first commit, then rerun the Phase 7 simulation suite (expected 16/16 still green). Reference DEF-07-01 in the Phase 8 commit. No Phase 7.1 — Phase 7 stays closed.
- **D-04 — Tier routing = auto-detect + `--tier` override.** Auto-detect uses repo-specific PATH RULES, not broad extension regexes (avoids false positives like `README.md`). Rule table:

  | Path pattern | Tier |
  |---|---|
  | `skills/dev-review/templates/*.md` OR `tests/fixtures/templates/**.md` | template |
  | `lab/pel/proposer/policy/policy.yaml` | policy |
  | Any exact-line match in `lab/pel/proposer/code/allowlist.txt` (`lib/co-evolution.sh`, `dev-review/codex/dev-review.sh`, `agent-bouncer/agent-bouncer.sh`) | code |
  | Anything else | hard-error |

  `--tier <name>` override wins for a single target. Mixed-tier globs hard-error. One invocation = one proposer tier. Ambiguous matches hard-error. Hard-errors exit 1 (input validation).
- **D-05 — Scoring compute budget.** Cache eval results keyed on `hash(fixture-content) + hash(executable-eval-scripts-under-evals/)`. Default hard cap = `$25`; exit code 6 on exhaustion. Preflight cost estimate shown only in interactive mode using a checked-in pricing table; `--yes` skips the prompt. v1.2 scoring stays deterministic — full fixture set within budget, no random sampling. Subset scoring (if ever added) must use explicit fixture names, never random sampling.

### Module Structure

- **D-06 — Two-file module.** `lab/pel/pr-emitter/pr-emitter.sh` + `lab/pel/pr-emitter/pr-body-template.md`. No `adapter.sh` — the emitter has no LLM call of its own. No `prompt.md` — the template file serves the same role for PR-body composition. Template uses `{{placeholder}}` substitution (matches the Phase 5/6/7 `prompt.md` convention for placeholders, without a misleading "prompt" filename for a non-LLM artifact).
- **D-07 — Self-containment invariant preserved.** The only source statements inside `lab/pel/pr-emitter/**` are sibling-only. Zero imports reach into `lib/co-evolution.sh`, classifier, or any proposer's internals. Cross-module communication happens via documented stdout contracts (proposer diff → emitter) and filesystem handoffs (proposer `state.json` → emitter reads).

### Scoring Sandbox Lifecycle

- **D-08 — Phase 8 owns its own sandbox.** Phase 7's proposer is NOT modified. Phase 7 emits the unified diff on stdout + `state.json` in its sandbox root, then cleans up its sandbox on EXIT via the existing trap handler. Phase 8 creates a SEPARATE `git worktree` (fresh sandbox) at `$TMPDIR/pel-score-sandbox-XXXXXX`, re-applies the diff there, runs before/after evals inside it, and cleans up on EXIT.
- **D-09 — Handoff contract = stdout diff + state.json snapshot.** The emitter invokes the proposer, captures stdout as the diff, and reads the proposer's `state.json` BEFORE the proposer's cleanup trap fires (architecturally: emitter reads state.json into shell variables while the proposer's sandbox still exists, then proceeds independently). Fields consumed: `outcome`, `flavor`, `diff_lines`, `diff_budget`, `canary` result, `target`, `timestamp`. The emitter does not re-read `sandbox_path` — Phase 7 has cleaned it up by the time scoring runs.
- **D-10 — Second `git worktree add` is cheap.** Shared `.git` object store makes the second sandbox near-instant. Emitter cleanup via `git worktree remove --force` + `rm -rf` in its EXIT trap (defense in depth, matching Phase 7's posture).

### PR Branch Strategy

- **D-11 — Hybrid branch naming (default + override).** Default: `pel/<tier>/<short-hash>`, where `<tier>` ∈ {template, policy, code} and `<short-hash>` is the first 7 chars of `sha1sum` (or `git hash-object`) of the diff content. Overrideable via `--pr-branch NAME` on the `co-evolve --lab pel-proposer` invocation. Same escape-hatch posture as `CLASSIFIER_MODEL`, `PROPOSER_MODEL`, `CODE_PROPOSER_MODEL` (everyday use = default; override for debugging / dogfood).
- **D-12 — Branch created on the emitter's fresh worktree, never the live checkout.** The emitter's scoring sandbox (D-08) IS the PR branch's worktree. The diff is applied there, committed, and pushed from there. Live checkout is never modified. Push target: `origin` (same remote as master).
- **D-13 — Commit message format.** Single commit per PR in v1.2. Subject: `pel(<tier>): <short description synthesized from classifier rationale>`. Body: eval delta summary + flavor + classifier rationale + DEF-07-01 reference when relevant.

### Plan Decomposition

- **D-14 — 3 plans:**
  - **Plan 01 — Foundation.** DEF-07-01 bugfix + rerun Phase 7's 16/16 sim + `--lab pel-proposer` dispatch in `dispatch_lab_mode` + new `co-evolve` CLI flags (`--target`, `--tier`, `--pr-branch`, `--dry-run`, `--budget`, `--yes`, `--flavor`) + tier auto-detect rule table implementation (D-04) + `CO_EVOLVE_DRY_RUN=1` plumbing + PATH-shadowed `gh` stub scaffolding. Byte-parity regression test: running `co-evolve "task"` or `dev-review "task"` WITHOUT `--lab pel-proposer` still matches v1.1 behavior (SC-5).
  - **Plan 02 — Feature + simulation gate.** Scoring loop with before/after eval runs in owned sandbox (D-08, D-09) + eval cache at `.co-evolve-cache/evals/<hash>.json` (fixture+script hash keyed, gitignored) + `$25` hard budget + exit 6 + preflight cost estimate + PR body composition via `pr-body-template.md` + `{{placeholder}}` substitution + `gh pr create --draft` with hybrid branch scheme (D-11) + failure policy branches (D-15, D-16) + simulation gate at `tests/pr-emitter-simulation.sh` covering SC-3: happy-path per tier + `--dry-run` stub verification + canary-failed PR + budget-exceeded abort + tier auto-detect hard-error + byte-parity check.
  - **Plan 03 — Release verification tracker.** Create `VERIFY-SC4.md` with the SC-4 rubric (≥3 real PEL PRs, ≥1 merged, ≥1 closed without merge), review-log template, and "updates post-ship during v1.2 dogfood period" framing. Not a code deliverable — a release-gate artifact that blocks the v1.2 git tag (not Phase 8 closure).

### Failure Policy (Claude's Discretion per original gray-area #7)

- **D-15 — Canary-failed (proposer exit 7) → diagnostic draft PR marked `[CANARY-FAILED]`.** PR title prefixed `[CANARY-FAILED]`. PR body includes: which canary scenario failed, state.json snapshot, mutation diff. Useful signal for prompt-tuning or canary-suite improvement. Humans closing these is part of the SC-4 count (counts as "closed without merge").
- **D-16 — All other non-zero proposer exits (1/2/3/4/5/6/8) → abort, no PR.** These represent either input errors (exit 1/2) or pre-flight rejections (allowlist exit 5 / budget exit 6 / malformed exit 3 / multi-file exit 4 / sandbox exit 8) where no reviewable diff exists. Emitter propagates the proposer's exit code so callers see the failure category.
- **D-17 — Emitter's own exits extend the Phase 7 taxonomy.** Exit 0 = PR draft created. Exit 6 = eval budget exhausted during scoring (NOT proposer budget — distinguished via log message). Exit 9 (new) = `gh pr create` failed post-scoring. Exit 10 (new) = tier auto-detect hard-error (ambiguous / no-match / mixed-tier glob).

### Eval Cache (Claude's Discretion per original gray-area #5)

- **D-18 — Cache location: `.co-evolve-cache/evals/<fixture-hash>-<script-hash>.json`.** Gitignored at repo root (`.co-evolve-cache/` added to root `.gitignore`). Persists per-repo for fast iteration; rebuilds when fixtures OR eval scripts change. No TTL — hash-based invalidation is sufficient.
- **D-19 — Cache entries are full scorer outputs.** Same JSON shape as Phase 2's `evals/reports/<timestamp>/scores.json`. Cache hit short-circuits the scorer invocation; cache miss runs the scorer, stores the result, then continues. Cost attribution: cache hits cost `$0.00`; cache misses bill against the `$25` budget.

### PR Body Composition (Claude's Discretion per original gray-area #2)

- **D-20 — External `pr-body-template.md` with `{{placeholder}}` substitution.** Illustrative placeholder set (final list determined at plan time): `{{tier}}`, `{{target}}`, `{{flavor}}`, `{{classifier_rationale}}`, `{{diff}}`, `{{diff_lines}}`, `{{diff_budget}}`, `{{eval_before}}`, `{{eval_after}}`, `{{eval_delta}}`, `{{canary_result}}` (code tier only), `{{timestamp}}`, `{{def_07_01_ref}}` (Plan 01 commits only). Substitution tool — sed, envsubst, or jq — chosen at plan time; requirement is that raw diff content passes through literally (no metacharacter interpretation).

### Wrapper Ergonomic

- **D-21 — `--flavor <name>` CLI flag added to wrapper in Plan 01.** Maps to `PEL_FLAVOR_OVERRIDE` env var before invoking the classifier. Alan already uses the env-var escape hatch; adding the CLI flag is a trivial ergonomic upgrade and parallels the existing `--branch`/`--worktree` flag style from v1.1.

### Claude's Discretion

Areas where Claude has planning-time flexibility:
- Exact placeholder set in `pr-body-template.md` (D-20 is illustrative)
- Exact rule-table implementation (bash case statement vs jq lookup vs separate `routing.yaml`)
- Exact hash function for `<short-hash>` in branch names (`sha1sum` vs `git hash-object`)
- Preflight cost estimate table shape and update cadence
- `gh pr create` failure handling (single retry vs immediate abort → exit 9)
- Exact simulation scenario count (≥5 per SC-3; cover happy-path per tier + `--dry-run` stub + canary-failed PR + budget-exceeded + tier auto-detect hard-error + byte-parity; target ≥10/10 green final line)
- Whether the wrapper uses a separate `lab/pel/pr-emitter/router.sh` helper for tier detection or inlines routing in `pr-emitter.sh`
- Whether `.co-evolve-cache/` also shelters non-eval artifacts in the future (v1.2 answer: evals only; v1.3+ up to the phase that adds another cache type)

### Trust Handoff (meta)

- **D-22 — Deep-stack decisions delegated.** Alan explicitly accepted agent recommendations wholesale on module layout, sandbox lifecycle, branch scheme, and plan decomposition ("above my head"). Planning agents MAY proceed confidently within the boundaries of D-01 through D-21. Planning agents MUST surface to Alan any SIGNIFICANT deviations from these locked decisions (e.g., if a plan breaks byte-parity, adds a 4th plan, or changes the module layout). Small implementation choices within a locked decision do not need pre-approval.

</decisions>

<canonical_refs>
## Canonical References

Downstream agents MUST read these before planning or implementing.

### Binding design + pre-discuss bounce
- `.planning/phases/08-pr-emitter-scoring/08-PRE-DISCUSS-BOUNCE.md` — **BINDING.** 5 Claude/Codex convergences that anchor D-01 through D-05. Read for the full dialectic behind the locked decisions, not just the summary in this CONTEXT.
- `.planning/notes/pel-design-decisions.md` §5 "Option 2 and Option 3 → graduate via lab/" — human-review IS the v1.2 Goodhart mitigation. The PR review gate is load-bearing, not ceremonial.
- `.planning/ROADMAP.md` §Phase 8 — SC-1..SC-5, dependency on Phases 5/6/7, "This IS the Option 1 ship" framing.
- `.planning/REQUIREMENTS.md` — PEL-05 is Phase 8's requirement.

### Phase precedents (pattern reuse)
- `.planning/phases/07-code-tier-proposer/07-CONTEXT.md` — D-19 stdout diff contract, D-20 `state.json` schema (the emitter's input), D-21 exit-code taxonomy (the emitter's failure classification source). Phase 8 consumes these via documented handoff.
- `.planning/phases/05-template-tier-proposer/05-CONTEXT.md` — template tier's stdout-diff contract.
- `.planning/phases/06-policy-tier-proposer/06-CONTEXT.md` — policy tier's JSON-delta contract (different shape from template/code). The emitter must branch on tier when rendering the PR body: diff goes in a fenced diff block, policy delta goes in a fenced json block.
- `.planning/phases/01-post-v11-fixes/01-CONTEXT.md` — v1.1 `--branch auto|NAME` / `--worktree auto|PATH` flag semantics the `--pr-branch` override inherits from (ergonomic posture, not direct flag reuse).

### Upstream code (integration points)
- `co-evolve-bouncer.sh` — main CLI entry. Phase 8 adds `--target`, `--tier`, `--pr-branch`, `--dry-run`, `--budget`, `--yes`, `--flavor` flags.
- `lib/co-evolution.sh` — shared shell core; `dispatch_lab_mode()` is where `--lab pel-proposer` routes (Phase 3 infrastructure).
- `lab/pel/classifier/classifier.sh` — classifier entry point. Emitter calls and parses JSON output (flavor + rationale + override flag + model).
- `lab/pel/proposer/template/proposer.sh` — template tier. Consumed via stdout (unified diff) + state.json.
- `lab/pel/proposer/policy/proposer.sh` — policy tier. Consumed via stdout (JSON delta) + state.json.
- `lab/pel/proposer/code/proposer.sh` — code tier. Consumed via stdout (unified diff) + state.json. **Subject to DEF-07-01 fix in Plan 01.**
- `lab/pel/proposer/code/allowlist.txt` — 3-line mutable surface; same file used by tier auto-detect to identify code-tier targets (D-04).
- `evals/scripts/` (Bash harness from Phase 2) — emitter's scorer invocation target.

### Lab contract
- `lab/pel/README.md` — PEL inhabitant conventions. Phase 8 extends with a "PR Emitter (v1.2)" section (env-var contract, output contract, exit codes, invocation example — matching the Phase 5/6/7 format).
- `lab/README.md` — lab conventions: W-3 argv contract, L-05 sandbox guarantee, L-06 graduation criteria. The `--dry-run` PATH-stub posture honors L-05.

### Project + state
- `.planning/PROJECT.md` — core value, constraints, key decisions. Especially: "byte-parity for the default runner" and "human review is the Goodhart backstop".
- `.planning/STATE.md` — v1.2 progress.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `dispatch_lab_mode()` in `lib/co-evolution.sh` — routes `--lab <mode>` into `lab/<mode>/`; Phase 8 registers `pel-proposer` as a new mode here.
- `validate_lab_mode()` in `lib/co-evolution.sh` — argument validation reused.
- PATH-injection pattern from Phases 4/5/6/7 canary + sim suites — direct precedent for the `--dry-run` `gh` stub.
- `lab/pel/classifier/classifier.sh` — standalone-invokable; emitter calls with env vars pre-exported and parses pure-JSON stdout.
- Proposer entry points (`proposer.sh` in each tier) — documented env-var + stdout + state.json contracts.
- Eval harness at `evals/scripts/` — Phase 2's scorer produces the exact JSON shape the emitter caches.
- v1.1 `--branch auto|NAME` ergonomic pattern — D-11's hybrid branch naming inherits the "default + named override" posture, not the flag verbatim.
- Hermetic simulation harness pattern from `tests/code-proposer-simulation.sh` — 16-scenario structure is the model; Phase 8's sim targets ≥10 scenarios covering SC-3.

### Established Patterns
- **Self-contained lab inhabitants** — siblings-only sourcing. Phase 8's two-file module honors this (no imports from `lab/pel/proposer/*/` or `lib/co-evolution.sh`).
- **Single-argv + env vars for all internal invocations** — W-3 contract. Phase 8's top-level `co-evolve --lab pel-proposer --target X` uses named flags on the WRAPPER surface; internal calls to classifier/proposers use their existing env-var contracts.
- **Exit-code taxonomy as load-bearing contract** — Phase 7's D-21 codes propagate upward; Phase 8's emitter extends them (exit 9 `gh pr create` failed, exit 10 tier routing hard-error) while preserving Phases 5/6/7 exits 1-8.
- **Hermetic simulation via PATH-injected stubs** — `gh`, `claude`, and proposer binaries all stubbable the same way. Sim structure mirrors `tests/code-proposer-simulation.sh`.

### Integration Points
- `co-evolve-bouncer.sh` arg parser — new flags default off / unset so v1.1 invocations remain byte-parity.
- `lib/co-evolution.sh` lab dispatcher — `pel-proposer` registered.
- Repo `.gitignore` — `.co-evolve-cache/` added.
- `evals/README.md` — brief note on scorer-cache existence + invalidation rules.
- `lab/pel/README.md` — "PR Emitter (v1.2)" section added at the end.

</code_context>

<specifics>
## Specific Ideas

- The bounce file's original dialectic (`08-PRE-DISCUSS-BOUNCE.md`) preserves nuance that the D-01..D-05 summaries compress. Planning agents should re-read it directly, not only the summary here.
- SC-3 (simulation) and SC-4 (dogfood) verify different things. SC-3 proves the pipeline assembles correctly in a hermetic environment. SC-4 proves humans can actually review the PRs usefully in reality. The v1.2 ship crosses SC-3; the v1.2 tag crosses SC-4.
- `[CANARY-FAILED]` PRs (D-15) are useful signal, not noise. They feed SC-4's "≥1 closed without merge" count naturally.
- The `--flavor` CLI flag (D-21) is deliberately lightweight — classifier's env-var override is the authoritative mechanism. The CLI flag is syntactic sugar that sets the env var.
- Alan's trust-handoff (D-22) is documented so planning agents don't mistake the wholesale acceptance for indifference. Alan cares about the outcome; he trusts the pattern-reuse argument the agent made. Deviations need surfacing.

</specifics>

<deferred>
## Deferred Ideas

- **Automatic branch / worktree cleanup after PR merge/close** — carried forward from v1.1 deferred list. Could be a standalone `co-evolve cleanup` utility post-v1.2.
- **Multi-mutation PR (stacked diffs)** — v1.2 is strictly one-mutation-per-PR. Stacked-PR emitter becomes an ergonomic upgrade once SC-4 data shows review fatigue.
- **Rendered-HTML PR body with collapsible diff sections** — `gh` supports markdown only. If dogfood shows reviewers drowning in long diffs, a post-v1.2 UX iteration could shorten the inline diff and link to a full gist/Artifact.
- **`co-evolve cost` subcommand** — a standalone "what would this cost?" query without running evals. Could precede a PEL run to help users pick fixtures. v1.3+.
- **PEL Options 2 (auto-promote) and 3 (explorer + curator)** — out-of-scope for v1.2, seeded in `.planning/seeds/pel-auto-promote-and-explorer.md`. Triggers: ≥4 weeks Option 1 production data + Goodhart research findings + lab conventions established.
- **Classifier evolution (PEL-META-01)** — allowing the Phase 4 classifier to mutate based on Option 1+2 data. Requires clean attribution signal separating protocol improvement from classifier changes. v1.3+.
- **Workspace-agnostic PS port of lab integration scripts** — v1.0 Phase 9 deferred item. Not blocking v1.2.

</deferred>

---

*Phase: 08-pr-emitter-scoring*
*Context gathered: 2026-04-19*
