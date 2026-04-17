## Summary

**Unification Absorb** — fold the private `codex-co-evolution/` reference implementation (with its eval harness) and selected `co-evolution-lab/` contents into this public repo. Parity the Bash runner with the Codex PowerShell reference. Adopt evals as the iteration mechanism for self-improvement over time.

**Milestone:** v1.0 Unification Absorb (2026-04-17)
**Phases completed:** 5 (Codex PS Preservation) → 6 (Protocol Parity) → 7 (Runner Parity) → 8 (Evals Absorbed) → 9 (Lab Folded)
**Plus:** P0 Required-Section quick win (pre-milestone)
**Commits:** 33 atomic commits
**Requirements closed:** 17/17 (CXPS-01, -02; PRTP-01..05; RNPT-01..05; EVAL-01..03; LABF-01, -02)

## What changed

### New top-level structure
```
co-evolution/
├── evals/                    # NEW — portable eval assets
│   ├── cases/                # 10 case YAMLs (cross-runner)
│   ├── fixtures/             # scorer unit fixtures
│   ├── VERIFICATION-PLAN.md  # 5-tier verification strategy
│   └── README.md             # pwsh-optional documented
├── schemas/                  # NEW
│   └── review-verdict.json
├── runners/                  # NEW
│   └── codex-ps/             # 111-file verbatim PS reference (read-only)
│       ├── evals/            # includes UPSTREAM-MESSAGE.md contract
│       ├── scripts/run-co-evolution.ps1
│       └── REFERENCE-STATUS.md
├── integrations/             # NEW
│   ├── mempalace.yaml
│   └── README.md
├── dev-review/codex/dev-review.sh       # MAJOR upgrades (P0, P6, P7)
├── lib/co-evolution.sh                  # new helpers
└── skills/dev-review/templates/bounce-protocol.md   # canonical (reconciled)
```

### Runner upgrades (P0 + Phase 6 + Phase 7)

**P0 Required-Section blocks (compose prompt):** eliminates ~66% missing-section variance. Mandatory `## Files to Change` and `## Risks` sections enforced with no-op fallback placeholders.

**Phase 6 — Protocol Parity (upstream MUST items 3-6):**
- Claude adapter passes `--disallowedTools "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch"` on text-producing phases
- Claude adapter passes `--permission-mode bypassPermissions --allowedTools "Edit,Write,Read,Glob,Grep,Bash(git status),Bash(git diff)" --add-dir <workdir>` on write-producing phases
- Broken `--tools ""` pattern removed; `--json-schema` never passed to Claude (confirmed broken on Windows `-p` mode)
- Structural bounce check: `outputs/bounce-NN.txt` persists per pass, `verify_bounce_ran` distinguishes "converged in 0 passes" from "bounce skipped entirely"
- `runners/codex-ps/templates/bounce-protocol.md` reconciled byte-identical to canonical source (SCOPE CONTROL + "complete document" clauses recovered)

**Phase 7 — Runner Parity (5 features Bash lacked):**
- **RNPT-01 Agent dispatcher:** single `invoke_agent` entry point; no direct `invoke_claude`/`invoke_codex` calls outside the dispatcher
- **RNPT-02 Writable-phase flag:** first-class abstraction via `phase_is_writable` + `WRITABLE_PHASES` array; zero hard-coded "true"/"false" literals at call sites
- **RNPT-03 Delta tracking:** pre-execute baseline hashes; post-execute `{modified, added, deleted}` delta
- **RNPT-04 Structured state.json:** phase history, marker counts, changed files, verify verdict — machine-readable ground truth per run
- **RNPT-05 Per-phase timeout:** upstream flagged this as the single most painful gap. Hang-kill smoke test proved 2.06s kill on 5s hang (exit 124). `--timeout SECONDS` CLI flag + `PHASE_TIMEOUT` env var, default 1800s

### Reference implementation preserved (Phase 5)
`runners/codex-ps/` = verbatim file-copy of `codex-co-evolution/` (the private repo had zero commits — no history to preserve; byte-level `diff -qr` confirms 100% fidelity). `REFERENCE-STATUS.md` declares this directory read-only + audit trail. Source workspace is now archivable.

### Evals absorbed (Phase 8)
Portable assets (`cases/`, `fixtures/`, `VERIFICATION-PLAN.md`, `review-verdict.json`) elevated to top-level so any runner can consume them. PS-specific harness (`run-evals.ps1`, `score-run.ps1`, `compare-reports.ps1`) stays under `runners/codex-ps/`. `pwsh` documented as optional dependency.

### Lab folded (Phase 9)
`mempalace.yaml` preserved as reference integration config. Karpathy's `autoresearch` **explicitly excluded** — unrelated ML training domain; kept as peer project. Lab-specific PS scripts excluded — workspace-tied; canonical harness lives under `runners/codex-ps/`. Source workspace is now archivable.

## Requirements addressed (17/17 v3)

| Phase | Requirements | Status |
|-------|--------------|--------|
| 5 Codex PS Preservation | CXPS-01, CXPS-02 | ✅ |
| 6 Protocol Parity | PRTP-01, -02, -03, -04, -05 | ✅ |
| 7 Runner Parity | RNPT-01, -02, -03, -04, -05 | ✅ |
| 8 Evals Absorbed | EVAL-01, -02, -03 | ✅ |
| 9 Lab Folded | LABF-01, LABF-02 | ✅ |

## Verification

Every phase landed with:
- Acceptance criteria (grep/diff/test-verifiable) passed per task
- Smoke tests passed — notable: Phase 7 hang-kill timeout test (2.06s wall-clock on 5s hang), Phase 5 byte-level `diff -qr` across 111 files
- CXPS-02 discipline held — `git status --porcelain runners/codex-ps/` empty after each non-Phase-5 phase (the one authorized exception was PRTP-05 bounce-protocol reconciliation)
- Per-phase SUMMARY.md written under `.planning/phases/{phase}/`

## Key decisions

1. **File-copy merge for codex-co-evolution** — that repo had zero commits; no history to subtree-merge. Verbatim copy preserves the reference impl as an audit trail.
2. **Karpathy autoresearch excluded** — unrelated ML training domain. Rationale documented in PROJECT.md Key Decisions.
3. **Evals are the iteration mechanism, not auto-research** — upstream 11 pilot bounces missed 8 bugs + 1 scorer blindness that evals caught. A future Protocol Evolution Loop is deferred post-milestone.
4. **`pwsh` optional** — Bash runner does NOT depend on pwsh. Bash port of eval harness deferred (~2 days estimated).
5. **Writable-phase default = `false`** — safer posture: Claude refuses to write rather than silently writing garbage if any caller forgets the flag.

## Test plan

- [x] Phase 5: byte-level `diff -qr` across 111 files
- [x] Phase 6: PRTP-01/02/03 adapter smoke test; PRTP-04 bounce-signal simulation (3 scenarios); PRTP-05 bounce-protocol byte-identity
- [x] Phase 7: RNPT-01/02 dispatcher smoke; RNPT-03/04 state.json end-to-end simulation; RNPT-05 hang-kill proof (2.06s wall-clock kill on 5s hang, exit 124)
- [x] Phase 8: 14-file `diff -q` sweep; JSON schema parse sanity on `review-verdict.json`; CXPS-02 audit
- [x] Phase 9: byte-identity on mempalace.yaml; README grep gates on exclusion rationale

## Upstream reference

The contract for phases 6-8 came from `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` — 8 latent bugs + 1 scorer blindness surfaced by the PS evals that 11 pilot bounces never caught. Every MUST-item and parity requirement in that message is now addressed or explicitly deferred.

## Breaking changes

None. All runner upgrades are additive:
- Existing `dev-review.sh` invocations still work (default writable=false is safe)
- New `--timeout` flag is optional (defaults to 1800s)
- No existing templates or prompts removed — only augmented

🤖 Generated with [Claude Code](https://claude.com/claude-code)
