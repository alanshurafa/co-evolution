# Phase 6: Policy-Tier Mutation Proposer - Context

**Gathered:** 2026-04-18
**Status:** Ready for planning
**Source:** Delegated-autonomous (CLAUDE.md Express — ROADMAP SC-1..SC-4 + pel-design-decisions.md §§1,3 + Phase 4/5 precedents)

<domain>
## Phase Boundary

Build `lab/pel/proposer/policy/` — the **policy-tier mutation proposer**. Second of three proposer tiers. Given eval-feedback + current policy file + a flavor pick, produces a structured **delta** (single knob or small coherent set) to an enumerated policy surface (YAML/JSON file). The delta applies deterministically via `jq`/`yq` and the resulting policy stays within documented bounds.

In scope:
- `lab/pel/proposer/policy/proposer.sh` — public entry point
- `lab/pel/proposer/policy/adapter.sh` — self-contained Haiku-4.5 adapter (policy mutations are simpler than templates; Haiku is enough)
- `lab/pel/proposer/policy/prompt.md` — mutation-proposer prompt (enumerated knob list + bounds + flavor-aware bias)
- `lab/pel/proposer/policy/policy.yaml` — **the policy surface itself** (NEW file) — enumerated mutable knobs with types and bounds
- `lab/pel/proposer/policy/bounds.jq` — bounds-validation jq program used by proposer and simulation
- `tests/policy-proposer-simulation.sh` — hermetic simulation covering SC-4
- `tests/fixtures/policy-feedback/*.json` — synthetic eval-feedback fixtures (3-4 scenarios)

Out of scope (explicit):
- Template-tier proposer (Phase 5 — parallelizable, non-overlapping file set)
- Code-tier proposer (Phase 7)
- PR emission / scoring loop (Phase 8)
- Applying the delta to live `.planning/config.json` or similar — the proposer emits a delta; applying to live state is Phase 8's PR-flow problem
- Inventing new knobs — knob set is locked in D-03 below (derived from pel-design-decisions.md §3 + PROJECT.md)

</domain>

<decisions>
## Implementation Decisions

### Policy surface (the mutable file)

- **D-01 — Policy file at `lab/pel/proposer/policy/policy.yaml`.** New YAML file. Not an extension of `.planning/config.json` (that's GSD workflow config, different concern). Clean separation: policy is PEL's runtime knobs; config is GSD's orchestration.
- **D-02 — YAML over JSON** for the policy file itself. Human-editable, supports comments documenting each knob's purpose + bounds. Proposer emits delta as JSON (simpler for jq/yq tooling) but the file on disk is YAML.
- **D-03 — Enumerated mutable knobs (from pel-design-decisions.md §3 + PROJECT.md):**
  - `retry_cap` — int, bounds [0, 10]. How many retries on transient failures.
  - `marker_semantics` — enum `{strict, lax}`. Whether `[CONTESTED]` / `[CLARIFY]` markers require exact-string match or fuzzy match.
  - `writable_phase_default` — bool. Default posture for unknown phase names (safer = false).
  - `arbitrate_threshold` — float, bounds [0.0, 1.0]. Confidence needed to arbitrate without another bounce.
  - `max_passes` — int, bounds [1, 10]. Maximum bounce passes before giving up.
  - `flavor_weights` — object `{bug_catcher: float, faster_converger: float, blind_spot_surfacer: float, general: float}`, each ∈ [0.0, 1.0], sum ∈ [0.95, 1.05]. Probabilistic weights when classifier is uncertain.
  - **These are the ONLY mutable knobs in v1.2. Adding new knobs is a new phase.** The proposer MUST NOT mutate any field not in this list.

### Lab isolation & invocation surface

- **D-04 — Lives under `lab/pel/proposer/policy/`** (parallel to Phase 4's classifier and Phase 5's template proposer). Self-contained adapter, same posture as Phase 4/5.
- **D-05 — Invocation: argv + env vars.** Task string via `$1` (optional hint). Non-task inputs via env vars:
  - `PEL_FEEDBACK` — path to eval-feedback JSON (required)
  - `PEL_POLICY_PATH` — path to policy YAML file to mutate (typically `lab/pel/proposer/policy/policy.yaml` but parameterized for testing)
  - `PEL_FLAVOR` — one of 4 flavor names (required)
  - `POLICY_PROPOSER_MODEL` — optional override (default `claude-haiku-4-5-20251001`)
- **D-06 — Missing required env var → die.** Same posture as Phase 5: caller-bug, fail clearly.

### LLM call path

- **D-07 — Haiku 4.5 default** (`claude-haiku-4-5-20251001`). Rationale: policy mutations are simpler than template mutations (pick a knob + a value from enumerated options, not free-form generation). Haiku handles it; Opus would be overkill.
- **D-08 — Self-contained adapter.** Same Phase 4/5 pattern. No dependency on runner internals.
- **D-09 — Fail-fast on claude call failure.** Standard posture.

### Output format

- **D-10 — JSON delta to stdout.** Shape:
  ```json
  {
    "mutations": [
      {"key": "retry_cap", "old": 3, "new": 5}
    ],
    "rationale": "Eval feedback shows transient failures; raising retry cap.",
    "flavor": "faster-converger",
    "policy_path": "lab/pel/proposer/policy/policy.yaml"
  }
  ```
  Multi-knob deltas permitted (up to 3 in v1.2 — single coherent knob set, e.g., both `retry_cap` and `max_passes` to relax retry posture). Mutations array is ordered — Phase 8 applies in order.
- **D-11 — Deterministic application via jq/yq.** Proposer emits delta; caller (Phase 8) applies with `yq -i '.retry_cap = 5' policy.yaml` pattern. The proposer does NOT modify the live policy file — it only emits the delta. Dry-run by construction.

### Bounds & validation

- **D-12 — Bounds enforced in two places:**
  1. **Prompt instructs the LLM** about bounds for each knob. Reduces bad proposals.
  2. **Proposer validates delta against bounds** before emitting. Uses `bounds.jq` program. If any proposed value out of bounds, die exit 4 (bounds violation). This catches LLM drift.
- **D-13 — `bounds.jq` is a reviewable asset.** Codifies the knob bounds from D-03 as a jq filter that returns exit 0 (valid) or exit 1 (violation) given a proposed delta. Used by proposer runtime AND simulation test. Single source of truth for bounds.
- **D-14 — flavor_weights sum constraint is a soft bound** (sum ∈ [0.95, 1.05]). Allows small rounding; proposer validates via jq `add` + abs-diff-from-1 < 0.05.

### Prompt architecture

- **D-15 — Prompt in separate file** (`prompt.md`) — mirrors Phase 4/5 precedent. Stable header (knob list + bounds + output schema + flavor definitions) ahead of variable tail (current policy YAML content + eval feedback).
- **D-16 — Prompt encodes flavor bias:** same 4 flavors as Phase 4/5.
  - `bug-catcher`: lower retry_cap (fail fast on latent issues)
  - `faster-converger`: lower max_passes, higher arbitrate_threshold (exit earlier)
  - `blind-spot-surfacer`: higher max_passes, strict marker_semantics (catch more)
  - `general`: balanced; nudge one knob at a time

### Simulation

- **D-17 — Hermetic with PATH-stubbed claude CLI.** Same pattern as Phase 4/5. Stub returns canned deltas per scenario.
- **D-18 — Fixture strategy.** `tests/fixtures/policy-feedback/*.json` holds 3-4 synthetic eval-feedback reports. Each targets a different knob (retry failure → retry_cap; convergence slow → max_passes; etc.).
- **D-19 — Simulation scenarios (SC-4):**
  - 4 scenarios: one per flavor, each produces a valid delta within bounds, each passes jq-apply to a test-copy of policy.yaml
  - 1 scenario: out-of-bounds delta (LLM drift) → rejected with exit 4
  - 1 scenario: mutation targeting non-enumerated knob (e.g., `"key": "secret_flag"`) → rejected with exit 5
  - 1 scenario: malformed JSON delta (missing required field) → rejected with exit 3
  - 1 scenario: missing required env var → rejected with exit 1
  - Final line: `8/8 scenarios passed` (v1.2 gate-footer convention)

### Claude's Discretion

- Exact prose of `prompt.md`.
- Whether to ship 3 or 4 eval-feedback fixtures.
- Exact bounds.jq syntax (choice of jq idioms).
- Whether to support `PEL_POLICY_PATH=-` for stdin input (deferred to post-v1.2).
- Default filename for the policy file (`policy.yaml` vs `knobs.yaml`) — recommend `policy.yaml`.
- Exit code numbering beyond the 5 listed above.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design spec (binding)
- `.planning/notes/pel-design-decisions.md` §3 "Mutable surface = templates + policy + code" — enumerates the policy knobs. D-03 descends directly.
- `.planning/notes/pel-design-decisions.md` §1 "Multi-flavor fitness" — 4 flavor definitions. D-16 descends.
- `.planning/notes/co-evolution-lab-concept.md` — lab-isolation principle.

### Project + milestone refs
- `.planning/ROADMAP.md` §Phase 6 — 4 success criteria.
- `.planning/REQUIREMENTS.md` §PEL-03.
- `.planning/PROJECT.md` Key Decisions: "Mutable surface = templates + policy + code".

### Phase 4 + Phase 5 integration (parallel sibling patterns)
- `.planning/phases/04-mode-classifier-frozen/04-CONTEXT.md` — adapter + prompt + env-var + simulation patterns. Reuse structure.
- `.planning/phases/05-template-tier-proposer/05-CONTEXT.md` — sibling proposer, different mutation tier. Reuse structural decisions where applicable (D-05 env var invocation; D-17 hermetic simulation).
- `lab/pel/classifier/` shipped code — reference implementation for lab isolation.

### Phase 2 integration (eval harness feedback is the input)
- `evals/score-run.sh` — JSON shape for eval feedback. Policy feedback fixtures mirror this.
- `.planning/phases/02-bash-eval-harness-port/02-03-SUMMARY.md` — scorer output schema.

### Analogous patterns
- `lab/pel/classifier/classifier.sh` + `adapter.sh` + `prompt.md` — structural template.
- `tests/classifier-simulation.sh` — simulation harness structure.
- `evals/tests/scorer-verification.sh` — PATH-stub CLI pattern.

### Tooling references
- `jq` is already an established dependency (Phase 2 scorer uses it extensively).
- `yq` — needs to be assumed available. Both Git Bash for Windows and Linux can install it; macOS `brew install yq`. Add to `require_tools` check in proposer.sh.

### Platform assumptions
- `C:/Users/alan/.claude/projects/C--Users-alan-Project-co-evolution-lab/memory/future_tools.md` — Haiku 4.5 + prompt caching assumed.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lab/pel/classifier/adapter.sh` — adapter shape template. Clone and customize for JSON-delta output.
- `lab/pel/classifier/prompt.md` — prompt-as-file template.
- `tests/classifier-simulation.sh` — simulation harness structure.
- `evals/lib/co-evolution-evals.sh` — YAML helper library from Phase 2. Reusable for policy.yaml loading in the simulation test (one exception to the "self-contained lab" rule: tests may use shared test-helpers).
- `evals/score-run.sh` — JSON schema for feedback.

### Established Patterns
- **Enum + bounds as a prompt instruction AND code validation** — belt-and-suspenders. Same structure as Phase 5 D-15 (single-file constraint).
- **jq for deterministic JSON operations** — Phase 2 established jq as the go-to tool. Phase 6 extends with yq for the YAML side.
- **PATH-stubbed claude CLI for hermetic tests** — Phase 4 + Phase 5.
- **`N/N scenarios passed` final-line gate** — v1.2 convention.

### Integration Points
- **Phase 8 invokes this proposer** alongside the template proposer. Phase 8's PR body combines deltas from both proposers (template-diff + policy-delta) into a single PR.
- **Phase 4 classifier output feeds `PEL_FLAVOR`** — same as Phase 5.
- **Phase 2 eval harness output feeds `PEL_FEEDBACK`** — same mechanism as Phase 5's `PEL_EVAL_REPORT`.

### Non-obvious risks
- **Knob coupling.** Changing `retry_cap` without thinking about `max_passes` can produce incoherent policy (e.g., retry_cap > max_passes means retries beyond the pass budget). Multi-knob mutations per D-10 let the LLM mutate coherent sets. Single-knob is also allowed.
- **yq dialect variance.** Several `yq` tools exist (Kislyuk's Python-yq wrapping jq, Mike Farah's Go yq). They use different syntax. Decide which and pin in docs. Recommend Mike Farah's Go yq (widely available, newer syntax — `.key = value`).
- **Bounds drift between prompt and code.** The prompt lists bounds; the code checks bounds. If they diverge, the LLM might produce "valid per prompt but invalid per code" deltas. `bounds.jq` is the single source — generate the prompt's bounds section from it (optional, deferred) or keep a frontmatter comment cross-referencing.
- **flavor_weights sum-to-1 soft bound.** Floating-point arithmetic is fragile. `sum ∈ [0.95, 1.05]` gives slack. Don't require exact 1.0.

</code_context>

<specifics>
## Specific Ideas

- **Start with single-knob mutations in v1.2.** Multi-knob (up to 3) is permitted by schema but the prompt should bias toward single. Phase 8 data will show whether multi-knob is useful; if rarely used, narrow to single in v1.3.
- **Bounds.jq is documentation-as-code.** Anyone wanting to know "what's the valid range of retry_cap?" reads `bounds.jq`. Single source. Prompt references it by path.
- **Policy file hand-editable.** Humans can edit `policy.yaml` directly between PEL runs. PEL proposes mutations; humans accept via PR merge. Both mechanisms coexist.

</specifics>

<deferred>
## Deferred Ideas

- **Adding new knobs beyond the 6 in D-03** — each new knob is its own phase (review bounds, test coverage, etc.). v1.3+ territory.
- **Multi-file policy mutations** (e.g., split policy across multiple YAML files) — not needed in v1.2 with 6 knobs.
- **Coupled-knob constraint validation** (retry_cap <= max_passes) — useful but deferred to v1.2.1. D-12 bounds are per-knob only.
- **YAML comment preservation on apply** — yq can strip comments. Deferred; if it becomes a UX issue, switch to yq-with-comments or implement a custom round-tripper.
- **Policy evolution tracking** (which knobs got mutated how often) — telemetry, deferred.
- **Auto-apply deltas to live policy.yaml** — NO. v1.2 Option 1 = human review gate. Phase 8 emits PR with delta; human merges.

*No folded todos — scope fully covered by ROADMAP SC-1..4 + pel-design-decisions.md §3.*

</deferred>

---

*Phase: 06-policy-tier-proposer*
*Context gathered: 2026-04-18 via delegated-autonomous CLAUDE.md Express*
