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
