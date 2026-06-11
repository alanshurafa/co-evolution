# Migration Plan

## Approach

We migrate the billing service to the new queue in a 14 day window using a
staged rollout. The cutover must keep availability at 99.9% and the consumer
lag below 500ms at p95. We use `dual-write` mode during the transition so the
"legacy ledger" stays authoritative until parity is proven.
[CONTESTED] A 14 day window is optimistic for dual-write parity; comparable
migrations needed 21 days. Either extend the window or cut the parity bar.

## Risks

The dual-write path doubles the write volume, and the queue cluster has a
budget of 20000 writes per second. If parity checks fail after 7 days we
roll back to the legacy path. Rollback must complete within 30 minutes.
[CLARIFY] Who executes the rollback runbook out of hours — the on-call lead
or the billing team? The 30 minute bound is only credible with a named owner.

## Rollout

Stage one covers 5% of tenants, stage two 25%, stage three 100%. Each stage
soaks for 48 hours before promotion. The on-call lead always owns the
promotion decision and never delegates it during a soak.
