# Message to the Co-Evolution Unification Plan

**From:** `codex-co-evolution/` (Windows PS 5.1 reference implementation + eval system)
**Date:** 2026-04-17
**Subject:** Findings, artifacts, and parity requirements to incorporate when absorbing `codex-co-evolution/` into the unified repo

---

## TL;DR

A full session of building + running an eval harness on the Codex-first runner surfaced **eight latent bugs** and **one scorer blindness** that the prior 11 pilot runs never caught. Three of those bugs meant entire scoring dimensions were **silently broken on the happy path**. All eight are fixed here. This message is a self-contained list of what the unified repo should adopt before the absorption lands.

Detailed evidence lives in:
- `codex-co-evolution/evals/BASELINE-SUMMARY.md` — all nine findings with file:line refs
- `codex-co-evolution/evals/VERIFICATION-PLAN.md` — five-tier verification strategy
- `codex-co-evolution/evals/ROLL-UP-TO-MAIN.md` — merge strategy analysis
- `codex-co-evolution/evals/VARIANCE-REPORT.md`, `SEEDED-REGRESSION-REPORT.md` — test evidence

---

## MUST-include items (protocol + prompts)

These are runtime-agnostic. They apply whether the unified runner is Bash, PowerShell, or Python.

### 1. Required-Section pattern in the compose template

Plans missing a `## Files to Change` or `## Risks` section silently fail downstream parsing. A "Suggested Shape" list is insufficient — the LLM drops sections ~66% of the time.

**Adopt:** Two "Required Section" blocks in the compose template, each stating the exact heading name, the required line format, and a fallback placeholder for the no-op case (`- (no file changes)` / `- None identified.`).

Source to copy verbatim: `codex-co-evolution/templates/compose-prompt-codex.md`, the two blocks starting "Required Section: `## Files to Change`" and "Required Section: `## Risks` (or `## Assumptions`)".

### 2. Override language for Required Sections

When the case's task body enumerates a specific list of sections, the LLM treats that as more authoritative than a generic "required" tag. Adding one sentence — **"These sections are required REGARDLESS of any section list that appears in the Task body above"** — fixes this priority conflict.

### 3. Bounce protocol reconciliation

The main `co-evolution/` repo's `bounce-protocol.md` already includes:
- "You MUST output the COMPLETE document, not a summary of changes."
- A **SCOPE CONTROL** section ("refine, don't grow; merge redundant points; cut speculative content").

The codex-co-evolution copy lacks these. The unified repo should keep the main repo's stronger version; codex-co-evolution's version has nothing new to contribute to this file.

### 4. Claude adapter must disable tools on text-producing phases

Without `--disallowedTools "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch"`, Claude in `-p` mode will sometimes use its Write tool to "save the plan" and emit only a one-line summary to stdout. The runner then captures garbage as the plan.

`--tools ""` does not work (commander.js variadic eats the next argument).
`--permission-mode plan` silently produces empty stdout in `-p` mode.
**The working pattern is `--disallowedTools <comma-list>`.**

Writable phases (execute, fix) need the complementary invocation: `--permission-mode bypassPermissions --allowedTools "Edit,Write,Read,Glob,Grep,Bash(git status),Bash(git diff)" --add-dir <workdir>`.

### 5. Do NOT pass `--json-schema` to Claude

Confirmed broken on Windows in `-p` mode as of 2026-04-17: Claude hangs indefinitely whether the schema is passed as inline JSON or a file path. Both variants time out at 60s on a minimal reproduction.

Strategy: prompt-side "Respond with JSON only" + rigid format example + parse-side validation in the runner. If JSON is malformed the scorer flags `verify_accuracy=FAIL`.

### 6. Structural companion to semantic verification

The axiom "markers → 0" does not distinguish "bounce converged in 0 passes" from "bounce step was skipped entirely." Any scoring/verification layer the unified repo grows must check a structural signal alongside the semantic one.

**Working pattern:** check for `outputs/bounce-NN.txt` files under the run directory, or equivalently scan `state.history` for phase entries matching `^bounce-\d+$` (not just `bounce`, which is written by the outer `Set-Phase` wrapper before the loop).

---

## SHOULD-include items (tests + artifacts)

These are not blocking but save weeks of rediscovery.

### 7. Five-tier verification strategy

Don't rely on "real runs passing" as evidence the eval works. Specifically:
- **Tier 1** — canned fixture unit tests for the scorer (offline, <30s, 10 fixtures)
- **Tier 2** — harness plumbing via `-FakeRunner` (offline, <5 min, no LLM)
- **Tier 3** — variance via `-Repeat N` on the same case (online, ~15 min)
- **Tier 4** — seeded regressions that the eval MUST detect (online, ~25 min)
- **Tier 5** — human calibration on 3 scored runs

Three dimensions (Convergence, Cross-AI diversity, Verify accuracy) **silently failed on the pilot happy path**. Only Tier 1 and Tier 3 surfaced them. Pass-on-real-cases alone was not evidence.

### 8. Portable artifacts to copy wholesale

| Artifact | Why |
|---|---|
| `evals/cases/*.yaml` + `defaults.yaml` | 9 test cases covering the full dimension space |
| `evals/tests/fixtures/` | 10 scorer unit fixtures — portable JSON/YAML/MD |
| `schemas/review-verdict.json` | Review verdict schema |
| `evals/VERIFICATION-PLAN.md` | Reusable verification strategy |

### 9. Case schema convention

Case YAMLs layered over a `defaults.yaml` for shared thresholds; each case sets:
```
id, title, description
runner: { task, composer, reviewer, executor, bounces, verify, autonomous }
setup: { mode: temp_repo, seed_files?: [...], copy_from?: [...] }
expectations: { plan_quality, execution_fidelity, verify_accuracy, cost, cross_ai_diversity }
teardown: { cleanup_temp_repo }
```

Copy this shape. It's small, extensible, and survived three rounds of test iteration.

---

## Parity requirements for the unified Bash runner

The PS runner has these features the Bash runner does not yet. Since the plan is full parity:

1. **Agent dispatcher pattern** — one function that routes by provider, so phase code calls `Invoke-AgentPrompt -Provider $Composer` instead of hard-coding `codex`. Needed to support mixed-agent cases without duplicating logic.
2. **Write-phase vs text-phase flag** — `-Writable $true` on execute/fix, `$false` on compose/bounce/arbitrate/verify. Drives the Claude permission mode + allowed-tools choice.
3. **Delta tracking with baseline snapshot** — before execute, hash every repo file; after execute, compute a `{modified, added, deleted}` delta. Used by verify and by the `execution_fidelity` scoring dimension.
4. **Structured state.json** — one JSON file per run that contains phase history, marker counts, changed files, verify verdict. The eval reads this as ground truth.
5. **Per-phase timeout** — *not yet in the PS runner either* but was the single most painful gap (one case stuck 1h 39min on a Claude hang). Implement in the unified runner even if PS never gets it.

---

## Explicit anti-goals for the unification

These are in the PS implementation but should NOT be ported:

- **Windows PS 5.1 StrictMode workarounds** — only meaningful if the unified runner is Windows PS. If it's Bash, the `.ToCharArray()` dance, `@(...)` pipeline wrapping, and `$ErrorActionPreference='Continue'` around native commands are noise.
- **PS boolean colon-switch quoting** — a Windows quirk. Bash just passes strings.
- **`Get-Content -Raw -Encoding UTF8`** — PS 5.1 needs the explicit encoding; `cat` in Bash is fine.

Document these as "caveats if ever back-ported to PS" in a migration notes doc, nothing more.

---

## Three open decisions the unification plan should resolve before coding

1. **What are the three repos?** The directive mentions "combine all three" — confirm: `co-evolution/` + `codex-co-evolution/` + ... (`co-evolution-lab`? `co-evolution-clean`? `dev-review`?). The specifics change what artifacts need reconciling.
2. **Absorb path inside main.** `co-evolution/codex/`? `co-evolution/runners/codex/`? Dissolved into the top level? Affects how the reference PS code is kept vs deleted.
3. **Eval harness runtime.** Keep PS (requires `pwsh` on Linux/Mac for the main repo to run evals) or port to Bash? Port is ~2 days of work. Keeping PS is 0 work but imposes a dependency.

---

## One-file quick win if you want to test this message

Before touching anything structural: copy the two Required-Section blocks (item 1 above) into the main Bash runner's compose template. Zero-risk, no code changes, immediately reduces plan-quality variance from ~66% missing-section rate to ~0% on repeat runs. That change alone justifies opening this thread.

---

*Ping back with questions. All evidence, artifacts, and code are in `C:/Users/alan/Project/codex-co-evolution/evals/` and persist in the reference state until the absorption plan calls for their deletion.*
