#!/usr/bin/env bash
# codex-access — single source of truth for invoking the Codex CLI across
# environments. Historically this logic was duplicated in 6+ places across
# the codebase; the lib/ helper centralizes the launch matrix so callers
# don't reimplement it.
#
# Launch matrix (checked in order):
#   1. WSL with Windows-side codex install:
#      `cmd.exe /c codex exec ...` — bridges from WSL to the Windows binary
#      because auth state is per-side (installing in both WSL AND Windows
#      doubles the OPENAI billing).
#   2. Native Linux/macOS with codex on PATH:
#      `codex exec ...` — direct invocation.
#   3. No codex reachable:
#      `codex_available` returns 1; `codex_invoke` writes the install hint
#      to stderr and produces empty output (matches the existing empty-output
#      contract so callers don't need a new branch).
#
# See skills/codex-access/SKILL.md for the user-facing description.
#
# This module is intentionally side-effect free at source time — it only
# defines functions. Source it from any script that needs codex access.

# codex_available → exit 0 iff codex is reachable via any supported path.
# WSL+cmd.exe path is checked first because that's the upstream-recommended
# install on Windows (auth lives on the Windows side).
codex_available() {
  if [[ -n "${WSL_DISTRO_NAME:-}" ]] \
     && command -v cmd.exe   >/dev/null 2>&1 \
     && command -v wslpath   >/dev/null 2>&1; then
    cmd.exe /c codex --version >/dev/null 2>&1 && return 0
  fi
  command -v codex >/dev/null 2>&1
}

# codex_install_hint → prints a multi-line, actionable install/availability
# message to stdout. Callers redirect to stderr when used inside an error path.
codex_install_hint() {
  cat <<'HINT'
codex CLI is not reachable from this environment.

To enable codex-backed runs:
  1. Install:      npm install -g @openai/codex
  2. Authenticate: export OPENAI_API_KEY=sk-...
  3. Verify:       codex --version

WSL users: install codex on the Windows side, NOT inside WSL.
codex-access bridges via cmd.exe automatically. Auth state is per-side,
so installing twice would double your OpenAI billing.

If codex is genuinely unavailable in this environment (e.g. a remote
container with no API key), use:
  bash co-evolve-bouncer.sh --single-model claude ...

to run same-model co-evolution. This trades cross-vendor diversity for
the ability to actually run at all.
HINT
}

# codex_invoke "$prompt_file" "$output_file" "$stderr_file"
# Drop-in equivalent of lib/co-evolution.sh's invoke_codex, but routed through
# the launch matrix above so the WSL/native/missing cases all live in one
# place. Returns 0 always — errors flow through empty output_file + populated
# stderr_file, matching the existing invoke_* contract (callers detect failure
# by checking [[ ! -s "$output_file" ]]).
codex_invoke() {
  local prompt_file="$1"
  local output_file="$2"
  local stderr_file="$3"
  local workdir="${WORKDIR:-$PWD}"
  local -a cmd
  local windows_workdir=""
  local windows_output=""

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] \
     && command -v cmd.exe >/dev/null 2>&1 \
     && command -v wslpath >/dev/null 2>&1; then
    windows_workdir=$(wslpath -w "$workdir")
    windows_output=$(wslpath -w "$output_file")
    cmd=(cmd.exe /c codex exec --full-auto --skip-git-repo-check -C "$windows_workdir")
  elif command -v codex >/dev/null 2>&1; then
    cmd=(codex exec --full-auto --skip-git-repo-check -C "$workdir")
  else
    {
      echo "ERROR: codex CLI not reachable in this environment."
      echo ""
      codex_install_hint
    } > "$stderr_file"
    : > "$output_file"
    return 0
  fi

  if [[ -n "${CODEX_MODEL:-}" ]]; then
    cmd+=(-c "model=${CODEX_MODEL}")
  fi

  if [[ -n "$windows_output" ]]; then
    cmd+=(-o "$windows_output")
  else
    cmd+=(-o "$output_file")
  fi

  "${cmd[@]}" < "$prompt_file" > /dev/null 2>"$stderr_file" || true
}
