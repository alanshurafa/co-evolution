# Token Evidence: the "50% Claude-limit reduction" claim

**Date:** 2026-06-12
**Phase:** v1.5 Phase 6 (dogfood + evidence)
**Purpose:** Establish the measurement method for the post's "~50% weekly
Claude-limit reduction" claim, record the first real `/codex-build` data point,
and enumerate what is still needed before a verdict on the claim can be drawn.

---

## Measurement method

The claim is that splitting roles (Claude plans/reviews, Codex executes) cuts
weekly Claude usage roughly in half versus Claude doing the whole loop. We
measure two distinct spend surfaces, because they live in different places:

1. **Runner-side agent tokens** — captured per phase into `state.json.tokens`
   when `CO_EVOLVE_TOKEN_CAPTURE=1` (Phase 4). Claude seats land under
   `.tokens.totals.claude_*` (from the `claude -p --output-format json` envelope,
   field map in `2026-06-12-claude-json-envelope.md`); Codex seats land under
   `.tokens.totals.codex_total_tokens` (harvested from the `tokens used` stderr
   line, format pinned in `2026-06-12-codex-headless-facts.md` R2). This is the
   part the runner can see and attribute by seat.

2. **Orchestrator-session spend** — the Fable/Claude Code session that plans and
   runs the review gate. The harness does **not** expose a token meter to the
   session, so this is visible only as **turn counts**: how many model turns the
   orchestrator burned (plan + kick + each wake/review gate). Under `/codex-build`
   the session ends its turn at KICK and is woken on exit, so the orchestrator
   pays for plan + review gates only — not for watching Codex grind.

**The comparison** is `/codex-build` (Codex executes, Claude only plans+reviews)
vs. an **interactive `/dev-review` baseline** on the *same task* (Claude in more
seats, session supervises inline every pass). The 50% question is whether the
Claude-attributable spend — runner-side `claude_*` totals **plus** orchestrator
turn count — drops by roughly half. Codex tokens are "free" against the
ChatGPT-plan quota and so are reported but excluded from the Claude-limit math.

---

## First real data point (T2 dogfood, 2026-06-12)

**Task:** add a `slugify` function to `utils.sh` (lowercase; spaces/underscores →
hyphens; strip other punctuation) + two test cases in `run-tests.sh`. Honest
scratch repo under `$TMPDIR`, clean tree, `--branch auto`, `--workdir` on the
scratch repo, `--run-dir` outside the main repo. Auth-degraded path
(`--verifier codex`) because the headless `claude` shell on this Mac is
**not logged in** (expected; the in-app session token does not reach sub-shells).

Exact kick (seats from `--preset codex-build`):

```bash
CO_EVOLVE_TOKEN_CAPTURE=1 bash dev-review/codex/dev-review.sh \
  --preset codex-build --skip-plan --plan "$PLAN" \
  --verifier codex --branch auto --workdir "$SCRATCH" \
  --run-dir "$TMPDIR/codex-build-dogfood-run" --timeout 900 \
  -- "Add a slugify function to utils.sh and two test cases to run-tests.sh"
```

### Result: execute SUCCEEDED, verify ERRORED (no verdict) — NOT an ACCEPT

| Signal | Value |
|---|---|
| Runner exit code | 2 (partial) |
| Wall clock | 65 s (run 1), 61 s (run 2 re-kick) |
| Status reader `status` / `verdict` / `verdict_present` | `partial` / `null` / `false` |
| Execute phase | `ok`, exit 0 — slugify landed |
| Verify phase | `error`, exit 2 — codex verifier returned an error payload |
| Diffstat | `utils.sh +7`, `run-tests.sh +2`, 2 files, 9 insertions |
| Scratch tests after execute | **ALL 4 PASS** (`bash run-tests.sh` → `ALL TESTS PASSED`) |

The executor's work was **correct** — the implemented `slugify` passes both new
assertions and the two pre-existing ones. The run did not reach ACCEPT only
because the **verify seat could not produce a verdict**.

### Tokens block (verbatim, run 1 — `jq '.tokens' state.json`)

```json
{
  "phases": {
    "execute": {
      "source": "codex-stderr",
      "total_tokens": 21497
    }
  },
  "totals": {
    "claude_input": 0,
    "claude_output": 0,
    "claude_cache_read": 0,
    "claude_cost_usd": 0,
    "codex_total_tokens": 21497
  }
}
```

Run 2 (re-kick, `--parent-run dev-review-20260612-133912`, lineage recorded)
re-ran execute and reported `codex_total_tokens: 34935`; verify failed the same
way. Both runs: `claude_*` totals are **0** — by design under the codex-verifier
degrade, the only Claude work was orchestrator-side (this session), and the
headless claude seats were never invoked.

### Seat models actually used (verbatim)

```json
{
  "composer": "opus:claude-fable-5@high",
  "executor": "codex:(default)@xhigh",
  "verifier": "codex:fable@max"
}
```

---

## Finding: the `--verifier codex` degrade is broken on a ChatGPT-plan Codex

Root cause, fully diagnosed (this is a real runner bug, not a plan or env fault):

- The `codex-build` preset hard-fills `VERIFIER_MODEL=fable` (correct for the
  **default** Claude verifier seat — Fable reviews).
- When the documented degrade `--verifier codex` flips the verifier *agent* to
  codex, `apply_seat_env verifier codex` exports `CODEX_MODEL=fable`
  (`dev-review.sh:1370-1372`: `export CODEX_MODEL="${model:-...}"` where
  `model` = `VERIFIER_MODEL` = `fable`). The verdict is the seat model string
  `codex:fable@max`.
- Codex on a **ChatGPT account** rejects an unknown model with HTTP 400:

  ```
  ERROR: {"type":"error","status":400,"error":{"type":"invalid_request_error",
  "message":"The 'fable' model is not supported when using Codex with a ChatGPT account."}}
  ```

So the skill's own documented auth-degrade (kick with `--verifier codex` when the
headless claude seat is logged out — the *exact* situation on this Mac) currently
**cannot produce a verdict**: the Claude model name leaks into the Codex seat.
`VERIFIER_MODEL=` (empty) does not fix it — the preset's `:=fable` refills an
empty value. A real fix is a runner change (clear/override `VERIFIER_MODEL` when
the verifier resolves to codex, or pass a codex-valid model), out of scope for
this evidence pass per Phase 6 ground rules. Per the skill's gate logic a missing
verdict is an **ESCALATE**, never an auto-merge — the gate behaved correctly.

> **Update 2026-06-12 (v1.5 fix):** degrade-path verifier model leak FIXED in
> `apply_seat_env` / `resolve_seat_model_string` (cross-agent leak guard drops a
> wrong-kind model+effort pair as a unit; codex seat falls back to
> `codex:(default)@(default)` = gpt-5.5/xhigh). Re-run proof: the `fable` HTTP 400
> is gone, execute SUCCEEDED, scratch `run-tests.sh` ALL PASS,
> `codex_total_tokens: 17237`, wall 54 s — but verdict is still `null` because the
> verify seat now hits a SEPARATE, pre-existing schema 400 (`invalid_json_schema`:
> `additionalProperties` required `false` on `issues.items` in
> `skills/dev-review/schemas/review-verdict.json`). Seat fix proven; degrade path
> still blocked one layer deeper by the schema bug (tracked separately).

> **Update 2026-06-12 (v1.5 schema fix — FULL ACCEPT path now green):** the
> schema 400 above is FIXED. OpenAI strict structured-output requires
> `additionalProperties: false` and a `required` list covering every property on
> every object node; `issues.items` was missing both, and the top-level `required`
> omitted `scope_creep_detected` / `iteration_notes`. All three canonical copies
> (`schemas/`, `runners/codex-ps/schemas/`, `skills/dev-review/schemas/`) were
> tightened identically (drift guard stays green). The shell `validate_review_verdict`
> gate is unaffected — it stays loose and is independent of this file. With both
> the seat leak and the schema 400 fixed, the degrade path (`--verifier codex`)
> reaches a **real verdict end-to-end** for the first time. See the data point
> immediately below.

---

## First COMPLETE-RUN data point — codex-verifier ACCEPT (2026-06-12)

**This is the first full ACCEPT-path evidence row.** Same harness as T2 (honest
scratch repo under `$TMPDIR`, plan outside it, clean tree, `--branch auto`,
`--workdir` on the scratch repo, `--run-dir` outside the main repo), auth-degraded
`--verifier codex` seat (headless `claude` still logged out on this Mac). The only
difference from T2 is the schema fix — so this isolates the schema 400 as the last
blocker on the degrade path.

**Task:** add a `subtract(a,b)` helper to `utils.sh` (echo `a-b`) + two assertions
in `run-tests.sh`.

Exact kick (seats from `--preset codex-build`):

```bash
CO_EVOLVE_TOKEN_CAPTURE=1 bash dev-review/codex/dev-review.sh \
  --preset codex-build --skip-plan --plan "$PLAN" \
  --verifier codex --branch auto --workdir "$SCRATCH" \
  --run-dir "$TMPDIR/codex-build-schema-proof" --timeout 900 \
  -- "Add a subtract(a,b) helper to utils.sh that echoes a-b, and add two assertions for it to run-tests.sh"
```

### Result: ACCEPT — execute OK, verify OK, real verdict produced

| Signal | Value |
|---|---|
| Runner exit code | **0** |
| Wall clock | **59 s** |
| Status reader `status` / `verdict` | `completed` / `APPROVED` |
| Execute phase | `ok`, exit 0 — `subtract()` landed |
| Verify phase | `ok`, exit 0 — codex `--output-schema` returned a valid verdict (no schema 400) |
| Diffstat | `utils.sh +4`, `run-tests.sh +2`, 2 files, 6 insertions |
| Scratch tests after execute | **ALL 4 PASS** (`bash run-tests.sh` → `ALL TESTS PASSED`) |

### Verdict (verbatim — `verdict.json`)

```json
{"verdict":"APPROVED","confidence":96,"summary":"Implementation matches the plan: `utils.sh` adds a `subtract()` helper in the same style as `add()`, `run-tests.sh` includes the two requested assertions, and `bash run-tests.sh` passes all checks. No logic, style, security, or scope issues found for the requested change.","issues":[],"scope_creep_detected":false,"iteration_notes":"No changes needed."}
```

The verdict carries all six strict-mode fields (including `scope_creep_detected`
and `iteration_notes`), proving the tightened schema round-trips through Codex.

### Tokens block (verbatim — `jq '.tokens' state.json`)

```json
{
  "phases": {
    "execute": {
      "source": "codex-stderr",
      "total_tokens": 30606
    },
    "verify": {
      "source": "codex-stderr",
      "total_tokens": 14485
    }
  },
  "totals": {
    "claude_input": 0,
    "claude_output": 0,
    "claude_cache_read": 0,
    "claude_cost_usd": 0,
    "codex_total_tokens": 45091
  }
}
```

Note this is the first row with a populated **`verify` phase** token entry
(14,485) — T2's verify never produced one because it errored before emitting a
`tokens used` line. `claude_*` totals remain **0** by design under the
codex-verifier degrade (no headless Claude seat was invoked); the Claude-limit
numerator still requires `claude /login` (see below). Codex tokens
(45,091) are excluded from the Claude-reduction math.

### Real-task matrix progress

T2 evidenced the **ESCALATE** row (missing verdict). This run evidences the
**ACCEPT** row for real on the degrade path. **REVISE→ACCEPT** and the
full-ladder (Fable-verifier, non-zero `claude_*`) ACCEPT remain — both still
gated on `claude /login`.

---

## What is still needed for a 50%-claim verdict

1. **`claude /login` on this Mac (human step).** The headless `claude` shell is
   not logged in, so the full ladder — and any non-zero `claude_*` token data —
   is unreachable here. Until then every runner-side `claude_*` total reads 0 and
   the Claude-limit math has no numerator. This is the single biggest gap.
2. **A real ACCEPT data point.** ~~T2 reached execute-OK but verify-error.~~
   **DONE on the degrade path (2026-06-12, schema fix):** the subtract-helper run
   reached a clean `APPROVED` verdict (`verdict.json` present, exit 0) — see the
   COMPLETE-RUN data point above. Still owed: a **full-ladder** ACCEPT with
   non-zero `claude_*` tokens (the degrade path's `claude_*` totals are 0 by
   design; that gap is item 1, `claude /login`).
3. **The real-task matrix (Phase 6 design):** ACCEPT, REVISE→ACCEPT, and
   ESCALATE each exercised once on real tasks. T2 produced an **ESCALATE** path
   for real (missing verdict); the subtract run produced an **ACCEPT** for real
   (degrade path). **REVISE→ACCEPT** remains.
4. **An interactive `/dev-review` baseline on the same task** — the denominator
   for the comparison. Without it there is no "half of what?" to measure against.
5. **Orchestrator turn-count instrumentation.** Harness-side session spend is
   visible only as turn counts (see Honest scope). For this orchestration the
   count is: plan + 1 kick + 1 re-kick + this gate ≈ 4 orchestrator turns;
   a clean ACCEPT would be plan + kick + 1 gate ≈ 3.

## Honest scope

- **Runner-side tokens are attributable; orchestrator-side spend is not metered.**
  The harness gives the session no token meter — only turn counts. Any 50% figure
  is therefore "runner-side Claude tokens (exact) + orchestrator turns (proxy)",
  not a single dollar number. State this whenever the claim is quoted.
- **Codex tokens do not count against the Claude limit.** They are reported
  (`codex_total_tokens`) for completeness and to size the ChatGPT-plan quota
  draw, but excluded from the Claude-reduction numerator.
- **This data point is auth-degraded.** It measures the codex-only-verify path,
  which is the fallback, not the blessed Fable-verifier ladder. Treat the
  `claude_* = 0` totals as "ladder not exercised here," not as "Claude spend was
  zero for this kind of task."

## Artifacts

| Item | Path |
|---|---|
| Run 1 dir (ACCEPT attempt) | `$TMPDIR/codex-build-dogfood-run/` |
| Run 2 dir (re-kick, parent-linked) | `$TMPDIR/codex-build-dogfood-run-r2/` |
| Plan file | `$TMPDIR/codex-build-plan-<ts>.md` |
| Scratch repo | `$TMPDIR/codex-build-dogfood-<ts>/` |
| Verifier error log | `<run-dir>/review-stderr.log` (the HTTP-400 fable rejection) |
