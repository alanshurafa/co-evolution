# Phase 7: Code-Tier Mutation Proposer - Context

**Gathered:** 2026-04-18
**Status:** Ready for planning
**Source:** Manual discuss-phase (CWD workaround) — ROADMAP SC-1..SC-5 + pel-design-decisions.md §§3,5 + phase-7-simulation-lessons.md + Phase 4/5/6 precedents

<domain>
## Phase Boundary

Build `lab/pel/proposer/code/` — the **code-tier mutation proposer**. Third and hardest of three proposer tiers. Given eval-failure feedback + a target code file + a flavor pick, proposes a **unified diff** against `lib/co-evolution.sh` or runner paths (`dev-review/codex/dev-review.sh`, `agent-bouncer/agent-bouncer.sh`). LLM-only (random mutation of shell produces syntax errors — not a choice, a constraint from pel-design-decisions.md §3).

**What makes Phase 7 different from Phases 5/6:** The mutation target is executable code, not text templates or YAML config. A bad mutation doesn't just produce a bad diff — it breaks the runner. Phase 7 ships three capabilities that Phases 5/6 didn't need:

1. **Sandbox isolation** — mutation applied in a git worktree, never the live checkout
2. **Canary smoke-test suite** — runs AFTER mutation, BEFORE eval scoring; rejects broken runners
3. **Diff budget + file allowlist** — caps blast radius; prevents mutation of frozen/protected paths

In scope:
- `lab/pel/proposer/code/proposer.sh` — public entry point (sandbox setup, allowlist gate, diff budget gate, canary orchestration, state.json emission)
- `lab/pel/proposer/code/adapter.sh` — self-contained Opus-4.7 adapter (prompt composition + claude CLI invocation + diff capture)
- `lab/pel/proposer/code/prompt.md` — mutation-proposer prompt (code-tier-specific: shell-aware, flavor-biased, budget-aware, safety-aware)
- `lab/pel/proposer/code/canary.sh` — canary smoke-test suite (5 scenarios: source-survives, helper-signatures, agent-bounce, dev-review-plan-only, one-eval-case)
- `lab/pel/proposer/code/allowlist.txt` — explicit file allowlist (one path per line; the enforcement mechanism for frozen-surface + protected-path invariants)
- `tests/code-proposer-simulation.sh` — hermetic simulation covering SC-5 (≥15 scenarios: 4 flavor happy-paths + 5 text-pipeline edge cases + 5 canary scenarios + 5 adversarial rejections — from phase-7-simulation-lessons.md)
- `tests/fixtures/code-feedback/*.json` — synthetic eval-failure fixtures targeting code-tier improvements
- `lab/pel/README.md` extension — code-tier proposer contract documentation
- `state.json` written to sandbox worktree root (canary result + eval delta + exit category for Phase 8)

Out of scope (explicit):
- Template-tier proposer (Phase 5 — shipped)
- Policy-tier proposer (Phase 6 — shipped)
- PR emission / scoring loop (Phase 8 — consumes Phase 7's state.json)
- Scoring the proposed diffs (proposer runs canary only; eval scoring is Phase 8's pipeline)
- Multi-file mutations (v1.2 constraint: exactly one file per invocation, same as Phases 5/6)
- Running real LLM eval scoring (canary runs one eval case for smoke-test only; full scoring is Phase 8)
- Auto-merging or applying mutations to the live checkout

</domain>

<decisions>
## Implementation Decisions

### Sandbox isolation

- **D-01 — Sandbox via `git worktree add`.** Uses git's worktree mechanism for isolation. Fast (shares .git object store, ~instant setup). The codebase already has worktree management patterns in `lib/co-evolution.sh`. Mutation is applied in the worktree; if canary fails, remove the worktree. Shared .git means no accidental push from sandbox. Fail-closed: if `git worktree add` fails, the proposer dies immediately (never falls back to mutating the live checkout).
- **D-02 — Worktree created at `$TMPDIR/pel-code-sandbox-XXXXXX`.** Uses `mktemp -d` for the path, then `git worktree add <path> HEAD` to create a detached-HEAD worktree from current state. Cleanup via `git worktree remove --force <path>` in a trap handler. If cleanup fails (e.g., process killed), the worktree is orphaned but harmless — `git worktree prune` in future runs or manual cleanup resolves it.
- **D-03 — Mutation applied via `git apply` in the sandbox worktree, not the live checkout.** The proposer `cd`s into the sandbox worktree before applying. All subsequent operations (canary, eval) run inside the sandbox. The live checkout is never modified.

### File allowlist + diff budget

- **D-04 — Explicit allowlist in `lab/pel/proposer/code/allowlist.txt`.** One relative path per line. Only files on this list may be targets of a code-tier mutation. v1.2 allowlist:
  ```
  lib/co-evolution.sh
  dev-review/codex/dev-review.sh
  agent-bouncer/agent-bouncer.sh
  ```
  Adding new files to the mutable surface is a deliberate act (edit the allowlist file, commit, review). The allowlist IS the frozen-surface enforcement mechanism — `lab/pel/classifier/**`, `.planning/**`, `tests/**`, `.gitignore` are excluded by absence, not by a denylist.
- **D-05 — Allowlist checked BEFORE sandbox application.** After the LLM emits a diff, the proposer parses `--- a/` and `+++ b/` headers, extracts target paths, and checks each against the allowlist. Any non-allowlisted path → die exit 5 (allowlist violation). This check happens BEFORE `git apply` — a diff targeting a frozen file never touches the sandbox.
- **D-06 — Diff budget = 20 lines changed.** "Lines changed" = count of lines starting with `+` or `-` in the unified diff body (excluding `---`/`+++` header lines and `@@` hunk headers). A line changed = 1 toward budget (a rewrite = 1 removal + 1 addition = 2). Budget checked BEFORE sandbox application. Exceeded → die exit 6 (budget exceeded).
- **D-07 — Budget and allowlist are pre-flight gates.** Both checked after LLM response, before `git apply`, before canary. Order: (1) parse diff headers → (2) allowlist check → (3) budget check → (4) `git apply --check` dry-run → (5) `git apply` in sandbox → (6) canary.

### Canary smoke-test suite

- **D-08 — Canary as a separate script `lab/pel/proposer/code/canary.sh`.** Invoked by `proposer.sh` after mutation is applied in the sandbox. Receives the sandbox worktree path as `$1`. Runs 5 scenarios sequentially (any failure = canary-failed, abort immediately). Reuses the PATH-injection stub pattern from Phases 4-6 for hermetic agent stubs.
- **D-09 — Canary scenarios (5 required, from phase-7-simulation-lessons.md §canary):**
  1. **Source-survives:** `bash -n lib/co-evolution.sh` + `source lib/co-evolution.sh` without error. Catches syntax errors.
  2. **Helper-signatures:** Mutated file still exports `validate_lab_mode`, `dispatch_lab_mode`, `phase_is_writable`, `list_available_lab_modes` (grep for function definitions). Catches renames or deletions.
  3. **Agent-bounce end-to-end:** `agent-bouncer/agent-bouncer.sh` with canned task + stubbed claude/codex (PATH-injected). Verify exit 0 + expected artifact structure.
  4. **Dev-review plan-only:** `dev-review/codex/dev-review.sh --plan-only <task>` with stubbed agents. Catches mutations that break phase-specific logic.
  5. **One eval case:** A fixed deterministic fixture from `evals/cases/` runs to completion. The canary's job is "did the runner survive?", not "did scores improve?" — score comparison is Phase 8's responsibility.
- **D-10 — Canary exit codes are distinct from proposer exit codes.** Canary returns: 0 = all 5 passed, 1 = source-survives failed, 2 = helper-signatures failed, 3 = agent-bounce failed, 4 = dev-review failed, 5 = eval-case failed. Proposer translates canary non-zero to proposer exit 7 (canary-failed) and logs which canary scenario failed.

### LLM call path

- **D-11 — Opus 4.7 default** (`claude-opus-4-7`). Code mutations against shell scripts require high reasoning quality. A bad mutation wastes an entire canary + eval cycle. Same rationale as Phase 5's template proposer. Overrideable via `CODE_PROPOSER_MODEL` env var (same escape-hatch pattern as `PROPOSER_MODEL` and `POLICY_PROPOSER_MODEL`).
- **D-12 — Self-contained adapter** in `lab/pel/proposer/code/adapter.sh`. Same Phase 4/5/6 pattern. Zero dependency on runner internals or `lib/co-evolution.sh`. The adapter sources only its sibling files.
- **D-13 — Prompt in separate file** (`prompt.md`). Code-tier-specific framing: the prompt instructs the LLM to produce shell-safe mutations, respect the diff budget (N=20), target only the specified file, and bias toward the flavor's focus. Cache-friendly ordering: stable instructions + flavor definitions ahead of variable content (eval report + current file content + target path).
- **D-14 — Fail-fast on claude call failure.** Standard posture from Phases 4-6.

### Lab isolation & invocation surface

- **D-15 — Lives under `lab/pel/proposer/code/`** (parallel to template/ and policy/). Self-contained per the lab-inhabitant pattern.
- **D-16 — Invocation: argv + env vars.** Task string via `$1` (optional hint). Non-task inputs via env vars:
  - `PEL_CODE_FEEDBACK` — path to eval-failure JSON (required)
  - `PEL_CODE_TARGET` — relative path to the file to mutate (required; must be on allowlist)
  - `PEL_FLAVOR` — one of 4 flavors (required)
  - `CODE_PROPOSER_MODEL` — optional override (default `claude-opus-4-7`)
- **D-17 — Missing required env var → die exit 1.** Same posture as Phases 5/6: caller-bug, fail clearly.
- **D-18 — Task hint via $1 is optional.** If empty, proposer uses only the eval-failure report + current file content. If present, coarse bias only — flavor wins on conflict.

### Output contract

- **D-19 — Unified diff to stdout on success (exit 0).** Same as Phase 5. The diff has already passed canary in the sandbox. All diagnostics go to stderr.
- **D-20 — state.json written to sandbox worktree root.** Contains:
  ```json
  {
    "outcome": "accepted|canary-failed|eval-regressed|budget-exceeded|allowlist-violation",
    "exit_code": 0,
    "target": "lib/co-evolution.sh",
    "flavor": "bug-catcher",
    "diff_lines": 14,
    "diff_budget": 20,
    "canary": {"passed": true, "scenarios": 5, "failed_at": null},
    "sandbox_path": "/tmp/pel-code-sandbox-XXXXXX",
    "timestamp": "2026-04-18T12:00:00Z"
  }
  ```
  Phase 8's PR emitter reads this before sandbox cleanup.

### Exit codes

- **D-21 — Exit code taxonomy:**

  | Code | Meaning |
  |------|---------|
  | 0 | Success — unified diff emitted to stdout, canary passed, state.json written |
  | 1 | Input validation failure (missing env var, invalid PEL_FLAVOR, invalid model, path traversal) |
  | 2 | claude CLI missing / auth failure / Opus call non-zero / empty response |
  | 3 | Malformed diff — does not apply cleanly via `git apply --check` |
  | 4 | Single-file constraint violation — diff touches more than one file |
  | 5 | Allowlist violation — diff targets a file not on `allowlist.txt` |
  | 6 | Diff budget exceeded — mutation exceeds N=20 lines changed |
  | 7 | Canary failed — mutation applied but runner broke (state.json has details) |
  | 8 | Sandbox setup failed — `git worktree add` failed |

  Exit codes 5/6/7/8 are new to Phase 7 (Phases 5/6 had 0-4). They're load-bearing for Phase 8's PR emitter: 5/6 = pre-flight rejection (no sandbox touched); 7 = mutation tested and rejected; 8 = infrastructure failure.

### Simulation gate

- **D-22 — Hermetic with PATH-stubbed claude CLI.** Same Phase 4/5/6 pattern.
- **D-23 — Simulation scenarios (≥15 total, from phase-7-simulation-lessons.md).** Three categories:

  **Happy-path (4 scenarios — one per flavor):**
  - A: Flavor = bug-catcher → stub returns valid 1-file diff against lib/co-evolution.sh within budget. Assert exit 0 + stdout contains unified diff + state.json written with outcome=accepted.
  - B: Flavor = faster-converger → valid diff against dev-review/codex/dev-review.sh.
  - C: Flavor = blind-spot-surfacer → valid diff against agent-bouncer/agent-bouncer.sh.
  - D: Flavor = general → valid diff against lib/co-evolution.sh (different mutation).

  **Text-pipeline edge cases (5 scenarios — from phase-7-simulation-lessons.md §simulation):**
  - E: Diff with empty-line context marker (single space + newline). Prove capture preserves it.
  - F: Diff whose last line has no trailing newline. Prove trailing-newline recovery works.
  - G: Diff against CRLF-on-disk file. Prove `--whitespace=nowarn` or equivalent handles it.
  - H: Diff containing shell metacharacters (`$VAR`, backticks, heredoc markers, quoted strings). Prove capture→apply pipeline doesn't eval or misparse content.
  - I: Diff that `patch --dry-run` accepts but `git apply --check` rejects (known divergence). Prove consistent tool choice.

  **Adversarial rejections (≥6 scenarios):**
  - J: Diff targeting `lab/pel/classifier/adapter.sh` → exit 5 (allowlist violation, frozen-surface invariant from Phase 4).
  - K: Diff targeting `.planning/STATE.md` → exit 5 (planning integrity).
  - L: Diff targeting `tests/classifier-simulation.sh` → exit 5 (test integrity).
  - M: Diff exceeding 20-line budget → exit 6 (budget exceeded).
  - N: Diff touching 2 files → exit 4 (single-file constraint).
  - O: Missing required env var → exit 1 (PEL_CODE_FEEDBACK unset).
  - P: Canary failure — stub returns a diff that breaks `bash -n` → exit 7 (canary-failed).

  Final line: `N/N scenarios passed` (N ≥ 15; exact count set during planning).

### Claude's Discretion

- Exact prose of `prompt.md` — the LLM's code-mutation instructions. Must incorporate: shell-safety awareness, diff budget reminder (N=20), single-file constraint, flavor-bias framing from pel-design-decisions.md §1.
- Exact structure of eval-failure JSON fixtures — must match Phase 2's scorer output schema.
- Whether to ship 3, 4, or 5 code-feedback fixtures.
- Exact helper-function names to check in canary scenario 2 (grep from current `lib/co-evolution.sh` at plan time).
- Which eval case fixture to use for canary scenario 5 (pick the simplest/fastest).
- Whether `canary.sh` cleanup is self-contained or delegated to `proposer.sh`'s trap handler.
- Exact `git worktree add` flags (detached HEAD vs. branch-based).
- Whether state.json includes the raw diff text or just metadata (recommend: metadata only — diff is on stdout).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Binding design + safety notes
- `.planning/notes/phase-7-simulation-lessons.md` — **BINDING.** Simulation + canary requirements distilled from Phase 5's red-simulation session. Specifies: 5 text-pipeline edge cases for simulation, 5 canary scenarios, 5 adversarial rejection scenarios. Also documents the meta-lesson: "a plan whose verify blocks are all syntactic is NOT complete."
- `.planning/notes/pel-design-decisions.md` §3 "Mutable surface = templates + policy + code" — why code-tier is LLM-only (random mutation breaks shell).
- `.planning/notes/pel-design-decisions.md` §5 "Option 2 and Option 3 → graduate via lab/" — human-review Goodhart mitigation rationale. Phase 7's canary is a safety net, not a replacement for human review.
- `.planning/ROADMAP.md` §Phase 7 — SC-1 (sandbox isolation), SC-2 (canary smoke-test), SC-3 (diff budget + file allowlist), SC-4 (exit codes), SC-5 (simulation test).

### Phase precedents (pattern reuse)
- `.planning/phases/05-template-tier-proposer/05-CONTEXT.md` — D-05 self-containment, D-08 diff-to-stdout, D-09 single-file gate, D-10 git-apply-check, D-13 PATH-stub simulation. Phase 7 inherits these patterns.
- `.planning/phases/06-policy-tier-proposer/06-CONTEXT.md` — D-11 dry-run-by-construction, D-12 bounds enforcement, D-13 bounds.jq single-source-of-truth. Phase 7's allowlist.txt is the analog of bounds.jq.
- `lab/pel/proposer/template/proposer.sh` — reference implementation for the proposer entry-point pattern (env validation → path sandboxing → LLM call → gate checks → emit).
- `lab/pel/proposer/policy/proposer.sh` — reference implementation for bounds enforcement + jq/yq tooling.
- `tests/template-proposer-simulation.sh` — 8-scenario hermetic template; Phase 7's simulation mirrors this structure.
- `tests/policy-proposer-simulation.sh` — 8-scenario hermetic policy template; same inheritance.

### Project + milestone refs
- `.planning/PROJECT.md` — core value, constraints, key decisions, requirements cross-ref.
- `.planning/REQUIREMENTS.md` — PEL-04 is Phase 7's requirement (sandbox + canary + budget + allowlist + exit codes).
- `.planning/STATE.md` — current project state (Phase 6 shipped, Phase 7 ready to plan).

### Upstream code (mutation targets)
- `lib/co-evolution.sh` — 1064 LOC shared shell core. Primary mutation target. Exports: `validate_lab_mode`, `dispatch_lab_mode`, `list_available_lab_modes`, `phase_is_writable`, `log`, `die`, and ~30 other helpers.
- `dev-review/codex/dev-review.sh` — Codex runtime entry point. Secondary mutation target.
- `agent-bouncer/agent-bouncer.sh` — Agent bouncer entry point. Secondary mutation target.

### Lab contract
- `lab/pel/README.md` — PEL inhabitant contract (env-var contract, output contract, frozen-surface documentation). Phase 7 extends this with the code-tier proposer section.
- `lab/README.md` — lab conventions (W-3 argv contract, L-05 sandbox guarantee, L-06 graduation criteria).

</canonical_refs>
