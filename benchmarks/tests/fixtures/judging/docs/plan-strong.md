# Ledger Migration Rollout
Dual-write to both tables behind a flag, then backfill in 10,000-row batches with a checkpoint after each batch.
Compare row counts and per-partition checksums before any read moves.
Move reads with a staged rollout behind a feature flag, one region per day.
Roll back by turning the read flag off; the legacy table stays authoritative until the final step.
Hold the legacy table read-only for 21 days, then drop it.
