---
name: dev-review
description: >
  Automated plan-bounce-execute workflow between Claude Code (Opus) and Codex CLI.
  One AI composes a plan, it bounces between agents with [CONTESTED]/[CLARIFY]
  markers until refined, then the designated agent executes the code.
  Replaces manual copy-paste between Claude Code and Codex desktops.
  Triggers on "dev review", "dev-review", "plan bounce", "bounce between agents",
  "have codex review", "cross-AI", "developer reviewer loop", "compose and review".
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, EnterWorktree, ExitWorktree
---

# /dev-review - Plan-Bounce-Execute Workflow

Automates the workflow of composing a plan with one AI, bouncing it between agents
for refinement using [CONTESTED]/[CLARIFY] markers, then having one agent execute
the final plan into code. Replaces manual copy-paste between Claude Code and Codex.

When `--live` is enabled on Windows, each Codex pass runs in a visible PowerShell
window so the user can watch progress in real time. The handoff contract stays
file-based: prompts are written to disk, Codex writes the final message to disk,
and Claude Code reads the resulting artifact before continuing.

The workflow has three phases:
1. **Compose** - One agent creates the initial plan/approach
2. **Bounce** - The plan document bounces between agents, each editing it directly
3. **Execute** - The designated agent writes the final code from the refined plan

## Step 1: Parse Arguments

Parse `$ARGUMENTS` for:

```text
/dev-review [--composer opus|codex] [--executor opus|codex] [--bounces N|auto] [--verify] [--worktree] [--model MODEL] [--skip-plan] [--plan-only] [--live] <task description>
```

Defaults:
- `--composer opus` (Opus creates the initial plan)
- `--executor codex` (Codex writes the final code)
- `--bounces auto` (bounce until convergence — zero [CONTESTED] and zero [CLARIFY]
  markers — up to a max of 6 passes. If not converged after 6, stop and ask the user
  to arbitrate the remaining markers. Use `--bounces N` to override with a fixed count.)
- `--verify` if set, adds a final code review pass after execution
- `--model` overrides Codex model
- `--worktree` creates isolated worktree
- `--skip-plan` jumps straight to code execution (backward compat with old behavior)
- `--plan-only` stops after the bounce phase, outputs the refined plan
- `--live` opens visible Windows terminal windows for Codex passes; if unavailable,
  warn once and fall back to the current headless behavior
- Remaining text = task description

The reviewer is always the agent that is NOT the composer.

Validation:
- If task is empty, ask: "What should be built?"

Store parsed values:
- `$COMPOSER` = opus | codex (who creates the initial plan)
- `$EXECUTOR` = opus | codex (who writes the final code)
- `$REVIEWER` = the other agent (whoever is not the composer in each bounce)
- `$BOUNCES` = integer or "auto". If "auto" (default), bounce until convergence up to
  max 6 passes. If integer, use that fixed count. NOT round trips - 4 passes = 2 round trips.
- `$VERIFY` = boolean
- `$TASK` = remaining text
- `$USE_WORKTREE` = boolean
- `$CODEX_MODEL` = model override or empty
- `$SKIP_PLAN` = boolean
- `$PLAN_ONLY` = boolean
- `$LIVE_MODE` = boolean (requested live Codex windows)

### Common Patterns (display these in help)

```text
# Opus-heavy workflow: Opus composes, auto-converge bouncing, Opus executes
/dev-review --composer opus --executor opus Build a dashboard for API metrics

# Reverse: Codex composes, Opus reviews, Codex executes
/dev-review --composer codex --executor codex --bounces 4 Add retry logic to the API client

# Quick: Opus plans, 2 bounces, Codex executes
/dev-review --bounces 2 Fix the date parsing bug

# Just plan, don't execute yet
/dev-review --plan-only Build a real-time notification system

# Watch each Codex pass in a visible terminal window on Windows
/dev-review --live --bounces 2 Fix a bug in the billing service

# Skip planning, just execute and review (old behavior)
/dev-review --skip-plan --verify Rename getUserData to fetchUserProfile
```

## Step 2: Environment Detection

Run these checks:

```bash
# Check if in a git repo
git rev-parse --is-inside-work-tree 2>/dev/null && echo "GIT=true" || echo "GIT=false"

# Check codex availability
command -v codex >/dev/null 2>&1 && codex --version 2>/dev/null || echo "CODEX=missing"

# Check working tree status
git status --porcelain 2>/dev/null | head -5
```

If `$LIVE_MODE` is true, extend detection before any Codex pass runs:
- Detect whether the current platform is Windows. First release is Windows-only.
- Resolve the native Windows path to `powershell.exe`.
- Resolve the native Windows path to `codex.ps1` or `codex.cmd`, preferring `codex.ps1`.
- Resolve the native Windows form of the working directory and every temp artifact path
  only when crossing into the visible launcher.
- If any required live-launch path cannot be resolved, display exactly:
  `WARNING: --live unavailable; falling back to headless Codex`
  Then set `$LIVE_ACTIVE=false` and continue with the existing headless flow.

Recommended live-mode state:
- `$LIVE_ACTIVE` = boolean (live requested and available on this machine)
- `$LIVE_POWERSHELL_WIN` = native Windows path to `powershell.exe`
- `$LIVE_CODEX_WIN` = native Windows path to `codex.ps1` or `codex.cmd`
- `$WORKDIR_WIN` = native Windows working directory used by visible Codex windows

Decision matrix:
- **GIT=false**: Set `$FILE_MODE=true`. Skip branch creation.
- **CODEX=missing** and Codex is needed: Error with install instructions. Suggest all-opus fallback.
- **Dirty working tree** and not `$USE_WORKTREE`: Warn but continue.
- **`--live` on non-Windows, or launcher unresolved**: Warn once, set `$LIVE_ACTIVE=false`,
  and keep the existing headless Codex behavior.

## Step 3: Setup

### If git repo and not $FILE_MODE:
```bash
BRANCH="dev-review/$(date +%Y%m%d-%H%M%S)"
git checkout -b "$BRANCH"
```

### If $USE_WORKTREE:
Use `EnterWorktree` tool.

### Display session banner:
```text
============================================
 DEV-REVIEW SESSION
============================================
 Task:      $TASK
 Composer:  $COMPOSER (creates initial plan)
 Executor:  $EXECUTOR (writes final code)
 Bounces:   $BOUNCES passes
 Verify:    $VERIFY
 Live:      yes|no
 Branch:    $BRANCH (or "file mode")
============================================
```

Use `Live: yes` only when `$LIVE_ACTIVE=true`. If `--live` was requested but fell back,
the warning from Step 2 is enough; still render the banner as `Live: no`.

### Initialize the plan document:
Create `/tmp/dev-review-plan-{timestamp}.md` - this is the living document that bounces.

### Shared helper: `launch_codex_live`

Use one helper for every live Codex pass: compose, bounce, execute, and verify.
It changes only the launch mode. Prompt files, output files, and schema files remain
the same artifacts the workflow already uses.

Responsibilities:
- Generate a unique run ID: `{timestamp}-{phase}-{pass}`
- Create a unique wrapper script: `/tmp/dev-review-live-{run_id}.ps1`
- Create unique sidecars:
  - `/tmp/dev-review-live-{run_id}.done`
  - `/tmp/dev-review-live-{run_id}.exitcode`
  - `/tmp/dev-review-live-{run_id}.pid`
- Launch a visible PowerShell window with a descriptive title
- Poll from Claude Code until `.done` appears, the process disappears, or 300s timeout
- Return the exit code and the output artifact path

Before launch, convert the POSIX working directory and all prompt/output/schema/sentinel
paths to native Windows form. Do this only at the launcher boundary. The underlying
workflow continues to use the same `/tmp/dev-review-*` files.

PowerShell wrapper shape:

```powershell
param(
  [string]$Title, [string]$CodexPath, [string]$WorkDir,
  [string]$PromptPath, [string]$OutputPath, [string]$DonePath,
  [string]$ExitPath, [string]$Mode, [string]$SchemaPath
)
$Host.UI.RawUI.WindowTitle = $Title
Write-Host "============================================"
Write-Host " $Title"
Write-Host "============================================"
try {
  if ($Mode -eq "exec") {
    Get-Content -Raw $PromptPath | & $CodexPath exec --full-auto -C $WorkDir -o $OutputPath -
  } elseif ($Mode -eq "exec-schema") {
    Get-Content -Raw $PromptPath | & $CodexPath exec --full-auto -C $WorkDir --output-schema $SchemaPath -o $OutputPath -
  } elseif ($Mode -eq "review") {
    Get-Content -Raw $PromptPath | & $CodexPath review - 2>&1 | Tee-Object -FilePath $OutputPath
  }
  $status = $LASTEXITCODE
} finally {
  Set-Content -NoNewline $ExitPath $status
  Start-Sleep -Seconds 5
  New-Item -ItemType File -Force $DonePath | Out-Null
}
```

Launch from Claude Code:

```bash
LIVE_PID=$(powershell.exe -NoProfile -Command "
  \$p = Start-Process -FilePath 'powershell.exe' \
    -ArgumentList '-NoLogo','-ExecutionPolicy','Bypass','-File','$SCRIPT_WIN' \
    -PassThru; \$p.Id")
```

Helper behavior:
- Save `LIVE_PID` to `/tmp/dev-review-live-{run_id}.pid`.
- Poll until the `.done` sentinel exists, the PID no longer exists, or 300 seconds pass.
- If the PID disappears before `.done` exists, treat the pass as interrupted because the
  user closed the window early. Surface that state and offer retry or abort.
- Read the exit code from `.exitcode` after completion.
- Keep the window open for a 5-second read delay before the wrapper writes `.done`, so the
  user can see the final Codex output and only one live window is open at a time.

Pseudo-implementation:

```bash
launch_codex_live() {
  local TITLE="$1"
  local MODE="$2"          # exec | exec-schema | review
  local PROMPT_PATH="$3"
  local OUTPUT_PATH="$4"
  local SCHEMA_PATH="$5"
  local PHASE="$6"
  local PASS="$7"

  local RUN_ID="$(date +%Y%m%d-%H%M%S)-${PHASE}-${PASS}"
  local SCRIPT_POSIX="/tmp/dev-review-live-${RUN_ID}.ps1"
  local DONE_POSIX="/tmp/dev-review-live-${RUN_ID}.done"
  local EXIT_POSIX="/tmp/dev-review-live-${RUN_ID}.exitcode"
  local PID_POSIX="/tmp/dev-review-live-${RUN_ID}.pid"

  # Convert WORKDIR, PROMPT_PATH, OUTPUT_PATH, SCHEMA_PATH, SCRIPT_POSIX,
  # DONE_POSIX, EXIT_POSIX, and PID_POSIX to native Windows paths here.

  # Write the wrapper script to SCRIPT_POSIX using the PowerShell shape above.

  LIVE_PID=$(powershell.exe -NoProfile -Command "
    \$p = Start-Process -FilePath 'powershell.exe' \
      -ArgumentList '-NoLogo','-ExecutionPolicy','Bypass','-File','$SCRIPT_WIN', \
      '-Title','$TITLE','-CodexPath','$LIVE_CODEX_WIN','-WorkDir','$WORKDIR_WIN', \
      '-PromptPath','$PROMPT_WIN','-OutputPath','$OUTPUT_WIN','-DonePath','$DONE_WIN', \
      '-ExitPath','$EXIT_WIN','-Mode','$MODE','-SchemaPath','$SCHEMA_WIN' \
      -PassThru; \$p.Id")

  printf '%s' "$LIVE_PID" > "$PID_POSIX"

  # Poll for .done, missing PID, or timeout.
  # On missing PID before .done, treat as interrupted.
  # On timeout, route to the existing retry logic for Codex timeout.
  # Return the exit code read from EXIT_POSIX.
}
```

## Step 4: Compose Phase

The composer creates the initial plan document.

**If $COMPOSER = opus:**

Claude Code reads the task, explores the codebase (Read, Glob, Grep), and writes
the initial plan directly to the plan document. The plan should include:
- What will be built
- Key technical decisions
- File structure / changes needed
- Implementation approach
- Any open questions marked with [CLARIFY]

Write the plan to the plan document file.

**If $COMPOSER = codex:**

Build a compose prompt and execute:

```bash
COMPOSE_PROMPT="You are creating an implementation plan for the following task.

TASK: $TASK

WORKING DIRECTORY: $(pwd)

Create a detailed plan that includes:
- What will be built
- Key technical decisions and rationale
- File structure and changes needed
- Implementation approach step by step
- Mark anything you're unsure about with [CLARIFY] followed by two possible interpretations

Output ONLY the plan document. No preamble."
```

If `$LIVE_ACTIVE=true`, write the compose prompt to a temp prompt file and launch:

```bash
printf '%s' "$COMPOSE_PROMPT" > /tmp/dev-review-compose-prompt.md
launch_codex_live "Codex - Compose" "exec" \
  /tmp/dev-review-compose-prompt.md \
  /tmp/dev-review-plan-{timestamp}.md \
  "" \
  "compose" \
  "0"
```

If `$LIVE_ACTIVE=false`, keep the existing headless behavior:

```bash
printf '%s' "$COMPOSE_PROMPT" | codex exec --full-auto -C "$(pwd)" -o /tmp/dev-review-plan-{timestamp}.md
```

**Important:** Always pipe plan content through stdin or embed it in the prompt file.
Never reference the plan file path in a way that Codex could discover and edit it
directly. Codex runs with `--full-auto` (full filesystem write access), so any file
path it can see is a file it can modify. The orchestrator is the sole owner of the
canonical plan file; Codex only ever receives plan content as inline text and writes
output to a separate `-o` path.

Display: "Plan composed by $COMPOSER. Starting bounce phase."

If `$SKIP_PLAN` is true: skip this entire step. The "plan" is just the task description itself, and we go straight to Step 6 (Execute).

## Step 5: Bounce Phase

The plan document bounces between agents. Each pass, the receiving agent:
1. Reads the plan as-is
2. Edits it directly (improves where they agree)
3. Adds [CONTESTED] notes where they disagree
4. Adds [CLARIFY] notes where something is ambiguous
5. Resolves any existing [CONTESTED]/[CLARIFY] notes from the previous pass

The bounce alternates: composer -> reviewer -> composer -> reviewer -> ...
Pass 1 goes to the reviewer (since the composer just wrote it).

### Bounce loop:

If `$BOUNCES` = "auto": set `$MAX_BOUNCES` = 6, `$AUTO_CONVERGE` = true.
If `$BOUNCES` = integer: set `$MAX_BOUNCES` = that integer, `$AUTO_CONVERGE` = false.

For each bounce pass (1 to $MAX_BOUNCES):

Determine whose turn it is:
- Odd passes (1, 3, 5...): REVIEWER's turn
- Even passes (2, 4, 6...): COMPOSER's turn

Read the current plan document from the file.

Read the bounce protocol template from `~/.claude/skills/dev-review/templates/bounce-protocol.md`.

Fill placeholders:
- `{PLAN_CONTENT}` = current plan document contents
- `{TASK}` = original task
- `{PASS_NUMBER}` = current pass
- `{TOTAL_PASSES}` = total bounces
- `{YOUR_ROLE}` = "reviewer" or "composer"

**If current agent = opus:**

Claude Code reads the plan document, applies the bounce protocol rules, and edits
the plan document directly using the Write tool. Claude should:
- Read the plan carefully
- Make improvements where it agrees
- Add [CONTESTED] notes where it disagrees (with counter-argument and concrete example)
- Add [CLARIFY] notes where ambiguous (with two interpretations or a specific question)
- Resolve any existing [CONTESTED]/[CLARIFY] from previous pass
- Write the updated plan back to the file

**If current agent = codex:**

```bash
# Read current plan content into the prompt — never pass the plan file path to Codex
PLAN_CONTENT=$(cat /tmp/dev-review-plan-{timestamp}.md)

# Build the bounce prompt with plan content embedded inline
cat > /tmp/dev-review-bounce-prompt.md << 'BOUNCE_EOF'
{filled bounce-protocol template with PLAN_CONTENT embedded}
BOUNCE_EOF
```

The bounce prompt file contains the full plan text inline. Codex receives it via
stdin or as a prompt file, and writes its revised plan to a **separate output file**
via `-o`. The orchestrator then reads from that output and overwrites the canonical
plan. Codex never sees the canonical plan file path.

If `$LIVE_ACTIVE=true`, launch the pass visibly:

```bash
launch_codex_live "Codex - Bounce {N}/{TOTAL}" "exec" \
  /tmp/dev-review-bounce-prompt.md \
  /tmp/dev-review-bounce-output-{timestamp}-{N}.md \
  "" \
  "bounce" \
  "{N}"
# Orchestrator overwrites canonical plan with Codex's output
cp /tmp/dev-review-bounce-output-{timestamp}-{N}.md /tmp/dev-review-plan-{timestamp}.md
```

If `$LIVE_ACTIVE=false`, keep the existing headless behavior:

```bash
printf '%s' "$(cat /tmp/dev-review-bounce-prompt.md)" | codex exec --full-auto -C "$(pwd)" -o /tmp/dev-review-bounce-output-{timestamp}-{N}.md
# Orchestrator overwrites canonical plan with Codex's output
cp /tmp/dev-review-bounce-output-{timestamp}-{N}.md /tmp/dev-review-plan-{timestamp}.md
```

### After each pass, display:

```text
--------------------------------------------
 BOUNCE {N}/{TOTAL} - {agent_name}'s pass
--------------------------------------------
 [CONTESTED] markers: {count}
 [CLARIFY] markers:   {count}
 Plan length:         {word_count} words
--------------------------------------------
```

Count markers by scanning for `[CONTESTED]` and `[CLARIFY]` in the document:

```bash
CONTESTED=$(grep -c '\[CONTESTED\]' /tmp/dev-review-plan-{timestamp}.md 2>/dev/null || echo 0)
CLARIFY=$(grep -c '\[CLARIFY\]' /tmp/dev-review-plan-{timestamp}.md 2>/dev/null || echo 0)
```

### Auto-convergence check (after each pass):

Count markers:
```bash
CONTESTED=$(grep -c '\[CONTESTED\]' /tmp/dev-review-plan-{timestamp}.md 2>/dev/null || echo 0)
CLARIFY=$(grep -c '\[CLARIFY\]' /tmp/dev-review-plan-{timestamp}.md 2>/dev/null || echo 0)
TOTAL_MARKERS=$((CONTESTED + CLARIFY))
```

**If TOTAL_MARKERS = 0:** The plan has converged. Display:
```text
Plan converged after {N} passes (no open markers).
```
Break out of the bounce loop. Proceed to Step 5b.

**If TOTAL_MARKERS > 0 and more passes remain:** Continue to the next pass.

**If TOTAL_MARKERS > 0 and this was the last pass ($MAX_BOUNCES reached):**

If `$AUTO_CONVERGE` is true (default "auto" mode): the plan did NOT converge within
the budget. Stop bouncing and escalate to the user for arbitration:

```text
============================================
 BOUNCE LIMIT REACHED — ARBITRATION NEEDED
============================================
 Passes used:   {N} / {$MAX_BOUNCES}
 Open markers:  {CONTESTED} [CONTESTED], {CLARIFY} [CLARIFY]
============================================

The agents could not fully agree within {$MAX_BOUNCES} passes.
Remaining disagreements are shown below.

{display each [CONTESTED] and [CLARIFY] marker with surrounding context}

Options:
 1. Resolve these yourself and continue to execution
 2. Add more bounces: /dev-review --bounces {N+4} --skip-plan "Continue: $TASK"
 3. Accept the plan as-is and execute with open markers
 4. Abort
```

Wait for user input. If the user picks option 1, let them edit the plan (or tell
Claude Code which side to take on each marker), then proceed to Step 5b. If option 3,
proceed with a warning. If option 4, exit.

If `$AUTO_CONVERGE` is false (fixed `--bounces N` mode): stop after N passes regardless.
Show marker count and proceed to Step 5b.

### Marker staleness rule:

If a [CONTESTED] or [CLARIFY] marker has survived 2 passes without being resolved,
the agent on the current pass MUST make a decision and remove it. This is enforced
by the bounce protocol template, not by the orchestrator.

## Step 5b: Display Refined Plan

After all bounces complete (or early convergence), display the final plan:

```text
============================================
 REFINED PLAN (after {N} bounces)
============================================
```

Read and display the plan document contents.

If any [CONTESTED] or [CLARIFY] markers remain, warn:

```text
WARNING: {count} unresolved markers remain in the plan.
```

If `$PLAN_ONLY`: stop here. Display:

```text
Plan saved to: /tmp/dev-review-plan-{timestamp}.md
To execute later: /dev-review --skip-plan --executor {$EXECUTOR} {$TASK}
```

Exit.

## Step 6: Execute Phase

The designated executor writes the actual code based on the refined plan.

**If $EXECUTOR = opus:**

Claude Code reads the refined plan and implements it directly using Edit, Write,
Read, Glob, Grep, and Bash tools. This is normal Claude Code development -
read existing code, match patterns, implement the plan, test.

After implementing, stage changes:

```bash
git add -A  # Safe on dedicated dev-review branch
```

**If $EXECUTOR = codex:**

Build an execution prompt that includes the refined plan:

```bash
cat > /tmp/dev-review-exec-prompt.md << 'EXEC_EOF'
You are implementing the following refined plan. This plan has been reviewed
and agreed upon by multiple AI agents. Implement it exactly as specified.

## Task
{$TASK}

## Refined Plan
{plan document contents}

## Instructions
- Implement the plan step by step
- Match existing code style
- Handle errors at system boundaries
- Write tests if the project has a test suite
- Stage and commit your changes
- Do NOT deviate from the plan
EXEC_EOF
```

If `$LIVE_ACTIVE=true`, launch visibly:

```bash
launch_codex_live "Codex - Execute" "exec" \
  /tmp/dev-review-exec-prompt.md \
  /tmp/dev-review-exec-output.md \
  "" \
  "execute" \
  "0"
```

If `$LIVE_ACTIVE=false`, keep the existing headless behavior:

```bash
codex exec --full-auto -C "$(pwd)" < /tmp/dev-review-exec-prompt.md > /tmp/dev-review-exec-output.md 2>&1
```

After execution, verify changes:

```bash
git diff --stat
```

If no changes: warn and ask user whether to retry or abort.

## Step 7: Verify Phase (Optional)

Only runs if `$VERIFY` is set.

After execution, the OTHER agent (not the executor) reviews the code diff
against the refined plan.

Capture the diff:

```bash
git diff --stat > /tmp/dev-review-diffstat.txt
git diff > /tmp/dev-review-diff.txt
# If committed:
if [ -z "$(git diff)" ] && [ -n "$(git diff HEAD~1)" ]; then
  git diff HEAD~1 --stat > /tmp/dev-review-diffstat.txt
  git diff HEAD~1 > /tmp/dev-review-diff.txt
fi
```

**If verifier = opus (subagent):**

Launch a Sonnet subagent with the review prompt from
`~/.claude/skills/dev-review/templates/review-prompt-opus.md`, filling:
- `{TASK}` = $TASK
- `{DIFF}` / `{DIFF_STAT}` = captured diff
- `{SESSION_LOG}` = the refined plan document (serves as context)

Parse the JSON verdict.

**If verifier = codex (two-pass):**

Pass 1: `codex review --uncommitted` (if available, skip if not)
- If `$LIVE_ACTIVE=true` and you run this pass, route it through `launch_codex_live`
  with mode `review`, title `Codex - Verify Review`, and output file
  `/tmp/dev-review-codex-rich-review.md`.
- If `$LIVE_ACTIVE=false`, keep the current headless `codex review` behavior.

Pass 2: `codex exec --output-schema` with the review prompt
- If `$LIVE_ACTIVE=true`, use `launch_codex_live` with title `Codex - Verify`,
  mode `exec-schema`, prompt `/tmp/dev-review-review-prompt.md`, output
  `/tmp/dev-review-verdict.json`, and schema path
  `~/.claude/skills/dev-review/schemas/review-verdict.json`.
- If `$LIVE_ACTIVE=false`, keep the existing headless `codex exec --output-schema`
  behavior.

Parse the JSON verdict.

### Judge pass:
Filter false positives (same as before - remove hallucinated file refs, pre-existing
issues, LOW-only blockers).

### Display result:

If APPROVED:

```text
Code verified against plan. Ready to merge.
```

If REVISE:

```text
Verifier found issues with the implementation:
{issues list}

Options:
- Fix issues: /dev-review --skip-plan --executor {$EXECUTOR} "Fix: {issues summary}"
- Accept anyway and merge manually
- Abort
```

## Step 8: Completion

```text
============================================
 DEV-REVIEW COMPLETE
============================================
 Task:       $TASK
 Composer:   $COMPOSER
 Executor:   $EXECUTOR
 Bounces:    {actual passes} / {max}
 Verified:   {yes/no}
 Confidence: {confidence}/100 (if verified)
============================================
 Next steps:
 - Review: git diff main..HEAD
 - Merge:  git checkout main && git merge $BRANCH
 - PR:     gh pr create
============================================
```

## Step 9: Cleanup

```bash
rm -f /tmp/dev-review-plan-*.md
rm -f /tmp/dev-review-compose-prompt.md
rm -f /tmp/dev-review-bounce-prompt.md
rm -f /tmp/dev-review-bounce-output-*.md
rm -f /tmp/dev-review-exec-prompt.md
rm -f /tmp/dev-review-exec-output.md
rm -f /tmp/dev-review-diff.txt
rm -f /tmp/dev-review-diffstat.txt
rm -f /tmp/dev-review-review-prompt.md
rm -f /tmp/dev-review-codex-rich-review.md
rm -f /tmp/dev-review-verdict.json
rm -f /tmp/dev-review-live-*.ps1
rm -f /tmp/dev-review-live-*.done
rm -f /tmp/dev-review-live-*.exitcode
rm -f /tmp/dev-review-live-*.pid
```

Leave the git branch. If worktree, prompt to keep/remove.

## Error Recovery

| Error | Detection | Response |
|-------|-----------|----------|
| Codex not found | `command -v codex` fails | Suggest all-opus mode |
| Codex timeout | Bash timeout 300s or live polling hits 300s | Offer retry or switch to opus for this pass |
| Codex failure | Non-zero exit | Show error, offer retry or abort |
| Live launcher unavailable | Windows path resolution fails or non-Windows platform | Warn once and fall back to headless Codex |
| Live terminal closed early | PID disappears before `.done` exists | Treat as interrupted, offer retry or abort |
| No code changes | Empty diff after execute | Ask user to clarify |
| Plan document empty | Empty file after bounce | Retry the pass |
| Markers stuck 2+ passes | grep count unchanged | Force resolution on current pass |
| Not git + worktree | git rev-parse fails | Drop worktree, warn, continue |

## GSD Integration

Dev-review is integrated into GSD workflows:
- `/gsd:execute-phase N --cross-ai` — delegates plan execution to dev-review via `--skip-plan --executor codex --verify`
- `/gsd:ship --review` — uses Codex + review-verdict schema as a code review gate before PR creation
- Enable globally: `gsd config-set workflow.cross_ai_execution true` or `gsd config-set workflow.code_review true`

## Notes

- **Cost**: Each Codex pass costs OpenAI tokens. A 4-bounce + execute + verify loop
  with Codex = ~7 codex exec calls.
- **Plan convergence**: Most plans converge (zero markers) in 2-3 bounces. The
  early termination check prevents wasting passes on an already-clean plan.
- **The bounce protocol** uses [CONTESTED]/[CLARIFY] markers as the coordination
  mechanism. This is lighter than JSON verdicts and produces a cleaner artifact.
- **Executor choice matters**: Codex (via `codex exec --full-auto`) has direct
  file access in its sandbox. Opus works through Claude Code's normal tool flow.
  Both produce working code; Codex is faster for greenfield, Opus is better when
  existing codebase context matters.
- **The plan document is the artifact**: Unlike chat history, the plan reads clean
  after every pass - as if one person wrote it. This is intentional per the bounce
  protocol.
- **`--live` is launch-mode only**: It does not change the artifact contract.
  Prompts still come from temp files, and the final Codex message still lands in
  the same output file before Claude Code continues.
- **`--live` is Windows-only in the first release**: On non-Windows platforms,
  warn once and continue headless.
- **Live windows auto-close after a short read delay**: The wrapper waits 5 seconds
  before writing `.done`, which gives the user time to read the terminal and keeps
  the workflow serialized to one visible Codex window at a time.
- **Codex never sees the canonical plan file path**: All plan content is embedded
  inline in the prompt (via stdin or prompt file). Codex writes its output to a
  separate `-o` file, and the orchestrator copies that back to the canonical plan.
  This prevents Codex from modifying the plan file directly via `--full-auto`
  filesystem access. Found during smoke testing: without this isolation, Codex
  edits the source plan on disk in addition to writing `-o` output.
