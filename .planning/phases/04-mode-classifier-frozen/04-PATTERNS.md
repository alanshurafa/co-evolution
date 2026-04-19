# Phase 4: Mode Classifier (frozen) - Pattern Map

**Mapped:** 2026-04-18
**Files analyzed:** 5 new files
**Analogs found:** 5 / 5 (100% coverage — Phase 4 is a pure mirror phase; every file has a concrete in-repo analog)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lab/pel/classifier/entry.sh` | controller (lab inhabitant entry point) | request-response (argv in → adapter dispatch out) | `agent-bouncer/agent-bouncer.sh` + Phase 3 dispatch call sites | role-match (first lab entry point ever) |
| `lab/pel/classifier/adapter.sh` | service (self-contained Haiku adapter) | request-response (prompt file → JSON stdout) | `lib/co-evolution.sh` `invoke_claude` (lines 336-370) + `agent-bouncer/agent-bouncer.sh` cleanup/validate idioms | role-match (adapter shape mirrored, not depended-on per D-05) |
| `lab/pel/classifier/prompt.md` | template (prompt-as-asset) | transform (read as data, composed by adapter) | `agent-bouncer/templates/bounce-protocol.md` | exact |
| `lab/pel/README.md` (or `lab/pel/classifier/README.md`) | config (env-var contract doc) | N/A (documentation) | `lab/README.md` + `dev-review/codex/README.md §Lab routing` | exact |
| `tests/classifier-simulation.sh` | test (hermetic simulation) | batch (per-scenario subshells, N/N final line) | `tests/lab-routing-simulation.sh` (Phase 3, 134 lines) + `evals/tests/scorer-verification.sh` (Phase 2, 234 lines) | exact |

---

## Pattern Assignments

### `lab/pel/classifier/entry.sh` (controller, request-response)

**Role:** argv-contract-compliant entry point resolved by `dispatch_lab_mode`. Owns the `--flavor <name>` override fast-path (D-09), env-var validation (D-03 + D-04), and adapter delegation. Receives `$TASK` as `$1` per W-3 contract.

**Analog A:** `agent-bouncer/agent-bouncer.sh` (sourcing + adapter dispatch style)
**Analog B:** Phase 3 dispatch call sites at `co-evolve-bouncer.sh:128-131` and `dev-review/codex/dev-review.sh:1059-1063` (the handshake entry.sh plugs INTO)

**Handshake entry.sh receives** — from `lib/co-evolution.sh:117-132`:

```bash
# dispatch_lab_mode <mode> <lab_root> <argv...>
#   Validates mode, resolves <lab_root>/<mode>/entry.sh, exec's it with remaining argv.
#   Never returns on success. Dies on invalid token, unknown mode, or missing entry.sh.
dispatch_lab_mode() {
  local mode="${1:?dispatch_lab_mode requires a mode}"
  local lab_root="${2:?dispatch_lab_mode requires a lab_root}"
  shift 2
  if ! validate_lab_mode "$mode"; then
    die "invalid --lab mode: $mode (must match [A-Za-z0-9_-]+)"
  fi
  local entry="$lab_root/$mode/entry.sh"
  if [[ ! -f "$entry" ]]; then
    local available
    available=$(list_available_lab_modes "$lab_root")
    die "unknown --lab mode: $mode. Available: $available"
  fi
  # exec replaces the current process — the lab inhabitant owns stdout/stderr/exit.
  exec bash "$entry" "$@"
}
```

Implication for `entry.sh`: it is `exec`'d with `$TASK` as `$1`. Full ownership of stdout/stderr/exit code from that moment on.

**Script header + set -euo pipefail + self-locating pattern** — from `agent-bouncer/agent-bouncer.sh:1-37`, lines 22, 30-36:

```bash
#!/usr/bin/env bash
# Co-Evolution <component name>
# Usage: ...
set -euo pipefail

TASK="${1:?Usage: entry.sh <task-string>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"  # lab/pel/classifier → repo root is 3 levels up

# NO `source "${REPO_ROOT}/lib/co-evolution.sh"` — D-05 sandbox: classifier is self-contained.
# Source instead the co-located adapter.sh:
source "${SCRIPT_DIR}/adapter.sh"
```

**Env-var defaults + validation pattern** — from `lib/co-evolution.sh:19-34`, the 5 in-repo precedents cited by D-02:

```bash
# RNPT-05: Default per-phase timeout in seconds. Override via --timeout flag
# or by exporting PHASE_TIMEOUT before running.
: "${PHASE_TIMEOUT:=1800}"

# RTUX-01: LIVE_MODE default. Set by --live CLI flag or LIVE_MODE env var.
# Default "false" preserves byte-parity with Phase 2 behavior (invariant).
: "${LIVE_MODE:=false}"

# RTUX-02: Branch + worktree env-var defaults. Empty = unset (no setup).
: "${DEV_REVIEW_BRANCH:=}"
: "${DEV_REVIEW_WORKTREE:=}"
```

Mirror for Phase 4 per D-03:

```bash
: "${PEL_BOUNCE_STEP:=unknown}"   # ∈ {compose, bounce, execute, verify, unknown}
: "${PEL_PHASE_TYPE:=unknown}"    # ∈ {scoping, implementation, verification, unknown}
: "${CLASSIFIER_MODEL:=claude-haiku-4-5-20251001}"  # D-06 escape hatch
```

**Domain-value validation that warns but continues** — D-04 degrades gracefully, does NOT die. No direct in-repo analog for the warn-and-continue case specifically; the closest precedent is `maybe_setup_branch` / `maybe_setup_worktree` in `lib/co-evolution.sh:252-334`:

```bash
# lib/co-evolution.sh:257-261 — warn-and-no-op on missing spec (prefer over die)
if [[ -z "$branch_spec" ]]; then
  log "WARNING: --branch ignored: value is empty" >&2
  return 0
fi
```

Apply to Phase 4 as:

```bash
# Validator pattern for PEL_BOUNCE_STEP (per D-04): warn, don't die.
case "$PEL_BOUNCE_STEP" in
  compose|bounce|execute|verify|unknown) ;;
  *)
    printf 'WARNING: unexpected PEL_BOUNCE_STEP value %q, treating as unknown\n' "$PEL_BOUNCE_STEP" >&2
    PEL_BOUNCE_STEP=unknown
    ;;
esac
```

Note: warnings go to stderr per D-08 — stdout is reserved for JSON. Use `>&2` everywhere for diagnostics.

**`--flavor` override fast-path shape** — D-09 bypasses the Haiku call entirely.

No in-repo analog for a full-bypass override on an argv-style entry point. Closest shape is the `if [[ -n "$LAB_MODE" ]]` byte-parity guard at `co-evolve-bouncer.sh:128`:

```bash
# The override presence → bypass model mirrors LAB_MODE empty → no-op, LAB_MODE non-empty → dispatch:
if [[ -n "$LAB_MODE" ]]; then
  dispatch_lab_mode "$LAB_MODE" "$SCRIPT_DIR/lab" "$TASK"
  # dispatch_lab_mode exec's — unreachable on success.
fi
```

Apply to Phase 4: if `--flavor <name>` is in effect (mechanism TBD in Phase 8; env var `PEL_FLAVOR_OVERRIDE` is the simplest extension of the existing env-var precedent), emit the override JSON and exit 0 without calling `invoke_haiku`.

---

### `lab/pel/classifier/adapter.sh` (service, request-response)

**Role:** owns the Haiku invocation. Composes `prompt.md` + inputs into a prompt file, shells out to `claude -p --model <model>`, captures stdout/stderr separately, validates the response is parseable JSON matching the D-08 schema, emits the final JSON object to stdout. Fail-fast on any failure per D-07.

**Analog A:** `lib/co-evolution.sh` `invoke_claude` (lines 336-370) — the shell-out shape, WSL cmd.exe fallback, redirect-discipline lesson.
**Analog B:** `agent-bouncer/agent-bouncer.sh:52-58` + cleanup trap at lines 74-77 — mktemp + trap pattern for prompt/output/stderr triplet.

**Do NOT reuse `invoke_claude` directly** per D-05 constraint — classifier is self-contained. But mirror the shape.

**The invoke_claude shape to mirror** — from `lib/co-evolution.sh:336-370`:

```bash
invoke_claude() {
  local prompt_file="$1"
  local output_file="$2"
  local stderr_file="$3"
  local writable="${4:-false}"
  local workdir="${WORKDIR:-$PWD}"
  local -a cmd
  local -a tool_flags

  # Text-phase (read-only): disable tools that could mutate the workdir.
  # Phase 4 is ALWAYS text-phase (classifier is stateless, reads no files).
  tool_flags=(--disallowedTools "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch")

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v cmd.exe >/dev/null 2>&1; then
    # Under WSL, reuse the Windows Claude session because WSL and Windows keep separate auth state.
    cmd=(cmd.exe /c claude -p --output-format text --model claude-opus-4-6 "${tool_flags[@]}")
  else
    cmd=(claude -p --output-format text --model claude-opus-4-6 "${tool_flags[@]}")
  fi

  "${cmd[@]}" < "$prompt_file" > "$output_file" 2>"$stderr_file" || true
}
```

Phase 4 mirror — hardcode Haiku, honor `CLASSIFIER_MODEL` escape hatch per D-06:

```bash
invoke_haiku() {
  local prompt_file="$1"
  local output_file="$2"
  local stderr_file="$3"
  local model="${CLASSIFIER_MODEL:-claude-haiku-4-5-20251001}"
  local -a cmd
  local -a tool_flags

  # Classifier is stateless + read-only. Disallow all mutation + search tools.
  tool_flags=(--disallowedTools "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch")

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v cmd.exe >/dev/null 2>&1; then
    cmd=(cmd.exe /c claude -p --output-format text --model "$model" "${tool_flags[@]}")
  else
    cmd=(claude -p --output-format text --model "$model" "${tool_flags[@]}")
  fi

  "${cmd[@]}" < "$prompt_file" > "$output_file" 2>"$stderr_file"
  # NOTE: no `|| true` — D-07 fail-fast. The caller will die on non-zero exit.
}
```

Key divergence from `invoke_claude`: **drop the `|| true` suffix.** `invoke_claude` swallows non-zero exits so the runner can inspect the output file and decide. The classifier per D-07 dies on adapter failure — let the exit code propagate.

**CLI availability check** — from `dev-review/codex/dev-review.sh:154-163`, the `require_agent_cli` pattern:

```bash
require_agent_cli() {
  case "$1" in
    codex)
      command -v codex >/dev/null 2>&1 || die "codex CLI is required but not installed"
      ;;
    opus)
      command -v claude >/dev/null 2>&1 || die "claude CLI is required but not installed"
      ;;
  esac
}
```

Phase 4 mirror:

```bash
require_claude_cli() {
  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c claude --version >/dev/null 2>&1 \
      || die "claude CLI (Windows side, via cmd.exe) is required but not installed or not authenticated"
  else
    command -v claude >/dev/null 2>&1 \
      || die "claude CLI is required but not installed"
  fi
}
```

**Auth-failure detection** — from `lib/co-evolution.sh:402-408`:

```bash
file_contains_auth_failure() {
  local file_path="$1"
  [[ -s "$file_path" ]] || return 1
  grep -qiE 'Failed to authenticate|authentication_error|Not authenticated|Unauthorized|login required|Please run .* login' "$file_path"
}
```

Apply to Phase 4 after the Haiku call returns: if `file_contains_auth_failure "$stderr_file"`, die with a clear "Haiku auth failed; run `claude login`" message. Part of D-07 fail-fast set.

**Temp-file + trap cleanup pattern** — from `agent-bouncer/agent-bouncer.sh:52-58, 71-77`:

```bash
# agent-bouncer/agent-bouncer.sh:52-58 — mktemp triplet
NAME_PROMPT_FILE=$(mktemp)
NAME_OUTPUT_FILE=$(mktemp)
NAME_STDERR_FILE=$(mktemp)
printf '%s' "$NAME_PROMPT" > "$NAME_PROMPT_FILE"
invoke_codex "$NAME_PROMPT_FILE" "$NAME_OUTPUT_FILE" "$NAME_STDERR_FILE"

# agent-bouncer/agent-bouncer.sh:74-77 — trap cleanup
cleanup() {
  rm -f "$PROMPT_FILE" "$OUTPUT_FILE" "${OUTPUT_FILE}.clean"
}
trap cleanup EXIT
```

Phase 4 apply: use `mktemp` for the composed prompt file, Haiku's stdout capture file, and Haiku's stderr capture file; wire them to a `trap` that fires on EXIT. Matches the stdout/stderr discipline risk called out in CONTEXT.md §non-obvious-risks (line 149).

**JSON validation via jq** — from `lib/co-evolution.sh:526-528`, the bedrock pattern for "is this really a JSON object":

```bash
# lib/co-evolution.sh:526-528
if command -v jq >/dev/null 2>&1; then
  jq -e 'type == "object"' "$json_file" >/dev/null 2>&1 || {
    printf '%s' "verdict was not a JSON object"
    return 1
  }
```

And the field-presence check at `lib/co-evolution.sh:532-535`:

```bash
jq -e 'has("verdict") and has("confidence") and has("summary") and has("issues")' "$json_file" >/dev/null 2>&1 || {
  printf '%s' "verdict was missing one or more required fields"
  return 1
}
```

Phase 4 mirror for validating Haiku's response before re-emitting:

```bash
# After invoke_haiku writes to $output_file:
jq -e 'type == "object" and has("flavor") and has("rationale")' "$output_file" >/dev/null 2>&1 \
  || die "Haiku response was not a valid JSON object matching expected shape"

# Then assert the flavor value is one of the four legal picks:
flavor=$(jq -r '.flavor' "$output_file")
case "$flavor" in
  bug-catcher|faster-converger|blind-spot-surfacer|general) ;;
  *) die "Haiku returned invalid flavor: $flavor" ;;
esac
```

**JSON emission pattern** — from `lib/co-evolution.sh:882-924`, `init_state_json` uses `jq -n` for schema-safe JSON composition:

```bash
# lib/co-evolution.sh:882-903 — jq -n with --arg for schema-safe string handling
jq -n \
  --arg run_id    "$run_id" \
  --arg task      "$task" \
  '{
    run_id: $run_id,
    task: $task
  }' > "$state_path"
```

Apply to Phase 4 for the final classifier JSON output per D-08 schema:

```bash
# Final JSON composition for stdout emission:
jq -n \
  --arg flavor "$flavor" \
  --arg rationale "$rationale" \
  --argjson override false \
  --arg model "$CLASSIFIER_MODEL" \
  --arg task "$TASK" \
  --arg bounce_step "$PEL_BOUNCE_STEP" \
  --arg phase_type "$PEL_PHASE_TYPE" \
  '{
    flavor: $flavor,
    rationale: $rationale,
    override: $override,
    model: $model,
    inputs: {
      task: $task,
      bounce_step: $bounce_step,
      phase_type: $phase_type
    }
  }'
```

This guarantees schema compliance + escapes embedded quotes/backslashes in the rationale automatically — which is essential because the rationale is LLM-generated and will contain arbitrary text.

---

### `lab/pel/classifier/prompt.md` (template, transform)

**Role:** frozen prompt asset. Read-as-data by the adapter, composed at invocation time. Prompt-cache-friendly ordering (stable system content leads, variable task + env-var values trail) per `future_tools.md` §§1+3.

**Analog:** `agent-bouncer/templates/bounce-protocol.md` (52 lines, placeholder-driven)

**Placeholder pattern** — from `agent-bouncer/templates/bounce-protocol.md:3-8, 51`. The file contains literal placeholder tokens (curly-brace-wrapped uppercase) like:

- `{TASK}` — the originating task string
- `{PASS_NUMBER}` — the current pass index
- `{TOTAL_PASSES}` — the max pass count
- `{YOUR_ROLE}` — "reviewer" or "composer"
- `{WORKING_DIR}` — the workdir path
- `{PLAN_CONTENT}` — the plan text (last placeholder, always at the bottom)

These tokens are substituted at invocation time by the bouncer script.

**Placeholder substitution mechanism** in the bouncer — from `agent-bouncer/agent-bouncer.sh:111-119`:

```bash
FILLED="${PROTOCOL//\{TASK\}/Review and refine this document}"
FILLED="${FILLED//\{PASS_NUMBER\}/$PASS}"
FILLED="${FILLED//\{TOTAL_PASSES\}/$MAX_BOUNCES}"
FILLED="${FILLED//\{YOUR_ROLE\}/$ROLE}"
FILLED="${FILLED//\{WORKING_DIR\}/$WORKDIR}"
FILLED="${FILLED//\{PLAN_CONTENT\}/$PLAN_CONTENT}"
```

Also available: `fill_template` helper in `lib/co-evolution.sh:726-743`:

```bash
fill_template() {
  local template_path="$1"
  shift
  local rendered
  local pair
  local key
  local value

  rendered=$(cat "$template_path")

  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    rendered="${rendered//\{$key\}/$value}"
  done

  printf '%s' "$rendered"
}
```

Note: `fill_template` lives in `lib/co-evolution.sh` and D-05 says the classifier must not depend on that lib. So Phase 4 should either (a) inline the same `${var//\{KEY\}/value}` bash parameter expansion pattern directly in `adapter.sh`, or (b) copy `fill_template`'s 18 lines verbatim into `adapter.sh`.

Recommend (a) — the pattern is 6 lines and self-documenting.

**Phase 4 prompt.md structure recommendation** per CONTEXT §Discretion for cache-friendly ordering:

Stable system content (cache-anchored portion, LEADS):
- Role declaration: "You are the PEL mode classifier. Pick one of four fitness flavors..."
- Flavor definitions (derived from `.planning/notes/pel-design-decisions.md:17-28`):
  - `bug-catcher` — protocol variants that catch more eval-known bugs
  - `faster-converger` — variants that reach good enough faster
  - `blind-spot-surfacer` — variants that catch bugs evals don't know yet
  - `general` — principled blend; NOT a neutral default
- Output schema: instruct Haiku to emit exactly a JSON object with `flavor` and `rationale` fields, no prose before or after.

Variable content (TRAILS, outside cache anchor):
- `Task: {TASK}`
- `Bounce step: {BOUNCE_STEP}`
- `Phase type: {PHASE_TYPE}`

Prose of the prompt is researcher/planner discretion per CONTEXT §Discretion.

---

### `lab/pel/README.md` or `lab/pel/classifier/README.md` (config/docs)

**Role:** env-var contract document. Pins the `PEL_*` caller-sets-config convention (D-02) + `CLASSIFIER_MODEL` escape hatch (D-06) + env-var stickiness warning (CONTEXT §non-obvious-risks line 148).

**Analog A:** `lab/README.md` (128 lines) — the peer-level README documenting a lab subsystem's contract.
**Analog B:** `dev-review/codex/README.md §Lab routing` — flag-doc co-location pattern from Phase 3 Plan 02 + Phase 2 `evals/README.md §--runner-path` precedent.

**Section-layout pattern** — from `lab/README.md:78-95`, the Invocation section. Key structural elements to mirror:

1. Heading: `## Invocation`
2. One-sentence framing: "Lab modes are opt-in via a single long-form flag. Both runners accept it with matching semantics:"
3. Fenced bash example showing invocation from both runners (`co-evolve --lab pel-proposer "task"` and `bash dev-review/codex/dev-review.sh --lab pel-proposer "task"`)
4. One-sentence error-behavior framing: "An unknown mode fails fast. The runner lists the available modes..."
5. Fenced plain-text example showing the exact error: `unknown --lab mode: foo. Available: pel-proposer, ...`
6. Closing pin: "No silent fallthrough to the default runner."

Apply to Phase 4: document the exact env-var contract + concrete examples using the same 6-element structure (heading, framing, positive example, error framing, negative example, closing pin).

**Argv-contract anchor language** — from `lab/README.md:121`:

```markdown
**Argv contract (v1.2):** Lab inhabitant entry points receive the full task string as `$1`
(single argument). The runner concatenates multi-word task tokens into one string before
dispatch, so an invocation like `co-evolve --lab pel-proposer one two three` resolves to
`lab/pel-proposer/entry.sh "one two three"` with `$1 = "one two three"`. If your inhabitant
needs multi-slot argv, split `$1` yourself ... This is a v1.2 contract constraint — may
relax in v1.3+.
```

Apply to Phase 4 env-var doc — should contain an equivalent pinned contract paragraph:

```markdown
**Env-var contract (v1.2):** Callers (future Phases 5-8 pel-proposer) MUST
`export PEL_BOUNCE_STEP=... PEL_PHASE_TYPE=...` explicitly before invoking the classifier,
NEVER inheriting from the user's shell. A developer running the classifier manually from a
shell that happens to have `PEL_BOUNCE_STEP=compose` set will get stale context silently.
Value domains:
- PEL_BOUNCE_STEP ∈ {compose, bounce, execute, verify, unknown} — default: unknown
- PEL_PHASE_TYPE ∈ {scoping, implementation, verification, unknown} — default: unknown
- Unexpected values warn to stderr and degrade to `unknown` (do NOT die).
```

---

### `tests/classifier-simulation.sh` (test, batch)

**Role:** hermetic simulation covering SC-5 — 4 flavor picks + override precedence + frozen-surface invariant. Per-scenario subshells, `N/N scenarios passed` final line.

**Analog A:** `tests/lab-routing-simulation.sh` (134 lines, Phase 3) — closest structural match.
**Analog B:** `evals/tests/scorer-verification.sh` (234 lines, Phase 2) — larger precedent with more scenarios.

**Header + scaffolding pattern** — from `tests/lab-routing-simulation.sh:1-36`:

```bash
#!/usr/bin/env bash
# tests/classifier-simulation.sh
# Phase 4 PEL-01: Hermetic simulation of lab/pel/classifier/entry.sh behavior.
#
# Scenarios (all hermetic — no network, no claude CLI — adapter is stubbed):
#   A-D: Each of the 4 flavor picks produces the expected JSON flavor + schema
#   E:   --flavor override bypasses adapter entirely (override=true in JSON)
#   F:   Frozen-surface invariant — lab/pel/classifier/** boundary is enforceable
#        (Phase 7 allowlist-exclusion glob would cleanly match)
#
# Exit 0 iff all 6 scenarios pass; exit 1 otherwise.
# Final line on success: `6/6 scenarios passed`.

set -euo pipefail

TEST_DIR=$(mktemp -d -t classifier-sim-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

FAILURES=0
TOTAL=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }
```

**Per-scenario subshell + grep assertion pattern** — from `tests/lab-routing-simulation.sh:74-83`:

```bash
TOTAL=$((TOTAL + 1))
(
  out=$(bash "$REPO_ROOT/co-evolve-bouncer.sh" --lab nonexistent-mode "trivial task" 2>&1 || true)

  echo "$out" | grep -qF "unknown --lab mode: nonexistent-mode" \
    || { echo "B: missing unknown-mode error; got: $out" >&2; exit 1; }
  echo "$out" | grep -qF "Available:" \
    || { echo "B: missing Available: listing; got: $out" >&2; exit 1; }
) && pass "Scenario B (co-evolve-bouncer.sh unknown-mode fail-fast)" \
  || fail "Scenario B (unknown mode on co-evolve)"
```

Apply to Phase 4 with adapter stubbing. The key hermeticity trick: the simulation must NOT invoke Haiku. Two options:

1. **Stub via `PATH` injection** — place a `claude` shim script in `$TEST_DIR/bin`, `export PATH="$TEST_DIR/bin:$PATH"`, have the shim emit canned JSON matching the flavor expected for each scenario. Mirrors how Phase 2 Tier 2 used `FAKE_MODE` to drive a fake runner.
2. **Split the classifier so `entry.sh` accepts a `CLASSIFIER_STUB_RESPONSE` env var** that short-circuits the adapter call. Simpler to author but adds a test-only code path — less pure.

Recommend option 1 (PATH injection) — matches how `evals/tests/scorer-verification.sh:149-152` drives the fake runner:

```bash
# evals/tests/scorer-verification.sh:149-152 — hermetic sub-process driving via env var:
FAKE_MODE="$fake_mode" bash "$REPO_ROOT/evals/run-evals.sh" \
  --case 01-trivial-task \
  --runner-path "$FAKE_RUNNER" \
  > "$tier2_out/run-evals.stdout" 2> "$tier2_out/run-evals.stderr" || rc=$?
```

Adapted to Phase 4:

```bash
# Build a stub claude shim that returns canned JSON for each scenario
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
# Stub: echo whatever canned JSON the test placed in $CLASSIFIER_STUB_FILE
cat "${CLASSIFIER_STUB_FILE:?CLASSIFIER_STUB_FILE required}"
STUB
chmod +x "$TEST_DIR/bin/claude"
export PATH="$TEST_DIR/bin:$PATH"

# For Scenario A (bug-catcher):
cat > "$TEST_DIR/stub-bug-catcher.json" <<'JSON'
{"flavor": "bug-catcher", "rationale": "Task emphasizes correctness; recent evals flagged false-positive markers."}
JSON
CLASSIFIER_STUB_FILE="$TEST_DIR/stub-bug-catcher.json" \
  PEL_BOUNCE_STEP=bounce PEL_PHASE_TYPE=verification \
  bash "$REPO_ROOT/lab/pel/classifier/entry.sh" "fix the off-by-one in marker counting" > "$TEST_DIR/scenario-a.json"

jq -e '.flavor == "bug-catcher"' "$TEST_DIR/scenario-a.json" >/dev/null \
  || { echo "A: wrong flavor; got $(cat $TEST_DIR/scenario-a.json)" >&2; exit 1; }
```

**Summary footer pattern** — from `tests/lab-routing-simulation.sh:123-134`, identical across Phase 2 + Phase 3:

```bash
passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
```

Apply verbatim to Phase 4.

**Scenario F — frozen-surface invariant** per D-11 path-based enforcement. Phase 4 doesn't implement the allowlist (Phase 7 does), but SC-5 requires a test that proves the boundary is clean. Shape:

```bash
# Scenario F: every file the classifier uses lives under lab/pel/classifier/**
# Phase 7's allowlist-exclusion glob will be `lab/pel/classifier/**`; this test
# asserts no adapter dependency leaks outside that boundary.
TOTAL=$((TOTAL + 1))
(
  # Simulate Phase 7's glob: find files OUTSIDE lab/pel/classifier/ that entry.sh sources.
  sourced_outside=$(grep -h -E '^(source|\.)' "$REPO_ROOT/lab/pel/classifier/entry.sh" "$REPO_ROOT/lab/pel/classifier/adapter.sh" \
    | grep -vE '(\$SCRIPT_DIR|lab/pel/classifier)' || true)
  if [[ -n "$sourced_outside" ]]; then
    echo "F: classifier sources files outside lab/pel/classifier/: $sourced_outside" >&2
    exit 1
  fi
) && pass "Scenario F (frozen-surface invariant — no external source dependencies)" \
  || fail "Scenario F (frozen-surface invariant)"
```

---

## Shared Patterns

### Pattern S-1: stderr for diagnostics, stdout reserved for data

**Source:** `lib/co-evolution.sh:252-292`, `maybe_setup_branch` routes all log lines to `>&2` so stdout carries only the branch name for the caller.

```bash
# lib/co-evolution.sh:258-259
if [[ -z "$branch_spec" ]]; then
  # Route log to stderr so the caller's stdout-capture stays clean (no-op = empty stdout).
  log "WARNING: --branch ignored: value is empty" >&2
  return 0
fi
```

**Apply to:** `entry.sh`, `adapter.sh`. All diagnostic output (validator warnings, progress, auth hints, errors) goes to stderr. Stdout carries ONLY the final JSON object per D-08. This is the direct mitigation for the stdout/stderr discipline risk called out at CONTEXT.md:149.

### Pattern S-2: fail-fast die() with specific error text

**Source:** `lib/co-evolution.sh:13-17` + `dev-review/codex/dev-review.sh:154-163`.

```bash
# lib/co-evolution.sh:13-17
die() {
  local message="${1:-Fatal error}"
  log "ERROR: $message"
  exit 1
}
```

**Apply to:** `adapter.sh`, `entry.sh`. Inline a local `die()` (don't source `lib/co-evolution.sh` per D-05). Per D-07, every Haiku-invocation failure path dies with specific error text:
- CLI missing → `die "claude CLI is required but not installed"`
- Auth failure → `die "Haiku auth failed; run 'claude login' and retry"` (detected via `file_contains_auth_failure`-equivalent regex on the stderr file)
- Non-JSON response → `die "Haiku response was not valid JSON matching classifier schema"`
- Invalid flavor → `die "Haiku returned invalid flavor: $flavor (expected one of bug-catcher, faster-converger, blind-spot-surfacer, general)"`

### Pattern S-3: env-var-as-caller-config precedent

**Source:** `lib/co-evolution.sh:19-34` — 5 existing precedents: `PHASE_TIMEOUT`, `LIVE_MODE`, `DEV_REVIEW_BRANCH`, `DEV_REVIEW_WORKTREE` all use `: "${VAR:=default}"` — plus `dev-review/codex/dev-review.sh` reads `COMPOSER`/`EXECUTOR`/`REVIEWER`/`CODEX_MODEL` the same way.

**Apply to:** `entry.sh` for `PEL_BOUNCE_STEP`, `PEL_PHASE_TYPE`, `CLASSIFIER_MODEL`. Same shape: `: "${VAR:=default}"` at top of script, docstring comment above each.

### Pattern S-4: hermetic simulation test with `N/N scenarios passed` final line

**Source:** `tests/lab-routing-simulation.sh:123-134` and `evals/tests/scorer-verification.sh:223-234` — identical footer; also shared scaffolding: `mktemp -d`, `trap cleanup EXIT`, `FAILURES=0 TOTAL=0 fail() {...} pass() {...}`, per-scenario subshells with exit-code propagation via `&& pass || fail`.

**Apply to:** `tests/classifier-simulation.sh`. Mirror the structure verbatim. This is a bedrock v1.2 convention now — every phase gate ships one.

---

## No Analog Found

None. Phase 4 is a pure mirror phase — every file has a concrete in-repo analog. The closest thing to a novel component is the `--flavor` override fast-path (D-09), and even that mirrors the `LAB_MODE empty → no-op, LAB_MODE non-empty → dispatch` byte-parity guard from Phase 3.

---

## Metadata

**Analog search scope:**
- `C:/Users/alan/Project/co-evolution-v12/lib/` (runner-helper precedents)
- `C:/Users/alan/Project/co-evolution-v12/agent-bouncer/` (template-pattern + adapter-shape precedent)
- `C:/Users/alan/Project/co-evolution-v12/dev-review/codex/` (require-cli + adapter-invocation precedent)
- `C:/Users/alan/Project/co-evolution-v12/co-evolve-bouncer.sh` (argv-contract dispatch site)
- `C:/Users/alan/Project/co-evolution-v12/tests/` (simulation-test precedent)
- `C:/Users/alan/Project/co-evolution-v12/evals/tests/` (older simulation-test precedent)
- `C:/Users/alan/Project/co-evolution-v12/lab/` (contract + invocation doc precedent)

**Files scanned (read in full or substantially):**
- `lib/co-evolution.sh` (1064 lines — helpers, env-var defaults, invoke_claude shape, jq patterns)
- `tests/lab-routing-simulation.sh` (134 lines — 4-scenario per-subshell template)
- `evals/tests/scorer-verification.sh` (234 lines — 13-scenario precedent)
- `agent-bouncer/README.md` (100 lines — adapter contract and templates philosophy)
- `agent-bouncer/agent-bouncer.sh` (187 lines — mktemp + trap + fill-template idioms)
- `agent-bouncer/templates/bounce-protocol.md` (52 lines — placeholder pattern)
- `lab/README.md` (128 lines — lab conventions + argv contract + first-inhabitant doc style)
- `co-evolve-bouncer.sh:1-140` + `dev-review/codex/dev-review.sh:1000-1075` (dispatch sites)
- `.planning/phases/03-lab-scaffold/03-02-SUMMARY.md` (141 lines — Phase 3 handshake details)
- `.planning/notes/pel-design-decisions.md` (100 lines — binding flavor definitions for prompt.md)

**Pattern extraction date:** 2026-04-18

---

*Phase: 04-mode-classifier-frozen*
*Patterns mapped: 2026-04-18*
