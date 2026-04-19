#!/usr/bin/env bash
# lab/pel/pr-emitter/entry.sh
# Phase 8: dispatch shim for --lab pel-proposer. dispatch_lab_mode exec's here
# with argv = [--target X --tier Y --pr-branch N --dry-run --budget N --yes
# --flavor F -- TASK]. We re-exec into pr-emitter.sh preserving argv.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/pr-emitter.sh" "$@"
