# Bounded PlanBench measurement

## Sonnet/Terra replication

The new profile uses Sonnet as author/self-critic/reviser and Terra as external
critic, with Claude280/Codex56 caps. `run.py` now accepts author/reviewer/grant
selection; frozen manifests control effort, role concurrency and retry limits.
Claude's combined response allowance is passed per call rather than shared
mutable state. Original Astra/Fable behavior remains the default profile.

The recorded Sonnet/Terra run had a readiness-only medium-effort amendment;
`reprofile_readiness.py` preserves six spent calls and allocates only the
remaining330. Do not reinitialize a settled run or repeat its high-effort
readiness failure. The completed medium stage produced200 scored outputs:
48/50 original and50/50 for plain revision, self-review and Terra review.
Use its manifest and profile amendment as the authoritative run settings.

The generic scorer supports both model pairs. `publish_report.py` accepts
separate data/page/study IDs and an optional reviewed assessment tied to the
source report hash. The site retains the Astra/Fable result alongside the
Sonnet/Terra result instead of pooling or overwriting them.

The September 13, 2026 attempt used the official PlanBench Blocksworld Hard
corpus, pinned at `fc638a1aff7df3fe7a1a1d289fa2c04cc24dc284`, and its bundled
VAL executable and PDDL extractor. The scored sample is 50 fixed tasks from
110. Four arms compare Astra original, plain revision, self-review, and Fable
review followed by Astra revision.

The initial attempt stopped at readiness after one Fable safeguard refusal.
User-directed continuations then reached 195 scored plans: A/B/C each
50/50 valid; D 45/45 valid, with five missing after critique refusals. The
original-draft arm already scored 100%, so review had no measured validity
gain. Public outcome: `../site/public/planbench-results.json`; the initial
readiness-only outcome is retained in the site's dated archive.
The run's local immutable manifest, attempts, SQLite accounting, generation
freeze, readiness fixtures and validator logs are under
`runs/planbench-hard-20260913`, `runs/planbench-hard-20260913-continuation` and
the final `runs/planbench-hard-20260913-continuation2` in the parent repository.

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
the two excluded live smoke tasks. Continuation added a focused refusal
classification check and four known-answer scoring/missingness checks.
All 195 available scored plans were validated once after final generation
freeze. Publication includes an explicit evidence assessment.

`continue_run.py` preserves the initial eleven calls and successful smoke
outputs for one identical retry. `recover_requests.py` preserves the next
246-call snapshot and corrects request-level refusal handling. Both prepare
new continuation directories without live dispatch. Neither raises a cap or
extends the deadline. `publish_report.py` stages the terminal result and
reviewed assessment, archives the original publication, and includes extracted
PDDL actions so the public outcomes can be independently reproduced.

Sources: https://github.com/karthikv792/LLMs-Planning and
https://github.com/KCL-Planning/VAL . Upstream PDDL extraction is loaded as
the exact AST function from the pinned source, avoiding unrelated LLM imports.
The VAL wrapper recognizes its normal invalid-plan exit code 1 as a failed
plan when its diagnostic identifies that outcome; validator infrastructure
failures stay missing.
