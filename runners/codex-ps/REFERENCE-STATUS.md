# Reference Implementation — Read Only

This directory is a **verbatim copy** of the private `codex-co-evolution/` workspace
(Windows PowerShell reference runner + eval harness), preserved as an audit trail
for the parity work that follows. **Subsequent phases do NOT extend or modify files
in this directory in place.** Treat `runners/codex-ps/` as immutable: every file
here matches the upstream source byte-for-byte, and that guarantee is the whole
point of keeping it separate from the main repo's working code.

## What Is Here

- `README.md` — upstream root readme describing the Codex-first runtime intent.
- `docs/` — upstream architecture notes and thread-handoff context for the runner.
- `evals/` — the full eval system: cases (`cases/*.yaml`), committed fixtures,
  verification plan, and the PowerShell harness (`run-evals.ps1`, `score-run.ps1`,
  `compare-reports.ps1`) plus its `lib/` and `tests/` support.
- `schemas/` — upstream `review-verdict.json` (review verdict contract).
- `scripts/` — `run-co-evolution.ps1`, the reference PS runner implementation.
- `templates/` — five Codex prompt templates: compose, bounce-protocol, dev,
  review, arbitrate.

## What Is NOT Here

These were excluded during the copy because they are non-deterministic runtime
output or test scratch — not part of the reference impl:

- `.co-evolution/` — runtime run directory (generated per-invocation).
- `.git/` — the upstream workspace had zero commits anyway, so no history to carry.
- `.playwright-mcp/` — scratch directory from browser-automation experiments.
- `evals/fixtures/tmp/` — test scratch (NB: `evals/fixtures/` itself IS preserved;
  only the `tmp/` subdirectory beneath it was skipped).
- `evals/reports/` — generated eval run outputs (regenerated each run).

The repo root `.gitignore` pins the first, fourth, and fifth of these so
accidental commits of generated content inside `runners/codex-ps/` are blocked.

## Parity Contract Pointer

The authoritative contract for downstream parity work is
[`evals/UPSTREAM-MESSAGE.md`](./evals/UPSTREAM-MESSAGE.md). That file enumerates
the MUST/SHOULD items and runner-parity gaps the unified repo needs to absorb.
Downstream consumers:

- **Phase 6 (Protocol Parity)** implements MUST-items 3-6 — bounce-protocol
  reconciliation, Claude adapter tool-gating on text-producing phases, write-phase
  invocation pattern, skip `--json-schema` on Windows, and structural-signal
  companion to semantic verification.
- **Phase 7 (Runner Parity)** ports five features the Bash runner lacks relative
  to `scripts/run-co-evolution.ps1`: one agent dispatcher function, writable-phase
  flag, pre/post-execute delta tracking, structured `state.json` as ground truth,
  and per-phase timeout (the single most painful gap upstream flagged — one PS
  case hung 1h 39min).
- **Phase 8 (Evals Absorbed)** elevates the portable eval assets
  (`evals/cases/`, `evals/fixtures/`, `evals/VERIFICATION-PLAN.md`, and
  `schemas/review-verdict.json`) to the top of the repo so any runner can use
  them, while the PS-specific harness scripts stay here.

## Read-Only Policy

Rules for future work touching this subtree:

- **Do NOT edit files under `runners/codex-ps/` in phases 6-9.** If reading this
  tree suggests a fix is needed, land the fix in the main repo's working copy
  (`templates/`, `lib/`, `evals/` at repo root, etc.) — leave the mirrored
  version here frozen as the original reference.
- **One exception:** this `REFERENCE-STATUS.md` itself is net-new content added
  in Phase 5. Everything else is verbatim upstream. No other files under this
  directory are net-new.
- **Refresh, don't patch.** If the upstream workspace
  `C:/Users/alan/Project/codex-co-evolution/` is ever updated again and the
  updates are worth mirroring, re-run the Phase 5 copy as a wholesale refresh
  rather than hand-editing individual files here.
- **Reconciliation goes in the main repo.** Example: per PRTP-05, the main
  repo's `templates/bounce-protocol.md` keeps its stronger "complete document"
  + SCOPE CONTROL clauses; the weaker upstream copy stays preserved here at
  `templates/bounce-protocol.md` as the historical reference.

## Archival Note

Once this copy lands and is pushed, the original
`C:/Users/alan/Project/codex-co-evolution/` workspace can be **archived without
loss of content** — every source file has a verbatim copy in this directory.
The upstream workspace had zero git commits, so there is no history to lose;
the filesystem snapshot captured here is the full record.
