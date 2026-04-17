# Roll-Up Preparation: codex-co-evolution → main co-evolution repo

**Date:** 2026-04-17
**Status:** Pre-merge analysis; no code moved yet
**Context:** Plan is to fold `C:/Users/alan/Project/codex-co-evolution/` into `C:/Users/alan/Project/co-evolution/`.

## Surface of the two repos (as of today)

| Aspect | `co-evolution` (main) | `codex-co-evolution` (this repo) |
|---|---|---|
| Runner | `co-evolve-bouncer.sh` (Bash, 558 LoC) | `scripts/run-co-evolution.ps1` (PowerShell, ~1070 LoC) |
| Platform | Portable Bash | Windows PS 5.1 |
| Agent CLIs | `claude` + `codex` already wired | Same, plus `ollama` slot (unimplemented) |
| Templates | Compose via chain-critique / defend / tighten; role-* light templates | compose / bounce / arbitrate / dev / review (Codex-first) |
| Bounce protocol | Has explicit SCOPE CONTROL + "output complete document" clauses | Missing those clauses (divergence!) |
| Schemas | `schemas/run-manifest.json` | `schemas/review-verdict.json` |
| Eval harness | None | `evals/` — scorer, 9 cases, 10 fixtures, 4 seeded regressions, harness with `-Validate` / `-FakeRunner` / `-UseRunner` / `-Repeat` |
| Tests | `experiments/` (ad-hoc) | `evals/tests/` (Tier 1 unit + regression tests) |
| Skills | `skills/dev-review/` + `~/.claude/skills/co-evolution/` | None |

The main repo is Bash and cross-platform; this repo is PS/Windows-first. A raw code merge won't work — the PS runner can't live beside a Bash runner as a peer.

## Three migration strategies

### A. Absorb codex-co-evolution as `co-evolution/codex/` subpath

- Keep the PS runner intact under `co-evolution/codex/scripts/`.
- Main Bash runner optionally delegates to it on Windows / when `--profile codex`.
- Templates and schemas are reconciled and shared under `co-evolution/templates/`.
- Eval system becomes `co-evolution/evals/` — portable.

**Pros:** preserves working PS code; quick migration.
**Cons:** two runtimes (bash + PS) in one repo; duplicate adapter logic; harder to keep in sync.

### B. Extract the PS runner's learnings and port to Bash

- Don't move the PS code. Port the key improvements (Claude adapter, required-section prompts, structural bounce check) into the existing Bash runner.
- Move the eval harness as-is (it's portable in principle; needs a Bash port or keep it PS-only for now).

**Pros:** single runtime; matches main repo's architecture.
**Cons:** several weeks of port work; regressions likely; loses the verified Windows runner.

### C. Hybrid: protocol + eval now, runner code later

- Immediately merge the language-agnostic learnings: bounce-protocol updates, required-section template patterns, verification plan, case library, schemas.
- Leave the PS runner in `codex-co-evolution/` as a reference implementation.
- Port or replace the PS runner in a follow-up.

**Pros:** captures the most valuable learnings now; defers the hard work; no regression risk.
**Cons:** user is asked to keep two repos alive until the port lands.

**Recommended:** C. The protocol and eval work is the expensive insight; the runner code is implementation detail that can be re-done.

## Findings to encode upstream (all strategies)

These are **protocol-level and runtime-agnostic**. They should land in the main repo regardless of when the runner code moves.

### 1. Bounce-protocol reconciliation

The main repo's bounce protocol has two clauses the codex-co-evolution copy lacks:
- "You MUST output the COMPLETE document, not a summary of changes."
- A whole SCOPE CONTROL section on refining rather than growing.

**Action:** these clauses WIN. The codex-co-evolution runner should adopt them before migration — or at minimum the merged repo's bounce protocol should have them.

Conversely, nothing in the codex version to contribute back on this file. Protocol stays as main has it.

### 2. Required-section pattern in the compose template (D #6)

Main's compose template doesn't have the explicit "Required Section: `## Files to Change`" / "Required Section: `## Risks`" blocks. This pattern is how we force structure that downstream tooling can parse. Without it, LLM output is ~66% missing-section on a three-run spread.

**Action:** copy the two Required-Section blocks from `templates/compose-prompt-codex.md:34-48` into the main repo's compose template (or nearest equivalent).

### 3. Required sections OVERRIDE task body enumeration (D #7)

Even a "Required" tag isn't enough if the case's task body enumerates sections and omits one. The template language needs: "These sections are required **REGARDLESS of any section list that appears in the task body**."

**Action:** adopt the stronger phrasing from `templates/compose-prompt-codex.md:32-34`.

### 4. Claude `-p` text phases must disable tools (D#5 pre-fix; implicit D in the adapter design)

Without `--disallowedTools "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch"`, Claude in `-p` mode will sometimes use the Write tool to "save the plan" and emit only a one-line summary to stdout. The runner then captures the summary as the plan. Garbage in the pipeline.

`--tools ""` doesn't work (commander.js variadic eats the next arg). `--permission-mode plan` silently produces empty output in `-p` mode. The working pattern is `--disallowedTools <comma-list>`.

**Action:** wherever the Bash runner calls Claude for a text-producing phase (compose, bounce, arbitrate, verify), pass `--disallowedTools` explicitly. The corresponding writable phases (execute, fix) must pass `--permission-mode bypassPermissions --allowedTools "..."`.

### 5. Claude `-p --json-schema` is broken (D #5)

Pass the schema as neither inline JSON nor a file path — both hang indefinitely. Rely on prompt-side "Respond with JSON only" and parse/validate on the harness side.

**Action:** don't add `--json-schema` to Claude calls in the main runner either. Document this caveat in the agent adapter docs.

### 6. Structural vs semantic verification (Tier 4a finding)

The Convergence axiom "markers → 0" doesn't distinguish "converged in 0 bounces" from "bypassed the bounce loop." Scoring needs a structural companion: "did the bounce phase actually run?"

The mechanism: check for `outputs/bounce-NN.txt` artifacts, or equivalently scan `state.history` for phase entries matching `^bounce-\d+$`. The outer "bounce" wrapper entry is written before the loop and is not sufficient proof.

**Action:** port this check into whatever scoring or verification layer the main repo grows.

### 7. Test fixture pattern (Tier 1)

Canned run directories with `case.yaml` + `run/{state.json, plan.md, verdict.json, outputs/}` + `EXPECTED.json` as ground truth. 10 fixtures cover: all-pass, each dimension's FAIL mode, unparseable verdict, rubber-stamp bounce, genuine bounce. Run via a ~60-LoC test script; no Pester dependency.

**Action:** the whole `evals/tests/fixtures/*/` directory is portable JSON/YAML/markdown. Copy wholesale.

### 8. Seeded regression pattern (Tier 4)

Four deliberately-broken runner variants proving the eval is falsifiable. Each planted bug is a surgical regex replacement on the real runner; `Build-Regressions.ps1` generates them. In Bash this maps directly to `sed`-patch copies.

**Action:** port the four patches as Bash equivalents once the main runner stabilizes.

### 9. Windows-specific gotchas (documentation only)

These won't affect a Bash runner but are worth capturing as caveats for any future PowerShell port:

- PS 5.1 StrictMode + `$str[int]` throws IndexOutOfRangeException on valid indices → use `.ToCharArray()` first.
- PS 5.1 StrictMode + null pipeline + `.Count` throws → wrap in `@(...)` explicitly.
- PS 5.1 `ConvertFrom-Json` returns PSCustomObject, not IDictionary → navigator functions must handle both.
- PS 5.1 native command stderr (git warnings) promotes to NativeCommandError under `$ErrorActionPreference=Stop` → wrap external-command calls with `$ErrorActionPreference='Continue'`.
- PS 5.1 Start-Process ArgumentList stringifies `$true`/`$false` to `"True"`/`"False"` which the child runner can't bind to a `[bool]` param → use `-Command` with `-Flag:$true` colon syntax.
- `Get-Content -Raw` defaults to ANSI on PS 5.1 → always specify `-Encoding UTF8` when round-tripping UTF-8 files.

## Portable artifacts ready to copy

| Artifact | Role |
|---|---|
| `evals/PLAN.md` | Eval system design (bounced once via `/co-evolve`) |
| `evals/VERIFICATION-PLAN.md` | 5-tier verification strategy |
| `evals/BASELINE-SUMMARY.md`, `VARIANCE-REPORT.md`, `SEEDED-REGRESSION-REPORT.md` | Evidence of prior findings |
| `evals/ROLL-UP-TO-MAIN.md` | (this file) |
| `evals/cases/*.yaml` | 9 test cases + `defaults.yaml` |
| `evals/tests/fixtures/` | 10 Tier 1 scorer fixtures |
| `evals/tests/Build-Fixtures.ps1`, `Build-Regressions.ps1` | Generators (PS — would need Bash port) |
| `schemas/review-verdict.json` | Review verdict schema |
| `templates/compose-prompt-codex.md` (just the Required Section blocks) | Prompt pattern |

## Pre-merge checklist

Before starting the roll-up:

- [ ] **Decide migration strategy** — A, B, or C (recommend C)
- [ ] **Pick a canonical bounce-protocol** — main's is stronger; adopt it here first for parity
- [ ] **Close D #7** — strengthen compose template language (done in this repo as of this session; copy upstream)
- [ ] **Decide on eval harness runtime** — keep PS, write a Bash clone, or shim from Bash into PS via `pwsh` on Linux
- [ ] **Decide on runs/ directory conventions** — the main repo's `runs/` and this repo's `.co-evolution/runs/` use different layouts; pick one
- [ ] **Agree on case-file schema** — this repo's YAML spec may differ from anything main has; lock it before porting cases
- [ ] **Commit identity** — this repo has `user.useConfigOnly=true` specifically for pseudonymous separation. Confirm that constraint doesn't apply to main.

## Open decisions for you

1. **Does the main repo absorb this one and delete it, or does this stay as a reference implementation?**
2. **If absorbing: what path in main — `codex/`, `codex-runner/`, or dissolved into existing dirs?**
3. **Is the Bash runner expected to reach PS-runner feature parity, or is PS kept for Codex-first / Windows workflows indefinitely?**
4. **Do we port the eval harness to Bash, or make the main repo depend on PS 7+ for eval work?**
5. **Windows support matters how much?** — if yes, the PS adapter patterns (D #1, D#2, D#3, D#4) are an asset; if no, they're overhead to document.

## Recommended first concrete step

Regardless of strategy chosen:

1. Copy the **Required-Section blocks** from this repo's `templates/compose-prompt-codex.md` into the main repo's compose template. One-file change; no code runtime implications; instantly reduces plan-quality variance.
2. Add `--disallowedTools` to the Bash runner's Claude text-phase invocations. Small change; prevents a whole class of silent garbage output.
3. Decide strategy A/B/C before doing anything else structural.
