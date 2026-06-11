# Migration Plan

## Approach

We migrate the billing service to the new queue in a 14 day window using a
staged rollout. The cutover must keep availability at 99.9% and the consumer
lag below 500ms at p95. We use `dual-write` mode during the transition so the
"legacy ledger" stays authoritative until parity is proven.

## Rollout

Stage one covers 5% of tenants, stage two 25%, stage three 100%. Each stage
soaks for 48 hours before promotion. The on-call lead always owns the
promotion decision and never delegates it during a soak.
