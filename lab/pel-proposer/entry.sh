#!/usr/bin/env bash
# lab/pel-proposer/entry.sh
# Phase 8 dispatch resolver for --lab pel-proposer.
#
# dispatch_lab_mode (lib/co-evolution.sh:113-132) resolves <lab_root>/<mode>/entry.sh
# from a single mode token. The PEL emitter canonically lives under
# lab/pel/pr-emitter/ to preserve the pel-namespace grouping for sibling
# inhabitants (classifier, proposer/). This file is the flat-namespace
# entry point that dispatch_lab_mode finds; it re-execs into the pr-emitter
# subdirectory WITHOUT modifying dispatch_lab_mode itself (per plan Part C).
#
# Deviation note (Rule 3 — plan inconsistency): the plan required both
# (a) dispatch via --lab pel-proposer, and
# (b) artifact at lab/pel/pr-emitter/entry.sh,
# and (c) dispatch_lab_mode unchanged. This shim is the minimum reconciling
# edit — no code lives here, just an exec passthrough.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# REPO_ROOT is one level up from lab/pel-proposer/ -> lab/ -> repo root.
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
exec bash "$REPO_ROOT/lab/pel/pr-emitter/entry.sh" "$@"
