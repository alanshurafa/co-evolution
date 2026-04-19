# Phase 4: Mode Classifier (frozen) - Context

**Gathered:** 2026-04-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Build `lab/pel/classifier/` — the frozen decision layer that picks one of four fitness flavors (`bug-catcher`, `faster-converger`, `blind-spot-surfacer`, `general`) per PEL invocation given (task description, bounce-step context, GSD-phase-type context), emits a transparent rationale, and honors a `--flavor <name>` override originating from `co-evolve --lab pel-proposer`.

In scope:
- `lab/pel/classifier/entry.sh` — argv-contract-compliant entry point (single argv slot = task string; bounce-step and phase-type flow via env vars)
- Self-contained Haiku-4.5 adapter inside `lab/pel/classifier/` (no dependency on `dev-review/codex/dev-review.sh`'s `invoke_claude` or any `lib/co-evolution.sh` runner helper)
- Frozen prompt asset at `lab/pel/classifier/prompt.md` (prompt-as-reviewable-asset pattern)
- Simulation test covering 4 flavor picks, `--flavor` override precedence, frozen-surface invariant (SC-5)
- Documentation of the `PEL_*` env var contract for future phase callers (Phases 5-8)

Out of scope (explicit):
- Proposer tiers (Phases 5-7) that consume the classifier output
- PR emission wiring (Phase 8 — `co-evolve --lab pel-proposer` flag plumbing for `--flavor`)
- Classifier self-evolution / cross-invocation memory — classifier is stateless by design (D-01)
- Opus fallback as a first-class path — documented-off for v1.2 per ROADMAP SC-2, reachable via env var escape hatch only (D-06)
- Any change to Phase 3's W-3 single-argv lab-dispatch contract or `lab/README.md`

</domain>

<decisions>
## Implementation Decisions

### Statelessness & inputs

- **D-01 — Classifier is stateless.** No cross-invocation memory, no reading of prior SUMMARY.md files, no hidden learning state. Each invocation classifies purely from its three inputs. Pattern-carrying across runs is the explicit job of `*-SUMMARY.md` files curated by a human before any classifier-prompt update in a later milestone. ("The pattern-carrying argument is real but weaker than it looks — SUMMARY.md files capture it explicitly. That's their job." — user preamble, 2026-04-18.)
- **D-02 — Invocation surface: environment variables.** `PEL_BOUNCE_STEP` and `PEL_PHASE_TYPE` carry the non-task inputs. The task arrives as `$1` per Phase 3's W-3 contract. This preserves the single-argv lab-dispatch pin (both runners + lab/README.md grep-anchored in Phase 3 Plan 02) and matches 5 existing env-var caller-sets-config precedents in this repo: `LIVE_MODE`, `DEV_REVIEW_BRANCH`, `DEV_REVIEW_WORKTREE`, `PHASE_TIMEOUT`, and `COMPOSER`/`EXECUTOR`/`REVIEWER`/`CODEX_MODEL`.
- **D-03 — Env var value domains:**
  - `PEL_BOUNCE_STEP` ∈ `{compose, bounce, execute, verify, unknown}`
  - `PEL_PHASE_TYPE` ∈ `{scoping, implementation, verification, unknown}`
  - Unset is treated as `unknown` — not an error. Degrades gracefully: Haiku still receives a valid prompt, just with lower-specificity context.
- **D-04 — Unexpected env var values log a warning but do NOT die.** A misspelled step or phase-type must not kill an entire PEL run. The classifier validator emits `WARNING: unexpected PEL_BOUNCE_STEP value '<x>', treating as unknown` to stderr and continues with `unknown` as the effective value. This aligns with the Phase 3 distinction: structural-contract violations die (invalid mode token, missing `entry.sh`), caller-input misspellings degrade.

### Haiku call path

- **D-05 — Self-contained adapter inside `lab/pel/classifier/`.** A small adapter file (suggested: `adapter.sh`) owns the Haiku invocation — builds the prompt by composing `prompt.md` with the inputs, calls `claude -p --model claude-haiku-4-5-20251001`, parses the response, emits JSON. Zero dependency on `dev-review/codex/dev-review.sh`'s `invoke_claude` or on any `lib/co-evolution.sh` runner helper. Keeps lab→runner dependency direction one-way (matches Phase 3 L-05 sandbox guarantee).
- **D-06 — Model ID hardcoded with env var escape hatch.** Default is `CLASSIFIER_MODEL=claude-haiku-4-5-20251001`; overrideable by exporting `CLASSIFIER_MODEL` before invocation (e.g., `CLASSIFIER_MODEL=claude-opus-4-7` for debugging). ROADMAP SC-2's "Opus fallback documented but off by default for cost" is satisfied via this escape hatch rather than a dedicated CLI flag (dedicated flag deferred to v1.3+ if demand emerges).
- **D-07 — Fail-fast on Haiku call failure.** The adapter dies with a clear error message if the `claude` CLI is missing, authentication fails, the call is rate-limited, or the response is not parseable as JSON matching the expected shape. Lab code must not mask signal with silent fallbacks. Callers in Phases 5-8 decide whether a classifier failure aborts the whole PEL run or uses a documented default — that is their decision, not the classifier's.

### Output format

- **D-08 — JSON to stdout, logging to stderr.** A successful classification emits a single JSON object to stdout, structured approximately:

  ```json
  {
    "flavor": "bug-catcher",
    "rationale": "one-to-three-sentence explanation of why this flavor",
    "override": false,
    "model": "claude-haiku-4-5-20251001",
    "inputs": {
      "task": "...",
      "bounce_step": "compose",
      "phase_type": "scoping"
    }
  }
  ```

  Machine-parseable by Phase 8's PR-body emitter; human-readable when piped to a log. All diagnostic output — validator warnings, Haiku CLI progress, auth hints — goes to stderr so stdout stays pure JSON.

- **D-09 — `--flavor <name>` fully bypasses the Haiku call.** When an override is in effect (propagated into the classifier by the pel-proposer caller — mechanism TBD in Phase 8), the adapter skips the Haiku invocation entirely and emits `{"flavor": "<override>", "rationale": "user override via --flavor", "override": true, ...}`. Saves tokens; the override IS the trust signal. No "would-have-been" comparison logging in v1.2 (deferred — would matter only for classifier evolution, which is v1.3+).

### Frozen-surface mechanics

- **D-10 — Prompt in a separate file.** The Haiku instruction text lives at `lab/pel/classifier/prompt.md`, mirroring the `agent-bouncer/templates/` pattern. Prompt-as-reviewable-asset rather than string-literal-in-code. The adapter reads and composes it at invocation time.
- **D-11 — Frozen status is path-based.** Phase 7's code-tier proposer must exclude `lab/pel/classifier/**` wholesale from its mutable-file allowlist. No banner comments, no `FROZEN.md` sentinel file — the allowlist is the single source of truth. (Banner comments get edited accidentally; path-based exclusion cannot be silently bypassed.) Phase 4 does not implement the allowlist; it just commits to living entirely within that directory boundary so Phase 7 has a clean glob to exclude.

### Claude's Discretion

- Exact prose of the Haiku classifier prompt (how the four flavors are described in instructions, whether to include few-shot examples, rationale-length cap) — researcher + planner decide after reading `.planning/notes/pel-design-decisions.md` §1.
- Prompt-cache anchor placement within `prompt.md` — stable portion (flavor definitions, instructions, output schema) should lead; variable portion (task + env-var values) trails. Planner detail.
- Exact adapter exit codes. Suggested: `0` success, `1` input-validation failure, `2` Haiku unreachable / auth / rate-limit, `3` malformed response. Planner may refine.
- Simulation test file location and layout — mirror `tests/lab-routing-simulation.sh` per-scenario-subshell pattern with `N/N scenarios passed` final line unless a Phase 4-specific need surfaces.
- Whether to publish a `lab/pel/README.md` now (documenting `PEL_*` env var contract and `CLASSIFIER_MODEL` escape hatch) or defer until Phase 5's proposer arrives. Recommend: write it now, since Phase 4 is the first `lab/pel/` inhabitant and documenting the env var contract here is the best place.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design spec (binding — the Haiku prompt derives from this)

- `.planning/notes/pel-design-decisions.md` §1 "Multi-flavor fitness" — the four flavor definitions. Prompt content descends from here.
- `.planning/notes/pel-design-decisions.md` §2 "Specialization across BOTH layers" — why `bounce_step` × `phase_type` are the context axes.
- `.planning/notes/co-evolution-lab-concept.md` — lab-isolation boundary, sandbox guarantee (L-05). Classifier must not reach into runner internals.

### Project + milestone refs

- `.planning/ROADMAP.md` §Phase 4 — the 5 success criteria (SC-1 through SC-5) that every plan-acceptance must address.
- `.planning/REQUIREMENTS.md` §PEL-01 — requirement spec.
- `.planning/PROJECT.md` §Key Decisions rows: "Classifier frozen in v1.2", "Mode classifier auto-picks flavor with transparent reasoning + user override".

### Phase 3 integration (the contract this phase plugs INTO, not modifies)

- `lab/README.md` — W-3 single-argv contract, unknown-mode semantics, sandbox guarantee. Phase 4 must honor, not modify.
- `.planning/phases/03-lab-scaffold/03-CONTEXT.md` §Decisions — L-02, L-03, L-04, L-05 are load-bearing for Phase 4.
- `.planning/phases/03-lab-scaffold/03-02-SUMMARY.md` — `dispatch_lab_mode` call sites and the grep-anchored "single argv slot" comments at both dispatch sites. Phase 4's `entry.sh` becomes the target of exactly this dispatch path.
- `lib/co-evolution.sh` §"Lab routing (Phase 3 LAB-01)" (lines ~69-132) — `validate_lab_mode` / `list_available_lab_modes` / `dispatch_lab_mode`. `dispatch_lab_mode` resolves `lab/<mode>/entry.sh` and `exec`'s it with remaining argv.

### Analogous patterns (style mirroring)

- `agent-bouncer/templates/` directory structure — prompt-as-reviewable-file pattern. Mirror for `lab/pel/classifier/prompt.md`.
- `agent-bouncer/README.md` §Adapters — `invoke_<name>` function shape (prompt file, output file, stderr file). Self-contained classifier adapter should mirror the spirit.
- `tests/lab-routing-simulation.sh` (Phase 3 Plan 02) and `evals/tests/scorer-verification.sh` (Phase 2) — hermetic simulation-test style with per-scenario subshells and `N/N scenarios passed` final line.

### Env var precedents (shape the `PEL_*` convention mirrors)

- `lib/co-evolution.sh` lines 19-34 — `PHASE_TIMEOUT`, `LIVE_MODE`, `DEV_REVIEW_BRANCH`, `DEV_REVIEW_WORKTREE` defaults + docstrings. Follow the `: "${VAR:=default}"` pattern.
- `dev-review/codex/dev-review.sh` — `COMPOSER`, `EXECUTOR`, `REVIEWER`, `CODEX_MODEL`. Caller-sets-config-before-invocation convention.

### Platform-upgrade assumptions (treat as infrastructure, not stretch goals)

- `C:/Users/alan/.claude/projects/C--Users-alan-Project-co-evolution-lab/memory/future_tools.md` §§1+3 — Haiku 4.5 + prompt caching are PEL prerequisites. Classifier MUST structure `prompt.md` for cache-friendliness (stable system prompt ahead of variable inputs).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `dispatch_lab_mode` in `lib/co-evolution.sh` — Phase 4's `entry.sh` becomes the target of this `exec`. No work needed in `lib/` for the dispatch handshake; classifier just has to exist at `lab/pel/classifier/entry.sh`.
- `agent-bouncer/templates/` — proven pattern for prompt-as-file, not prompt-as-string-in-code. Directly reusable mental model for `lab/pel/classifier/prompt.md`.
- Simulation-test harness pattern from Phase 2 + Phase 3 — per-scenario subshell, `TOTAL`/`FAILURES` counters, `pass`/`fail` helpers, trap-based cleanup, `N/N scenarios passed` final line.

### Established Patterns

- **"Env var for caller-sets-config, argv for the-thing-being-worked-on"** — D-02 extends this, doesn't violate it.
- **Self-contained lab inhabitants with path-based isolation** — Phase 3 L-05 + Phase 4 D-05/D-11 compose into a clean story: `lab/pel/classifier/**` is both the inhabitant's physical location AND the Phase 7 allowlist-exclusion glob.
- **Fail-fast with specific error text** — Phase 2 `--runner-path` and Phase 3 `dispatch_lab_mode` both die with exact messages on invalid input. Classifier adapter follows suit (D-07).
- **Flag-doc / contract-doc co-location** — Phase 2 pinned `--runner-path` docs in `evals/README.md`; Phase 3 pinned `--lab` docs in `dev-review/codex/README.md` + `lab/README.md`. Phase 4 should pin `PEL_*` env var contract in `lab/pel/README.md` (or `lab/pel/classifier/README.md`).

### Integration Points

- **Dispatch handshake:** `dispatch_lab_mode "pel" "$REPO_ROOT/lab" "$TASK"` → `exec bash lab/pel/classifier/entry.sh "$TASK"` — the Phase 3→4 contract. (Or `dispatch_lab_mode "pel-proposer" ...` once Phase 8 exists; the classifier itself may not be the primary lab mode, but is reachable for debugging via a dedicated mode or direct invocation.)
- **Caller contract for Phases 5-8:** the proposer must `export PEL_BOUNCE_STEP=... PEL_PHASE_TYPE=...` before invoking the classifier. Document this in the `lab/pel/README.md` env var contract section.
- **Phase 7 allowlist anchor:** `lab/pel/classifier/**` is a MUST-NOT-MUTATE glob. Phase 7 enforces; Phase 4 guarantees the directory boundary contains all classifier code (including `adapter.sh`, `prompt.md`, `entry.sh`, any helpers).

### Non-obvious risks

- **Env var stickiness.** If a human developer sets `PEL_BOUNCE_STEP=compose` at a shell prompt and forgets to unset, a later manual `bash lab/pel/classifier/entry.sh "task"` invocation inherits stale context. Mitigation: the proposer that launches the classifier (Phases 5-8) sets the vars explicitly per call, never inheriting from user shell. Document this in the env var contract.
- **Stdout/stderr discipline.** The `claude -p` CLI and any auth-layer diagnostics can leak to stdout. Adapter must redirect Haiku stderr to its own stderr, capture Haiku stdout separately, and validate it is pure JSON before emitting. Otherwise the JSON output contract (D-08) is brittle.
- **Prompt cache invalidation on prompt edit.** Since the classifier is frozen for v1.2, this shouldn't happen mid-milestone. But a future milestone that modifies `prompt.md` invalidates the cache — document the cost so the milestone-kickoff author knows.
- **Argv-injection surface from `$TASK`.** The classifier's `$1` is untrusted user input (the task string). Phase 3's `validate_lab_mode` regex protects the mode token, but the task string itself is passed verbatim to the Haiku prompt. Adapter must ensure the task string is incorporated into the prompt body as a data field, never concatenated into a shell command. (Standard LLM-input-hygiene, but worth pinning.)

</code_context>

<specifics>
## Specific Ideas

- **User preamble (2026-04-18):** "The pattern-carrying argument is real but weaker than it looks — SUMMARY.md files capture it explicitly. That's their job." Decides D-01. The classifier does not carry patterns between runs; `.planning/phases/**/SUMMARY.md` is the explicit between-runs mechanism, and human curation is what lifts patterns into a future classifier prompt update (when the classifier unfreezes in v1.3+).
- **"What we've been doing" pattern analysis** is the decisive argument for env vars (D-02): 5 existing precedents in this codebase use env vars for caller-level config. Option B (sourced library function) would introduce a second kind of lab inhabitant (sourced rather than exec'd), splitting the Phase 3 dispatch model. Option C (bend W-3 to multi-argv) would undo the grep-anchored pin shipped in Phase 3 Plan 02 two days ago and widen the argv surface for every future lab inhabitant.
- **JSON output example in D-08** is the ship, not a suggestion. Phase 8's PR-body emitter will parse exactly these fields. The `inputs` object exists so a PR body can show "classifier was given X, picked Y, because Z" with zero ambiguity for the human reviewer.
- **`--flavor` bypass decision (D-09)** — chose "fully bypass Haiku" over "run-and-log-for-comparison" because v1.2 has no consumer for the comparison data (classifier is frozen — no evolution signal to feed). Revisit in v1.3+ if PEL-META-01 goes on the roadmap.
- **Frozen-status via path, not banner (D-11)** — comments in code can be edited accidentally during a refactor; path-based allowlists cannot be silently bypassed. The allowlist IS the enforcement mechanism; comments would be decoration.

</specifics>

<deferred>
## Deferred Ideas

- **Run-and-log-for-comparison when `--flavor` fires** — pointless in v1.2 (frozen classifier has no evolution signal to benefit from the data). Becomes valuable if/when classifier evolution (PEL-META-01) reaches the roadmap.
- **Dedicated `--model` CLI flag on the classifier** — env var escape hatch (D-06) covers the debugging case. Dedicated flag is ergonomic polish, deferred to post-v1.2.
- **Prompt cache hit/miss telemetry** — `future_tools.md` already assumes caching works; instrumentation to verify is useful but not shipping-blocking. Defer to a v1.2.1 or v1.3 ergonomics pass.
- **Classifier evolution (PEL-META-01 per REQUIREMENTS.md §Future)** — explicitly v1.3+. Classifier is frozen in v1.2; any evolution proposal must cleanly separate protocol improvement from classifier changes (attribution-muddiness risk named in `pel-design-decisions.md` §"Open risks").
- **Multi-inhabitant lab patterns** (sourced libraries vs exec'd entries) — Phase 4 sticks with the Phase 3 exec'd-entry pattern. A future lab inhabitant with a genuinely different need is its own design phase.

*No folded todos — all Phase 4 inputs were covered by the prior context load (ROADMAP, PROJECT, REQUIREMENTS, Phase 3 artifacts, `pel-design-decisions.md`, `co-evolution-lab-concept.md`, user preamble on statelessness). No pending todos matched Phase 4 scope.*

</deferred>

---

*Phase: 04-mode-classifier-frozen*
*Context gathered: 2026-04-18*
