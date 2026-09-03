---
name: codex-build
description: >
  Orchestrate Codex to BUILD code in the background while this Claude Code
  session (typically Opus) plans and reviews — never babysitting. The session
  composes the implementation plan, kicks the dev-review runner detached via a
  background Bash task with --preset codex-build, ENDS ITS TURN, and is woken on
  exit to run a schema-bound review gate (ACCEPT / REVISE / ESCALATE, max 2
  rounds). Use when the user wants to "build with codex", "have codex build",
  "have codex implement", "orchestrate codex", "kick off codex in the
  background", "let codex grind", or "codex builds while I review". For an
  interactive single-session compose-bounce-execute loop with no detach, use
  /dev-review. For non-code document refinement, use /co-evolution.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# /codex-build - Detached Codex Execution with Gate-Based Review

This is the **orchestration protocol** behind the "best Claude plans, Codex
executes, best Claude reviews" model ladder. The session is the composer and the
reviewer; Codex
is the executor. The defining rule: **the session is never kept busy while Codex
grinds.** You kick the runner as a background task, end your turn, and the
harness wakes you when it exits.

Use `/dev-review` instead when you want the classic interactive
compose-bounce-execute loop in one session (you watch every pass). Use
`/co-evolution` for questions, drafts, plans, and document refinement with no
code execution.

The protocol has five steps. Steps 1-3 happen in the FIRST turn (preflight,
plan, kick-and-stop). Steps 4-5 happen on WAKE, after the background task exits.

---

## Step 1: PREFLIGHT (one turn, before planning)

Run these checks. Each gate either passes, degrades with a stated fallback, or
dies with a fix hint.

### Codex present

```bash
command -v codex
```

If missing, die with the install hint:

```text
codex CLI not found. On this Mac with Codex.app installed:
  ln -s "/Applications/Codex.app/Contents/Resources/codex" ~/.local/bin/codex
Otherwise install the CLI:
  npm i -g @openai/codex
Then re-run /codex-build.
```

### Claude CLI auth probe (decides the verifier seat)

The runner's `claude` verifier seat runs in a headless shell that does NOT carry
the interactive app's session token. Probe it:

```bash
claude -p --output-format text --model claude-haiku-4-5-20251001 "ping" 2>&1 | head -2
```

- If the output contains `Not logged in` (or `/login`): the runner's claude
  verifier seat cannot run. **DEGRADE** — kick with `--verifier codex` so the
  verify phase uses Codex's schema-bound review instead. Tell the user plainly:
  the in-session review gate (Step 4, which YOU run) is then the only Claude-side
  review of the diff, and to run `claude /login` in a terminal to restore the
  full ladder (the claude verifier seat inside the runner).
- Otherwise: the full ladder is available. Kick with the preset's default claude
  verifier (best/Opus, max effort) — no `--verifier` override needed.

### No other active run

```bash
bash dev-review/codex/dev-review-status.sh --list
```

If the `ACTIVE` section shows a non-terminal run (`status=pending` or
`status=null`), do NOT kick a second one — one orchestrated run per workdir.
Either wait for it (check its status on wake) or escalate to the user.

### Isolation — clean vs dirty tree

```bash
git -C "$(pwd)" status --short
```

- **Clean tree** → kick with `--branch auto` (the runner cuts
  `dev-review/auto-<ts>-<slug>` off HEAD before execute).
- **Dirty tree** → kick with `--worktree auto` (required). A dirty tree
  otherwise makes the runner's verify phase silently skip: it returns early with
  `verification skipped - workdir had pre-existing uncommitted changes` because
  it cannot isolate this run's diff. `--worktree auto` gives Codex a clean
  sibling checkout so verify runs against an isolatable diff.

### Local clone, never an SMB mount

The workdir must be a local git clone. Never run from a network/SMB mount
(`/Volumes/...`, `\\server\...`) — it causes line-ending churn and the runner's
diff isolation is unreliable. If the cwd is a mount, stop and ask the user to
point at a local clone.

---

## Step 2: PLAN (in-session — the session is the composer)

This is the cheap, interactive part. You explore and write the plan; you do NOT
hand planning to Codex.

1. Explore the codebase with Read / Grep / Glob (or an Explore Agent for
   fan-out). Understand the task, the files involved, and the conventions.
2. Write the implementation plan to a temp file **outside the workdir**:

   ```bash
   PLAN_FILE="${TMPDIR:-/tmp}/codex-build-plan-$(date +%Y%m%d-%H%M%S).md"
   ```

   **Never** write the plan inside the workdir. An untracked plan file there
   makes the runner's verify phase skip (`run left untracked files that cannot
   be diffed automatically`). **Never** pass the plan path inside a prompt to
   Codex — per repo convention the runner embeds plan content inline; the
   orchestrator is the sole owner of the canonical plan file.

3. Shape the plan the way `--skip-plan --plan FILE` expects. The runner's plan
   validator wants a real plan artifact: a top-level heading, >= ~60 words, >= 5
   non-empty lines, and >= 2 structural lines (headings / bullets). Write the
   plan with these sections:

   ```text
   # <Task title>

   ## Approach
   <what will be built and the key technical decisions>

   ## Files to Change
   - `path/to/file` — <what changes and why>

   ## Steps
   1. <ordered implementation steps>

   ## Risks / Out of scope
   - <risks, and anything explicitly NOT in scope>
   ```

   A thin or malformed plan makes the runner's plan-quality gate fail before
   execute.

### Optional plan hardening (≤ 2 synchronous bounce passes)

For higher-stakes work, harden the plan against Codex BEFORE kicking, using the
bounce protocol markers. This is the only synchronous Codex use in this skill —
keep it short (a plan bounce is seconds-to-low-minutes, well under the 5-minute
synchronous ceiling):

- Send the plan to Codex asking it to critique with `[CONTESTED]` (disagreement
  + counter-argument) and `[CLARIFY]` (ambiguity + two interpretations) markers.
- Resolve EVERY `[CONTESTED]` / `[CLARIFY]` before kicking. Apply the 2-pass
  expiry rule: any marker still open after 2 passes — decide it yourself or ask
  the user. Do not kick with open markers.

If you skip hardening, that is fine for routine tasks — go straight to Step 3.

---

## Step 3: KICK + END TURN (the load-bearing step)

Kick the runner as a **background** Bash task, report the run id, and **end your
turn**. This is what makes the model ladder pay off — the session pays only for
plan + review gates, not for watching Codex grind.

Run this with the Bash tool, **`run_in_background: true`**:

```bash
CO_EVOLVE_TOKEN_CAPTURE=1 bash dev-review/codex/dev-review.sh \
  --preset codex-build --skip-plan --plan "$PLAN_FILE" \
  [--verifier codex] \
  [--branch auto | --worktree auto] \
  [--parent-run <previous-run-id>] \
  [--timeout 1800] \
  -- "<task description>"
```

Fill the brackets from Step 1:
- `--verifier codex` ONLY when the auth probe degraded (else omit — the preset's
  best/max claude verifier is the default).
- `--branch auto` for a clean tree; `--worktree auto` for a dirty tree.
- `--parent-run <id>` only on a REVISE re-kick (Step 4), to tag lineage.
- `--timeout` defaults to 1800s; raise it for large tasks.

The preset expands to: composer = Opus (high),
executor = Codex (xhigh, model pinned to `gpt-5.6-sol`),
verifier = Opus (max), `--verify` on, bounces 2,
revise-loop 1. The two Claude seats default through the `best` alias (currently
`claude-opus-4-8`), so a future model bump is a one-line edit in
`resolve_claude_model_alias` (now in `lib/co-evolution.sh`). The codex executor
seat is model-pinned (A-3), so a preset run reproduces across machines rather than
inheriting the local codex `config.toml`; ad-hoc (non-preset) runs may still
inherit it. `CO_EVOLVE_TOKEN_CAPTURE=1` records per-phase tokens into `state.json`
so you can report spend at the gate.

**Optional — make the seats follow THIS session's model.** By default the plan and
review seats run `best` (a strong model) regardless of what you're driving the
session with. To instead pin them to a specific model — e.g. match the session
you're in — prepend the seat env vars to the kick (fill-if-empty means they win
over the preset):

```bash
COMPOSER_MODEL=claude-opus-4-8 VERIFIER_MODEL=claude-opus-4-8 \
CO_EVOLVE_TOKEN_CAPTURE=1 bash dev-review/codex/dev-review.sh \
  --preset codex-build --skip-plan --plan "$PLAN_FILE" -- "<task>"
```

Only the Claude seats follow this; Codex always executes. A weak model here means
weak planning/review — keep these on a strong model.

After kicking:
1. Capture the run id. It is `dev-review-<timestamp>` and the run dir is
   `runs/dev-review-<timestamp>/`. Read it from the runner's early stdout, or
   resolve the newest run with `ls -dt runs/dev-review-* | head -1`.
2. Report to the user: the run id, and how to check it manually —
   `bash dev-review/codex/dev-review-status.sh <run-id>` (human) or `--json`
   (machine).
3. **END THE TURN.**

### Hard rules for Step 3

- Do **NOT** poll. Do **NOT** sleep. Do **NOT** loop waiting on status.
- Do **NOT** run Codex synchronously for anything expected to take longer than
  ~5 minutes — that defeats the entire purpose (the session burns cache reads
  every turn while idle, the exact anti-pattern this skill exists to avoid).
- The harness re-invokes this session when the background task exits. **That
  notification IS the wake signal.** You do not build the wake mechanism.
- Optional safety net for very long runs (reference, do not build inline): a
  one-shot scheduled reminder that re-checks status after the expected duration,
  in case a machine-sleep drops the wake notification.

---

## Step 4: WAKE → REVIEW GATE (1-2 turns, after the background task exits)

When the background task exits, you are re-invoked. Reconstruct state from disk —
read the status JSON FIRST, then read narrowly. Do not re-read the whole tree.

```bash
bash dev-review/codex/dev-review-status.sh --json <run-id>
```

This emits one object with: `status`, `verdict` (APPROVED / REVISE / null),
`verdict_json` (path to `verdict.json`), `verdict_present`, `diffstat_tail`,
`current_phase`, `marker_counts`, `assess`, and `exit_code` (the status reader's
liveness code: 0 done / 2 partial / 4 presumed-dead / 5 running / 3 no-run).

**The gate reads the status JSON only — never the raw runner logs.** The status
reader is the contract; `runs/<run-id>/*.log` (compose/execute/review stderr) and
the runner's stdout are noisy and not the interface. Base every ACCEPT / REVISE /
ESCALATE decision on the `--json` object plus the narrow reads below (`verdict.json`,
diffstat, named `issues[]` hunks). Only crack open a raw log when ESCALATING for a
human — and even then, hand the log path to the user rather than pasting its
contents into your reasoning.

Then, BEFORE reading any source files:
1. Read `verdict.json` (the path is in `.verdict_json`) — the schema-bound
   verdict: `verdict`, `confidence`, `summary`, `issues[]`,
   `scope_creep_detected`.
2. Read the diffstat (`.diffstat_tail`, or
   `runs/<run-id>/execute-diffstat.txt`).

Only THEN read targeted diff hunks and the specific files named in `issues[]`.
Never re-read the whole tree to form an opinion.

Decide exactly ONE of three outcomes.

### ACCEPT

Conditions: verdict is `APPROVED` AND your own spot-check of the named diff
hunks agrees. Report and finish:

- Branch or worktree path (where the code landed).
- Diffstat (files changed, insertions/deletions).
- Verdict confidence and one-line summary.
- Token totals:

  ```bash
  jq '.tokens.totals' runs/<run-id>/state.json
  ```

- Your own turn count for this orchestration (plan + kick + this gate).
- Suggested next step: merge / PR commands, e.g.
  `git checkout master && git merge <branch>` or `gh pr create`.

Then you are done. **Never auto-merge** — surface the commands for the user.

### REVISE (max 2 orchestrator rounds total)

Conditions: verdict is `REVISE`, or your spot-check finds a real, fixable
problem, AND you have not already used 2 revise rounds.

1. Copy the plan file to a new path (keep the original; lineage is by file):

   ```bash
   REVISE_PLAN="${TMPDIR:-/tmp}/codex-build-plan-$(date +%Y%m%d-%H%M%S)-rN.md"
   cp "$PLAN_FILE" "$REVISE_PLAN"
   ```

2. Append a corrections section with **file-specific, actionable** fixes drawn
   from `issues[]` and your spot-check:

   ```text
   ## Reviewer Corrections (Round N)
   - `path/to/file`: <concrete fix — what to change and to what>
   ```

3. Re-kick Step 3 with the new plan and `--parent-run <this-run-id>` (tags the
   re-kick's lineage). Then END THE TURN again.

Never re-kick on identical feedback twice — if the same issue survives a round,
that is an ESCALATE, not another REVISE.

### ESCALATE

Conditions (any): verdict missing (`verdict_present: false` /
`verdict: null`) · runner exited non-zero (status `failed`) · status reader exit
4 (presumed-dead runner) · 2 revise rounds exhausted · `scope_creep_detected:
true`.

Write a concise human summary — do NOT auto-merge, do NOT silently retry:
- What was attempted (task, rounds used).
- Artifact paths (run dir, `verdict.json`, diffstat, the plan file).
- Open issues (from `issues[]` and/or the dead-runner assessment).
- Recommended manual step (inspect the worktree, re-kick with `--skip-plan`,
  fix by hand, etc.).

---

## Step 5: BUDGET + TROUBLESHOOTING

### Budget rules

- **Max 2 orchestrator revise rounds.** Round 3 is an ESCALATE.
- The runner's internal `--revise-loop 1` (set by the preset) adds at most one
  cheap automatic retry per kick, INSIDE the runner — that is separate from and
  cheaper than your orchestrator rounds. You still cap your own re-kicks at 2.
- **One orchestrated run per workdir.** The Step 1 `--list` check enforces this.

### Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| status reader exits 4 (presumed-dead) | runner process gone mid-phase | `pkill -f 'codex exec'` to clear orphans, then re-kick `--skip-plan --plan "$PLAN_FILE"` (add `--parent-run <dead-run-id>`) |
| Machine slept during the run | wake notification may have been dropped | Run the status script manually; do not assume the run failed |
| `tokens` block missing from state.json | `CO_EVOLVE_TOKEN_CAPTURE=1` was not set, or `jq` is missing | Re-kick with the flag set; install `jq` for token capture |
| Verify silently skipped | dirty tree kicked without `--worktree auto`, or run left untracked files | Re-kick on a clean tree with `--branch auto`, or `--worktree auto` |
| `claude` verifier seat errors mid-run | headless shell not logged in | Re-kick with `--verifier codex`; run `claude /login` to restore the claude verifier seat |

---

## Transport B: the OpenAI plugin (secondary, interactive flavor)

When you are already mid-session on small ad-hoc work and want to delegate a
quick build/fix to Codex without the full runner, the official OpenAI plugin is
a supported alternative.

Install (one-time, non-interactive):

```bash
claude plugin marketplace add openai/codex-plugin-cc
claude plugin install codex@openai-codex
```

It provides `/codex:rescue --background` (delegate a task to Codex detached),
`/codex:status` (check the job), `/codex:result` (fetch the result), and
`/codex:cancel`.

Protocol when using the plugin:
1. Delegate execution to `codex-rescue` (or `/codex:rescue --background`).
2. Apply the **same review contract** in-session: read the diff and fill the
   review-verdict JSON yourself (`skills/dev-review/schemas/review-verdict.json`
   — `verdict`, `confidence`, `summary`, `issues[]`, `scope_creep_detected`).
3. Same `≤ 2`-round revise cap. Same **never auto-merge** rule.

State plainly to the user: the plugin path shares our templates/schema **by
convention** but is **NOT** exercised by evals/CI — there is no `--output-schema`
contract enforced through it (you fill the verdict by hand), and it is pinned to
the plugin's major version (`v1.x`). Format drift in the plugin's output is the
plugin's risk, not ours. The runner path (Transport A above) is the one that
carries CI.

---

## Notes

- **Why detached, not babysat:** the post that inspired this (strong model plans,
  Codex executes, strong model reviews) keeps a session supervising inline,
  burning cache reads every turn. This skill kicks the runner via background Bash,
  ends the turn, and gets woken on exit — the session pays only for plan + review
  gates.
- **The preset is the single source of truth for the seats.** `codex-build`
  expands to best/high · Codex/xhigh · best/max · verify on · bounces 2 ·
  revise-loop 1, inside `dev-review/codex/dev-review.sh` (`apply_preset`). The
  `best` alias resolves to the current Opus line. The
  preset triple is pinned by `tests/docs-sync-simulation.sh` so this doc and the
  runner cannot drift.
- **Live-mode caveat:** `--live` codex windows ignore model/effort overrides
  (documented v1 limitation in /dev-review). This skill does not use `--live`.
- **Plan ownership:** the orchestrator owns the canonical plan file; Codex only
  ever receives plan content inline (embedded by the runner) and writes to a
  separate output. Never let Codex see the canonical plan path.
