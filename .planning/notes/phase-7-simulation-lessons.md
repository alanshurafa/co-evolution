---
title: Phase 7 simulation + canary design — lessons from Phases 4/5/6
date: 2026-04-18
context: Carry-forward from v1.2 Phase 5's red-simulation session. Binding for Phase 7 planning.
---

# Phase 7 planners: read this before writing simulation/canary plans

Phases 4/5/6 established the PEL lab-inhabitant pattern: self-contained adapter, prompt-as-file, PATH-stubbed claude CLI, `N/N scenarios passed` footer. Phase 7 inherits all of that. But Phase 5 exposed a class of bug that Phase 7 will hit harder — and Phase 7's canary suite has to be designed with that in mind.

## The specific failure mode

Phase 5 Plan 01 shipped with 4 tasks. Every `<verify>` block passed green:
- `bash -n proposer.sh` → exit 0
- Files exist, grep matches expected strings
- adapter.sh returns non-empty output

Then Plan 02's 8-scenario simulation ran and **4/8 failed** with `git apply: corrupt patch at line N`. Two real bugs had been living in the code the whole time:

1. **`capture_diff` over-trimmed.** awk regex `^[[:space:]]*$` matched single-space-then-newline lines — which in a unified diff are meaningful empty-context-line markers. Trimming them broke hunk line counts.
2. **Command substitution stripped the trailing newline.** `$(run_adapter)` loses the diff's final `\n`. `printf "%s" "$diff_text" | git apply` gets an incomplete patch. Fix: `printf "%s\n"`.

Both bugs hid in the glue between LLM-output capture and the apply tool. Neither was visible to any structural check. Only the end-to-end simulation caught them — AFTER the plan claimed "done".

## Why Phase 7 will hit this harder

Phase 7 mutates `lib/co-evolution.sh` and runner paths. Compared to Phases 5/6, the diff bodies will contain:
- **Shell metacharacters:** `$`, `\`, `"`, `'`, backtick, heredoc markers (`<<EOF`, `<<'EOF'`, `<<-EOF`), glob patterns
- **Longer hunks** because shell code tends to have more context-relevant structure
- **CRLF on disk** (`core.autocrlf=true` is the Windows Git Bash default) while LLM output is LF
- **Executable files** where a bad mutation isn't a broken text render, it's a broken runner

The class of text-processing-glue bug that bit Phase 5 will bite harder. Every place in Phase 7's code where bash captures LLM output and pipes it to `patch` / `git apply` / `bash -c` / eval is a potential failure point.

## What Phase 7's planner MUST include

### In the simulation gate

Beyond the 4-flavor happy paths, add explicit edge-case scenarios:

1. **Diff with an empty-line context marker** — a hunk containing a line that's just one space + newline. Prove `capture_diff` (or equivalent) preserves it.
2. **Diff whose last line is a context line with no trailing newline** — prove trailing-newline recovery in the capture→apply glue works.
3. **Diff against a CRLF-on-disk file on Windows Git Bash** — prove `--whitespace=nowarn` (or `-c core.autocrlf=false`, or equivalent) is wired so valid LF diffs apply against CRLF targets.
4. **Diff containing shell metacharacters** — `$VAR` references, backticks, heredoc markers, quoted strings in added/removed lines. Prove nothing in the capture→apply pipeline evals or misparses the content.
5. **Diff that `patch --dry-run` accepts but `git apply --check` rejects** — a known-divergence case. Pick one consistent tool and justify it.

### In the canary suite (Phase 7's distinct contribution)

The canary runs AFTER the mutation is applied in the sandbox, BEFORE eval scoring. Its job is "did the runner survive the mutation?". Minimum scenarios:

1. **Source-survives:** `bash -n lib/co-evolution.sh` + `source lib/co-evolution.sh` without error. Trivial cases where the mutation introduced a syntax error must be caught here.
2. **Helper signatures preserved:** the mutated file still exports `validate_lab_mode`, `dispatch_lab_mode`, `phase_is_writable`, etc. with their expected argv shapes. A mutation that renames or drops a helper fails canary.
3. **End-to-end agent bounce:** run a trivial `agent-bouncer/agent-bouncer.sh` invocation with a canned task and stubbed claude/codex. Verify exit code 0 and the expected artifact structure. This catches mutations that make the runner syntactically valid but semantically broken.
4. **dev-review plan-only flow:** `dev-review --plan-only <task>` runs end-to-end against stubbed agents. Catches mutations that break specific phase logic.
5. **One real eval case:** a single fixture from `evals/cases/` runs to completion against the mutated runner. Catches mutations that break the eval integration specifically.

Each canary scenario needs a distinct exit code so the PR-emitter in Phase 8 can distinguish "canary-failed → runner broken" from "eval-regressed → runner works but scores dropped".

### Adversarial paths (diff budget + file allowlist)

Per ROADMAP SC-3:

1. **Diff exceeding budget (N lines, N=20 in v1.2):** rejected BEFORE sandbox application with exit code for budget-exceeded.
2. **Diff touching `.planning/`:** rejected (planning/state integrity).
3. **Diff touching `tests/`:** rejected (test integrity — a mutation that edits its own test to pass is the Goodhart failure mode).
4. **Diff touching `lab/pel/classifier/**`:** rejected (frozen-surface invariant from Phase 4).
5. **Diff touching `.gitignore`:** rejected (prevents hiding test files).

All rejections BEFORE the sandbox even applies the diff. File allowlist is a pre-flight gate.

## Pattern to reuse

PATH-injected stub CLI with fingerprint-marker channel — used in Phases 4, 5, 6 — is the right hermetic-but-end-to-end pattern. Stub claude in `$TEST_DIR/bin/claude` reads canned diffs from an env-var-pointed file and optionally writes a marker file on invocation. Test asserts marker absence/presence to prove invariants (bypass paths never call claude; canary-pass paths do).

## The meta-lesson

**A plan whose `<verify>` blocks are all syntactic is NOT complete.** Every Phase 7 plan must include at least one end-to-end scenario where a mutation is applied in the sandbox and the canary runs. If a plan's verify is all "grep matches / bash -n passes / file exists", flag it as incomplete before executing.

## References

- `.planning/phases/05-template-tier-proposer/05-02-SUMMARY.md` §"Root causes / inline fixes" — full writeup of the two bugs and the fix
- `lab/pel/proposer/template/adapter.sh` — `capture_diff` fix (narrow regex to `^$` truly-empty only)
- `lab/pel/proposer/template/proposer.sh` — `printf "%s\n"` trailing-newline recovery + `--whitespace=nowarn` for CRLF tolerance
- `tests/template-proposer-simulation.sh` — 8-scenario hermetic template for Phase 7's simulation to mirror
- `tests/policy-proposer-simulation.sh` — Phase 6 analog with bounds validation and yq-apply
- `evals/tests/scorer-verification.sh` — Phase 2 precedent for PATH-stubbed runner + FAILURE counter

---

*Carry-forward authored 2026-04-18 from v1.2 Phase 5's red-simulation session. Phase 7's planner should consider this binding alongside ROADMAP §Phase 7 SC-1..5 and `.planning/notes/pel-design-decisions.md` §§3,5.*
