# Rebuild Phase 1 — core engine + document pipeline

- **Derived from:** proposal v1.1 §6 Phase 1 (AUTHORITY), grounded in Phase 0's slice results and wave-review findings (TRACKER 2026-07-17). Same branch, worktree, gates (G1/G2/G3), and standing constraints as PHASE-0-PLAN.md.
- **Phase goal:** a TypeScript engine that runs the full document pipeline (compose optional later; bounce-only/chain first) against real subscription CLIs, emits contract-valid evidence, and proves behavioral equivalence with the Bash bouncer on recorded inputs. Estimates re-forecast from Phase 0: **6–9 sessions**; exit criteria control progression, not session counts.
- **Slice inputs this plan builds on:** WP-04 adapter (typed results, resolveBin bridge, A-2/C-8 ladder), WP-05 kill contract (`killWindowsProcessTree`, POSIX groups), WP-06 serializer (internal model + `bounce-state/1.x` legacy serializer, score-invariant), the review's consolidation mandate (one managed-spawn primitive; codex adapter must not become a third spawn copy).

## Work packages

### WP-1.01 — Managed-spawn primitive (the review mandate; FIRST, everything else builds on it)
One primitive in `src/proc/`: `spawnManaged(bin, args, opts)` composing resolveSpawn + cmd-arg guard, RNPT-06 env hygiene (default ON, explicit opt-out), stdin delivery, stdout/stderr capture with bounded tails, per-call deadline, tree-kill (Windows: `killWindowsProcessTree`; POSIX: detached process group + SIGTERM→SIGKILL — capture works with `pipe` stdio on a detached child). Rework `invokeClaudeRead` onto it, deleting its local spawn/timer machinery; extend the grandchild-reap test to run THROUGH the adapter path.
**Done:** whole suite green with the adapter on the primitive; hang-with-grandchild reaped via the adapter on Windows locally (CI proves POSIX); paid smoke re-run passes. *(Opus)*

### WP-1.02 — Codex adapter
`invokeCodexExec` porting `invoke_codex`/`invoke_codex_schema` (lib:513–592): `codex exec --full-auto --skip-git-repo-check -C <workdir> -o <file>`, model/effort via config, schema variant allowed (PRTP-03 is Claude-only — encode the asymmetry in tests). Extract the classification ladder into a shared module with injectable banner/loose regex sets so claude/codex configure, not copy.
**Done:** hermetic stub suite mirroring the claude adapter's; one paid codex smoke (default plan model, trivial prompt — G3 smoke-scale). *(Opus)*

### WP-1.03 — Recorded-transcript harness + fault injection
Record one real claude and one real codex invocation (tiny prompts, smoke-scale), redact, store as replayable fixtures; contract tests replay them against both adapters. Fault-injection set per the kit: auth banner (short + long), rc=2, empty, timeout, CRLF output, shell metacharacters in content.
**Done:** replay suite green; each fault produces the contracted result kind. *(Sonnet, Opus review)*

### WP-1.04 — Marker engine
Port `count_markers` semantics exactly (fence-aware, inline-code-stripped), `strip_human_summary`, `strip_protocol_markers`; ledger fates (resolved / deleted-with-section / expired / unresolved); pass budget + final-pass clause; convergence and `protocol_outcome` derivation (converged / adjudicated / stuck — adjudication pass itself may stub until Phase 2 if scope demands, recorded honestly).
**Done:** golden tests derived from the 4 bounce-run fixtures reproduce the scorer's ledger classifications; property tests for fence/inline-code edge cases (the fragility top-10 item). *(Opus)*

### WP-1.05 — Turns, seats, and the document loop
Seat assignment by pass parity; template loading from `contracts/templates/` (light roles default, adversarial variant, chain critique/defend/tighten); prompt assembly; retry-once-on-empty at the turn layer (the adapter contract's caller side); `validate_output`-style size/structure sanity (the WP-04 header's promised caller obligation); per-turn deadline wired through the primitive. Pipeline modes: bounce-only, chain, adversarial; compose mode may land late in the phase.
**Done:** a hermetic end-to-end bounce over stub adapters converges, expires, and sticks correctly across the three terminal outcomes. *(Opus)*

### WP-1.06 — Evidence writer
Run dir per the proposal (`CO_EVOLVE_RUNS_DIR` honored; project-local default), `journal.jsonl`, `state.json` via the WP-06 serializer, `report.md` minimal, required-vs-optional durability tiers (required failure → `run_status: failed`, non-success exit; optional failure → `evidence_degraded`). No dot-prefixed transients; `tmp/` subdir.
**Done:** `score-bounce.sh` consumes a hermetic run's emitted state via the state path; durability tiers covered by fault tests (read-only dir, mid-write kill). *(Sonnet, Opus review)*

### WP-1.07 — CLI
`co-evolve` bin: bounce-only/chain/adversarial flags mapping to the loop, `--agents`, `--bounces`, `--output`, exit bands preserved (0/2/1 semantics per the spec's two-field model); `runs list|show|prune` (prune dry-run default, refuses active runs).
**Done:** one real end-to-end CLI bounce on a small doc with subscription CLIs (G3 smoke-scale) produces a scored run dir; help text documents every flag. *(Sonnet, Opus review)*

### WP-1.08 — Measurement: classify, label, recalibrate, validate
From the archived corpus: classify all runs by terminal status + marker outcome (extends WP-06's scan); produce the stratified ~30-run labeling sample; labeling via the cross-family judge panel (fable-5 + gpt-5.5 — spend pre-approved 2026-07-07 for measurement, re-confirmed in STOP B's batched request; Alan spot-check optional); diagnose structural-preservation failures (the 12% pass-rate dimension); recalibrate `bounce-thresholds.yaml` on a training split; validate on holdout. Wire `evals/tests/bounce-scorer-verification.sh` into `tests/run-all.sh` on this branch.
**Done:** new thresholds documented with train/holdout numbers; scorer-verification wired; thresholds remain non-gating until STOP B accepts them. *(Sonnet sweep + Opus analysis; spend items listed in TRACKER before running)*

### WP-1.09 — Parity gate (differential + live smoke)
Differential replay: identical recorded adapter outputs fed to Bash bouncer and TS engine → equivalent normalized ledgers, pass counts, terminal outcomes (equivalence relation defined in the test, not vibes). Live smoke: one real bounce (small doc) verifying contract, liveness, and artifact integrity without requiring identical prose.
**Done:** differential suite green across the recorded set; live smoke's run dir passes `score-bounce.sh` via the state path. This is Phase 1's exit gate. *(Opus)*

### WP-1.10 — Phase review + Phase 2 plan + STOP B
`/code-review high` on the phase diff; findings fixed or filed; PHASE-2-PLAN.md authored (code pipeline + gates; detached mode split out per proposal Phase 2b); STOP B report with re-forecast and any threshold-acceptance decision.

## Dependencies and waves

1.01 → (1.02, 1.03, 1.05) | 1.04 independent | 1.06 → 1.04 (state fields) | 1.07 → 1.05+1.06 | 1.08 independent (archive-only until judge spend) | 1.09 → all engine WPs | 1.10 last.
**Wave A:** 1.01, 1.04, 1.08-classification. **Wave B:** 1.02, 1.03, 1.05. **Wave C:** 1.06, 1.07, 1.08-recalibration. **Wave D:** 1.09, 1.10.

## Carried notes

- `finished_at` absent-tolerance asymmetry (review C-4): resolve in WP-1.06 — either tolerate absent like `convergence_status` or document why not, in the serializer comment and the contract note.
- mcp `preflight.ts` extension-list divergence: Phase 3 (MCP rework) — do not touch mcp/ in Phase 1.
- Detached mode, execute/verify, gate objects: Phase 2/2b. Nothing in Phase 1 touches repo-mutation effectors.
- Session hygiene: fresh Opus session per 1–2 waves, TRACKER is the handoff.
