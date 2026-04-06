# Concerns

## 1. No Automated Regression Net

- The repository has no tracked automated tests and no CI.
- Core behavior in `agent-bouncer/agent-bouncer.sh` depends on string substitution, prompt assembly, and CLI interactions that are easy to break silently.
- `skill/SKILL.md` is even more exposed because it is mostly executable prose for another runtime.

## 2. Documentation And Implementation Drift Risk

- Behavior is described in multiple places: `README.md`, `agent-bouncer/README.md`, `skill/README.md`, `skill/SKILL.md`, and prompt templates.
- There is already at least one concrete drift point: `agent-bouncer/README.md` documents the Claude adapter with `--max-turns 5`, while `agent-bouncer/agent-bouncer.sh` actually uses `--tools ""`.
- Because the repo is documentation-heavy, these drifts can mislead users even when the shell logic still works.

## 3. Hard Dependency On Local CLI State

- Successful runs require installed, authenticated `claude` and `codex` CLIs.
- The bouncer hard-codes model and flag choices inside `agent-bouncer/agent-bouncer.sh`.
- Any upstream CLI flag, auth, or model-name change can break the workflow without any local compile-time signal.

## 4. Silent Or Deferred Failure Handling

- Both adapter functions in `agent-bouncer/agent-bouncer.sh` end in `|| true`.
- That means subprocess failures are tolerated initially and may only surface later as empty output or low-signal logs.
- This makes the happy path resilient, but it weakens fast diagnosis for partial or non-fatal command failures.

## 5. Prompt Duplication Across Surfaces

- The bounce protocol exists in both `agent-bouncer/templates/bounce-protocol.md` and `skill/templates/bounce-protocol.md`.
- They are currently aligned, but there is no shared source or automated check to keep them aligned.
- Similar duplication exists across execution and review prompt variants in `skill/templates/`.

## 6. Platform Friction

- The standalone tool is Bash-first, so Windows users still need Git Bash, WSL, or equivalent POSIX tooling.
- At the same time, `skill/SKILL.md` contains Windows-specific live-launch logic using PowerShell.
- Supporting both environments increases operational complexity for a small repo.

## 7. Run Artifact Growth And Local State Ambiguity

- `runs/` is ignored and accumulates local state over time; the current working tree already contains many run directories.
- The folder also mixes scratch markdown documents with generated run artifacts.
- This is practical for experimentation but can make it harder to distinguish reproducible examples from disposable local work.

## 8. Extra Cost And Failure Surface In Run Naming

- Every bounce run asks Codex to name the run before the actual bounce begins.
- That adds latency, token usage, and one more external dependency before the first real pass.
- If Codex is unavailable, run naming falls back, but the repo still pays the integration cost on the normal path.

## Bottom Line

- The project is promising and already usable, but reliability currently depends on human discipline, sample runs, and prompt quality more than on automated enforcement.
- The fastest quality improvements would come from lightweight shell tests, drift checks for duplicated prompts, and tighter documentation-to-code synchronization.
