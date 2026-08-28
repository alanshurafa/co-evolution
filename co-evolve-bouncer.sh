#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/co-evolution.sh"

# --- Defaults ---
SKIP_INTERVIEW=false
AUTO=false
EXOCORTEX_QUERY=""
CONTEXT_FILE=""
AUDIENCE=""
LENS=""
# Adversarial reviewer persona (falsification method, vendored from the
# compound-engineering adversarial-document-reviewer). Default off so runs
# without the flag are byte-identical to the pre-persona bouncer.
ADVERSARIAL=false
CHAIN=false
MAX_BOUNCES=2
AGENT_A="claude"
AGENT_B="codex"
# v1.5 Phase 1 (A-4b): document-pipeline per-role seats. Both roles default empty
# (= inherit the global CLAUDE_MODEL/CODEX_MODEL + effort), so a run with no seat
# flags/env is byte-identical to the pre-Phase-1 bouncer (argv parity). The
# reviewer role covers odd passes + chain critique/tighten; the composer role
# covers even passes + chain defend. Set via --composer-model/-effort and
# --reviewer-model/-effort, or the COMPOSER_MODEL/COMPOSER_EFFORT/REVIEWER_MODEL/
# REVIEWER_EFFORT env vars (flag wins over env via last-wins fill below).
: "${COMPOSER_MODEL:=}"; : "${COMPOSER_EFFORT:=}"
: "${REVIEWER_MODEL:=}"; : "${REVIEWER_EFFORT:=}"
BOUNCE_ONLY=false
OUTPUT_FILE=""
# Dev-review hand-off flags. Default off so a plain co-evolve run stays a pure
# compose/bounce (byte-parity). When --execute is set, the bounced document is
# treated as an implementation plan and handed to the dev-review execute (and,
# with --verify, verify) engine — see the "Dev-review hand-off" block near EOF.
# We delegate to dev-review/codex/dev-review.sh rather than re-implement its
# ~600-line execute/verify engine here: that engine is CI-tested and shares this
# script's lib/co-evolution.sh, so a copy would only duplicate tested code and
# deepen this script's scope creep. See .notes/dev-review-merge-plan.md.
EXECUTE=false
DEV_REVIEW_VERIFY=false
EXEC_WORKDIR=""
EXEC_VERIFIER=""
EXEC_REVISE_LOOP=""
EXEC_BRANCH_SPEC=""
EXEC_WORKTREE_SPEC=""
EXEC_TIMEOUT=""
TASK=""
INPUT_CONTENT=""
INPUT_TYPE=""  # "string", "file", or "pipe"
# Phase 3 LAB-01: opt-in lab-mode routing. Empty = default runner (byte-parity invariant L-03).
LAB_MODE=""
# Phase 8 flags — default off / unset so v1.1 invocations remain byte-parity (SC-5).
TARGET=""
TIER=""
PR_BRANCH=""
DRY_RUN=false
BUDGET_USD="25"
AUTO_YES=false
FLAVOR_OVERRIDE=""
# v1.3-adaptive flags — default off so PEL behavior unchanged unless invoked.
NO_ADAPTIVE=0
NO_REPORT=0
COMPLEXITY_OVERRIDE=""
# R-7: timestamp + entropy — two runs in the same second must not share a dir.
TIMESTAMP=$(generate_run_suffix)

TEMPLATE_DIR="$SCRIPT_DIR/templates/co-evolve"
PROTOCOL_TEMPLATE="$SCRIPT_DIR/agent-bouncer/templates/bounce-protocol.md"

# Validate templates exist
for _tmpl in "$TEMPLATE_DIR/role-reviewer-light.md" "$TEMPLATE_DIR/role-composer-light.md" \
             "$TEMPLATE_DIR/role-reviewer-adversarial.md" \
             "$TEMPLATE_DIR/chain-critique.md" "$TEMPLATE_DIR/chain-defend.md" \
             "$TEMPLATE_DIR/chain-critique-adversarial.md" \
             "$TEMPLATE_DIR/chain-tighten.md" "$TEMPLATE_DIR/adjudicate.md" \
             "$PROTOCOL_TEMPLATE"; do
  [[ -f "$_tmpl" ]] || die "Missing template: $_tmpl"
done

# --- Usage ---
usage() {
  cat <<'USAGE'
Usage:
  co-evolve [OPTIONS] <input>

  input can be a question ("quoted string"), a file path, or piped stdin.

Options:
  --skip-interview   Skip the opening interview questions
  --auto             Skip human checks between passes
  --vanilla          Shorthand for --skip-interview --auto
  --exocortex QUERY  Search ExoCortex for relevant context
  --context FILE     Include a file as background context (not bounced; one file, concatenate if needed)
  --audience WHO     Prime agents for a specific reader
  --lens NAME        Use a named adversarial lens (replaces auto-shaped roles)
  --adversarial      Structured adversarial reviewer persona (falsification
                     method: premises, assumptions, decisions, complexity,
                     alternatives). Composes with --lens (lens becomes the
                     focus) and --chain (swaps the critique stage).
  --chain            Use staged passes: critique -> defend -> tighten
  --bounces N        Max bounce passes (default: 2, ignored with --chain)
  --agents A,B       Agent pair (default: claude,codex)
  --claude-model M   Override the Claude model (default: claude-opus-4-8; also via CLAUDE_MODEL env)
  --composer-model M   Model for the composer role (even passes / chain defend). Also COMPOSER_MODEL env. Default: inherit global.
  --composer-effort E  Reasoning effort for the composer role. Also COMPOSER_EFFORT env.
  --reviewer-model M   Model for the reviewer role (odd passes / chain critique+tighten). Also REVIEWER_MODEL env. Default: inherit global.
  --reviewer-effort E  Reasoning effort for the reviewer role. Also REVIEWER_EFFORT env. (No global --effort: a bounce has two roles.)
  --execute          After bounce, hand the result to dev-review as a plan and write code
  --verify           With --execute, add the verify pass (APPROVED/REVISE verdict)
  --dev-review       Shorthand for --execute --verify
  --workdir DIR      With --execute: directory the executor writes into (default: cwd)
  --verifier AGENT   With --execute --verify: force the verify agent (codex|opus|claude)
  --revise-loop N    With --execute --verify: auto-retry on REVISE up to N extra passes (default 0)
  --exec-branch SPEC With --execute: create a branch before writing (auto|NAME); excl. with --exec-worktree
  --exec-worktree SPEC With --execute: create a worktree before writing (auto|PATH); excl. with --exec-branch
  --exec-timeout SEC With --execute: per-phase timeout for the execute/verify engine (default 1800)
  --bounce-only      Skip compose, bounce a file directly
  --output FILE      Write final output to a file instead of stdout
  --lab MODE         Route to lab/<MODE>/entry.sh (opt-in beta channel; see lab/README.md)
  --target FILE      PEL-only: file to mutate (used with --lab pel-proposer; repo-relative forward-slash path, e.g. lib/co-evolution.sh)
  --tier TIER        PEL-only: override tier auto-detect (template|policy|code)
  --pr-branch NAME   PEL-only: override default pel/<tier>/<short-hash> branch name
  --dry-run          PEL-only: stub `gh` via CO_EVOLVE_DRY_RUN=1 + PATH shadow
  --budget USD       PEL-only: scoring budget cap (default 25; exit 6 on exhaustion)
  --yes              PEL-only: skip interactive preflight cost-estimate prompt
  --flavor NAME      PEL-only: override classifier (maps to PEL_FLAVOR_OVERRIDE)
  --no-adaptive      PEL-only: skip the adaptive router (force pre-router behavior — always Opus)
  --no-report        Skip the post-run HUMAN-REPORT.md / bounce-scores.json generation
  --complexity TIER  PEL-only: force complexity (NORMAL|COMPLEX); skips Haiku router call
  --help             Show this help text

Convergence lifecycle:
  Every run ends converged | adjudicated | stuck (recorded in state.json
  convergence_status; adjudicated runs also write adjudication-report.md).
  A stuck DOCUMENT run still exits 0 by design: the output is labeled
  CO-EVOLVE:STUCK / NOT-final and the deterministic scorer gate fails it —
  the label and the gate carry the signal, not the exit code. --execute is
  the exception: it refuses a stuck plan and exits 1.
USAGE
  exit 0
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help) usage ;;
    --skip-interview) SKIP_INTERVIEW=true; shift ;;
    --auto) AUTO=true; shift ;;
    --vanilla) SKIP_INTERVIEW=true; AUTO=true; shift ;;
    --exocortex) EXOCORTEX_QUERY="$2"; shift 2 ;;
    --context) CONTEXT_FILE="$2"; shift 2 ;;
    --audience) AUDIENCE="$2"; shift 2 ;;
    --lens) LENS="$2"; shift 2 ;;
    --adversarial) ADVERSARIAL=true; shift ;;
    --chain) CHAIN=true; shift ;;
    --bounces)
      MAX_BOUNCES="$2"
      [[ "$MAX_BOUNCES" =~ ^[0-9]+$ ]] || die "--bounces must be a positive integer, got: $MAX_BOUNCES"
      shift 2
      ;;
    --agents)
      # Must be exactly two non-empty, comma-separated agent names. A value with
      # NO comma (e.g. `--agents claude`) previously self-paired silently:
      # ${2%%,*} and ${2#*,} both return the whole string, so AGENT_A==AGENT_B
      # and the "bounce" ran an agent against itself with no error. Require a
      # comma so that mistake dies loudly. The three checks together — comma
      # present, not two commas, both names non-empty — mean exactly one comma
      # separating two non-empty names.
      [[ "${2:-}" == *","* ]] || die "--agents requires two comma-separated agents (e.g., claude,codex), got: ${2:-<missing>}"
      [[ "$2" == *","*","* ]] && die "--agents requires exactly two agents (e.g., claude,codex)"
      AGENT_A="${2%%,*}"
      AGENT_B="${2#*,}"
      AGENT_B="${AGENT_B%%,*}"
      [[ -z "$AGENT_A" || -z "$AGENT_B" ]] && die "--agents requires exactly two agents separated by comma (e.g., claude,codex)"
      shift 2
      ;;
    --claude-model)
      [[ $# -gt 1 ]] || die "--claude-model requires a value"
      CLAUDE_MODEL="$2"
      shift 2
      ;;
    # v1.5 Phase 1 (A-4b): per-role seats for the document pipeline. There is NO
    # single global --effort (deliberately rejected as ambiguous — a bounce has
    # two roles with different needs). Flag wins over the same-named env var.
    --composer-model)
      [[ $# -gt 1 ]] || die "--composer-model requires a value"
      COMPOSER_MODEL="$2"
      shift 2
      ;;
    --composer-effort)
      [[ $# -gt 1 ]] || die "--composer-effort requires a value"
      COMPOSER_EFFORT="$2"
      shift 2
      ;;
    --reviewer-model)
      [[ $# -gt 1 ]] || die "--reviewer-model requires a value"
      REVIEWER_MODEL="$2"
      shift 2
      ;;
    --reviewer-effort)
      [[ $# -gt 1 ]] || die "--reviewer-effort requires a value"
      REVIEWER_EFFORT="$2"
      shift 2
      ;;
    # v1.5 Phase 4 (A-6): dev-review hand-off. --execute (and --verify) treat the
    # bounced document as a plan and delegate to the dev-review execute/verify
    # engine. Doc-pipeline seats (COMPOSER_/REVIEWER_MODEL above) are the bounce's
    # seats and are NOT forwarded to the engine — the engine has its own seats and
    # presets. Only --claude-model forwards (below, near the hand-off).
    --execute) EXECUTE=true; shift ;;
    --verify) DEV_REVIEW_VERIFY=true; shift ;;
    --dev-review) EXECUTE=true; DEV_REVIEW_VERIFY=true; shift ;;
    --workdir)
      [[ $# -gt 1 ]] || die "--workdir requires a value"
      EXEC_WORKDIR="$2"
      shift 2
      ;;
    --verifier)
      [[ $# -gt 1 ]] || die "--verifier requires a value"
      case "$2" in
        codex|opus|claude) EXEC_VERIFIER="$2" ;;
        *) die "--verifier must be codex|opus|claude (got: $2)" ;;
      esac
      shift 2
      ;;
    --revise-loop)
      [[ $# -gt 1 ]] || die "--revise-loop requires a value"
      [[ "$2" =~ ^[0-9]+$ ]] || die "--revise-loop must be a non-negative integer (got: $2)"
      EXEC_REVISE_LOOP="$2"
      shift 2
      ;;
    --exec-branch)
      [[ $# -gt 1 ]] || die "--exec-branch requires a value"
      EXEC_BRANCH_SPEC="$2"
      shift 2
      ;;
    --exec-worktree)
      [[ $# -gt 1 ]] || die "--exec-worktree requires a value"
      EXEC_WORKTREE_SPEC="$2"
      shift 2
      ;;
    --exec-timeout)
      [[ $# -gt 1 ]] || die "--exec-timeout requires a value"
      { [[ "$2" =~ ^[0-9]+$ ]] && [[ "$2" != "0" ]]; } || die "--exec-timeout must be a positive integer (got: $2)"
      EXEC_TIMEOUT="$2"
      shift 2
      ;;
    --bounce-only) BOUNCE_ONLY=true; shift ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    --lab)
      [[ $# -gt 1 ]] || die "--lab requires a mode"
      LAB_MODE="$2"
      shift 2
      ;;
    --target)
      [[ $# -gt 1 ]] || die "--target requires a value"
      TARGET="$2"
      shift 2
      ;;
    --tier)
      [[ $# -gt 1 ]] || die "--tier requires a value"
      case "$2" in
        template|policy|code) TIER="$2" ;;
        *) die "--tier must be template|policy|code (got: $2)" ;;
      esac
      shift 2
      ;;
    --pr-branch)
      [[ $# -gt 1 ]] || die "--pr-branch requires a value"
      PR_BRANCH="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --budget)
      [[ $# -gt 1 ]] || die "--budget requires a value"
      [[ "$2" =~ ^[0-9]+$ ]] || die "--budget must be a positive integer (got: $2)"
      BUDGET_USD="$2"
      shift 2
      ;;
    --yes)
      AUTO_YES=true
      shift
      ;;
    --flavor)
      [[ $# -gt 1 ]] || die "--flavor requires a value"
      case "$2" in
        bug-catcher|faster-converger|blind-spot-surfacer|general) FLAVOR_OVERRIDE="$2" ;;
        *) die "--flavor must be one of bug-catcher|faster-converger|blind-spot-surfacer|general (got: $2)" ;;
      esac
      shift 2
      ;;
    --no-adaptive)
      NO_ADAPTIVE=1
      shift
      ;;
    --no-report)
      NO_REPORT=1
      shift
      ;;
    --complexity)
      [[ $# -gt 1 ]] || die "--complexity requires a value (NORMAL|COMPLEX)"
      case "$2" in
        NORMAL|COMPLEX) COMPLEXITY_OVERRIDE="$2" ;;
        *) die "invalid --complexity value: $2 (expected NORMAL|COMPLEX)" 1 ;;
      esac
      shift 2
      ;;
    --)
      shift
      TASK="$*"
      break
      ;;
    -*)
      die "Unknown flag: $1. Use --help for usage."
      ;;
    *)
      if [[ -z "$TASK" ]]; then
        TASK="$1"
      else
        TASK="${TASK} $1"
      fi
      shift
      ;;
  esac
done

# A GLM seat may receive its key through this worktree's gitignored .env.local.
# Read only ZAI_API_KEY; sourcing the file would import unrelated settings into
# the long-lived bouncer process. The value remains a shell variable and is
# never exported — invoke_glm places it on its one child command with `env`.
load_zai_api_key_from_env_local() {
  local env_file="$SCRIPT_DIR/.env.local"
  local line="" value=""

  [[ -z "${ZAI_API_KEY:-}" && -r "$env_file" ]] || return 0
  line=$(grep -m 1 -E '^[[:space:]]*(export[[:space:]]+)?ZAI_API_KEY[[:space:]]*=' "$env_file" 2>/dev/null || true)
  [[ -n "$line" ]] || return 0

  value=$(printf '%s' "$line" | sed -e 's/^[^=]*=//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  case "$value" in
    \"*\") value="${value#\"}"; value="${value%\"}" ;;
    \'*\') value="${value#\'}"; value="${value%\'}" ;;
  esac
  [[ -n "$value" ]] && ZAI_API_KEY="$value"
}

# Order is intentional: a key present only in .env.local must be loaded before
# the per-seat prerequisite checks. Unknown agents also fail here, before a run
# directory or any paid/live compose call is created.
load_zai_api_key_from_env_local
for _seat_agent in "$AGENT_A" "$AGENT_B"; do
  if ! seat_prereqs_ok "$_seat_agent"; then
    die "$SEAT_PREREQ_ERROR"
  fi
done
unset _seat_agent
if [[ "$AGENT_A" == "kimi" && -n "$REVIEWER_EFFORT" ]]; then
  die "kimi seat does not support reviewer effort overrides"
fi
if [[ "$AGENT_B" == "kimi" && -n "$COMPOSER_EFFORT" ]]; then
  die "kimi seat does not support composer effort overrides"
fi
if [[ "$BOUNCE_ONLY" == "false" && "$AGENT_A" == "kimi" && -n "$COMPOSER_EFFORT" ]]; then
  die "kimi seat does not support composer effort overrides"
fi

# Normalize user-supplied filesystem paths after parsing. This lets WSL-backed
# Bash runs accept Windows-style file arguments such as C:/Users/.../plan.md.
[[ -n "$CONTEXT_FILE" ]] && CONTEXT_FILE=$(normalize_path_for_bash "$CONTEXT_FILE")
[[ -n "$OUTPUT_FILE" ]] && OUTPUT_FILE=$(normalize_path_for_bash "$OUTPUT_FILE")
[[ -n "$EXEC_WORKDIR" ]] && EXEC_WORKDIR=$(normalize_path_for_bash "$EXEC_WORKDIR")
TASK_AS_PATH=""
[[ -n "$TASK" ]] && TASK_AS_PATH=$(normalize_path_for_bash "$TASK")

# v1.5 Phase 1 (A-4b): snapshot the post-parse base model/effort globals so the
# per-role seat layer (apply_role_seat) can fall back to them. Captured AFTER
# parsing so --claude-model is reflected. CLAUDE_MODEL carries its lib default
# (best -> claude-opus-4-8); the others default empty (OFF) = argv parity.
CLAUDE_MODEL_BASE="$CLAUDE_MODEL"; CODEX_MODEL_BASE="${CODEX_MODEL:-}"
GLM_MODEL_BASE="${GLM_MODEL:-glm-5.3-flash}"; KIMI_MODEL_BASE="${KIMI_MODEL:-kimi-code/k3}"
CLAUDE_EFFORT_BASE="${CLAUDE_EFFORT:-}"; CODEX_EFFORT_BASE="${CODEX_REASONING_EFFORT:-}"
GLM_EFFORT_BASE="${GLM_EFFORT:-}"

# v1.5 Phase 4 (A-6): dev-review hand-off flag validation. Fail fast BEFORE any
# side effect so a misconfigured code run never composes/bounces first and then
# dies. Every execute-only flag requires --execute; --verify requires it too
# because verify only makes sense on code the executor just wrote.
if [[ "$EXECUTE" == "false" ]]; then
  _bad_exec_flag=""
  [[ "$DEV_REVIEW_VERIFY" == "true" ]] && _bad_exec_flag="--verify"
  [[ -n "$EXEC_WORKDIR" ]]             && _bad_exec_flag="--workdir"
  [[ -n "$EXEC_VERIFIER" ]]            && _bad_exec_flag="--verifier"
  [[ -n "$EXEC_REVISE_LOOP" ]]         && _bad_exec_flag="--revise-loop"
  [[ -n "$EXEC_BRANCH_SPEC" ]]         && _bad_exec_flag="--exec-branch"
  [[ -n "$EXEC_WORKTREE_SPEC" ]]       && _bad_exec_flag="--exec-worktree"
  [[ -n "$EXEC_TIMEOUT" ]]             && _bad_exec_flag="--exec-timeout"
  [[ -n "$_bad_exec_flag" ]] && die "${_bad_exec_flag} requires --execute (dev-review hand-off)."
  unset _bad_exec_flag
fi
# --verifier / --revise-loop are verify-phase knobs; they no-op without --verify.
if [[ "$EXECUTE" == "true" && "$DEV_REVIEW_VERIFY" == "false" ]]; then
  [[ -n "$EXEC_VERIFIER" ]]    && die "--verifier requires --verify."
  [[ -n "$EXEC_REVISE_LOOP" ]] && die "--revise-loop requires --verify."
fi
# Branch and worktree are mutually exclusive (dev-review enforces this too, but
# failing here gives a clearer message before the pipeline runs).
if [[ -n "$EXEC_BRANCH_SPEC" && -n "$EXEC_WORKTREE_SPEC" ]]; then
  die "--exec-branch and --exec-worktree are mutually exclusive."
fi
# Locate the dev-review engine up front so a missing engine fails before the
# (potentially slow, paid) compose/bounce rather than after it.
# CO_EVOLVE_DEV_REVIEW_SCRIPT (mirrors CO_EVOLVE_RUNS_DIR): let an external
# embedder — or a hermetic test — point at a relocated engine. Default unchanged.
DEV_REVIEW_SCRIPT="${CO_EVOLVE_DEV_REVIEW_SCRIPT:-$SCRIPT_DIR/dev-review/codex/dev-review.sh}"
if [[ "$EXECUTE" == "true" && ! -f "$DEV_REVIEW_SCRIPT" ]]; then
  die "--execute needs the dev-review engine, not found at: $DEV_REVIEW_SCRIPT"
fi

# Phase 3 LAB-01: opt-in lab routing. Dispatch BEFORE any side effects
# (RUN_DIR creation, interview, compose). Byte-parity invariant (L-03):
# when LAB_MODE is empty, this block is a no-op and the rest of the script
# runs byte-identically to pre-Phase-3. L-04: unknown-mode fail-fast is
# handled inside dispatch_lab_mode.
#
# Argv contract (v1.2, W-3): "$TASK" here is the concatenated task string
# produced by the existing parser (TASK="${TASK} $1" loop). Lab inhabitants
# receive it as a single argv slot — i.e. entry.sh's $1 is the whole task
# string. See lab/README.md §How-to-add for the v1.2 contract. If a lab
# inhabitant needs multi-slot argv, it must split $1 itself.
# Phase 8: when routing to pel-proposer, rebuild argv from the parsed
# flag variables so the emitter sees them. For other lab modes, preserve
# Phase 3 behavior (pass $TASK as sole trailing arg).
if [[ "$LAB_MODE" == "pel-proposer" ]]; then
  # v1.3-adaptive: propagate routing flags as env vars (consumed by router.sh).
  # Default-on means router runs unless --no-adaptive set; --complexity
  # short-circuits the Haiku call inside the router.
  if [[ "$NO_ADAPTIVE" == "1" ]]; then
    export PEL_NO_ADAPTIVE=1
  fi
  if [[ -n "$COMPLEXITY_OVERRIDE" ]]; then
    export PEL_COMPLEXITY_OVERRIDE="$COMPLEXITY_OVERRIDE"
  fi

  lab_tail=()
  [[ -n "$TARGET" ]] && lab_tail+=("--target" "$TARGET")
  [[ -n "$TIER" ]] && lab_tail+=("--tier" "$TIER")
  [[ -n "$PR_BRANCH" ]] && lab_tail+=("--pr-branch" "$PR_BRANCH")
  [[ "$DRY_RUN" == "true" ]] && lab_tail+=("--dry-run")
  [[ "$BUDGET_USD" != "25" ]] && lab_tail+=("--budget" "$BUDGET_USD")
  [[ "$AUTO_YES" == "true" ]] && lab_tail+=("--yes")
  [[ -n "$FLAVOR_OVERRIDE" ]] && lab_tail+=("--flavor" "$FLAVOR_OVERRIDE")
  [[ -n "$TASK" ]] && lab_tail+=("--" "$TASK")
  dispatch_lab_mode "$LAB_MODE" "$SCRIPT_DIR/lab" "${lab_tail[@]}"
  # dispatch_lab_mode exec's — unreachable on success.
elif [[ -n "$LAB_MODE" ]]; then
  dispatch_lab_mode "$LAB_MODE" "$SCRIPT_DIR/lab" "$TASK"
  # dispatch_lab_mode exec's — unreachable on success.
fi

# --- Input Detection ---
if [[ -n "$TASK_AS_PATH" && -f "$TASK_AS_PATH" ]]; then
  INPUT_TYPE="file"
  TASK="$TASK_AS_PATH"
  INPUT_CONTENT=$(cat "$TASK")
elif [[ -n "$TASK" ]]; then
  INPUT_TYPE="string"
  # S-1: a question/task string containing literal [CONTESTED]/[CLARIFY]
  # tokens would inject live protocol markers into the loop and skew marker
  # accounting. Strip them from string input; file input is NOT stripped —
  # a document under bounce legitimately carries markers. (Marker hygiene
  # only, not a prompt-injection defense.)
  TASK=$(strip_protocol_markers "$TASK")
  INPUT_CONTENT="$TASK"
elif [[ ! -t 0 ]]; then
  INPUT_TYPE="pipe"
  INPUT_CONTENT=$(cat)
  TASK="(piped input)"
else
  echo "Error: no input provided. Pass a question, file, or pipe stdin." >&2
  echo "Use --help for usage." >&2
  exit 1
fi

# --- Run Directory ---
RUN_LABEL=$(echo "$TASK" | head -c 60 | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//;s/-$//')
RUN_LABEL="${RUN_LABEL:-co-evolve}"
# CO_EVOLVE_RUNS_DIR (v1.4): external embedders (the npm MCP server) redirect
# run artifacts away from the script's own directory, which may live inside a
# read-only global package install. Default unchanged.
RUNS_ROOT="${CO_EVOLVE_RUNS_DIR:-$SCRIPT_DIR/runs}"
RUN_DIR="$RUNS_ROOT/co-evolve-${RUN_LABEL}-${TIMESTAMP}"
mkdir -p "$RUN_DIR"
LOG_FILE="$RUN_DIR/run.log"
WORKING_FILE="$RUN_DIR/working.md"

printf '%s' "$INPUT_CONTENT" > "$RUN_DIR/original-input.md"

# --- Bounce state (bounce-state/1.0; see evals/BOUNCE-RUNNER-CONTRACT.md) ---
STATE_FILE="$RUN_DIR/state.json"
if [[ "$CHAIN" == "true" ]]; then
  RUN_MODE="chain"
elif [[ "$BOUNCE_ONLY" == "true" ]]; then
  RUN_MODE="bounce-only"
else
  RUN_MODE="compose"
fi
# baseline_file is mode-aware: in compose mode the bounce loop's job is to
# improve the composed draft, so that draft is the comparison baseline.
BASELINE_FILE="original-input.md"
[[ "$RUN_MODE" == "compose" ]] && BASELINE_FILE="compose-output.md"
# Reviewer persona is orthogonal to RUN_MODE (the scorer's baseline logic keys
# off mode, so persona must never become a mode value). Precedence mirrors
# build_reviewer_preamble: adversarial > lens > light.
REVIEWER_PERSONA="light"
if [[ "$ADVERSARIAL" == "true" ]]; then
  REVIEWER_PERSONA="adversarial"
elif [[ -n "$LENS" ]]; then
  REVIEWER_PERSONA="lens"
fi
init_bounce_state "$STATE_FILE" "co-evolve-bouncer.sh" "$RUN_MODE" "$TASK" "$INPUT_TYPE" "$BASELINE_FILE" "working.md" "$REVIEWER_PERSONA"

# Any fatal exit (die, set -e, auth abort) marks the run aborted so the
# scorer never issues a quality verdict for a half-finished run.
_finalize_bounce_state_on_exit() {
  local exit_code=$?
  if [[ -f "$STATE_FILE" ]] && command -v jq >/dev/null 2>&1; then
    if [[ "$(jq -r '.status' "$STATE_FILE" 2>/dev/null)" == "running" ]]; then
      if (( exit_code == 0 )); then
        finalize_bounce_state "$STATE_FILE" "complete"
      else
        finalize_bounce_state "$STATE_FILE" "aborted"
      fi
    fi
  fi
}
trap _finalize_bounce_state_on_exit EXIT

# --- Interview Phase ---
run_interview() {
  log ""
  log "--- INTERVIEW ---"

  if [[ -z "$AUDIENCE" ]]; then
    printf 'Who is the audience for this? (e.g., judge, co-parent, lawyer, general) [general]: ' > /dev/tty
    read -r AUDIENCE < /dev/tty
    AUDIENCE="${AUDIENCE:-general}"
  fi
  log " Audience: $AUDIENCE"

  if [[ -z "$EXOCORTEX_QUERY" ]]; then
    printf 'Search your ExoCortex for relevant context? [y/N]: ' > /dev/tty
    read -r exo_answer < /dev/tty
    if [[ "$exo_answer" =~ ^[Yy] ]]; then
      printf 'What should I search for? ' > /dev/tty
      read -r EXOCORTEX_QUERY < /dev/tty
    fi
  fi
  if [[ -n "$EXOCORTEX_QUERY" ]]; then
    log " ExoCortex query: $EXOCORTEX_QUERY"
  fi

  if [[ -z "$CONTEXT_FILE" ]]; then
    printf 'Any files to include as context? (path or Enter to skip): ' > /dev/tty
    read -r CONTEXT_FILE < /dev/tty
  fi
  if [[ -n "$CONTEXT_FILE" ]]; then
    log " Context file: $CONTEXT_FILE"
  fi

  printf 'What kind of output do you want? (e.g., argument, email draft, analysis, plan) [auto]: ' > /dev/tty
  read -r OUTPUT_TYPE < /dev/tty
  OUTPUT_TYPE="${OUTPUT_TYPE:-auto}"
  log " Output type: $OUTPUT_TYPE"

  log "--- END INTERVIEW ---"
  log ""
}

if [[ "$SKIP_INTERVIEW" == "false" ]]; then
  run_interview
  [[ -n "$CONTEXT_FILE" ]] && CONTEXT_FILE=$(normalize_path_for_bash "$CONTEXT_FILE")
fi

# --- Context Enrichment ---
CONTEXT_BLOCK=""

if [[ -n "$EXOCORTEX_QUERY" ]]; then
  log "NOTE: ExoCortex CLI search not yet available. Use --context with a file or run from Claude Code for ExoCortex integration."
fi

if [[ -n "$CONTEXT_FILE" && ! -f "$CONTEXT_FILE" ]]; then
  die "Context file not found: $CONTEXT_FILE"
fi

if [[ -n "$CONTEXT_FILE" && -f "$CONTEXT_FILE" ]]; then
  CONTEXT_BLOCK="## Background Context

$(cat "$CONTEXT_FILE")

---

"
  log " Loaded context from: $CONTEXT_FILE ($(wc -w < "$CONTEXT_FILE" | tr -d '\r\n ') words)"
fi

# --- Role Preamble Generation ---
build_reviewer_preamble() {
  # --adversarial wins over --lens: adversarial is the METHOD, lens the FOCUS,
  # so a lens given alongside it composes as a focus line instead of replacing
  # the persona. Adversarial-off paths below are byte-identical to pre-persona.
  if [[ "$ADVERSARIAL" == "true" ]]; then
    local preamble
    preamble=$(cat "$TEMPLATE_DIR/role-reviewer-adversarial.md")
    if [[ -n "$LENS" ]]; then
      preamble="${preamble}
Focus your adversarial review through this lens: ${LENS}."
    fi
    if [[ "$SKIP_INTERVIEW" != "true" && -n "$AUDIENCE" && "$AUDIENCE" != "general" && "$AUDIENCE" != "auto" ]]; then
      preamble="${preamble}
Evaluate this as if you are a ${AUDIENCE} reading it. What would they find unconvincing, unclear, or missing?"
    fi
    echo "$preamble"
  elif [[ -n "$LENS" ]]; then
    echo "You are the ${LENS} reviewing this work. Be adversarial from that perspective. Every critique must include a concrete alternative."
  elif [[ "$SKIP_INTERVIEW" == "true" ]]; then
    cat "$TEMPLATE_DIR/role-reviewer-light.md"
  else
    local preamble
    preamble=$(cat "$TEMPLATE_DIR/role-reviewer-light.md")
    if [[ -n "$AUDIENCE" && "$AUDIENCE" != "general" && "$AUDIENCE" != "auto" ]]; then
      preamble="${preamble}Evaluate this as if you are a ${AUDIENCE} reading it. What would they find unconvincing, unclear, or missing?"
    fi
    echo "$preamble"
  fi
}

build_composer_preamble() {
  if [[ -n "$LENS" ]]; then
    echo "Resolve all critiques from the ${LENS} perspective. Strengthen weak points. Make it bulletproof."
  elif [[ "$SKIP_INTERVIEW" == "true" ]]; then
    cat "$TEMPLATE_DIR/role-composer-light.md"
  else
    local preamble
    preamble=$(cat "$TEMPLATE_DIR/role-composer-light.md")
    if [[ -n "${OUTPUT_TYPE:-}" && "$OUTPUT_TYPE" != "auto" ]]; then
      preamble="${preamble}The output should be a ${OUTPUT_TYPE}. Shape it accordingly."
    fi
    echo "$preamble"
  fi
}

# --- v1.5 Phase 1 (A-4b): document-pipeline per-role seat layer ---
# Mirrors dev-review.sh's apply_seat_env: layer an optional per-role model/effort
# override onto the global CLAUDE_MODEL/CODEX_MODEL/effort vars around each
# invocation, with the same cross-agent leak guard (a seat override configured for
# one agent kind must never reach the other kind's argv). Byte-parity: with no
# COMPOSER_/REVIEWER_ seat set, every role resolves to the base globals, so argv is
# unchanged. The base snapshot (…_BASE) is captured once after arg parsing.
apply_role_seat() {
  local role="$1" agent="$2" model="" effort=""
  case "$role" in
    composer|defend)          model="$COMPOSER_MODEL"; effort="$COMPOSER_EFFORT" ;;  # composer side
    reviewer|critique|tighten) model="$REVIEWER_MODEL"; effort="$REVIEWER_EFFORT" ;;  # reviewer side
    *) : ;;  # unknown role: globals only
  esac
  # Cross-agent leak guard (same coupling rule as dev-review): a model picked for
  # the wrong agent kind means its effort is wrong too, so drop the WHOLE pair and
  # fall back to that agent's base values. Every supported agent has an explicit
  # arm so a new/typoed name can never silently inherit Claude's credentials.
  case "$agent" in
    claude)
      case "$model" in gpt-*|codex*|glm-*|kimi-*) model=""; effort="" ;; esac
      export CLAUDE_MODEL="$(resolve_claude_model_alias "${model:-$CLAUDE_MODEL_BASE}")"
      export CLAUDE_EFFORT="${effort:-$CLAUDE_EFFORT_BASE}"
      ;;
    codex)
      case "$model" in fable|best|opus|claude-*|glm-*|kimi-*) model=""; effort="" ;; esac
      export CODEX_MODEL="${model:-$CODEX_MODEL_BASE}"
      export CODEX_REASONING_EFFORT="${effort:-$CODEX_EFFORT_BASE}"
      ;;
    glm)
      case "$model" in gpt-*|codex*|kimi-*) model=""; effort="" ;; esac
      GLM_MODEL="$(resolve_claude_model_alias "${model:-$GLM_MODEL_BASE}")"
      GLM_EFFORT="${effort:-$GLM_EFFORT_BASE}"
      ;;
    kimi)
      case "$model" in fable|best|opus|claude-*|gpt-*|codex*|glm-*) model=""; effort="" ;; esac
      [[ -z "$effort" ]] || die "kimi seat does not support composer/reviewer effort overrides"
      KIMI_MODEL="${model:-$KIMI_MODEL_BASE}"
      ;;
    *)
      die "Unknown agent: $agent"
      ;;
  esac
}

# Resolve a role's "agent:model@effort" descriptor with the SAME precedence
# apply_role_seat uses, but without mutating the exported env. Feeds the banner.
# When a role inherits (no seat set), reports "(inherit:<global>)" — never blank.
resolve_role_seat_string() {
  local role="$1" agent="$2" model="" effort="" model_str="" effort_str=""
  case "$role" in
    composer|defend)           model="$COMPOSER_MODEL"; effort="$COMPOSER_EFFORT" ;;
    reviewer|critique|tighten) model="$REVIEWER_MODEL"; effort="$REVIEWER_EFFORT" ;;
    *) : ;;
  esac
  case "$agent" in
    claude)
      case "$model" in gpt-*|codex*|glm-*|kimi-*) model=""; effort="" ;; esac
      if [[ -n "$model" ]]; then model_str="$(resolve_claude_model_alias "$model")"; else model_str="(inherit:${CLAUDE_MODEL_BASE})"; fi
      if [[ -n "$effort" ]]; then effort_str="$effort"; else effort_str="(inherit:${CLAUDE_EFFORT_BASE:-default})"; fi
      ;;
    codex)
      case "$model" in fable|best|opus|claude-*|glm-*|kimi-*) model=""; effort="" ;; esac
      if [[ -n "$model" ]]; then model_str="$model"; else model_str="(inherit:${CODEX_MODEL_BASE:-CLI-config})"; fi
      if [[ -n "$effort" ]]; then effort_str="$effort"; else effort_str="(inherit:${CODEX_EFFORT_BASE:-default})"; fi
      ;;
    glm)
      case "$model" in gpt-*|codex*|kimi-*) model=""; effort="" ;; esac
      model_str="$(resolve_claude_model_alias "${model:-$GLM_MODEL_BASE}")"
      if [[ -n "$effort" ]]; then effort_str="$effort"; else effort_str="${GLM_EFFORT_BASE:-default}"; fi
      ;;
    kimi)
      case "$model" in fable|best|opus|claude-*|gpt-*|codex*|glm-*) model=""; effort="" ;; esac
      model_str="${model:-$KIMI_MODEL_BASE}"
      effort_str="default"
      ;;
    *)
      die "Unknown agent: $agent"
      ;;
  esac
  printf '%s:%s@%s' "$agent" "$model_str" "$effort_str"
}

# --- Agent Invocation Helper ---
# v1.5 Phase 1 (A-4b): `role` (composer/reviewer/critique/defend/tighten) selects
# the per-role seat; apply_role_seat layers it onto the globals before dispatch.
invoke_agent() {
  local agent="$1"
  local prompt_file="$2"
  local output_file="$3"
  local stderr_file="$4"
  local role="${5:-}"

  [[ -n "$role" ]] && apply_role_seat "$role" "$agent"

  case "$agent" in
    claude) invoke_claude "$prompt_file" "$output_file" "$stderr_file" ;;
    codex)  invoke_codex "$prompt_file" "$output_file" "$stderr_file" ;;
    glm)    invoke_glm "$prompt_file" "$output_file" "$stderr_file" ;;
    kimi)   invoke_kimi "$prompt_file" "$output_file" "$stderr_file" ;;
    *)      die "Unknown agent: $agent" ;;
  esac
}

# Additive observability matching dev-review's seat_models convention. GLM and
# Kimi descriptors always contain their concrete model ids, even with no role
# override, so state.json never reports an ambiguous inherited/default model for
# either new seat.
write_state_field "$STATE_FILE" ".seat_models.compose" "string" \
  "$(resolve_role_seat_string composer "$AGENT_A")"
write_state_field "$STATE_FILE" ".seat_models.reviewer" "string" \
  "$(resolve_role_seat_string reviewer "$AGENT_A")"
write_state_field "$STATE_FILE" ".seat_models.composer" "string" \
  "$(resolve_role_seat_string composer "$AGENT_B")"

# --- Compose Phase ---
run_compose_phase() {
  local compose_prompt_file="$RUN_DIR/.compose-prompt.md"
  local compose_output_file="$RUN_DIR/compose-output.md"
  local compose_stderr_file="$RUN_DIR/compose-stderr.log"
  local compose_retry_stderr_file="$RUN_DIR/compose-stderr-retry.log"
  local compose_prompt

  if [[ "$INPUT_TYPE" == "file" ]]; then
    compose_prompt="Review and improve the following document. Identify gaps, strengthen weak points, and tighten the language.

${CONTEXT_BLOCK}${INPUT_CONTENT}"
  else
    compose_prompt="Respond to the following thoroughly and substantively.

${CONTEXT_BLOCK}${INPUT_CONTENT}"
  fi

  printf '%s' "$compose_prompt" > "$compose_prompt_file"

  log "--- COMPOSE PHASE ---"
  log " Agent: $AGENT_A"
  log " Seat:  $(resolve_role_seat_string composer "$AGENT_A")"
  # v1.5 Phase 1 (M2): the composer seat override can be shaped for the OTHER
  # agent kind (e.g. COMPOSER_MODEL=gpt-5.5 while the compose phase runs on
  # claude). apply_role_seat's leak guard drops it correctly — but used to do so
  # silently. Surface the drop with an explicit one-liner so the operator sees
  # why the compose phase is not using their composer override.
  if [[ -n "$COMPOSER_MODEL" ]]; then
    if [[ "$AGENT_A" == "codex" ]]; then
      case "$COMPOSER_MODEL" in
        fable|best|opus|claude-*) log " NOTE: composer seat override dropped for compose phase: agent mismatch (claude override, codex phase)" ;;
      esac
    else
      case "$COMPOSER_MODEL" in
        gpt-*|codex*) log " NOTE: composer seat override dropped for compose phase: agent mismatch (codex override, claude phase)" ;;
      esac
    fi
  fi
  log " Input: $INPUT_TYPE ($(echo "$INPUT_CONTENT" | wc -w | tr -d '\r\n ') words)"

  invoke_agent "$AGENT_A" "$compose_prompt_file" "$compose_output_file" "$compose_stderr_file" composer

  # R-1/R-2: fail fast on CLI-missing / auth-failure (rc 2) instead of
  # accepting the error text as a composed document or burning a retry.
  local compose_artifact_rc=0
  validate_agent_artifact "$compose_output_file" "$compose_stderr_file" "$AGENT_A" || compose_artifact_rc=$?
  if (( compose_artifact_rc == 2 )); then
    return 1
  fi

  if [[ ! -s "$compose_output_file" ]] || (( $(wc -w < "$compose_output_file" | tr -d '\r\n ') < 10 )); then
    log " WARNING: compose returned empty or minimal output. Retrying once..."
    : > "$compose_output_file"
    invoke_agent "$AGENT_A" "$compose_prompt_file" "$compose_output_file" "$compose_retry_stderr_file" composer

    compose_artifact_rc=0
    validate_agent_artifact "$compose_output_file" "$compose_retry_stderr_file" "$AGENT_A" || compose_artifact_rc=$?
    if (( compose_artifact_rc == 2 )); then
      return 1
    fi
  fi

  if [[ ! -s "$compose_output_file" ]]; then
    log " ERROR: compose returned empty output on retry."
    return 1
  fi

  local compose_words
  compose_words=$(wc -w < "$compose_output_file" | tr -d '\r\n ')
  log " Compose output: $compose_words words"
  log "--- END COMPOSE ---"
  log ""

  cp "$compose_output_file" "$WORKING_FILE"
}

# --- Bounce Phase ---
# v1.5 Phase 4 (A-5): the bounce loop reports its convergence outcome via three
# globals so the post-loop adjudication step (below) can decide honestly:
#   RUN_CONVERGED_NATURALLY — "true" iff the RAW marker count hit 0 within the
#     configured passes. Decided post-loop from RUN_FINAL_MARKERS_RAW only.
#   RUN_FINAL_MARKERS       — fence-aware count after the last pass (per-pass
#     accounting semantics; informational and for the loop's early break).
#   RUN_FINAL_MARKERS_RAW   — fence-AGNOSTIC count of WORKING_FILE after the
#     last pass; the honesty gate's authority (a marker inside a code fence
#     still blocks convergence — see count_markers_raw in lib).
# Byte-parity: these are set but, on the naturally-converging path, drive NO
# extra work — the adjudication block only fires when raw markers survive.
RUN_CONVERGED_NATURALLY="false"
RUN_FINAL_MARKERS=0
RUN_FINAL_MARKERS_RAW=0
# C-2: count bounce passes that produced usable output AND were applied to
# WORKING_FILE (i.e. reached append_bounce_pass). A loop that breaks on empty
# agent output (call + retry both empty) never applies a pass, so this stays 0
# and the post-loop guard refuses to launder the un-reviewed compose draft as a
# converged final. Healthy runs apply >= 1 pass, so the guard never fires on
# them and byte-parity is untouched.
RUN_PASSES_APPLIED=0
run_bounce_phase() {
  local pass
  local role
  local current_agent
  local role_preamble
  local protocol
  local filled
  local prompt_file
  local output_file
  local stderr_file
  local clean_file

  local total_passes="$MAX_BOUNCES"
  if [[ "$CHAIN" == "true" ]]; then
    total_passes=3
  fi

  for (( pass=1; pass<=total_passes; pass++ )); do
    prompt_file="$RUN_DIR/.bounce-pass-${pass}-prompt.md"
    output_file="$RUN_DIR/.bounce-pass-${pass}-output.md"
    stderr_file="$RUN_DIR/pass-${pass}-stderr.log"
    # Plain name (not dot-prefixed): dot-prefixed pass artifacts are invisible
    # to ls and were repeatedly missed — see evals/BOUNCE-RUNNER-CONTRACT.md.
    clean_file="$RUN_DIR/pass-${pass}-clean.md"

    # Determine agent and role
    if (( pass % 2 == 1 )); then
      current_agent="$AGENT_A"
      if [[ "$CHAIN" == "true" ]]; then
        case "$pass" in
          1)
            # --adversarial swaps only the critique stage; defend/tighten keep
            # their templates (the persona is a critique method, not a chain).
            if [[ "$ADVERSARIAL" == "true" ]]; then
              role_preamble=$(cat "$TEMPLATE_DIR/chain-critique-adversarial.md")
            else
              role_preamble=$(cat "$TEMPLATE_DIR/chain-critique.md")
            fi
            ;;
          3) role_preamble=$(cat "$TEMPLATE_DIR/chain-tighten.md") ;;
        esac
        role="critique"
        [[ "$pass" == "3" ]] && role="tighten"
      else
        role_preamble=$(build_reviewer_preamble)
        role="reviewer"
      fi
    else
      current_agent="$AGENT_B"
      if [[ "$CHAIN" == "true" ]]; then
        role_preamble=$(cat "$TEMPLATE_DIR/chain-defend.md")
        role="defend"
      else
        role_preamble=$(build_composer_preamble)
        role="composer"
      fi
    fi

    # Build prompt — avoid bash string replacement for user-controlled values
    # to prevent corruption of & > \ and other special chars in TASK and paths.
    # Only substitute safe integer/keyword values inline; append everything else.
    protocol="${role_preamble}
$(cat "$PROTOCOL_TEMPLATE")"

    # Safe substitutions (integers and single keywords only)
    protocol="${protocol//\{PASS_NUMBER\}/$pass}"
    protocol="${protocol//\{TOTAL_PASSES\}/$total_passes}"
    protocol="${protocol//\{YOUR_ROLE\}/$role}"

    # Remove placeholders for values we'll append separately
    protocol="${protocol//\{TASK\}/see TASK section below}"
    protocol="${protocol//\{WORKING_DIR\}/see TASK section below}"
    protocol="${protocol//\{PLAN_CONTENT\}/see DOCUMENT section below}"

    {
      printf '%s\n\n' "$protocol"
      printf '## TASK\n\n%s\n\n' "$TASK"
      printf '## WORKING DIRECTORY\n\n%s\n\n' "$SCRIPT_DIR"
      printf '## DOCUMENT TO REVIEW\n\n'
      cat "$WORKING_FILE"
    } > "$prompt_file"

    log "--------------------------------------------"
    log " BOUNCE $pass/$total_passes - ${role} (${current_agent})"
    log " Seat:  $(resolve_role_seat_string "$role" "$current_agent")"
    log "--------------------------------------------"

    invoke_agent "$current_agent" "$prompt_file" "$output_file" "$stderr_file" "$role"

    # Validate output. R-1/R-2: rc 2 = CLI missing or unauthenticated — an
    # auth-error page must never be copied into WORKING_FILE as the document,
    # and a `break` here would let the run finalize as if it had converged.
    local bounce_artifact_rc=0
    validate_agent_artifact "$output_file" "$stderr_file" "$current_agent" || bounce_artifact_rc=$?
    if (( bounce_artifact_rc == 2 )); then
      die "bounce pass $pass aborted: ${current_agent} CLI failure (see message above)"
    fi

    if [[ ! -s "$output_file" ]]; then
      log " WARNING: ${current_agent} returned empty output. Retrying..."
      invoke_agent "$current_agent" "$prompt_file" "$output_file" "$stderr_file" "$role"

      bounce_artifact_rc=0
      validate_agent_artifact "$output_file" "$stderr_file" "$current_agent" || bounce_artifact_rc=$?
      if (( bounce_artifact_rc == 2 )); then
        die "bounce pass $pass aborted: ${current_agent} CLI failure (see message above)"
      fi
    fi

    if [[ ! -s "$output_file" ]]; then
      # C-2/C-8: die, don't break. A `break` here would hand whatever passes
      # already applied to the post-loop convergence block, which happily
      # finalizes "converged" on a run the protocol never finished — pass 1
      # applied, pass 2's agent died, and the half-bounced document launders
      # into a clean final. An empty retry only ever happens when another pass
      # was still REQUIRED (markers open, or chain stages pending), so the
      # honest terminal is the same aborted path as the zero-pass case: the
      # EXIT trap finalizes status=aborted and a chained --execute never runs.
      die "bounce pass $pass: ${current_agent} returned empty output on call and retry — the bounce did not complete; run ABORTED. See run.log."
    fi

    cp "$output_file" "$RUN_DIR/pass-${pass}-${role}-${current_agent}-raw.md"

    strip_human_summary "$output_file" "$clean_file"
    cp "$clean_file" "$WORKING_FILE"

    # Marker counts
    local contested clarify total_markers word_count
    contested=$(count_markers "$WORKING_FILE" "[CONTESTED]")
    clarify=$(count_markers "$WORKING_FILE" "[CLARIFY]")
    total_markers=$((contested + clarify))
    word_count=$(wc -w < "$WORKING_FILE" | tr -d '\r\n ')
    # A-5: remember the live-marker count after the most recent pass so the
    # post-loop adjudication step knows whether anything survived.
    RUN_FINAL_MARKERS=$total_markers

    log " [CONTESTED] markers: $contested"
    log " [CLARIFY] markers:   $clarify"
    log " Length:              $word_count words"
    log "--------------------------------------------"
    log ""

    append_bounce_pass "$STATE_FILE" "$pass" "$role" "$current_agent" \
      "pass-${pass}-${role}-${current_agent}-raw.md" "pass-${pass}-clean.md" \
      "$contested" "$clarify" "$word_count"
    # C-2: this pass produced usable output and is now recorded in state.passes.
    RUN_PASSES_APPLIED=$((RUN_PASSES_APPLIED + 1))

    # Human check
    if [[ "$AUTO" == "false" ]]; then
      printf '\nPass %d complete. %d [CONTESTED], %d [CLARIFY] markers.\n' "$pass" "$contested" "$clarify" > /dev/tty
      printf 'Press Enter to continue, "e" to edit, "s" to stop: ' > /dev/tty
      read -r human_input < /dev/tty
      case "$human_input" in
        e|E)
          "${EDITOR:-nano}" "$WORKING_FILE" < /dev/tty > /dev/tty
          log " Human edited the working file after pass $pass."
          ;;
        s|S)
          log " Human stopped after pass $pass."
          break
          ;;
      esac
    fi

    # Early convergence (standard mode only). Uses the fence-aware per-pass
    # count — pass semantics are unchanged; the HONEST convergence decision is
    # made post-loop on the raw count below.
    if [[ "$CHAIN" == "false" && "$total_markers" -eq 0 ]]; then
      log "Converged after $pass passes (no open markers)."
      log ""
      break
    fi
  done

  # C-2: a bounce that applied ZERO usable passes never reviewed the document,
  # and WORKING_FILE still holds the un-reviewed compose draft. That draft is
  # marker-free, so the convergence honesty block below would read 0 raw
  # markers and finalize "converged" — laundering a failed bounce into a clean
  # final that --execute would run. Empty agent output now dies IN the loop
  # (C-8, above), so this guard is the belt-and-suspenders invariant for any
  # other way of arriving here passless (e.g. --bounces 0). Refuse it: die
  # non-zero. The EXIT trap (_finalize_bounce_state_on_exit) then finalizes
  # status=aborted with convergence_status left null, exactly like the
  # auth-failure abort (bounce-state-simulation.sh S4); the scorer gate fails
  # on status=aborted, and a chained --execute never runs because the process
  # died before the hand-off. This is the honest terminal state for "the agent
  # produced nothing usable" — distinct from `stuck` (passes ran, but markers
  # could not be resolved). Healthy runs apply >= 1 pass, so this never fires
  # and the byte-parity path below is unchanged.
  if (( RUN_PASSES_APPLIED == 0 )); then
    die "bounce produced zero usable passes; the document was never reviewed — run ABORTED. See run.log."
  fi

  # A-5: convergence is decided by the marker count after the last pass, NOT by
  # mode. Any run — standard OR chain — that ends with 0 live markers converged
  # naturally and takes the byte-parity path (no adjudication). This also covers
  # standard mode converging exactly on the final pass (the loop just ends
  # without tripping the early-break) and chain mode's tighten pass clearing the
  # last markers. Chain mode gets the same post-final adjudication as standard
  # mode (it has no early-convergence break of its own and historically ran all
  # 3 passes then left markers live — exactly the case adjudication exists to
  # make honest).
  #
  # HONESTY GATE (adversarial-review fix): this decision uses the fence-AGNOSTIC
  # raw count, not count_markers. The per-pass counts above skip ``` fences and
  # inline code (correct for pass accounting — quoted examples are not
  # disagreements), but a live marker tucked inside a fence would count 0 and be
  # presented as natural convergence with the marker text still in the final
  # document. Raw counting closes that hole: a fenced survivor forces
  # adjudication (which may legitimately resolve or drop it) or ends the run
  # stuck — never silent "converged".
  local raw_contested raw_clarify
  raw_contested=$(count_markers_raw "$WORKING_FILE" "[CONTESTED]")
  raw_clarify=$(count_markers_raw "$WORKING_FILE" "[CLARIFY]")
  RUN_FINAL_MARKERS_RAW=$((raw_contested + raw_clarify))
  if [[ "$RUN_FINAL_MARKERS_RAW" -eq 0 ]]; then
    RUN_CONVERGED_NATURALLY="true"
  elif [[ "$RUN_FINAL_MARKERS" -eq 0 ]]; then
    # Fence-aware saw 0 but raw found survivors: say why adjudication fires.
    log " NOTE: $RUN_FINAL_MARKERS_RAW marker token(s) survive inside code fences/inline code — honesty gate forces adjudication."
  fi
}

# --- Forced Adjudication (A-5, convergence honesty) ---
# When the bounce ends with markers still live, "0 markers" can only be earned,
# not forced-in-silence. run_adjudication attempts ONE composer pass whose job
# is to resolve-or-drop every remaining marker AND emit a defensible receipt
# (adjudication-report.md) mapping each stripped marker -> chosen text + reason.
#
# Outcome is returned in the global ADJUDICATION_RESULT (NOT echoed: this
# function calls log(), which tees to stdout, so a command-substitution capture
# would swallow the log lines into the result). Values:
#   adjudicated — the pass produced a well-formed report AND left 0 live markers
#   stuck       — anything else (empty/failed pass, missing/malformed report, or
#                 markers still present). WORKING_FILE is left AS-IS (markers
#                 preserved) and the caller must NOT present it as a clean final.
ADJUDICATION_RESULT=""
#
# The report is emitted by the agent as a trailing `## ADJUDICATION REPORT`
# section (same channel as HUMAN SUMMARY); we split it out to adjudication-
# report.md and strip it from the document body. A "defensible choice for every
# marker" is checked structurally: one report bullet per pre-adjudication marker
# (>= PRE count) and zero live markers left in the body.

# Extract the `## ADJUDICATION REPORT` section from an agent output file into a
# standalone report file, and write the document body (everything before the
# section) to a clean file. Returns 0 iff a non-empty report section was found.
split_adjudication_report() {
  local raw_file="$1" body_file="$2" report_file="$3"
  awk '/^## ADJUDICATION REPORT[ \t]*$/{found=1} !found{print}' "$raw_file" > "$body_file"
  awk '
    /^## ADJUDICATION REPORT[ \t]*$/ { found=1; next }
    found { print }
  ' "$raw_file" > "$report_file"
  [[ -s "$report_file" ]]
}

# Count report bullets: lines under the report that name a resolved note. Each
# must start with a list marker and carry a [CONTESTED]/[CLARIFY] tag plus the
# CHOSE/WHY structure the template mandates. Code-fence-agnostic (the report is
# plain bullets, never fenced).
count_adjudication_entries() {
  local report_file="$1"
  awk '
    /^[ \t]*[-*][ \t]+\[(CONTESTED|CLARIFY)\]/ && /CHOSE:/ && /WHY:/ { n++ }
    END { print n + 0 }
  ' "$report_file" | tr -d '\r\n '
}

run_adjudication() {
  local pre_markers="$1"
  local adj_prompt_file="$RUN_DIR/.adjudicate-prompt.md"
  local adj_output_file="$RUN_DIR/.adjudicate-output.md"
  local adj_stderr_file="$RUN_DIR/adjudicate-stderr.log"
  local adj_raw_file="$RUN_DIR/adjudicate-raw.md"
  local adj_body_file="$RUN_DIR/adjudicate-clean.md"
  local report_file="$RUN_DIR/adjudication-report.md"
  local adj_agent="$AGENT_B"   # composer side owns resolution (defend/composer)

  # Build the adjudication prompt the same safe way as bounce passes: substitute
  # only safe tokens inline, append the document verbatim.
  local adj_protocol
  adj_protocol=$(cat "$TEMPLATE_DIR/adjudicate.md")
  adj_protocol="${adj_protocol//\{PLAN_CONTENT\}/see DOCUMENT section below}"
  {
    printf '%s\n\n' "$adj_protocol"
    printf '## TASK\n\n%s\n\n' "$TASK"
    printf '## DOCUMENT TO ADJUDICATE\n\n'
    cat "$WORKING_FILE"
  } > "$adj_prompt_file"

  log "--------------------------------------------"
  log " ADJUDICATION PASS - ${adj_agent} ($pre_markers marker token(s) survived the bounce, raw count)"
  log " Seat:  $(resolve_role_seat_string composer "$adj_agent")"
  log "--------------------------------------------"

  invoke_agent "$adj_agent" "$adj_prompt_file" "$adj_output_file" "$adj_stderr_file" composer

  # A CLI/auth failure (rc 2) or empty output cannot yield a defensible report.
  local adj_artifact_rc=0
  validate_agent_artifact "$adj_output_file" "$adj_stderr_file" "$adj_agent" || adj_artifact_rc=$?
  if (( adj_artifact_rc == 2 )) || [[ ! -s "$adj_output_file" ]]; then
    log " ADJUDICATION FAILED: agent produced no usable output — run is STUCK."
    ADJUDICATION_RESULT="stuck"
    return 0
  fi

  cp "$adj_output_file" "$adj_raw_file"

  # Split the report out of the document body. No report => cannot verify a
  # defensible choice for every marker => stuck.
  if ! split_adjudication_report "$adj_raw_file" "$adj_body_file" "$report_file"; then
    log " ADJUDICATION FAILED: no '## ADJUDICATION REPORT' section produced — run is STUCK."
    rm -f "$report_file"   # do not leave an empty report masquerading as valid
    ADJUDICATION_RESULT="stuck"
    return 0
  fi

  # The adjudicated body must itself carry zero marker tokens — counted
  # fence-AGNOSTICALLY (honesty gate). adjudicate.md forbids ANY
  # [CONTESTED]/[CLARIFY] token in the body above the report, so a raw count is
  # the defensible verdict here; a marker smuggled into a code fence must not
  # slip through as "adjudicated".
  local body_markers
  body_markers=$(( $(count_markers_raw "$adj_body_file" "[CONTESTED]") + $(count_markers_raw "$adj_body_file" "[CLARIFY]") ))

  # The report must account for at least every marker that was live going in.
  local entries
  entries=$(count_adjudication_entries "$report_file")

  if (( body_markers > 0 )); then
    log " ADJUDICATION FAILED: $body_markers marker token(s) still present after the pass (raw count, fences included) — run is STUCK."
    ADJUDICATION_RESULT="stuck"
    return 0
  fi
  if (( entries < pre_markers )); then
    log " ADJUDICATION FAILED: report maps $entries choice(s) for $pre_markers marker(s) — run is STUCK."
    ADJUDICATION_RESULT="stuck"
    return 0
  fi

  # Success: the adjudicated body becomes the working document.
  cp "$adj_body_file" "$WORKING_FILE"
  log " ADJUDICATED: $entries choice(s) recorded in adjudication-report.md; 0 live markers remain."
  ADJUDICATION_RESULT="adjudicated"
  return 0
}

# --- Banner ---
log "============================================"
log " CO-EVOLVE SESSION"
log "============================================"
log " Input:     $INPUT_TYPE"
log " Task:      $(echo "$TASK" | head -c 80)"
log " Compose:   $AGENT_A"
log " Bounce:    $AGENT_A / $AGENT_B"
log " Persona:   $REVIEWER_PERSONA (reviewer)"
if [[ "$AGENT_A" == "$AGENT_B" ]]; then
  log " NOTE: same-model bounce ($AGENT_A vs $AGENT_B) — no cross-vendor disagreement; persona and per-role seats are the only independence between passes."
fi
# v1.5 Phase 1 (A-4b): resolved per-role seats. Reviewer runs on AGENT_A (odd
# passes / critique+tighten); composer runs on AGENT_B (even passes / defend).
# The compose PHASE also runs the composer role, but on AGENT_A — its resolved
# seat can differ from the bounce-composer's (M2: leak guard drops a wrong-kind
# override), so it gets its own line and the actual compose model is always
# surfaced. Each shows agent:model@effort, or (inherit:<global>) when no seat
# override is set.
log " Compose seat:  $(resolve_role_seat_string composer "$AGENT_A")"
log " Reviewer seat: $(resolve_role_seat_string reviewer "$AGENT_A")"
log " Composer seat: $(resolve_role_seat_string composer "$AGENT_B")"
if [[ "$CHAIN" == "true" ]]; then
  log " Mode:      chain (critique -> defend -> tighten)"
else
  log " Mode:      standard ($MAX_BOUNCES passes)"
fi
log " Interview: $([[ "$SKIP_INTERVIEW" == "true" ]] && echo "skipped" || echo "completed")"
log " Auto:      $AUTO"
log " Run dir:   $RUN_DIR"
log "============================================"
log ""

# --- Execute Pipeline ---
if [[ "$BOUNCE_ONLY" == "true" ]]; then
  if [[ "$INPUT_TYPE" != "file" ]]; then
    die "--bounce-only requires a file input"
  fi
  cp "$RUN_DIR/original-input.md" "$WORKING_FILE"
  log "Skipping compose (--bounce-only). Bouncing file directly."
  log ""
else
  run_compose_phase || exit 1
fi

run_bounce_phase

# --- Convergence honesty (A-5) ---
# Decide the run's convergence outcome and record it. Three terminal states:
#   converged  — markers hit 0 naturally; NOTHING extra runs here, so a
#                naturally-converging run is byte-identical to the pre-Phase-4
#                bouncer on this path (the byte-parity invariant).
#   adjudicated — markers survived; one forced-adjudication pass resolved every
#                one with a receipt in adjudication-report.md.
#   stuck      — adjudication could not defensibly resolve every marker; the
#                working document is kept WITH its markers and is NOT presented
#                as a clean final.
CONVERGENCE_STATUS="converged"
RUN_STUCK="false"
if [[ "$RUN_CONVERGED_NATURALLY" == "true" ]]; then
  CONVERGENCE_STATUS="converged"
  log "Convergence: converged (markers resolved naturally within the configured passes)."
else
  # Markers survived the configured passes (standard mode with leftovers, any
  # chain run, or fence-hidden markers the raw honesty count caught). Force one
  # adjudication pass; it self-reports adjudicated|stuck via the
  # ADJUDICATION_RESULT global (not stdout — log() tees to stdout). The RAW
  # count is passed: every raw survivor needs a report entry.
  run_adjudication "$RUN_FINAL_MARKERS_RAW"
  CONVERGENCE_STATUS="$ADJUDICATION_RESULT"
  if [[ "$CONVERGENCE_STATUS" == "stuck" ]]; then
    RUN_STUCK="true"
  fi
fi

set_bounce_convergence_status "$STATE_FILE" "$CONVERGENCE_STATUS"
finalize_bounce_state "$STATE_FILE" "complete"

# Post-run human report (deterministic scorer + HUMAN-REPORT.md; no LLM
# cost). Best-effort: a reporting failure must never fail the run.
if (( NO_REPORT == 0 )); then
  bash "$SCRIPT_DIR/evals/report-bounce.sh" --run-dir "$RUN_DIR" >/dev/null 2>&1 \
    || log " WARNING: report generation failed (run is unaffected); run evals/report-bounce.sh --run-dir $RUN_DIR manually."
fi

# --- Output ---
FINAL_FILE="$RUN_DIR/${RUN_LABEL}.md"
# A-5: a STUCK run must never masquerade as a clean final. Prepend a loud,
# machine-greppable banner to the emitted document so both humans and any
# downstream consumer see it is unresolved and still carries markers. The
# working document (markers intact) is preserved verbatim below the banner.
if [[ "$RUN_STUCK" == "true" ]]; then
  {
    printf '<!-- CO-EVOLVE:STUCK — unresolved markers remain; this is NOT a converged final. -->\n'
    printf '> **STUCK — NOT A CLEAN FINAL.** The bounce could not resolve every disagreement, and\n'
    printf '> the forced adjudication pass failed to produce a defensible choice for every marker.\n'
    printf '> The document below is preserved AS-IS with its unresolved [CONTESTED]/[CLARIFY]\n'
    printf '> markers. Do not treat it as converged. See run.log and (if present) adjudication-report.md.\n\n'
    cat "$WORKING_FILE"
  } > "$FINAL_FILE"
  log " WARNING: run is STUCK — $FINAL_FILE carries unresolved markers and is labeled NOT-FINAL."
else
  cp "$WORKING_FILE" "$FINAL_FILE"
fi

if [[ -n "$OUTPUT_FILE" ]]; then
  cp "$FINAL_FILE" "$OUTPUT_FILE"
  log "Output written to: $OUTPUT_FILE"
fi

log "============================================"
log " CO-EVOLVE COMPLETE"
log "============================================"
log " Task:      $(echo "$TASK" | head -c 80)"
log " Run dir:   $RUN_DIR"
log " Final:     $FINAL_FILE"
log " Convergence: $CONVERGENCE_STATUS"
log "============================================"

# --- Dev-review hand-off (--execute / --verify) ---
# The bounce is done and the converged document is $FINAL_FILE. When --execute
# is set we now treat that document as an implementation plan and hand it to the
# dev-review engine via --skip-plan --plan, which runs its execute (and, with
# --verify, verify) phases. We do NOT re-implement those phases here: the engine
# is a separate, CI-tested script that already sources this repo's shared
# lib/co-evolution.sh, so delegating keeps a single source of truth and avoids
# doubling this script's size. Intent per .notes/dev-review-merge-plan.md: one
# entry point (co-evolve) for both non-code and code tasks; the flags differ.
#
# `exec` replaces this process so the engine owns the terminal and its exit code
# becomes co-evolve's exit code (0 APPROVED / clean, 2 REVISE / needs-review,
# 1 fatal) — the byte-for-byte contract dev-review callers already rely on.
if [[ "$EXECUTE" == "true" ]]; then
  # v1.5 Phase 4 (A-5 x A-6): a STUCK plan must NEVER be executed. If the bounce
  # could not converge and adjudication failed, $FINAL_FILE carries the
  # CO-EVOLVE:STUCK banner plus live [CONTESTED]/[CLARIFY] markers — it is not a
  # fit implementation plan. Refuse the hand-off (the empty-plan guard below does
  # NOT catch this: a stuck plan is non-empty). Exit 1 so callers/CI see the
  # code run did not proceed. The labeled plan + state.json/run.log explain why.
  if [[ "$RUN_STUCK" == "true" ]]; then
    die "cannot --execute: bounce is STUCK (unresolved markers). Resolve the document first; see $FINAL_FILE"
  fi

  # Byte-parity guard: the converged plan must exist and be non-empty, or the
  # executor would run against nothing. run_bounce_phase always writes it, but
  # fail loudly rather than hand the engine an empty plan.
  [[ -s "$FINAL_FILE" ]] || die "cannot --execute: bounced plan is empty ($FINAL_FILE)"

  # Print the plan first (unless redirected) so the operator sees what is about
  # to be executed; the engine's own logs follow on the same stream.
  if [[ -z "$OUTPUT_FILE" ]]; then
    cat "$FINAL_FILE"
  fi

  dev_review_args=(--skip-plan --plan "$FINAL_FILE")
  [[ "$DEV_REVIEW_VERIFY" == "true" ]] && dev_review_args+=(--verify)
  [[ -n "$EXEC_WORKDIR" ]]       && dev_review_args+=(--workdir "$EXEC_WORKDIR")
  [[ -n "$EXEC_VERIFIER" ]]      && dev_review_args+=(--verifier "$EXEC_VERIFIER")
  [[ -n "$EXEC_REVISE_LOOP" ]]   && dev_review_args+=(--revise-loop "$EXEC_REVISE_LOOP")
  [[ -n "$EXEC_BRANCH_SPEC" ]]   && dev_review_args+=(--branch "$EXEC_BRANCH_SPEC")
  [[ -n "$EXEC_WORKTREE_SPEC" ]] && dev_review_args+=(--worktree "$EXEC_WORKTREE_SPEC")
  [[ -n "$EXEC_TIMEOUT" ]]       && dev_review_args+=(--timeout "$EXEC_TIMEOUT")
  # v1.5 Phase 4 (A-6): forward ONLY the base --claude-model, NOT the doc-pipeline
  # per-role seats. Rationale (the seat-forwarding boundary): COMPOSER_/REVIEWER_
  # seats shape the *bounce's* two roles; the dev-review engine has its OWN seats
  # and presets (composer/executor/verifier), so leaking a doc-role seat into it
  # would be meaningless at best and wrong at worst. We forward CLAUDE_MODEL_BASE
  # (the snapshot taken before any apply_role_seat mutation) rather than the live
  # CLAUDE_MODEL, which apply_role_seat rewrites per pass — by the hand-off it
  # holds the last reviewer/composer seat, not the user's global choice. dev-review
  # resolves best/opus/fable aliases; ids pass through.
  [[ -n "${CLAUDE_MODEL_BASE:-}" ]] && dev_review_args+=(--claude-model "$CLAUDE_MODEL_BASE")

  # The boundary must hold for the ENVIRONMENT too, not just argv
  # (adversarial-review fix): apply_role_seat exports CLAUDE_MODEL/CLAUDE_EFFORT
  # (claude passes) and CODEX_MODEL/CODEX_REASONING_EFFORT (codex passes), and
  # `exec` hands the mutated environment to the engine, which snapshots those
  # very vars as ITS base seats (dev-review.sh ~:1428) — so `--reviewer-effort
  # high` would silently become the execute/verify effort. Restore each var to
  # its post-parse base before the exec: base non-empty -> export the base
  # (user's own global env passes through unchanged); base empty -> unset (the
  # var only exists because a seat exported it mid-run).
  export CLAUDE_MODEL="$CLAUDE_MODEL_BASE"
  if [[ -n "$CLAUDE_EFFORT_BASE" ]]; then export CLAUDE_EFFORT="$CLAUDE_EFFORT_BASE"; else unset CLAUDE_EFFORT; fi
  if [[ -n "$CODEX_MODEL_BASE" ]]; then export CODEX_MODEL="$CODEX_MODEL_BASE"; else unset CODEX_MODEL; fi
  if [[ -n "$CODEX_EFFORT_BASE" ]]; then export CODEX_REASONING_EFFORT="$CODEX_EFFORT_BASE"; else unset CODEX_REASONING_EFFORT; fi

  log ""
  log "--- Handing bounced plan to dev-review (execute$([[ "$DEV_REVIEW_VERIFY" == "true" ]] && echo " + verify")) ---"
  log ""

  exec bash "$DEV_REVIEW_SCRIPT" "${dev_review_args[@]}"
fi

# Print clean result to stdout unless output was redirected to file
if [[ -z "$OUTPUT_FILE" ]]; then
  cat "$FINAL_FILE"
fi
