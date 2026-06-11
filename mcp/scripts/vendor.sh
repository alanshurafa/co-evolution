#!/usr/bin/env bash
# Copy the bounce toolkit from the repo root into mcp/vendor/co-evolution/.
# The npm package ships this snapshot; the publish workflow runs it at a git
# tag, so the npm version and the vendored scripts stay in lockstep.
# Vendored set per docs/superpowers/specs/2026-06-11-mcp-v14-addendum.md D-01.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MCP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$MCP_ROOT/.." && pwd)"
VENDOR="$MCP_ROOT/vendor/co-evolution"

[[ -f "$REPO_ROOT/co-evolve-bouncer.sh" ]] || {
  echo "ERROR: repo root not found at $REPO_ROOT (vendor.sh must run from a co-evolution checkout)" >&2
  exit 1
}

rm -rf "$VENDOR"
mkdir -p "$VENDOR/lib" "$VENDOR/templates" "$VENDOR/agent-bouncer/templates" "$VENDOR/evals"

cp "$REPO_ROOT/co-evolve-bouncer.sh"                      "$VENDOR/"
cp "$REPO_ROOT/lib/co-evolution.sh"                       "$VENDOR/lib/"
cp -R "$REPO_ROOT/templates/co-evolve"                    "$VENDOR/templates/"
cp "$REPO_ROOT/agent-bouncer/templates/bounce-protocol.md" "$VENDOR/agent-bouncer/templates/"
cp "$REPO_ROOT/evals/score-bounce.sh"                     "$VENDOR/evals/"
cp "$REPO_ROOT/evals/report-bounce.sh"                    "$VENDOR/evals/"
cp "$REPO_ROOT/evals/bounce-thresholds.yaml"              "$VENDOR/evals/"
cp "$REPO_ROOT/evals/BOUNCE-RUNNER-CONTRACT.md"           "$VENDOR/evals/"

chmod +x "$VENDOR/co-evolve-bouncer.sh" "$VENDOR/evals/score-bounce.sh" "$VENDOR/evals/report-bounce.sh"

echo "vendored co-evolution toolkit -> $VENDOR"
