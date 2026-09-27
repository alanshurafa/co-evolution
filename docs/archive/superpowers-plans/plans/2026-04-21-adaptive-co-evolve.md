# Adaptive Co-Evolve Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add complexity-aware model routing to PEL — pick Sonnet for NORMAL mutations, Opus for COMPLEX, with `--fallback-model sonnet` on every claude -p call to prevent silent quota hangs.

**Architecture:** New `lab/pel/router/` subdirectory invoked from `pr-emitter.sh` between flavor classifier and proposer dispatch. Single Haiku call per PEL invocation emits routing JSON consumed by pr-emitter.sh to set `PROPOSER_MODEL` env var. Aggregate telemetry appended to `.co-evolve/router-history.jsonl`. Default-on; `--no-adaptive` and `--complexity` flags provide escape hatches.

**Tech Stack:** Bash (POSIX-ish per repo conventions); jq for JSON; Claude CLI (`claude -p`) for Haiku classification with PATH-injected stub for hermetic tests. No new dependencies.

**Spec reference:** [`docs/superpowers/specs/2026-04-21-adaptive-co-evolve-design.md`](../specs/2026-04-21-adaptive-co-evolve-design.md)

---

## Task 1: Scaffold `lab/pel/router/` directory

**Files:**
- Create: `lab/pel/router/README.md`
- Create: `lab/pel/router/prompt.md`
- Create: `lab/pel/router/adapter.sh` (skeleton)
- Create: `lab/pel/router/router.sh` (skeleton)

- [ ] **Step 1: Create the directory + README**

```bash
mkdir -p lab/pel/router
```

Write `lab/pel/router/README.md`:

```markdown
# PEL Router

Complexity-aware model routing for PEL invocations. Picks Sonnet for NORMAL mutations, escalates to Opus + thinking budget for COMPLEX. Invoked from `lab/pel/pr-emitter/pr-emitter.sh` between flavor classification and proposer dispatch.

## Contract

### Inputs (env vars set by caller)
- `TARGET` — target file path (already known to pr-emitter)
- `PEL_TIER` — `template`/`policy`/`code` (already resolved)
- `PEL_FLAVOR` — flavor classifier output
- `PEL_FEEDBACK` — path to eval feedback JSON
- `PEL_COMPLEXITY_OVERRIDE` — optional; skips Haiku call if set

### Output (single JSON object on stdout)

```json
{
  "complexity": "NORMAL" | "COMPLEX",
  "model": "sonnet" | "opus",
  "fallback_model": "sonnet",
  "thinking_budget": null | "harder",
  "rationale": "<one-sentence explanation>",
  "inputs": {
    "pel_tier": "...",
    "target": "...",
    "target_size_bytes": ...,
    "flavor": "...",
    "user_override": null | "..."
  }
}
```

## Tier-to-model mapping

| Complexity | Model | Thinking budget | Use cases |
|------------|-------|-----------------|-----------|
| NORMAL | `sonnet` | none | Most template + policy mutations |
| COMPLEX | `opus` | `harder` (append "think harder" to prompt) | Code-tier always; large/risky template/policy changes |

## Bias hints (passed to Haiku in prompt)

- `pel_tier == "code"` → strongly bias COMPLEX
- `pel_tier == "template" && target_size_bytes < 2000` → bias NORMAL
- `pel_tier == "policy"` → bias NORMAL
- Otherwise → Haiku decides from feedback content + flavor

## Failure handling

- Router script not found / unexecutable → caller prints WARN, falls back to current hardcoded `opus` default
- Haiku call fails → router emits canonical JSON with `complexity: "COMPLEX"` (safe-side default) + `rationale: "router-failure-fallback"` and exits 0
- `--complexity` override → skip Haiku entirely; emit canonical JSON with `inputs.user_override` set

The router is best-effort. PEL must keep working even if the router itself misbehaves.

## See also

- Spec: [`docs/superpowers/specs/2026-04-21-adaptive-co-evolve-design.md`](../../../docs/superpowers/specs/2026-04-21-adaptive-co-evolve-design.md)
- Pattern reference: `lab/pel/classifier/` (the frozen Phase 4 classifier this router structure mirrors)
```

- [ ] **Step 2: Create the Haiku prompt**

Write `lab/pel/router/prompt.md`:

```markdown
You are the PEL Router classifier. Your job is to look at one PEL mutation invocation and classify it as NORMAL or COMPLEX so we route it to the right Claude model.

## Context

- PEL tier: {PEL_TIER}
- Target file: {TARGET}
- Target size: {TARGET_SIZE_BYTES} bytes
- Flavor (chosen by upstream classifier): {PEL_FLAVOR}

## Bias hints (apply BEFORE judging from content)

- If `pel_tier == "code"` → almost always COMPLEX. Shell mutations are risky; the better model justifies its cost.
- If `pel_tier == "template"` AND target size < 2000 bytes → bias NORMAL. Small template tweaks are routine.
- If `pel_tier == "policy"` → bias NORMAL. Bounded knob surface; mutations are constrained.
- Otherwise → judge from the feedback content and flavor. If the feedback signals a deep semantic issue (multiple correlated failures, marker-resolution edge cases, novel failure modes), pick COMPLEX. Routine wording or single-knob tweaks are NORMAL.

## Output

Output exactly one JSON object on stdout. No prose before or after. Schema:

```json
{
  "complexity": "NORMAL" | "COMPLEX",
  "rationale": "<one sentence, ≤120 chars, explaining the pick>"
}
```

`complexity` must be one of "NORMAL" or "COMPLEX" exactly. Any other value is a contract violation.
```

- [ ] **Step 3: Create the adapter skeleton**

Write `lab/pel/router/adapter.sh`:

```bash
# lab/pel/router/adapter.sh
# Co-Evolution PEL Router — Haiku adapter (Phase v1.3-adaptive).
#
# SELF-CONTAINED per Phase 4 D-05 pattern: zero import of co-evolution runner
# helpers, classifier subtree, or other proposer adapters. All helpers inline
# so lab/pel/router/** is a clean self-contained subtree.
#
# Sourced by router.sh; not executed standalone.
#
# Required env when run_adapter is called (router.sh sets these):
#   TARGET                    target file path
#   PEL_TIER                  template|policy|code
#   PEL_FLAVOR                bug-catcher|faster-converger|blind-spot-surfacer|general
#   ROUTER_MODEL              Haiku model ID (default: claude-haiku-4-5-20251001)
#
# Stdout contract: raw JSON object {complexity, rationale} from Haiku.
# Stderr: diagnostics only.

# Default ROUTER_MODEL to Haiku 4.5 (mirrors classifier model choice).
: "${ROUTER_MODEL:=claude-haiku-4-5-20251001}"

# Inline die() — matches classifier/adapter.sh:13-17 semantics.
die() {
  printf "ERROR: %s\n" "${1:-Fatal error}" >&2
  exit "${2:-1}"
}

# Inline log_stderr() — stdout reserved for JSON.
log_stderr() {
  printf "%s\n" "$1" >&2
}

# require_claude_cli — mirrors classifier/adapter.sh require_claude_cli.
require_claude_cli() {
  if [[ -n "${WSL_DISTRO_NAME:-}" || "$(uname -s)" == "MINGW"* ]]; then
    cmd.exe /c claude --version >/dev/null 2>&1 \
      || die "claude CLI (Windows side, via cmd.exe) is required but not installed or not authenticated" 2
  else
    command -v claude >/dev/null 2>&1 \
      || die "claude CLI is required but not installed" 2
  fi
}

# strip_markdown_fences <response_file>
#   Edits response_file IN PLACE: strip markdown fence wrappers if present.
#   Mirrors lab/pel/classifier/adapter.sh::strip_markdown_fences (defense
#   against Haiku emitting fenced JSON despite prompt instructions).
strip_markdown_fences() {
  local file="$1"
  head -n 1 "$file" 2>/dev/null | grep -q '^```' || return 0
  local tmp
  tmp=$(mktemp -t router-stripped-XXXXXX)
  sed '/^```[a-zA-Z0-9_-]*[[:space:]]*$/d' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Placeholder run_adapter — Task 3 will fill this in.
# This skeleton just exists so router.sh can source and reference run_adapter
# without exploding during Task 1's commit.
run_adapter() {
  die "run_adapter not yet implemented (Task 3)" 99
}
```

Make it sourcable (not executable):

```bash
# Don't chmod +x — adapter is sourced by router.sh.
```

- [ ] **Step 4: Create the router skeleton**

Write `lab/pel/router/router.sh`:

```bash
#!/usr/bin/env bash
# lab/pel/router/router.sh
# Co-Evolution PEL Router entry — picks model based on complexity classification.
#
# Reads env vars (TARGET, PEL_TIER, PEL_FLAVOR, PEL_FEEDBACK,
# PEL_COMPLEXITY_OVERRIDE). Emits routing JSON on stdout.
#
# Invoked from lab/pel/pr-emitter/pr-emitter.sh between flavor classification
# and proposer dispatch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=adapter.sh
source "$SCRIPT_DIR/adapter.sh"

# Placeholder — Tasks 3-5 will replace this.
die "router.sh not yet implemented (Tasks 3-5)" 99
```

Make it executable:

```bash
chmod +x lab/pel/router/router.sh
```

- [ ] **Step 5: Verify scaffold + commit**

Run:

```bash
ls -la lab/pel/router/
bash -n lab/pel/router/adapter.sh && echo "adapter.sh syntax OK"
bash -n lab/pel/router/router.sh && echo "router.sh syntax OK"
```

Expected: 4 files listed (README.md, prompt.md, adapter.sh, router.sh); both `bash -n` checks print OK.

Commit:

```bash
git add lab/pel/router/
git commit -m "scaffold(adaptive): create lab/pel/router/ skeleton

New subdirectory for the PEL complexity router. README documents
the contract; prompt.md will drive the Haiku classification call;
adapter.sh + router.sh are skeletons (Tasks 2-5 fill them in).

Mirrors lab/pel/classifier/ structure per Phase 4 D-05 self-
containment pattern."
```

---

## Task 2: Write router simulation test (5 failing scenarios)

**Files:**
- Create: `tests/router-simulation.sh`

- [ ] **Step 1: Create the test scaffold with helper functions**

Write `tests/router-simulation.sh`:

```bash
#!/usr/bin/env bash
# tests/router-simulation.sh
# Hermetic simulation gate for lab/pel/router/.
#
# Scenarios (5 primary — all hermetic, no network, no real claude):
#   A: NORMAL pick — template-tier small file → router emits complexity=NORMAL,
#      model=sonnet
#   B: COMPLEX pick — code-tier any size → router emits complexity=COMPLEX,
#      model=opus, thinking_budget=harder
#   C: --complexity user override — PEL_COMPLEXITY_OVERRIDE=COMPLEX skips
#      Haiku call; canonical JSON includes inputs.user_override="COMPLEX"
#   D: --no-adaptive bypass — caller (co-evolve-bouncer.sh + pr-emitter.sh)
#      respects PEL_NO_ADAPTIVE=1 by skipping router entirely (proxy test:
#      router.sh exits cleanly when invoked under PEL_NO_ADAPTIVE=1; in
#      production the caller never invokes it at all)
#   E: Router-failure fallback — Haiku stub forced to fail; router emits
#      canonical JSON with complexity="COMPLEX" + rationale="router-failure-
#      fallback" and exit 0
#
# Pattern: PATH-injected claude stub (mirrors tests/classifier-simulation.sh).

set -uo pipefail  # NOT -e: per-scenario subshells handle their own exit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$(mktemp -d -t router-sim-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
FAILURES=0

pass() {
  printf "PASS: %s\n" "$1"
}

fail() {
  printf "FAIL: %s\n" "$1" >&2
  FAILURES=$((FAILURES + 1))
}

# Build the PATH-injected claude stub.
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
# Hermetic claude stub for router-simulation.sh.
if [[ "$*" == *"--version"* ]]; then
  echo "claude 1.0.0 (router-stub)"
  exit 0
fi
cat > /dev/null  # consume stdin
if [[ -n "${ROUTER_STUB_EXIT:-}" ]]; then
  exit "$ROUTER_STUB_EXIT"
fi
if [[ -z "${ROUTER_STUB_FILE:-}" || ! -f "${ROUTER_STUB_FILE:-}" ]]; then
  echo "STUB ERROR: ROUTER_STUB_FILE not set or file missing" >&2
  exit 99
fi
cat "$ROUTER_STUB_FILE"
STUB
chmod +x "$TEST_DIR/bin/claude"

# Helper: write canned Haiku response.
write_stub() {
  local dest="$1" complexity="$2" rationale="$3"
  jq -n --arg complexity "$complexity" --arg rationale "$rationale" \
    '{complexity: $complexity, rationale: $rationale}' > "$dest"
}

# Tiny target files used by scenarios (need real files so target_size_bytes
# resolves correctly).
mkdir -p "$TEST_DIR/targets"
printf "small template" > "$TEST_DIR/targets/small.md"  # ~14 bytes
printf "%.0sX" {1..3000} > "$TEST_DIR/targets/big.md"   # 3000 bytes
printf "#!/bin/bash\necho hi\n" > "$TEST_DIR/targets/code.sh"

echo "Router simulation starting..."
```

- [ ] **Step 2: Add Scenario A (NORMAL pick — template tier, small file)**

Append to `tests/router-simulation.sh`:

```bash
# ---------------------------------------------------------------------------
# Scenario A: NORMAL pick (template tier, small target → bias NORMAL)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-A.json"
  write_stub "$stub_file" "NORMAL" "small template tweak"

  result=$(ROUTER_STUB_FILE="$stub_file" \
           PATH="$TEST_DIR/bin:$PATH" \
           TARGET="$TEST_DIR/targets/small.md" \
           PEL_TIER="template" \
           PEL_FLAVOR="bug-catcher" \
           PEL_FEEDBACK="$TEST_DIR/dummy-feedback.json" \
           bash "$REPO_ROOT/lab/pel/router/router.sh" 2>/dev/null)

  echo "$result" | jq -e '.complexity == "NORMAL"' >/dev/null \
    || { echo "A: .complexity expected NORMAL; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.model == "sonnet"' >/dev/null \
    || { echo "A: .model expected sonnet; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.fallback_model == "sonnet"' >/dev/null \
    || { echo "A: .fallback_model expected sonnet; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.thinking_budget == null' >/dev/null \
    || { echo "A: .thinking_budget expected null; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.pel_tier == "template"' >/dev/null \
    || { echo "A: .inputs.pel_tier mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.user_override == null' >/dev/null \
    || { echo "A: .inputs.user_override expected null; got: $result" >&2; exit 1; }
) && pass "Scenario A (NORMAL pick — template tier small file)" \
  || fail "Scenario A (NORMAL pick)"
```

- [ ] **Step 3: Add Scenarios B, C, D, E**

Append to `tests/router-simulation.sh`:

```bash
# ---------------------------------------------------------------------------
# Scenario B: COMPLEX pick (code tier — always escalate)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-B.json"
  write_stub "$stub_file" "COMPLEX" "code-tier mutation"

  result=$(ROUTER_STUB_FILE="$stub_file" \
           PATH="$TEST_DIR/bin:$PATH" \
           TARGET="$TEST_DIR/targets/code.sh" \
           PEL_TIER="code" \
           PEL_FLAVOR="bug-catcher" \
           PEL_FEEDBACK="$TEST_DIR/dummy-feedback.json" \
           bash "$REPO_ROOT/lab/pel/router/router.sh" 2>/dev/null)

  echo "$result" | jq -e '.complexity == "COMPLEX"' >/dev/null \
    || { echo "B: .complexity expected COMPLEX; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.model == "opus"' >/dev/null \
    || { echo "B: .model expected opus; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.thinking_budget == "harder"' >/dev/null \
    || { echo "B: .thinking_budget expected harder; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.pel_tier == "code"' >/dev/null \
    || { echo "B: .inputs.pel_tier mismatch; got: $result" >&2; exit 1; }
) && pass "Scenario B (COMPLEX pick — code tier)" \
  || fail "Scenario B (COMPLEX pick)"

# ---------------------------------------------------------------------------
# Scenario C: --complexity user override (skip Haiku entirely)
# ---------------------------------------------------------------------------
# Marker file proves Haiku was NOT called.
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-C.json"
  write_stub "$stub_file" "NORMAL" "should not be called"
  marker_file="$TEST_DIR/marker-C"

  # Override the stub to write a marker on invocation, so we can assert it
  # was NOT called.
  cat > "$TEST_DIR/bin/claude" <<STUB
#!/usr/bin/env bash
echo "called" > "$marker_file"
[[ "\$*" == *"--version"* ]] && { echo "claude 1.0.0 (stub)"; exit 0; }
cat > /dev/null
cat "$stub_file"
STUB
  chmod +x "$TEST_DIR/bin/claude"

  result=$(PATH="$TEST_DIR/bin:$PATH" \
           TARGET="$TEST_DIR/targets/code.sh" \
           PEL_TIER="template" \
           PEL_FLAVOR="bug-catcher" \
           PEL_FEEDBACK="$TEST_DIR/dummy-feedback.json" \
           PEL_COMPLEXITY_OVERRIDE="COMPLEX" \
           bash "$REPO_ROOT/lab/pel/router/router.sh" 2>/dev/null)

  [[ -f "$marker_file" ]] && { echo "C: Haiku was called despite override" >&2; exit 1; }
  echo "$result" | jq -e '.complexity == "COMPLEX"' >/dev/null \
    || { echo "C: .complexity expected COMPLEX (from override); got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.user_override == "COMPLEX"' >/dev/null \
    || { echo "C: .inputs.user_override expected COMPLEX; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.model == "opus"' >/dev/null \
    || { echo "C: .model expected opus (from override); got: $result" >&2; exit 1; }
) && pass "Scenario C (--complexity COMPLEX override skips Haiku)" \
  || fail "Scenario C (override)"

# Restore the standard stub for remaining scenarios.
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"--version"* ]]; then
  echo "claude 1.0.0 (router-stub)"
  exit 0
fi
cat > /dev/null
if [[ -n "${ROUTER_STUB_EXIT:-}" ]]; then
  exit "$ROUTER_STUB_EXIT"
fi
if [[ -z "${ROUTER_STUB_FILE:-}" || ! -f "${ROUTER_STUB_FILE:-}" ]]; then
  echo "STUB ERROR: ROUTER_STUB_FILE not set or file missing" >&2
  exit 99
fi
cat "$ROUTER_STUB_FILE"
STUB
chmod +x "$TEST_DIR/bin/claude"

# ---------------------------------------------------------------------------
# Scenario D: PEL_NO_ADAPTIVE=1 bypass — router exits 0 cleanly without
# emitting JSON. (Caller is responsible for not invoking the router at all
# when PEL_NO_ADAPTIVE=1; this scenario documents that the router itself
# also short-circuits gracefully if accidentally called.)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-D.json"
  write_stub "$stub_file" "NORMAL" "should not run"

  exit_code=0
  result=$(ROUTER_STUB_FILE="$stub_file" \
           PATH="$TEST_DIR/bin:$PATH" \
           TARGET="$TEST_DIR/targets/small.md" \
           PEL_TIER="template" \
           PEL_FLAVOR="bug-catcher" \
           PEL_FEEDBACK="$TEST_DIR/dummy-feedback.json" \
           PEL_NO_ADAPTIVE=1 \
           bash "$REPO_ROOT/lab/pel/router/router.sh" 2>/dev/null) || exit_code=$?

  [[ "$exit_code" -eq 0 ]] || { echo "D: expected exit 0, got $exit_code" >&2; exit 1; }
  [[ -z "$result" ]] || { echo "D: expected empty stdout under PEL_NO_ADAPTIVE; got: $result" >&2; exit 1; }
) && pass "Scenario D (PEL_NO_ADAPTIVE=1 bypass — clean no-op)" \
  || fail "Scenario D (no-adaptive bypass)"

# ---------------------------------------------------------------------------
# Scenario E: Router-failure fallback — Haiku call fails, router emits
# safe-side COMPLEX default and exits 0
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-E.json"
  write_stub "$stub_file" "NORMAL" "should not be reached"

  result=$(ROUTER_STUB_FILE="$stub_file" \
           ROUTER_STUB_EXIT=1 \
           PATH="$TEST_DIR/bin:$PATH" \
           TARGET="$TEST_DIR/targets/small.md" \
           PEL_TIER="template" \
           PEL_FLAVOR="bug-catcher" \
           PEL_FEEDBACK="$TEST_DIR/dummy-feedback.json" \
           bash "$REPO_ROOT/lab/pel/router/router.sh" 2>/dev/null)

  echo "$result" | jq -e '.complexity == "COMPLEX"' >/dev/null \
    || { echo "E: .complexity expected COMPLEX (safe-side); got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.rationale == "router-failure-fallback"' >/dev/null \
    || { echo "E: .rationale expected router-failure-fallback; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.model == "opus"' >/dev/null \
    || { echo "E: .model expected opus (safe-side); got: $result" >&2; exit 1; }
) && pass "Scenario E (router-failure fallback — safe-side COMPLEX)" \
  || fail "Scenario E (router-failure fallback)"
```

- [ ] **Step 4: Add the summary footer**

Append:

```bash
# ---------------------------------------------------------------------------
# Summary footer
# ---------------------------------------------------------------------------
passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
```

- [ ] **Step 5: Run test, verify all scenarios FAIL (router not implemented yet)**

```bash
chmod +x tests/router-simulation.sh
bash tests/router-simulation.sh 2>&1 | tail -10
```

Expected:
```
FAIL: Scenario A (NORMAL pick)
FAIL: Scenario B (COMPLEX pick)
FAIL: Scenario C (override)
FAIL: Scenario D (no-adaptive bypass)
FAIL: Scenario E (router-failure fallback)
0/5 scenarios passed (5 failed)
```

(All 5 fail because router.sh exit 99 with "not yet implemented" — that's expected; subsequent tasks make them pass.)

Commit:

```bash
git add tests/router-simulation.sh
git commit -m "test(adaptive): add router-simulation.sh (5 scenarios, all failing)

Hermetic 5-scenario gate following tests/classifier-simulation.sh
PATH-injection pattern. Currently all scenarios fail because
router.sh is a skeleton — Tasks 3-6 implement the behaviors that
make each scenario pass:

  Scenario A → Task 3 (NORMAL happy path)
  Scenario B → Task 3 (COMPLEX happy path)
  Scenario C → Task 4 (--complexity override)
  Scenario D → Task 6 (PEL_NO_ADAPTIVE bypass)
  Scenario E → Task 5 (router-failure fallback)"
```

---

## Task 3: Implement router happy paths (Scenarios A + B)

**Files:**
- Modify: `lab/pel/router/adapter.sh:60-65` (replace placeholder run_adapter)
- Modify: `lab/pel/router/router.sh:14-15` (replace die placeholder)

- [ ] **Step 1: Implement `run_adapter` in adapter.sh**

Replace the placeholder `run_adapter` at the bottom of `lab/pel/router/adapter.sh` with the real implementation:

```bash
# run_adapter
#   Invokes Haiku with the prompt template + context vars, writes raw response
#   to stdout. Caller (router.sh) handles fence-stripping and JSON parsing.
#
#   Required env (caller sets these):
#     TARGET, PEL_TIER, PEL_FLAVOR, TARGET_SIZE_BYTES, ROUTER_MODEL
run_adapter() {
  require_claude_cli

  local prompt_file output_file stderr_file
  prompt_file=$(mktemp -t router-prompt-XXXXXX)
  output_file=$(mktemp -t router-output-XXXXXX)
  stderr_file=$(mktemp -t router-stderr-XXXXXX)

  # shellcheck disable=SC2064
  trap "rm -f \"$prompt_file\" \"$output_file\" \"$stderr_file\"" RETURN

  # Render prompt by substituting template vars.
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local template
  template=$(cat "$script_dir/prompt.md")
  local rendered
  rendered="${template//\{PEL_TIER\}/$PEL_TIER}"
  rendered="${rendered//\{TARGET\}/$TARGET}"
  rendered="${rendered//\{TARGET_SIZE_BYTES\}/$TARGET_SIZE_BYTES}"
  rendered="${rendered//\{PEL_FLAVOR\}/$PEL_FLAVOR}"
  printf "%s" "$rendered" > "$prompt_file"

  log_stderr "INFO: invoking router Haiku (model: $ROUTER_MODEL)"

  local cmd
  if [[ -n "${WSL_DISTRO_NAME:-}" || "$(uname -s)" == "MINGW"* ]]; then
    cmd=(cmd.exe /c claude -p --output-format text --model "$ROUTER_MODEL" --tools "")
  else
    cmd=(claude -p --output-format text --model "$ROUTER_MODEL" --tools "")
  fi

  # Run Haiku. On failure, return non-zero so caller can take fallback path.
  if ! "${cmd[@]}" < "$prompt_file" > "$output_file" 2> "$stderr_file"; then
    log_stderr "ERROR: Haiku call failed; stderr: $(head -c 500 "$stderr_file")"
    return 1
  fi

  # Strip fences, then emit response on stdout.
  strip_markdown_fences "$output_file"
  cat "$output_file"
}
```

- [ ] **Step 2: Implement router.sh main flow (no-adaptive bypass + tier/size detection + Haiku invoke + fallback + JSON emit)**

Replace the entire body of `lab/pel/router/router.sh` (after `source "$SCRIPT_DIR/adapter.sh"`):

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=adapter.sh
source "$SCRIPT_DIR/adapter.sh"

# ---------------------------------------------------------------------------
# Bypass: PEL_NO_ADAPTIVE=1 → router is a no-op (Scenario D).
# ---------------------------------------------------------------------------
if [[ "${PEL_NO_ADAPTIVE:-0}" == "1" ]]; then
  log_stderr "INFO: PEL_NO_ADAPTIVE=1 — router skipped"
  exit 0
fi

# ---------------------------------------------------------------------------
# Required inputs.
# ---------------------------------------------------------------------------
: "${TARGET:?TARGET env var required}"
: "${PEL_TIER:?PEL_TIER env var required}"
: "${PEL_FLAVOR:?PEL_FLAVOR env var required}"
: "${PEL_FEEDBACK:?PEL_FEEDBACK env var required}"

# Resolve target size (best-effort; falls back to 0 if file missing).
TARGET_SIZE_BYTES=0
if [[ -f "$TARGET" ]]; then
  TARGET_SIZE_BYTES=$(wc -c < "$TARGET" | tr -d ' ')
fi
export TARGET_SIZE_BYTES

# ---------------------------------------------------------------------------
# Tier-to-model mapping helper. Single source of truth — every code path
# that emits routing JSON goes through this.
# ---------------------------------------------------------------------------
emit_routing_json() {
  local complexity="$1" rationale="$2" user_override="${3:-null}"
  local model thinking_budget

  case "$complexity" in
    NORMAL)
      model="sonnet"
      thinking_budget="null"
      ;;
    COMPLEX)
      model="opus"
      thinking_budget='"harder"'
      ;;
    *)
      die "invalid complexity value: $complexity (expected NORMAL|COMPLEX)" 1
      ;;
  esac

  # Quote user_override correctly (null vs "STRING").
  local override_json
  if [[ "$user_override" == "null" ]]; then
    override_json="null"
  else
    override_json="\"$user_override\""
  fi

  # Quote string fields that need it.
  local rationale_json
  rationale_json=$(printf '%s' "$rationale" | jq -R -s '.')

  # Emit canonical JSON via jq for safety (no manual string concatenation).
  jq -n \
    --arg complexity "$complexity" \
    --arg model "$model" \
    --arg fallback_model "sonnet" \
    --argjson thinking_budget "$thinking_budget" \
    --arg rationale "$rationale" \
    --arg pel_tier "$PEL_TIER" \
    --arg target "$TARGET" \
    --argjson target_size_bytes "$TARGET_SIZE_BYTES" \
    --arg flavor "$PEL_FLAVOR" \
    --argjson user_override "$override_json" \
    '{
      complexity: $complexity,
      model: $model,
      fallback_model: $fallback_model,
      thinking_budget: $thinking_budget,
      rationale: $rationale,
      inputs: {
        pel_tier: $pel_tier,
        target: $target,
        target_size_bytes: $target_size_bytes,
        flavor: $flavor,
        user_override: $user_override
      }
    }'
}

# ---------------------------------------------------------------------------
# Override path (Scenario C) — Task 4 fills this in. Skeleton here so the
# control flow shape exists.
# ---------------------------------------------------------------------------
if [[ -n "${PEL_COMPLEXITY_OVERRIDE:-}" ]]; then
  die "Override path not yet implemented (Task 4)" 99
fi

# ---------------------------------------------------------------------------
# Standard path: invoke Haiku, parse complexity, emit canonical JSON.
# Failure path (Scenario E) — Task 5 will replace die with safe-side fallback.
# ---------------------------------------------------------------------------
haiku_response=""
if ! haiku_response=$(run_adapter); then
  die "Haiku call failed (Task 5 will add safe-side fallback here)" 99
fi

# Validate Haiku response shape.
echo "$haiku_response" | jq -e 'type == "object" and has("complexity") and has("rationale")' >/dev/null 2>&1 \
  || die "Haiku response was not a valid JSON object: $haiku_response" 3

complexity=$(echo "$haiku_response" | jq -r '.complexity')
rationale=$(echo "$haiku_response" | jq -r '.rationale')

case "$complexity" in
  NORMAL|COMPLEX) ;;
  *)
    die "Haiku returned invalid complexity: $complexity (expected NORMAL|COMPLEX)" 3
    ;;
esac

emit_routing_json "$complexity" "$rationale"
```

- [ ] **Step 3: Run scenarios A + B, verify they pass**

```bash
bash tests/router-simulation.sh 2>&1 | tail -10
```

Expected:
```
PASS: Scenario A (NORMAL pick — template tier small file)
PASS: Scenario B (COMPLEX pick — code tier)
FAIL: Scenario C (override)        # Task 4
PASS: Scenario D (PEL_NO_ADAPTIVE=1 bypass — clean no-op)
FAIL: Scenario E (router-failure fallback)  # Task 5
3/5 scenarios passed (2 failed)
```

(A, B, D pass. C and E still fail — Tasks 4 + 5 fix them.)

- [ ] **Step 4: Verify scenarios C + E still fail with the expected reason**

Run with -x for diagnostics on the failing scenarios:

```bash
PEL_COMPLEXITY_OVERRIDE=COMPLEX TARGET=/tmp/dummy PEL_TIER=template PEL_FLAVOR=bug-catcher PEL_FEEDBACK=/tmp/dummy bash lab/pel/router/router.sh 2>&1 | tail -3
```

Expected: "ERROR: Override path not yet implemented (Task 4)"

That confirms Scenario C is failing for the right reason (placeholder die in router.sh, not a different bug).

- [ ] **Step 5: Commit**

```bash
git add lab/pel/router/adapter.sh lab/pel/router/router.sh
git commit -m "feat(adaptive): implement router happy paths (Scenarios A+B+D)

Adapter invokes Haiku via claude -p with prompt template substitution
and fence-strip defense (mirrors classifier/adapter.sh pattern).

Router orchestrates: PEL_NO_ADAPTIVE bypass (Scenario D), tier+size
detection, Haiku invocation, response validation, canonical JSON
emission via jq.

Override path (Scenario C) and Haiku-failure fallback (Scenario E)
are placeholder die() calls — Tasks 4+5 implement those.

Test status: 3/5 scenarios passing (A, B, D)."
```

---

## Task 4: Implement `--complexity` user override (Scenario C)

**Files:**
- Modify: `lab/pel/router/router.sh:80-84` (the override placeholder block)

- [ ] **Step 1: Replace the override placeholder with real logic**

In `lab/pel/router/router.sh`, find this block:

```bash
if [[ -n "${PEL_COMPLEXITY_OVERRIDE:-}" ]]; then
  die "Override path not yet implemented (Task 4)" 99
fi
```

Replace with:

```bash
if [[ -n "${PEL_COMPLEXITY_OVERRIDE:-}" ]]; then
  # Validate the override value.
  case "$PEL_COMPLEXITY_OVERRIDE" in
    NORMAL|COMPLEX) ;;
    *)
      die "invalid PEL_COMPLEXITY_OVERRIDE: $PEL_COMPLEXITY_OVERRIDE (expected NORMAL|COMPLEX)" 1
      ;;
  esac

  log_stderr "INFO: --complexity override active: $PEL_COMPLEXITY_OVERRIDE (skipping Haiku)"
  emit_routing_json "$PEL_COMPLEXITY_OVERRIDE" "user-override" "$PEL_COMPLEXITY_OVERRIDE"
  exit 0
fi
```

- [ ] **Step 2: Run test, verify Scenario C now passes**

```bash
bash tests/router-simulation.sh 2>&1 | tail -10
```

Expected:
```
PASS: Scenario A (NORMAL pick — template tier small file)
PASS: Scenario B (COMPLEX pick — code tier)
PASS: Scenario C (--complexity COMPLEX override skips Haiku)
PASS: Scenario D (PEL_NO_ADAPTIVE=1 bypass — clean no-op)
FAIL: Scenario E (router-failure fallback)  # Task 5
4/5 scenarios passed (1 failed)
```

- [ ] **Step 3: Commit**

```bash
git add lab/pel/router/router.sh
git commit -m "feat(adaptive): implement --complexity user override (Scenario C)

PEL_COMPLEXITY_OVERRIDE skips the Haiku call entirely; emits
canonical routing JSON with inputs.user_override populated. Validates
override value is NORMAL|COMPLEX (rejects invalid with exit 1).

Test status: 4/5 scenarios passing (A, B, C, D)."
```

---

## Task 5: Implement router-failure safe-side fallback (Scenario E)

**Files:**
- Modify: `lab/pel/router/router.sh:90-95` (the Haiku-failure die placeholder)

- [ ] **Step 1: Replace the Haiku-failure die with safe-side fallback**

In `lab/pel/router/router.sh`, find this block:

```bash
haiku_response=""
if ! haiku_response=$(run_adapter); then
  die "Haiku call failed (Task 5 will add safe-side fallback here)" 99
fi
```

Replace with:

```bash
haiku_response=""
if ! haiku_response=$(run_adapter); then
  # Safe-side default: when in doubt, escalate to COMPLEX (Opus). The router
  # is best-effort; PEL must keep working even if the router itself fails.
  log_stderr "WARN: Haiku call failed; falling back to COMPLEX (safe-side default)"
  emit_routing_json "COMPLEX" "router-failure-fallback"
  exit 0
fi
```

- [ ] **Step 2: Run test, verify Scenario E now passes**

```bash
bash tests/router-simulation.sh 2>&1 | tail -10
```

Expected:
```
PASS: Scenario A (NORMAL pick — template tier small file)
PASS: Scenario B (COMPLEX pick — code tier)
PASS: Scenario C (--complexity COMPLEX override skips Haiku)
PASS: Scenario D (PEL_NO_ADAPTIVE=1 bypass — clean no-op)
PASS: Scenario E (router-failure fallback — safe-side COMPLEX)
5/5 scenarios passed
```

- [ ] **Step 3: Commit**

```bash
git add lab/pel/router/router.sh
git commit -m "feat(adaptive): implement router-failure safe-side fallback (Scenario E)

When the Haiku call fails (auth, network, malformed), router emits
canonical JSON with complexity=COMPLEX (safe-side default — escalate
when uncertain) + rationale=router-failure-fallback and exits 0.
PEL keeps running with the more capable model rather than crashing.

Router is now feature-complete. Test status: 5/5 scenarios passing.

Tasks 6-7 wire the new flags into co-evolve-bouncer.sh; Tasks 8-9
integrate the router into pr-emitter.sh."
```

---

## Task 6: Add `--no-adaptive` flag to `co-evolve-bouncer.sh`

**Files:**
- Modify: `co-evolve-bouncer.sh` (argv parsing + Phase 8 wrapper-flag rebuild)

- [ ] **Step 1: Locate the argv-parser arm for `--lab` (it's the canonical reference for flag-arm placement)**

```bash
grep -n -- "--lab\b\|--target\b" co-evolve-bouncer.sh | head -10
```

Note the line numbers; new flag arms should sit BEFORE the `--)` argv terminator (consistent with all other flags).

- [ ] **Step 2: Add the `--no-adaptive` flag arm + variable initialization**

Near the top of `co-evolve-bouncer.sh` where other flag variables are initialized (look for `LAB_MODE=""`), add:

```bash
NO_ADAPTIVE=0
```

In the `case` block where flag arms live (find the existing `--lab)` arm), add a new arm BEFORE the `--)` terminator:

```bash
    --no-adaptive)
      NO_ADAPTIVE=1
      shift
      ;;
```

- [ ] **Step 3: Pass `PEL_NO_ADAPTIVE` to the lab dispatch when set**

Find the Phase 8 wrapper-flag rebuild block (look for `if [[ "$LAB_MODE" == "pel-proposer" ]]`). At the point where `lab_tail` is being built, add a line that exports `PEL_NO_ADAPTIVE`:

```bash
if [[ "$LAB_MODE" == "pel-proposer" ]]; then
  lab_tail=()
  [[ -n "$TARGET" ]] && lab_tail+=("--target" "$TARGET")
  # ... other existing additions ...

  # NEW: propagate --no-adaptive as PEL_NO_ADAPTIVE env var.
  if [[ "$NO_ADAPTIVE" == "1" ]]; then
    export PEL_NO_ADAPTIVE=1
  fi

  # ... rest of dispatch ...
fi
```

- [ ] **Step 4: Smoke test — flag parses cleanly**

```bash
bash co-evolve-bouncer.sh --no-adaptive --lab pel-proposer --target /tmp/nonexistent 2>&1 | head -5
```

Expected: parser doesn't reject `--no-adaptive`; eventually dies for a different reason (missing target/feedback) — that's fine, we just want to confirm flag parsing.

If it dies with "unknown flag: --no-adaptive", the flag arm placement is wrong (probably after `--)`). Move it before.

- [ ] **Step 5: Commit**

```bash
git add co-evolve-bouncer.sh
git commit -m "feat(adaptive): add --no-adaptive flag to co-evolve-bouncer.sh

Flag exports PEL_NO_ADAPTIVE=1, which router.sh honors as a clean
no-op (Scenario D). Lets users force the pre-router behavior
(always Opus) without removing the router from the pipeline.

Use case: testing PEL with the router temporarily disabled to
isolate whether a regression is in the router or somewhere else."
```

---

## Task 7: Add `--complexity` flag to `co-evolve-bouncer.sh`

**Files:**
- Modify: `co-evolve-bouncer.sh` (same argv parser, same wrapper-flag rebuild)

- [ ] **Step 1: Add the `--complexity` variable initialization**

Near the other flag variable initializations, add:

```bash
COMPLEXITY_OVERRIDE=""
```

- [ ] **Step 2: Add the `--complexity` flag arm**

In the `case` block (next to `--no-adaptive` from Task 6):

```bash
    --complexity)
      [[ $# -gt 1 ]] || die "--complexity requires a value (NORMAL|COMPLEX)"
      case "$2" in
        NORMAL|COMPLEX) COMPLEXITY_OVERRIDE="$2" ;;
        *) die "invalid --complexity value: $2 (expected NORMAL|COMPLEX)" 1 ;;
      esac
      shift 2
      ;;
```

- [ ] **Step 3: Export `PEL_COMPLEXITY_OVERRIDE` to the lab dispatch when set**

In the Phase 8 wrapper-flag rebuild block:

```bash
if [[ "$LAB_MODE" == "pel-proposer" ]]; then
  # ... existing ...
  if [[ -n "$COMPLEXITY_OVERRIDE" ]]; then
    export PEL_COMPLEXITY_OVERRIDE="$COMPLEXITY_OVERRIDE"
  fi
  # ... rest of dispatch ...
fi
```

- [ ] **Step 4: Update the usage() help text**

Find the usage() function (look for `cat <<USAGE` or similar). Add the two new flags to the help output:

```bash
  --no-adaptive           Skip the PEL router (force pre-router behavior — always Opus)
  --complexity TIER       Force complexity tier (NORMAL|COMPLEX); skips Haiku router call
```

- [ ] **Step 5: Smoke test + commit**

```bash
bash co-evolve-bouncer.sh --complexity COMPLEX --lab pel-proposer --target /tmp/nonexistent 2>&1 | head -5
bash co-evolve-bouncer.sh --complexity BOGUS --lab pel-proposer --target /tmp/nonexistent 2>&1 | head -5
bash co-evolve-bouncer.sh --help 2>&1 | grep -A1 "complexity\|no-adaptive"
```

Expected:
- First call: parser accepts; dies later for different reason
- Second call: dies with "invalid --complexity value: BOGUS (expected NORMAL|COMPLEX)"
- Third call: help text shows both new flags

```bash
git add co-evolve-bouncer.sh
git commit -m "feat(adaptive): add --complexity flag to co-evolve-bouncer.sh

Flag exports PEL_COMPLEXITY_OVERRIDE, which router.sh consumes to
skip the Haiku call and emit canonical JSON with the user-chosen
tier (Scenario C). Validates value at parse time; rejects anything
outside NORMAL|COMPLEX with exit 1.

Use case: \"I know this is hard, stop guessing\" — force Opus on
a target the router would have picked Sonnet for, or vice versa.

Usage text updated with both --complexity and --no-adaptive."
```

---

## Task 8: Wire router invocation into `pr-emitter.sh`

**Files:**
- Modify: `lab/pel/pr-emitter/pr-emitter.sh` (add router invocation between flavor classifier and proposer dispatch)

- [ ] **Step 1: Locate the right insertion point**

```bash
grep -n "INFO: classifier picked flavor\|invoking proposer\|export PROPOSER_MODEL" lab/pel/pr-emitter/pr-emitter.sh | head -10
```

You're looking for the lines AFTER flavor classification finishes and BEFORE proposer dispatch begins. The router insert goes between them.

- [ ] **Step 2: Add router invocation block**

After the flavor classifier completes (look for the line printing `INFO: classifier picked flavor=...`), insert:

```bash
# ---------------------------------------------------------------------------
# Section A.0: Capture PEL invocation start time (used by Section K telemetry).
# Add this near the very top of pr-emitter.sh, AFTER `set -euo pipefail` and
# variable defaults but BEFORE any work starts. Use ms-resolution if available;
# fall back to seconds*1000 for portability.
# ---------------------------------------------------------------------------
PEL_START_MS=$(date +%s%3N 2>/dev/null || echo "$(($(date +%s) * 1000))")

# ---------------------------------------------------------------------------
# Section C.5: Adaptive router (NEW — picks complexity tier + model).
# Skipped entirely if PEL_NO_ADAPTIVE=1. Best-effort: router failure
# falls back to current hardcoded behavior (PROPOSER_MODEL=opus).
# ---------------------------------------------------------------------------
if [[ "${PEL_NO_ADAPTIVE:-0}" != "1" ]]; then
  log_stderr "INFO: invoking adaptive router for tier=$resolved_tier"

  # Export inputs the router expects.
  export TARGET PEL_TIER="$resolved_tier" PEL_FLAVOR="$flavor" PEL_FEEDBACK

  # Time the router call so telemetry has a real router_duration_ms value.
  router_start_ms=$(date +%s%3N 2>/dev/null || echo "$(($(date +%s) * 1000))")

  router_json=""
  if router_json=$(bash "$REPO_ROOT/lab/pel/router/router.sh" 2>/dev/null) && [[ -n "$router_json" ]]; then
    router_end_ms=$(date +%s%3N 2>/dev/null || echo "$(($(date +%s) * 1000))")
    ROUTER_DURATION_MS=$((router_end_ms - router_start_ms))

    chosen_model=$(printf '%s' "$router_json" | jq -r '.model')
    chosen_complexity=$(printf '%s' "$router_json" | jq -r '.complexity')
    fallback_model=$(printf '%s' "$router_json" | jq -r '.fallback_model')

    # Export PROPOSER_MODEL so the proposer adapter picks it up.
    case "$resolved_tier" in
      template) export PROPOSER_MODEL="$chosen_model" ;;
      code)     export CODE_PROPOSER_MODEL="$chosen_model" ;;
      policy)   ;;  # policy uses Haiku — router decision N/A but logged
    esac
    export FALLBACK_MODEL="$fallback_model"

    log_stderr "INFO: router picked complexity=$chosen_complexity model=$chosen_model"
  else
    router_end_ms=$(date +%s%3N 2>/dev/null || echo "$(($(date +%s) * 1000))")
    ROUTER_DURATION_MS=$((router_end_ms - router_start_ms))
    log_stderr "WARN: router invocation failed; falling back to default model"
    chosen_complexity="UNKNOWN"
    chosen_model="opus"  # the existing default
  fi
else
  log_stderr "INFO: PEL_NO_ADAPTIVE=1 — adaptive router skipped"
  chosen_complexity="DISABLED"
  chosen_model="opus"  # the existing default
  ROUTER_DURATION_MS=0  # router not invoked; record zero so telemetry is honest
fi
```

- [ ] **Step 3: Smoke test — pr-emitter.sh syntax + invocation order**

```bash
bash -n lab/pel/pr-emitter/pr-emitter.sh && echo "syntax OK"
```

Expected: "syntax OK"

- [ ] **Step 4: Run the existing pr-emitter simulation gate to ensure no regression**

```bash
bash tests/pr-emitter-simulation.sh 2>&1 | tail -5
```

Expected: "10/10 scenarios passed" — same as before this task. The router insertion is non-destructive: it only sets PROPOSER_MODEL if the router responds; otherwise the existing default is preserved.

If the simulation breaks: check that the router fallback path correctly preserves the prior hardcoded `opus` behavior.

- [ ] **Step 5: Commit**

```bash
git add lab/pel/pr-emitter/pr-emitter.sh
git commit -m "feat(adaptive): wire router into pr-emitter.sh

New Section C.5 between flavor classifier and proposer dispatch:
invoke lab/pel/router/router.sh, parse routing JSON, export
PROPOSER_MODEL (or CODE_PROPOSER_MODEL for code tier) + FALLBACK_MODEL
so the proposer adapter picks them up.

PEL_NO_ADAPTIVE=1 skips the router entirely; PEL behaves as before
this PR. Router failure falls back to hardcoded opus (existing
default), so a misbehaving router never breaks PEL.

Existing tests/pr-emitter-simulation.sh still passes (10/10) —
the router insert is non-destructive."
```

---

## Task 9: Wire telemetry append into `pr-emitter.sh`

**Files:**
- Modify: `lab/pel/pr-emitter/pr-emitter.sh` (add telemetry write at the end of the run)

- [ ] **Step 1: Locate the end of the pr-emitter flow**

```bash
grep -n "exit 0\|gh pr create\|^# Section\b" lab/pel/pr-emitter/pr-emitter.sh | tail -10
```

You want a spot AFTER PR creation succeeds but BEFORE the script exits — typically the last block in the file.

- [ ] **Step 2: Add the telemetry append**

At the end of the script (just before any `exit 0`), insert:

```bash
# ---------------------------------------------------------------------------
# Section K: Append routing telemetry (best-effort; never fail PEL on a
# logging error).
# ---------------------------------------------------------------------------
{
  telemetry_dir="$REPO_ROOT/.co-evolve"
  mkdir -p "$telemetry_dir" 2>/dev/null || true
  telemetry_file="$telemetry_dir/router-history.jsonl"

  fallback_fired="false"
  # Future: detect fallback fire from claude -p stderr signal; for now record false.

  # Compute total PEL duration from the start marker set in Section A.0.
  pel_end_ms=$(date +%s%3N 2>/dev/null || echo "$(($(date +%s) * 1000))")
  PEL_DURATION_MS=$((pel_end_ms - ${PEL_START_MS:-pel_end_ms}))

  jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg run_id "${TIMESTAMP:-unknown}" \
    --arg target "$TARGET" \
    --arg pel_tier "$resolved_tier" \
    --arg flavor "$flavor" \
    --arg complexity "${chosen_complexity:-UNKNOWN}" \
    --arg model_chosen "${chosen_model:-opus}" \
    --argjson fallback_fired "$fallback_fired" \
    --argjson router_duration_ms "${ROUTER_DURATION_MS:-0}" \
    --argjson total_pel_duration_ms "${PEL_DURATION_MS:-0}" \
    --arg user_override "${PEL_COMPLEXITY_OVERRIDE:-}" \
    '{
      ts: $ts,
      run_id: $run_id,
      target: $target,
      pel_tier: $pel_tier,
      flavor: $flavor,
      complexity: $complexity,
      model_chosen: $model_chosen,
      fallback_fired: $fallback_fired,
      router_duration_ms: $router_duration_ms,
      total_pel_duration_ms: $total_pel_duration_ms,
      user_override: (if $user_override == "" then null else $user_override end)
    }' >> "$telemetry_file" 2>/dev/null || true
} || true  # outer || true: telemetry never fails PEL
```

- [ ] **Step 3: Verify .gitignore covers `.co-evolve/`**

```bash
grep -n "co-evolve" .gitignore
```

Expected: line(s) showing `.co-evolve-cache/` or `.co-evolve/` already gitignored. If only `-cache/` is ignored, add `.co-evolve/` (the new path):

```bash
echo "" >> .gitignore
echo "# Adaptive router telemetry (append-only JSONL log of routing decisions)" >> .gitignore
echo ".co-evolve/" >> .gitignore
```

- [ ] **Step 4: Smoke test — write a fake telemetry record manually to verify the format**

```bash
# Mimic what pr-emitter.sh would do, with all the env vars set.
TIMESTAMP=test-run-001 TARGET=fake.md resolved_tier=template flavor=bug-catcher \
chosen_complexity=NORMAL chosen_model=sonnet PEL_COMPLEXITY_OVERRIDE="" \
ROUTER_DURATION_MS=850 PEL_DURATION_MS=120000 \
REPO_ROOT=$(pwd) bash -c '
mkdir -p "$REPO_ROOT/.co-evolve"
jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg run_id "$TIMESTAMP" \
  --arg target "$TARGET" \
  --arg pel_tier "$resolved_tier" \
  --arg flavor "$flavor" \
  --arg complexity "$chosen_complexity" \
  --arg model_chosen "$chosen_model" \
  --argjson fallback_fired false \
  --argjson router_duration_ms "$ROUTER_DURATION_MS" \
  --argjson total_pel_duration_ms "$PEL_DURATION_MS" \
  --arg user_override "$PEL_COMPLEXITY_OVERRIDE" \
  "{ts: \$ts, run_id: \$run_id, target: \$target, pel_tier: \$pel_tier, flavor: \$flavor, complexity: \$complexity, model_chosen: \$model_chosen, fallback_fired: \$fallback_fired, router_duration_ms: \$router_duration_ms, total_pel_duration_ms: \$total_pel_duration_ms, user_override: (if \$user_override == \"\" then null else \$user_override end)}" \
  >> "$REPO_ROOT/.co-evolve/router-history.jsonl"
'

# Verify the line is valid JSON.
tail -1 .co-evolve/router-history.jsonl | jq .
```

Expected: pretty-printed JSON object with all the fields populated correctly.

Clean up the test record:

```bash
rm -rf .co-evolve/
```

- [ ] **Step 5: Commit**

```bash
git add lab/pel/pr-emitter/pr-emitter.sh .gitignore
git commit -m "feat(adaptive): append routing telemetry to .co-evolve/router-history.jsonl

New Section K at the end of pr-emitter.sh writes one JSON object
per PEL invocation: timestamp, target, tier, flavor, complexity,
model chosen, fallback firing, durations, user override.

Best-effort: telemetry write never fails PEL (outer || true). Path
gitignored. Format is append-only JSONL — can be analyzed with
\`jq -s\` later (or fed into a dashboard once we have ≥100 records).

Use cases: \"did the router pick well?\" — grep + manual; \"how often
does Opus overload trigger fallback?\" — quota signal over time."
```

---

## Task 10: Add `--fallback-model sonnet` to template + code proposer adapters

**Files:**
- Modify: `lab/pel/proposer/template/adapter.sh` (claude -p invocation)
- Modify: `lab/pel/proposer/code/adapter.sh` (claude -p invocation)

- [ ] **Step 1: Locate the claude -p invocation in the template adapter**

```bash
grep -n "cmd=(.*claude -p" lab/pel/proposer/template/adapter.sh
```

Note the exact line(s). Both Windows (cmd.exe) and POSIX branches need updating.

- [ ] **Step 2: Add --fallback-model to template adapter**

Find this block (line ~125-130):

```bash
  if [[ -n "${WSL_DISTRO_NAME:-}" || "$(uname -s)" == "MINGW"* ]]; then
    cmd=(cmd.exe /c claude -p --output-format text --model "$model" "${tool_flags[@]}")
  else
    cmd=(claude -p --output-format text --model "$model" "${tool_flags[@]}")
  fi
```

Replace with:

```bash
  local fallback_model="${FALLBACK_MODEL:-sonnet}"
  if [[ -n "${WSL_DISTRO_NAME:-}" || "$(uname -s)" == "MINGW"* ]]; then
    cmd=(cmd.exe /c claude -p --output-format text --model "$model" --fallback-model "$fallback_model" "${tool_flags[@]}")
  else
    cmd=(claude -p --output-format text --model "$model" --fallback-model "$fallback_model" "${tool_flags[@]}")
  fi
```

- [ ] **Step 3: Same change to the code adapter**

Find the equivalent block in `lab/pel/proposer/code/adapter.sh`:

```bash
grep -n "cmd=(.*claude -p" lab/pel/proposer/code/adapter.sh
```

Apply the same `local fallback_model="${FALLBACK_MODEL:-sonnet}"` line + `--fallback-model "$fallback_model"` flag insertion.

- [ ] **Step 4: Verify syntax + invocation shape**

```bash
bash -n lab/pel/proposer/template/adapter.sh && echo "template adapter OK"
bash -n lab/pel/proposer/code/adapter.sh && echo "code adapter OK"

# Confirm both have the new flag.
grep -n "fallback-model" lab/pel/proposer/template/adapter.sh lab/pel/proposer/code/adapter.sh
```

Expected: both syntax checks pass; grep returns one match per file with `--fallback-model "$fallback_model"`.

- [ ] **Step 5: Commit**

```bash
git add lab/pel/proposer/template/adapter.sh lab/pel/proposer/code/adapter.sh
git commit -m "feat(adaptive): add --fallback-model sonnet to proposer adapters

Both template + code proposer adapters now pass --fallback-model
sonnet to claude -p. When Opus is overloaded or quota-exhausted,
the CLI auto-degrades to Sonnet instead of hanging silently — the
quota-induced silent-hang we hit during 2026-04-20 SC-4 dogfood.

FALLBACK_MODEL env var lets the router (or a user) override the
default sonnet target with another model alias.

Policy adapter unaffected — uses Haiku, doesn't have the same
overload pressure."
```

---

## Task 11: Regression check — `pr-emitter-simulation.sh` still passes

**Files:**
- Verify (no edit): `tests/pr-emitter-simulation.sh`

- [ ] **Step 1: Run the existing 10-scenario gate**

```bash
bash tests/pr-emitter-simulation.sh 2>&1 | tail -10
```

Expected: "10/10 scenarios passed" — same as before this PR.

- [ ] **Step 2: If it fails, diagnose**

If any scenario fails:
- Check whether the failing scenario expected a specific PROPOSER_MODEL value and the router is now overriding it (possible bug in router invocation block — should leave PROPOSER_MODEL untouched in PEL_NO_ADAPTIVE mode)
- Check whether telemetry write is failing because `.co-evolve/` doesn't exist (the simulation may run in a tmp dir without it)

Fix the bug, re-run.

- [ ] **Step 3: Run the new router simulation gate AGAIN to confirm no break**

```bash
bash tests/router-simulation.sh 2>&1 | tail -5
```

Expected: "5/5 scenarios passed" — same as Task 5 ending state.

- [ ] **Step 4: Run the classifier simulation gate (the one we shipped yesterday)**

```bash
bash tests/classifier-simulation.sh 2>&1 | tail -5
```

Expected: "6/6 scenarios passed" + "3/3 bonus scenarios passed" — confirms we didn't regress yesterday's classifier work either.

- [ ] **Step 5: Commit if any test files changed (if not, skip)**

If any test file required tweaks during diagnosis:

```bash
git add tests/
git commit -m "test(adaptive): regression-fix tests/<file> for router integration

[describe specific fix]"
```

If no changes needed, no commit. The regression check is the point.

---

## Task 12: End-to-end smoke + telemetry verification

**Files:**
- No edits expected; verification only

- [ ] **Step 1: Verify --no-adaptive smoke through co-evolve-bouncer.sh**

The full bypass should work end-to-end (no real PEL invocation needed — just confirm flag propagates):

```bash
bash co-evolve-bouncer.sh --no-adaptive --lab pel-proposer --target /tmp/missing-target 2>&1 | grep -E "PEL_NO_ADAPTIVE|router skipped|adaptive" | head -5
```

Expected: log lines mentioning either "PEL_NO_ADAPTIVE" or "router skipped" (depending on where exec dies; the variable should be set even if PEL itself fails for missing target).

- [ ] **Step 2: Verify --complexity smoke through co-evolve-bouncer.sh**

```bash
bash co-evolve-bouncer.sh --complexity COMPLEX --lab pel-proposer --target /tmp/missing-target 2>&1 | grep -E "PEL_COMPLEXITY_OVERRIDE|complexity override|adaptive" | head -5
```

Expected: log lines confirming the override propagated.

- [ ] **Step 3: Verify telemetry directory structure (after a real run)**

This step requires a real PEL invocation (consumes Claude Max quota). Skip if you don't want to burn quota; the unit tests cover the telemetry write logic.

Optional — if running:

```bash
# Use a fixture as the eval report (no real eval bounce needed for the
# telemetry flow to fire).
PEL_EVAL_REPORT=tests/fixtures/pr-emitter/template-feedback.json \
  bash co-evolve-bouncer.sh --no-adaptive --lab pel-proposer \
  --target skills/dev-review/templates/review-prompt-opus.md 2>&1 | tail -10

# Verify telemetry record was written.
ls -la .co-evolve/router-history.jsonl 2>&1 | head -3
tail -1 .co-evolve/router-history.jsonl 2>&1 | jq .
```

Expected: file exists; latest record shows `complexity: "DISABLED"`, `model_chosen: "opus"`, `user_override: null` (since --no-adaptive bypasses the router).

- [ ] **Step 4: Final state check + summary commit (no code, just the audit trail)**

```bash
# Confirm all task acceptance criteria from the spec §10.
echo "=== Success criteria check ==="
echo "1+2: router picks model based on tier — verified by tests/router-simulation.sh (Scenarios A, B)"
echo "3: --no-adaptive bypass — verified by Scenario D + Step 1 above"
echo "4: --complexity override — verified by Scenario C + Step 2 above"
echo "5: --fallback-model fires — verified by Task 10 grep; runtime fire requires real overload"
echo "6: tests/router-simulation.sh: 5/5 — verified by Task 5"
echo "7: tests/pr-emitter-simulation.sh: 10/10 — verified by Task 11"
echo "8: cost reduction — empirical, requires telemetry data to confirm; verify after first 3 PEL runs"
echo ""
echo "=== Files changed in this plan ==="
git log --oneline origin/master..HEAD | head -20
```

If everything looks right:

```bash
git log --oneline | head -20  # confirm commit chain is clean
```

This is the final state of the plan. All tasks complete. The work is ready to ship as a PR.

---

## Notes for the implementer

1. **TDD discipline:** Tasks 2-5 are deliberately TDD — test scaffold first, then implementation makes scenarios pass one at a time. Don't skip the "run test, verify it fails for the right reason" step. That's how you catch placeholder bugs.

2. **No GSD overhead:** This plan is direct execution. Each task → commit → next task. No phase planning, no discuss-phase, no plan-checker. The brainstorming spec already did the upfront design work.

3. **Expected total commits:** ~12 (one per task, sometimes one per implementation step within a task). All on a single feature branch.

4. **PR strategy:** Open one PR for the whole feature when all 12 tasks are done. Review against the spec's success criteria (§10). Don't open intermediate PRs — this is a coherent feature, not a series of independent fixes.

5. **If you hit unexpected behavior:** the spec at `docs/superpowers/specs/2026-04-21-adaptive-co-evolve-design.md` is the source of truth. If implementation reveals the spec is wrong (not just incomplete), pause and surface — don't drift the implementation away from the spec without updating the spec.

6. **Quota awareness:** Real PEL runs cost real quota. Tasks 2-11 are all hermetic (no LLM calls). Task 12 step 3 is the only real-call step and it's optional. Don't spend quota on what tests already cover.
