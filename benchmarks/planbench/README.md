# Bounded PlanBench measurement

The September 13, 2026 attempt used the official PlanBench Blocksworld Hard
corpus, pinned at `fc638a1aff7df3fe7a1a1d289fa2c04cc24dc284`, and its bundled
VAL executable and PDDL extractor. The scored sample is 50 fixed tasks from
110. Four arms compare Astra original, plain revision, self-review, and Fable
review followed by Astra revision.

The attempt stopped at readiness after one Fable safeguard refusal. No scored
task ran. Seven available excluded smoke plans validated, but that is not a
benchmark accuracy result. Public outcome: `../site/public/planbench-results.json`.
The run's local immutable manifest, attempts, SQLite accounting, generation
freeze, readiness fixtures and validator logs are under
`runs/planbench-hard-20260913` in the parent working repository.

`run.py init --root RUN --started EPOCH` creates a new frozen run from a
pre-fetched official repository at RUN/upstream. It does not authorize a new
budget by itself; supply an explicitly authorized plan before using this
task-specific controller. `run.py check --root RUN` validates the three
offline fixtures. `run.py run --root RUN --live` runs one locked controller.
`score.py --root RUN` settles only frozen terminal generation. `run.py status`
is read-only. Never reinitialize or restart a settled attempt unchanged.

This implementation is specific to the recorded stage. Source hashes are
frozen inside the run before dispatch; copying edited source over it is not
a valid resume. The preserved launch3 planning transport supplies the exact
model/catalog isolation repair, process-tree ownership and subscriptions.
Changes for this stage replace the system prompt and set Fable's output
allowance to 1024 tokens. Astra's CLI output targets are instructions, not an
enforced token limit. Both calls time out at 120 seconds. Model fallback is
not allowed. Transport is isolated from solutions and scoring files.

The preserved campaign ledger reserves each call transactionally, retains
failed calls and limits jobs to two attempts. The controller additionally
enforces family retry reserves, family concurrency and the dispatch cutoff.
The old custom-study ledgers are not imported, reset or modified.

Validation performed once: official valid/invalid/malformed fixtures; an
offline lifecycle with a charged transient retry and a duplicate-free resume;
the two excluded live smoke tasks. No scored benchmark was run after the
provider refusal. Publication includes an explicit evidence assessment.

Sources: https://github.com/karthikv792/LLMs-Planning and
https://github.com/KCL-Planning/VAL . Upstream PDDL extraction is loaded as
the exact AST function from the pinned source, avoiding unrelated LLM imports.
The VAL wrapper recognizes its normal invalid-plan exit code 1 as a failed
plan when its diagnostic identifies that outcome; validator infrastructure
failures stay missing.
