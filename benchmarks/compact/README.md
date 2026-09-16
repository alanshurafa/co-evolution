# Bounded three-benchmark campaign

Authorized by the user on 2026-09-16: run the planned public tests with Sonnet
and Terra. Each benchmark has four setup calls, 24 calibration calls and
168 conditional main calls. Hard limits are 204 total, Sonnet 144 and Terra
60, including six/two possible identical transient retries. All three tests
were requested; each main phase still requires its own calibration gate.

`prepare.py` freezes inputs and private grading payloads. LiveCodeBench uses
hard tasks dated 2024-08-01 through 2025-04-30 from the pinned lite release,
excluding upstream errata. BigCodeBench-Hard uses v0.1.4 and excludes tasks
whose reference does not pass in the pinned official container. Reasoning Gym
uses the parameters and seeds in the approved plan, with disjoint phases.

`verifier.py` bridges to upstream CPU checkers in network-isolated containers.
It imports only the required Reasoning Gym modules, preserving their generator
and checker implementations. Countdown also uses a restricted rational
expression check before the upstream SymPy scorer, to enforce the question's
operator/number contract. Graph-color success requires upstream reward 1.0.

`run.py` reuses the established isolated subscription transport and transactional
call ledger. Models are claude-sonnet-5 and gpt-5.6-terra, medium effort,
300-second calls, 8,192 combined Claude output allowance, two calls per provider.
Visible output targets are not universal enforced token caps. No paid API
fallback. Never resume unresolved calls or overwrite a frozen run.

Launch with `launch.ps1` under a hidden detached supervisor, with stdout and
stderr redirected to the run directory. The supervisor writes an exit receipt.
An unrecoverable calibration failure stops new dispatches. Remaining active
calls settle before scoring. Main outputs are scored only after generation
freezes; no validator feedback is sent to participants.

`report.py` exports terminal evidence and paired comparisons. `publish-compact.py`
in the site folder publishes all three assessed reports; run the existing
assessment builder and publication validator afterward. Do not equate a
readiness or calibration failure with a zero Co-Evolution effect.

Primary sources:
- https://github.com/LiveCodeBench/LiveCodeBench
- https://github.com/bigcode-project/bigcodebench
- https://github.com/open-thought/reasoning-gym

Exact commits, Docker image IDs, dataset hashes and eligible/excluded task IDs
are recorded in each local source manifest under
`runs/three-benchmark-20260916/{lcb,bcb,gym}` in the main project directory.
