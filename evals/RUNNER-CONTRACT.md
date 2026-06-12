---
title: Runner ↔ scorer contract
version: 1.1
status: locked
owners:
  - dev-review/codex/dev-review.sh (runner)
  - evals/score-run.sh (scorer)
  - evals/tests/fake-runner.sh (reference implementation)
updated: 2026-06-12
---

# Runner ↔ scorer contract

`evals/score-run.sh` scores a single run by reading `state.json` and a small
set of artifact files from the run directory. `dev-review/codex/dev-review.sh`
(real runner) and `evals/tests/fake-runner.sh` (hermetic reference) MUST both
emit the shape below so the scorer sees a stable interface.

The rule is "doc first, code conforms" — any field the scorer reads appears in
§1; any path the scorer reads appears in §2; any exit the scorer maps to a
status lives in §3. Changes land here in the same commit that touches the
emitting code.

## 1. State fields

`state.json` at the run-directory root. All fields are snake_case to match the
reference implementation at `evals/tests/fake-runner.sh:79-112` and the
historical fixture corpus under `runners/codex-ps/evals/tests/fixtures/**`.

| Field | Type | Required | Written by | Read by (scorer line) | Description |
|-------|------|----------|------------|-----------------------|-------------|
| `run_id` | string | yes | runner at init | `score-run.sh:232` | Unique per-run identifier |
| `task` | string | yes | runner at init | — (echo only) | Echo of the task argv |
| `composer` | string | yes | runner at init | — | Composer agent id |
| `executor` | string | yes | runner at init | — | Executor agent id |
| `reviewer` | string | yes | runner at init | — | Reviewer agent id |
| `status` | string (`pending` \| `completed` \| `failed` \| `partial`) | yes | runner — `pending` at init, overwritten at EOF | `score-run.sh:239` | Terminal run status; anything ≠ `completed` → Robustness FAIL. `pending` is the init sentinel; observing `pending` post-run means the runner aborted before EOF — maps to `failed`. |
| `started_at` | string (ISO8601) | yes | runner at init | `score-run.sh:260` | Run start timestamp |
| `updated_at` | string (ISO8601) \| null | nullable at init | runner (post-verify) | `score-run.sh:261` | Last-touch timestamp; feeds Cost wall-clock calc |
| `completed_at` | string (ISO8601) \| null | nullable | runner (EOF) | — | Set at successful termination |
| `marker_counts` | object `{contested, clarify, total}` | yes | runner (post-bounce) | `score-run.sh:310` | Bounce-phase marker counts; `total` drives Convergence |
| `changed_files` | array\<string\> | yes | runner (post-execute) | `score-run.sh:450-456` | Files actually changed; feeds Execution Fidelity Jaccard vs plan |
| `verify_verdict` | string \| null | nullable | runner (post-verify) | `score-run.sh:498` | Verify-phase verdict — `APPROVED` / `REVISE` / null |
| `history` | array\<`{phase,status,detail,timestamp}`\> | yes | runner (per phase) | `score-run.sh:338` | Canonical bounce-trace array. Convergence needs ≥1 entry with `phase` matching `^bounce-[0-9]+$` when bounces were expected. |
| `mode` | string | no | runner (optional tag) | — | Fake-runner sets `"fake-runner"`; real runner may set `"real"` or omit. Runner-owned metadata — NOT written by the shared `init_state_json` library. |
| `seat_models` | object `{composer, executor, verifier}` (each string `agent:model@effort`) | no | `dev-review.sh` (post-init) | — | v1.5 observability: what each seat resolved to under the per-seat env layer (e.g. `"claude:claude-fable-5@high"`, `"codex:(default)@xhigh"`). Runner-owned metadata — NOT written by the shared `init_state_json` library; scorer ignores it. |
| `current_phase` | object `{name, started_at}` \| null | no | `dev-review.sh` (`begin_state_phase` at each phase start; null at EOF) | — | v1.5 additions — observability. The phase the runner is currently in; `name` matches the `phases[]`/`history[]` phase name (`compose`, `bounce-NN`, `execute[-N]`, `verify[-N]`). Set at phase **start**, cleared to null at EOF (incl. plan-only). A non-null value on a non-terminal run means the runner is in that phase or died there. Read by `dev-review-status.sh`; scorer ignores it. |
| `runner_pid` | number | no | `dev-review.sh` (post-init, once) | — | v1.5 additions — observability. The runner process's PID (`$$`). A status reader probes liveness via `kill -0`. Runner-owned; scorer ignores it. |
| `pre_execute_sha` | string (40-hex) \| null | no | `dev-review.sh` (execute phase, before executor) | — | v1.5 additions — observability. Workdir `git rev-parse HEAD` captured just before the executor runs; null when non-git/detached. Scorer ignores it. |
| `post_execute_sha` | string (40-hex) \| null | no | `dev-review.sh` (execute phase, after change detection) | — | v1.5 additions — observability. Workdir HEAD just after change detection; `pre != post` means the executor committed. Null when non-git/detached. Scorer ignores it. |
| `orchestration` | object `{parent_run_id}` | no | `dev-review.sh` (post-init, only when `--parent-run` passed) | — | v1.5 additions — lineage. Records the orchestrator's parent run id for re-kicks (re-kicks always get a fresh run dir; no `--resume`). Omitted entirely for standalone runs. Runner-owned; scorer ignores it. |

### Legacy alias: `phases` → `history`

`dev-review.sh` wrote `phases[]` in v1.1 and v1.2-pre-08.1. That field remains
present for one minor-version transition window so downstream consumers can
migrate without a coordinated flag day; new consumers read `history[]` only.
Plan 02 of Phase 08.1 adds a mirror write that copies each `phases[]` entry
into `history[]` at write-time so both exist. The contract locks `history` as
the forward name; Plan 05+ in a future minor version removes the `phases`
alias.

### `// "unknown"` fallback preservation

`score-run.sh` reads every state field with a defensive `// "unknown"` /
`// ""` / `// 0` fallback. Those fallbacks STAY — they are the safety net for
partial / corrupted state.json files (mid-run crash, disk full, jq unavailable
on init). The contract says runners MUST emit the fields; the fallbacks say
the scorer MUST NOT crash when a runner ignores the contract. Defense in depth.

## 2. Artifact paths

Resolved relative to the run directory (`$RUN_DIR` in runner-speak). Paths are
plain (no dot-prefix) so `cleanup_runtime_artifacts` — which sweeps
`$RUN_DIR/.*` at `-maxdepth 1` — does not delete them mid-run.

| Path | Content | Required | Written by | Read by (scorer line) |
|------|---------|----------|------------|-----------------------|
| `state.json` | see §1 | yes | runner (init + per-phase updates + EOF) | `score-run.sh:232-498` |
| `plan.md` | compose-phase plan output | yes | runner post-compose | — (passthrough to eval corpus) |
| `original-plan.md` | snapshot of plan.md at bounce-loop start | yes | runner post-compose | — |
| `outputs/compose.txt` | raw compose-phase output (byte-for-byte of the LLM reply) | yes | runner post-compose | `score-run.sh:559` — drives Cross-AI Diversity |
| `outputs/bounce-NN.txt` | per-bounce output; `NN` zero-padded starting at `01` | yes when `max_bounces > 0` | runner per bounce pass | `score-run.sh:563` — first match drives Cross-AI Diversity |
| `outputs/*.log` | runner diagnostic logs (stdout/stderr captures) | no | runner (optional) | — (ignored by scorer) |
| `verdict.json` | verify-phase verdict object (schema: `skills/dev-review/schemas/review-verdict.json`) | yes when `verify=true` | runner post-verify | `score-run.sh:498` |

### Why `outputs/compose.txt` is not dot-prefixed

`cleanup_runtime_artifacts` in `dev-review.sh` runs
`find "$RUN_DIR" -maxdepth 1 -type f -name '.*' -delete`. Historical compose
output lived at `$RUN_DIR/.compose-output.md` (dot-prefixed, swept post-run)
which was fine for v1.1 but invisible to the scorer. The contract fixes the
scorer-visible path at the plain `outputs/compose.txt` location so cleanup
cannot touch it. The dot-prefixed `.compose-output.md` remains as an
intermediate working-file for one minor version; contract consumers read the
plain path only.

## 3. Exit-code contract

The runner's terminal exit code is the authoritative signal. `state.status`
MUST be derived from the same exit-code band used in `dev-review.sh`'s final
`exit N` switch so scorer and runner never disagree.

| Exit code | Meaning | Maps to `state.status` |
|-----------|---------|------------------------|
| `0` | All phases green (compose + bounce + execute + verify) | `completed` |
| `2` | Some phases failed but run reached EOF (partial run) | `partial` |
| `>= 3` (non-zero, non-`2`) | Hard failure mid-run or terminal abort | `failed` |
| — (process killed / OOM / crash) | Runner never wrote EOF | `pending` observed by scorer — maps to `failed` per §1 semantics |

The exit-code bands mirror `dev-review.sh:1420-1428`. The `state.status`
write at EOF is the single point of truth; the scorer never re-derives status
from exit codes directly (it reads the field the runner wrote).

## 4. Cache invalidation

`lab/pel/pr-emitter/pr-emitter.sh::compute_cache_key` (lines 547-550) globs
`evals/**/*.md` at `-maxdepth 3` and includes the SHA-1 of every match in the
emitter's `scripts_hash`. `evals/RUNNER-CONTRACT.md` sits at depth 2, so the
existence of this doc auto-invalidates every existing PR-emitter cache entry
the first time the new scripts_hash is computed.

That is the correct, documented behavior — contract-surface changes SHOULD
invalidate caches. Re-running the PR-emitter after landing this doc may
incur one cold-path classifier call per task / target combination. No manual
cache purge is required.

## 5. Worked example

Byte-stable `state.json` shape (copy of `evals/tests/fake-runner.sh:79-112`
output with the `FAKE_TS` placeholder expanded to a concrete ISO8601
timestamp):

```json
{
  "run_id": "dev-review-2026-04-19-120000",
  "task": "fake-runner task",
  "composer": "codex",
  "reviewer": "codex",
  "executor": "codex",
  "max_bounces": 0,
  "verify": false,
  "autonomous": true,
  "status": "completed",
  "status_detail": "Synthetic fake-runner output.",
  "current_phase": "verify",
  "marker_counts": { "contested": 0, "clarify": 0, "total": 0 },
  "changed_files": [],
  "verify_verdict": "APPROVED",
  "started_at": "2026-04-19T12:00:00Z",
  "updated_at": "2026-04-19T12:00:01Z",
  "completed_at": "2026-04-19T12:00:01Z",
  "mode": "fake-runner",
  "history": [
    { "phase": "compose",   "status": "running", "detail": "", "timestamp": "2026-04-19T12:00:00Z" },
    { "phase": "execute",   "status": "running", "detail": "", "timestamp": "2026-04-19T12:00:01Z" },
    { "phase": "verify",    "status": "running", "detail": "", "timestamp": "2026-04-19T12:00:01Z" }
  ]
}
```

Grep-pinned tokens used by the contract-conformance test gate:
`State fields`, `Artifact paths`, `Exit-code contract`,
`pending | completed | failed | partial`, `bounce-NN.txt`, `history`,
`outputs/compose.txt`, `scripts_hash`.

## 6. Versioning policy

The `version:` frontmatter field is the single version token for this
contract. Bump rules:

- **Minor bump** (e.g. `1.0` → `1.1`) — any change that adds, removes, or
  renames a field in §1 or §2, or alters the exit-code table in §3.
- **Major bump** (e.g. `1.0` → `2.0`) — any change that alters a field's
  type or runtime semantics (e.g. `changed_files` goes from array to object,
  or `history[].timestamp` switches time zones).
- **Patch / no bump** — pure documentation clarifications with no shape
  change.

Bump the `version:` in the same commit that lands the field change. That
commit MUST also update the emitting side (`dev-review.sh` and/or
`fake-runner.sh`) and the reading side (`score-run.sh`) together, so no
commit ever lands the repo in a state where the contract doc and the code
disagree.
