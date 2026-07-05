# Workflow Upgrade Plan — Model Routing, Token Discipline, Tool Boundaries

**Date:** 2026-07-05 · **Planned on:** Fable 5 · **Execute on:** Opus sessions, one phase per PR
**Baseline:** master `14b684a` (v1.5 merged, CI green 3-OS) · **Branch:** `claude/vigilant-antonelli-32d5bc`
**Prerequisite:** this plan file is currently untracked. Before P0, commit it on the branch so every phase PR references a fixed revision; cite that commit SHA in each phase PR description.

## Inputs

1. Full repo audit (4 parallel agents + direct verification, 2026-07-05).
2. Anthropic Advisor tool docs (`platform.claude.com/docs/.../advisor-tool`, fetched 2026-07-05). Treated as manual research: the specific behaviors relied on are re-stated in the corrections table and must be reverified before any Advisor implementation (Backlog only for now).
3. X-sourced advice: model-ranking table + Codex plugin delegation pattern, treated as untrusted leads unless independently verified below.
4. A pasted "Co-Evolution Workflow Upgrade — Session Prompt" (third-party draft; verified below — partially stale).

---

## 1. Corrections to the input material (read before executing anything)

The pasted session prompt was written against a pre-v1.3 snapshot. Executing it as-is would redo finished work and chase phantom flags:

| Claim in pasted prompt / X advice | Reality (verified) |
|---|---|
| "Translator function duplicated in lib and dev-review.sh" (Phase 0 defect 1) | **Already fixed.** Single `normalize_path_for_bash` at `lib/co-evolution.sh:198`; `dev-review/codex/dev-review.sh:114` sources it. |
| "template-proposer-simulation.sh hardcodes absolute paths" (Phase 0 defect 2) | **Already fixed on master** (commit `cc4c907`); `REPO_ROOT` derived at `tests/template-proposer-simulation.sh:57`. 8/8 scenarios, worktree-safe. The branch `fix/template-proposer-worktree-portability` is byte-identical leftover. |
| "co-evolve-bouncer.sh --execute/--verify delegate via exec to dev-review.sh" | **Not on master** — there `--dev-review` is a `die "not yet implemented"` stub at `co-evolve-bouncer.sh:119`. The port **does exist on unmerged branch `claude/dev-review-port`** (commit `80b2aca`, 2026-07-02: +145 bouncer lines, +`tests/dev-review-handoff-simulation.sh`, 23/23 suites green per the skill doc). Action: merge, don't rebuild (P4.2). |
| Plugin ships skills `codex-implementation` / `codex-review` / `codex-computer-use`; `/codex:rescue` command | **Wrong names.** Real surface of `openai/codex-plugin-cc`: commands `/codex:review`, `/codex:adversarial-review`, `/codex:transfer`, `/codex:status`, `/codex:result`, `/codex:cancel`, `/codex:setup`; plus a `codex:codex-rescue` **subagent** (not a slash command). Review gate = a `Stop` hook toggled via `/codex:setup --enable-review-gate/--disable-review-gate`. |
| "gpt-5.5-codex" model; plugin defaults to 5.5/xhigh | `gpt-5.5-codex` **does not exist**. `gpt-5.5` is the intended Codex model. Alan's `~/.codex/config.toml` sets `model="gpt-5.5"`, `model_reasoning_effort="xhigh"`, but that is a local convenience, not a repo default. Treat `gpt-5.5` as the pinned model only after P1 adds an argv-level assertion (the model reaches `codex exec` as `-c model=gpt-5.5`) plus one manual smoke confirming the installed Codex CLI accepts it; if the smoke fails, pin the strongest documented model the CLI does accept. |
| Advisor tool: fable advice encrypted, opus readable; API-only | **Confirmed.** Beta header `advisor-tool-2026-03-01`, Messages-API-only (`type: advisor_20260301`); Fable 5 / Mythos 5 advisors return `advisor_redacted_result` (encrypted), Opus 4.8 returns readable `advisor_result`. Not reachable from `claude -p`, bash, or inside Claude Code. |
| Repo defects F-1/F-2/F-5a/F-6 pending | **All merged in v1.3 Phase 0** per `docs/audits/2026-06-10-v13-audit.md:22-31`. The `fix/*` branches are stranded duplicates. |

The pasted prompt's Phases 1–3 (routing / discipline / boundary) remain sound in intent and are adapted below. Its GSD framing is correct (`.planning/` is live, v1.5 currently `executing`, Phase 6 partial).

---

## 2. Audit findings register

Healthy and verified (no action): hermetic 24-sim suite + scorer 14/14 on 3-OS CI; auth-failure gating wired (`lib/co-evolution.sh:569-631`, refined by `deb4669`); deterministic bounce scoring auto-runs post-bounce (`co-evolve-bouncer.sh:684` → `evals/report-bounce.sh` → `score-bounce.sh`); `runners/codex-ps` frozen with zero live references; PEL opt-in only.

| ID | Sev | Finding | Where |
|----|-----|---------|-------|
| A-1 | LOW | Branch debris: 4 superseded branches present both locally and on origin (`feat/bounce-quality-scorer`, `fix/audit-phase-1-correctness`, `fix/f2-canonicalize-review-verdict`, `fix/template-proposer-worktree-portability`); plus origin-only `fix/bug-*` ×7 and `pel/*` ×3, 56–64 commits behind | git branches |
| A-2 | **HIGH** | Auth-gate blind spot: auth-error output **>50 words** passes `validate_agent_artifact` and is accepted as a document (the <50-word ceiling was an anti-false-positive heuristic) | `lib/co-evolution.sh:608-615` |
| A-3 | **HIGH** | Codex executor model **unpinned** in both presets — "model left to the CLI's config"; routing to gpt-5.5/xhigh works only because of Alan's local `config.toml`. Not reproducible across machines/agents | `dev-review/codex/dev-review.sh:160,166` |
| A-4 | **HIGH** | Document pipeline has zero per-role model/effort control; one global default hardcoded to outdated `claude-opus-4-6`; no effort CLI flags; no adjudicator role in code; alias resolver (`best/opus/fable`) exists only in dev-review.sh, not lib | `lib/co-evolution.sh:59`, `co-evolve-bouncer.sh:114-118`, `dev-review/codex/dev-review.sh:137-144` |
| A-5 | MED | "Markers auto-expire after 2 passes" (CLAUDE.md) is **not implemented** — MAX_BOUNCES=2 is a hard stop; unresolved markers persist; marker-count oscillation exits "not converged" with no escalation or forced adjudication | `co-evolve-bouncer.sh:638-642` vs `CLAUDE.md` Conventions |
| A-6 | MED | `--dev-review` stub on master; the port is already implemented on unmerged `claude/dev-review-port` (`80b2aca`, incl. 250-line handoff sim) — needs adversarial review + rebase + merge, not a build | `co-evolve-bouncer.sh:119`; branch `claude/dev-review-port` |
| A-7 | MED | No return-size contracts anywhere: verdict `summary`/`issues` unbounded; no output caps in any seat prompt | `skills/dev-review/schemas/review-verdict.json:19-22`, `dev-review/codex/dev-review.sh:393-411` |
| A-8 | LOW | Bounce-counterparty seat has no model/effort knob (globals only) | `dev-review/codex/dev-review.sh:1398` |
| A-9 | LOW | No pre-flight cost/budget estimate for presets; PEL's `--budget` preflight not wired to codex-build/claude-build | `dev-review/codex/dev-review.sh:107-108` |
| A-10 | LOW | LLM blind judge (`judge-bounce.sh`, defaults fable-5/high) reachable only manually or via calibrate; no `--judge` flag, no cadence | `evals/judge-bounce.sh:38`, `evals/calibrate-bounce.sh:74` |
| A-11 | LOW | Stale docs: CLAUDE.md marker-expiry claim; agent-bouncer still "primary executable" (`README.md:124`, `CLAUDE.md:47`, `AGENTS.md:59,133`); `AGENTS.md:71` claims hardcoded model (override exists); no v1.4/v1.5 status anywhere in CLAUDE.md; `.planning/codebase/CONCERNS.md` pre-v1.0 ("no CI") | as listed |
| A-12 | MED | Milestone loose ends: v1.5 Phase 6 dogfood evidence is degrade-path only (no happy-path ACCEPT run); v1.4 npm/MCP publish blocked on human (scope/NPM_TOKEN/tag); no v1.4/v1.5 git tags | `.planning/STATE.md:6,29-42` |
| A-13 | LOW | Codex plugin not installed; interactive-vs-pipeline boundary undocumented (prior decision exists: plugin = interactive only, ExoCortex #322778) | `~/.claude/plugins` |

---

## 3. The plan — six phases, one PR each

Sequencing: P0 → P1 → (P2 ∥ P3) → P4 → P5. P0–P3 are each single-session on Opus. All work happens on `claude/*` branches, PRs to master. **`runners/codex-ps/**` is untouchable in every phase.** All tests referenced are hermetic (stubbed CLIs) unless marked 💰.

### Phase 0 — Hygiene and the one real correctness hole (S)
1. **A-2 fix:** the auth gate currently accepts any auth-error output longer than 50 words as a valid document. Replace the length heuristic with a head-scan using a *strict* detector. Add a strict, anchored auth variant (auth-context banners only — `Not logged in`, `Please run /login`, `authentication_error`, `Failed to authenticate`, and equivalents — never a bare `Unauthorized` substring) and apply it to the first ~20 non-empty lines of agent output; keep the existing broad `file_contains_auth_failure` for stderr and empty-output fatal checks. New hermetic sims: a >50-word auth-error fixture must be rejected; a legitimate structured plan whose body contains an example "Unauthorized" must pass.
2. **A-1 cleanup:** produce a deletion manifest listing only the superseded branches — local **and their origin copies** for `feat/bounce-quality-scorer`, `fix/audit-phase-1-correctness`, `fix/f2-canonicalize-review-verdict`, `fix/template-proposer-worktree-portability`, plus origin-only `fix/bug-*` (×7) and `pel/*` (×3) — each with branch name, last commit, merged-to-master status, and the exact delete command. Safety rule: **only manifest-listed branches are deleted**; nothing else is touched — in particular no other `claude/*`, `archive/*`, `chore/*`, `codex/*`, or unlisted branch (several belong to other sessions). 🚧 gate: origin deletions listed for one-shot approval before push.
3. **A-11 doc corrections** (factual only): CLAUDE.md marker line reworded until A-5 ships ("bounce stops after MAX_BOUNCES=2; unresolved markers are reported, not auto-expired"); agent-bouncer demoted to "legacy runner (used by tests/experiments)"; `AGENTS.md:71` model claim fixed; CLAUDE.md gains a 3-line Status block (v1.4 publish pending, v1.5 Phase 6 partial); CONCERNS.md and STACK.md header-stamped as historical where they claim no CI.
- **Done means:** new auth sims green in 3-OS CI; the deletion manifest is approved and applied exactly, with no unlisted branch removed; grep for "auto-expire" in docs returns the corrected wording.

### Phase 1 — Model routing layer: code first, then CLAUDE.md (M)
1. **A-3:** presets pin the Codex seat explicitly: `codex-build` executor → `CODEX_MODEL=gpt-5.5`, `EXECUTOR_EFFORT=xhigh`; `claude-build` codex seats likewise. Still env/flag-overridable. `seat_models` in state.json shows a concrete model for every **preset** seat, never `(default)`; ad-hoc non-preset runs may still resolve `(default)`, and the docs state that cross-machine reproducibility is guaranteed only for presets.
2. **A-4:** move `resolve_claude_model_alias` into `lib/co-evolution.sh` as the single source (dev-review.sh consumes it); bump the base default `claude-opus-4-6` → alias `best` (resolves to `claude-opus-4-8` after a manual CLI smoke confirms the installed Claude CLI accepts it); update `tests/claude-model-override-simulation.sh` expectations. Add per-role seats to the document pipeline (`COMPOSER_MODEL/EFFORT`, `REVIEWER_MODEL/EFFORT` honored by `co-evolve-bouncer.sh`, mirroring `apply_seat_env`) with explicit per-seat flags `--composer-model/--composer-effort/--reviewer-model/--reviewer-effort`. There is no single global `--effort` flag — it would be ambiguous across two seats.
3. **A-8:** add `BOUNCER_MODEL/BOUNCER_EFFORT` env for the bounce counterparty in dev-review.sh, and include it in startup logs/state when the bounce seat resolves.
4. Add the **"Model Routing"** section to repo CLAUDE.md (§4 draft below).
- **Done means:** hermetic sims assert env propagation per seat (extend the existing seat sims); doc-pipeline run headers log resolved model@effort per role; preset state.json records concrete Codex model IDs; CLAUDE.md section merged.
- Note: `AGENTS.md`/README model references updated in the same PR.

### Phase 2 — Token discipline (S)
1. Add the **"Token Discipline"** section to CLAUDE.md (§5 draft below).
2. Enforce where the output is structured, not just in prose. The review-verdict schema gains machine-checkable caps (`issues.maxItems: 5`; bounded `summary`/`description`/`suggestion` lengths); an oversized or cap-violating verdict is treated as unusable verifier output (rejected/normalized, never passed downstream). Prompt templates carry the matching guidance as a backstop: verifier `summary` ≤40 words and ≤5 one-line `issues` with file:line; composer/plan templates cap the plan at ≤120 lines. `skills/codex-build/SKILL.md` gate instructions require status-first review via `dev-review-status.sh --json`.
3. Optional (fold in if trivial): wire PEL's `--budget` preflight estimate into presets as an informational line (A-9).
- **Done means:** templates in `skills/dev-review/templates/` carry the limits; `review-verdict.json` enforces max issue count and practical string bounds; a bounce/verify sim asserts the limit text reaches the prompt and the schema rejects an oversized verdict; CLAUDE.md merged.

### Phase 3 — Interactive vs pipeline boundary + Codex plugin (S)
This phase ships **only docs** as the PR; the plugin install is a manual post-merge checklist item for Alan (CI cannot verify a user-level plugin install).
1. **Repo PR (CI-verifiable):** add the **"Interactive vs Pipeline Boundary"** section to CLAUDE.md + a short README subsection (§6 draft below), using the real command names. Advisor tool documented as API-only (no code change; experiment parked in Backlog). `grep -r "codex:" co-evolve-bouncer.sh lib/ dev-review/` must return zero hits (the pipeline stays plugin-free).
2. **Manual checklist for Alan (post-merge, not CI):** 🚧 install the plugin — `/plugin marketplace add openai/codex-plugin-cc` → `/plugin install codex@openai-codex`; smoke with `/codex:status`; keep the **review gate OFF** (`/codex:setup --disable-review-gate` if it defaults on) — this repo has its own review engine and a second automatic one would loop against it and burn Codex quota (standing decision, ExoCortex #322778). Record the observed `/codex:status` output in the checklist/PR.
- **Done means:** CLAUDE.md/README merged with the grep clean; the manual checklist records `/codex:status` output.

### Phase 4 — Convergence honesty + the --execute port (M/L)
1. **A-5 marker lifecycle — convergence honesty first:** track marker count per pass. If unresolved markers survive the final pass, never print a live-marker document as "converged." Instead either (a) run one forced-adjudication pass that writes a clean final document plus `adjudication-report.md` mapping each stripped marker to the selected text and the rationale for that choice, or (b) exit `stuck` with the working document preserved for manual resolution. A marker may be stripped only when a defensible choice is recorded; if none exists, the status is `stuck`, not a clean-looking final. Log `converged|adjudicated|stuck` in the report. Hermetic sims: an oscillating-marker fixture resolves to `adjudicated` or `stuck` by explicit policy; a converging run stays byte-identical to today.
2. **A-6 --dev-review port:** already implemented on branch `claude/dev-review-port` (`80b2aca`: `--execute`/`--verify` + `--dev-review` shorthand; pass-throughs `--workdir/--verifier/--revise-loop/--exec-branch/--exec-worktree/--exec-timeout`; engine exit codes propagate; `tests/dev-review-handoff-simulation.sh`). Task = adversarially review that 399-line diff, rebase onto post-P1 master (the seat changes may conflict), add handoff assertions for model/effort forwarding or intentional non-forwarding, rerun the full suite, merge. Then remove the "merge before relying on it" note from `~/.claude/skills/co-evolution/SKILL.md` and update the workspace CLAUDE.md workflow table.
3. Optional: `--judge` flag running `evals/judge-bounce.sh` post-run 💰 (off by default; A-10).
- **Done means:** all sims green 3-OS; README/CLAUDE.md updated; **workspace-level follow-up:** update `C:\Users\alan\CLAUDE.md` workflow table ("Cross-AI execution is pending the --execute port" → done).

### Phase 5 — Live evidence + milestone closure (S, 💰 gated)
1. 💰 One happy-path `codex-build` dogfood run (completes v1.5 Phase 6 evidence: live ACCEPT on the happy path).
2. 💰 One `calibrate-bounce.sh` pass (fable-5 judge) to baseline document-bounce quality now that scoring is wired.
3. Tag `v1.5` after the happy-path evidence merges to master. Tag `v1.4` as a **code-state** tag on the commit that introduced the MCP package, independent of npm publication — the tag records code state, not a release to a registry (publication stays a separate human gate).
- **Done means:** `.planning/STATE.md` v1.5 marked complete; tags pushed; calibration report saved under `evals/` docs (reports dir stays gitignored — copy the summary into the PR).

### Approval gates (one-shot list)
- Origin branch deletions (P0.2). — destructive
- Plugin install + any `/codex:setup` change (P3.2). — user-level config
- Phase 5 items 1–2. — real Codex/Claude spend
- npm publish. — Alan only
- `runners/codex-ps/**`: no gate exists because **no change is permitted**.

---

## 4. CLAUDE.md draft — Model Routing (paste-ready, Phase 1)

```markdown
## Model Routing

Seats and defaults (env/flag overridable; state.json `seat_models` must always show a concrete model for preset seats):

| Work | Component | Model |
|------|-----------|-------|
| Code execution + mechanical verify | dev-review executor seat (`codex exec`) | `gpt-5.5` @ `xhigh` — pinned in presets, not inherited from local config.toml |
| Plan composition | dev-review composer seat / document composer role | `best` alias → `claude-opus-4-8` @ high |
| Verification verdicts | dev-review verifier seat | codex-build: opus @ max; claude-build: `gpt-5.5` @ xhigh |
| Bounce critique (document pipeline reviewer role) | co-evolve-bouncer | `gpt-5.5` @ xhigh via codex (cross-vendor disagreement is the point) |
| Accept / bounce / escalate decisions, adjudication passes | orchestrating session | fable-5 preferred, opus-4.8 acceptable |
| Plan review before execution | session or `/codex:adversarial-review` | fable-5 or opus-4.8; optionally add a gpt-5.5 pass as an independent second perspective |
| Blind quality judging | `evals/judge-bounce.sh` | fable-5 @ high (existing default) |
| Glue/scout subagents inside Claude Code | Agent tool | sonnet-5; **Haiku is not used anywhere in this repo** (workspace-level Haiku automations elsewhere are unaffected) |

Rules:
- These are defaults, not limits. Standing permission: if a cheaper model's output misses the bar, redo with a smarter model without asking. Judge the output, not the price tag.
- When axes conflict on anything that ships: intelligence > taste > cost. Cost is a tie-breaker only.
- Bulk/mechanical work (clear-spec implementation, migrations, data transforms) → gpt-5.5. It is cheap under the Codex plan but **not free**: the codex-guard daily cap applies; batch calls, never poll-loop them.
- Anything user-facing (docs prose, README, API/CLI surface design) needs high taste → opus-4.8 or fable-5 authors/reviews it.
- gpt-5.5 is reachable only through the Codex CLI (`codex exec`, `codex review`). Inside Agent/Workflow calls (model param takes Claude models only), use the wrapper pattern: a thin sonnet wrapper agent (effort low) that writes a self-contained codex prompt, runs `codex exec` via Bash (`-s read-only` for investigation work), and returns only the final message.
```

## 5. CLAUDE.md draft — Token Discipline (paste-ready, Phase 2)

```markdown
## Token Discipline

Return contracts (a wall of raw output is a failed task even when the work was correct):
- Scout/discovery reports: <=15 lines; file:line refs + one-sentence facts; never pasted file contents.
- Build reports: <=20 lines; files + line ranges changed, what was run to verify, pass/fail; diffs only when <=30 lines.
- Deep review reports: <=40 lines, conclusion first.
- Test/lint runs report failures only; passing output is one line ("N passed").
- Verifier verdicts: `summary` <=40 words; <=5 `issues`, one line each with file:line.

Working style:
- Grep before read. Read line ranges, not whole files. Never re-read an unchanged file already in context.
- Noisy operations (tests/run-all.sh, log inspection, large-file summaries) run in an isolated subagent so only the summary reaches the main thread. Gate decisions read `dev-review-status.sh --json`, never raw runner logs.
- Escalation ladder: one retry with a tighter prompt, then escalate upward carrying the prior failure evidence. Disagreements resolve upward, never re-litigated sideways. Ambiguity in high-risk areas — path normalization, git history, anything under runners/codex-ps/ — stops and surfaces immediately.

Delegation template (exactly four parts, nothing else):
1. **Goal** — one sentence.
2. **Scope** — in bounds and explicitly out of bounds.
3. **Contract** — which return format above.
4. **Done means** — the observable check.
```

## 6. CLAUDE.md draft — Interactive vs Pipeline Boundary (paste-ready, Phase 3)

```markdown
## Interactive vs Pipeline Boundary

**Pipeline (scripted, reproducible, headless):** `co-evolve-bouncer.sh`, `dev-review/codex/dev-review.sh`, `runners/codex-ps/` (frozen reference). No plugin slash commands, no advisor tool, no live-session dependencies. Anything here must run unattended and produce stable output.

**Interactive (live Claude Code sessions on this repo):** the official Codex plugin (`openai/codex-plugin-cc`) is allowed and encouraged:
- `/codex:adversarial-review` before letting the bouncer pass a risky plan.
- The `codex:codex-rescue` subagent when a session is stuck.
- `/codex:transfer` to hand work between Claude and Codex; `/codex:status` / `/codex:result` / `/codex:cancel` for job control.
- The review gate (Stop hook) stays **off** (`/codex:setup --disable-review-gate`): this repo already has a review engine; a second automatic one would loop against it and burn Codex usage.

**Advisor tool (Anthropic API beta, header `advisor-tool-2026-03-01`):** valid only inside API agent loops (Messages API `advisor_20260301`-type tool); never available to bash scripts, `claude -p`, or Claude Code sessions. If/when this repo grows an API-driven layer, pair a Sonnet executor with an **opus-4.8 advisor** — its advice returns readable and can be logged in the dev-review trail; a fable-5 advisor returns encrypted advice that cannot be audited. Timing discipline: consult before the first write, when stuck, and before declaring work done.
```

---

## 7. Backlog (explicitly not now)

- Dual-critique mode: `--dual-critique` on `co-evolve-bouncer.sh` — run the chain twice with flipped `--agents`, emit both critiques + a merged-union report. New workflow feature, not a convergence fix; shipping it alongside marker lifecycle would make failures hard to attribute. Start only after marker lifecycle (P4.1) and the `--dev-review` handoff (P4.2) are green on master, as its own PR/commit.
- Advisor-tool experiment: Sonnet executor + opus-4.8 advisor inside a future API-driven layer; measure verdict-quality delta vs current verifier seat.
- PEL activation cadence (proposer runs on a schedule) — parked until the marker-lifecycle work (P4.1) settles the protocol.
- npm/MCP publish (v1.4 Phase 5) — human gate.
- Scheduled monthly `calibrate-bounce.sh` run — decide after the first baseline (P5.2).
- Positioning ideas (marker protocol as standard, npm distribution) per 2026-04-18 brainstorm — separate track.

## 8. Execution notes

- Plan lives at `.planning/notes/2026-07-05-workflow-upgrade-plan.md`. Execute it as PR-per-phase directly, without reinstalling GSD. This is an explicit, owner-approved bypass of the AGENTS.md "start file-changing work through GSD" rule for this plan; treat the plan as v1.6 candidate scope if GSD is later reinstalled (`/gsd-update`).
- Per token policy: execute each phase in a fresh Opus session reading this file; orchestrate workers on sonnet; use gpt-5.5 (`codex exec`) for any mechanical sweep. A dual-critique-style pre-execution review is optional and only worthwhile once the model routing table has a concrete smoke result for every named model.
- Every phase reruns `bash tests/run-all.sh` (hermetic) before PR; CI must be green on 3 OS; PR descriptions follow the build-report contract (§5) and cite this plan's committed SHA.

