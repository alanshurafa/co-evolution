# claude-build - Codex-Orchestrated Claude Execution

This is the Codex-facing orchestration protocol for `--preset claude-build`.
Codex is the orchestrator: it plans, kicks the runner, waits synchronously, and
reviews the result. Claude is the executor: it gets the writable execute phase.

Use this when the user wants Codex to supervise a build but wants Claude to write
the code. This is intentionally the mirror of `codex-build`, with one important
difference: Codex has no harness wake-on-exit. The Phase 1 mode is therefore
blocking and synchronous.

The preset expands to: composer = Codex (xhigh, model pinned to `gpt-5.6-sol`),
executor = Opus (best/high), verifier = Codex (xhigh, model pinned to `gpt-5.6-sol`),
`--verify` on, bounces 2, revise-loop 1. The codex composer and verifier seats are
model-pinned (A-3), so a preset run reproduces across machines rather than
inheriting the local codex `config.toml`.

## Step 1: PREFLIGHT

Run these checks before writing the plan or kicking the runner.

### Claude CLI present and authenticated

Claude is the executor in this preset, so missing or logged-out Claude is a
HARD STOP. Do not degrade the executor to Codex; that is just `codex-build`.

```bash
command -v claude
claude -p --model claude-haiku-4-5-20251001 "ping"
```

If either command fails, stop and tell the user to install or authenticate the
`claude` CLI, then re-run. A logged-out Claude executor cannot write code.

### Codex CLI present

Codex is still the composer and verifier.

```bash
command -v codex
```

If missing, stop and tell the user to install or expose the Codex CLI before
running `claude-build`.

### No other active dev-review run

```bash
bash dev-review/codex/dev-review-status.sh --list
```

If the `ACTIVE` section shows a non-terminal run (`status=pending` or
`status=null`), do not kick a second orchestrated run in the same workdir.
Escalate or wait for the existing run to reach a terminal status.

### Tree state and isolation

```bash
git -C "$(pwd)" status --short
```

Record whether the tree is clean. This protocol always kicks with
`--worktree auto` so Claude writes in an isolated sibling checkout. That matters
because this feature edits the same runner it invokes, and because dirty
workdirs make diff-based verification ambiguous.

Never run from a network or SMB mount. Use a local git clone.

## Step 2: PLAN

Codex writes the implementation plan before invoking the runner.

1. Inspect the repo with `rg`, shell reads, and narrow file opens.
2. Write the plan to `$TMPDIR`, never inside the workdir:

   ```bash
   PLAN_FILE="${TMPDIR:-/tmp}/claude-build-plan-$(date +%Y%m%d-%H%M%S).md"
   ```

3. Shape the file for `--skip-plan --plan FILE`: a top-level heading, at least
   about 60 words, at least 5 non-empty lines, and at least 2 structural lines.
   Include:

   ```text
   # <Task title>

   ## Approach
   <what will be built and the key technical decisions>

   ## Files to Change
   - `path/to/file` - <what changes and why>

   ## Steps
   1. <ordered implementation steps>

   ## Risks / Out of scope
   - <risks, assumptions, and explicit exclusions>
   ```

Optional hardening: ask Claude for a synchronous plan critique using the bounce
markers `[CONTESTED]` and `[CLARIFY]`. Resolve every marker before kicking. After
2 passes, resolve remaining markers yourself or ask the user; do not run with
open markers.

## Step 3: RUN (BLOCKING)

Kick the runner synchronously and wait for it to exit:

```bash
CO_EVOLVE_TOKEN_CAPTURE=1 bash dev-review/codex/dev-review.sh \
  --preset claude-build --skip-plan --plan "$PLAN_FILE" \
  --worktree auto \
  -- "<task>"
```

For a revision re-kick, add `--parent-run <previous-run-id>` and use the revised
plan file. The parent id is lineage only; every re-kick gets a fresh run dir.

Do not background this command in Phase 1. Codex cannot wake itself on runner
exit, so detached execution would only create an orphaned process without a
reliable gate.

## Step 4: GATE

After the blocking runner exits, read status first:

```bash
bash dev-review/codex/dev-review-status.sh --json <run-id>
```

The status reader contract provides `status`, `verdict`, `verdict_json`,
`verdict_present`, `diffstat_tail`, `current_phase`, `marker_counts`, `assess`,
and its own terminal exit code. The verdict file follows
`skills/dev-review/schemas/review-verdict.json`.

Then inspect narrowly:

1. Read `verdict.json` from `.verdict_json`.
2. Read the diffstat and only the changed files needed to spot-check the verdict.
3. Decide one gate outcome.

### ACCEPT

Accept only when `verdict` is `APPROVED` and Codex's own spot-check finds no
material issue. Never auto-merge.

### REVISE

Revise when the verdict is `REVISE` or the spot-check finds a fixable issue, and
the orchestrator has not exhausted its revise budget. Write a revised plan in
`$TMPDIR`, preserve the original scope, and re-run Step 3 with
`--parent-run <current-run-id>`.

### ESCALATE

Escalate on any missing verdict, non-zero runner exit, status-reader failure,
scope creep, repeated identical feedback, or exhausted revise rounds. Report the
run dir, plan path, verdict path if present, diffstat, and the concrete blocker.

## Step 5: BUDGET

Codex gets at most 2 orchestrator revise rounds. The runner's internal
`--revise-loop 1` can add one cheap execute retry inside each run, but that does
not increase the orchestrator budget. Round 3 is an escalation.

Never auto-merge. The gate decides whether to accept, revise, or escalate; a
human still controls merge/push policy.

## Future: detached mode (design only)

A future `claude-build.sh` wrapper could background the runner with `nohup`,
print a run id, and let a polling driver watch:

```bash
nohup bash dev-review/codex/dev-review.sh \
  --preset claude-build --skip-plan --plan "$PLAN_FILE" \
  --worktree auto -- "<task>" &

while true; do
  sleep 30
  bash dev-review/codex/dev-review-status.sh --json <run-id>
  # stop on terminal status-reader exits: 0, 2, or 4
done
```

That mode is not implemented in this milestone. It adds orphan handling,
stale-pid detection, and no-auto-wake failure modes, and it only pays off for
very long Claude builds. Until the wrapper and polling contract exist, use the
synchronous Phase 1 protocol above.
