# Co-Evolution Benchmark — Batch `pilot1`

Generated 2026-08-30T19:31:15Z by `benchmarks/report.sh`.
Judges reported separately and never adjudicated into one score.

## 0. Data completeness

Read this before any number below it.

- Tasks: 2 (`t1 t7`)
- Conditions: 4 (`A B C D`)
- Judges requested: `fable codex glm`; judges with verdicts on disk: `fable codex glm`
- Generation cells: all 2x4 complete
- Degraded cells: none

| Judge | Verdict files | Expected pairs | Unjudged |
|---|---|---|---|
| `fable` | 12 | 12 | 0 |
| `codex` | 12 | 12 | 0 |
| `glm` | 12 | 12 | 0 |

"Expected pairs" assumes every condition survives sanitization and no cell
is degraded; a nonzero "Unjudged" column means pairs are still missing and
every rate below is computed over what exists, not over what was planned.

## 1. Pre-registered outcomes

Decision rules frozen in `benchmarks/PREREGISTRATION.md` before generation.
Primary judge: `fable`.

### Primary comparison: B (cross-vendor bounce) vs A (solo)

| Judge | B wins | A wins | Non-decisive | Missing |
|---|---|---|---|---|
| `fable` | 1 | 0 | 1 | 0 |
| `codex` | 2 | 0 | 0 | 0 |
| `glm` | 2 | 0 | 0 | 0 |

Primary-judge sign test (`fable`): **No evidence** — 1/2 decisive wins is below the pre-registered 5/8 band.

**Caveat:** the frozen rule was written for N=8 tasks; this batch has 2.
The thresholds are applied as absolute win counts, so read the outcome above as
indicative only.

Per-task detail (primary judge `fable`):

| Task | Difficulty | Verdict |
|---|---|---|
| `t1` | medium | B |
| `t7` | easy | position_biased |

### Secondary confirmatory: B (cross-vendor bounce) vs D (self-bounce)

| Judge | B wins | D wins | Non-decisive | Missing |
|---|---|---|---|---|
| `fable` | 0 | 1 | 1 | 0 |
| `codex` | 1 | 1 | 0 | 0 |
| `glm` | 0 | 2 | 0 | 0 |

Per-task detail (primary judge `fable`):

| Task | Difficulty | Verdict |
|---|---|---|
| `t1` | medium | position_biased |
| `t7` | easy | D |

## 2. Per-judge win matrices and Bradley-Terry ranking (secondary)

Ties and position-biased pairs count as half a win each
(`PREREGISTRATION.md` §4); invalid-evidence and sanitize-leak pairs are
excluded from win counts entirely.

### Judge `fable`

Win rate of the row condition against the column condition (wins / comparisons):

| vs | A | B | C | D |
|---|---|---|---|---|
| **A** | — | 0.25 (0.5/2) | 0.00 (0.0/2) | 0.00 (0.0/2) |
| **B** | 0.75 (1.5/2) | — | 0.00 (0.0/2) | 0.25 (0.5/2) |
| **C** | 1.00 (2.0/2) | 1.00 (2.0/2) | — | 1.00 (2.0/2) |
| **D** | 1.00 (2.0/2) | 0.75 (1.5/2) | 0.00 (0.0/2) | — |

Bradley-Terry strengths (normalized to sum 1; **no confidence intervals** —
with 2 tasks none would be meaningful):

| Rank | Condition | BT strength | Total wins |
|---|---|---|---|
| 1 | `C` | 0.9273 | 6.0 |
| 2 | `D` | 0.0550 | 3.5 |
| 3 | `B` | 0.0143 | 2.0 |
| 4 | `A` | 0.0034 | 0.5 |

### Judge `codex`

Win rate of the row condition against the column condition (wins / comparisons):

| vs | A | B | C | D |
|---|---|---|---|---|
| **A** | — | 0.00 (0.0/2) | 0.00 (0.0/2) | 0.00 (0.0/2) |
| **B** | 1.00 (2.0/2) | — | 0.00 (0.0/2) | 0.50 (1.0/2) |
| **C** | 1.00 (2.0/2) | 1.00 (2.0/2) | — | 1.00 (2.0/2) |
| **D** | 1.00 (2.0/2) | 0.50 (1.0/2) | 0.00 (0.0/2) | — |

Bradley-Terry strengths (normalized to sum 1; **no confidence intervals** —
with 2 tasks none would be meaningful):

| Rank | Condition | BT strength | Total wins |
|---|---|---|---|
| 1 | `C` | 0.9295 | 6.0 |
| 2 | `B` | 0.0352 | 3.0 |
| 3 | `D` | 0.0352 | 3.0 |
| 4 | `A` | 0.0000 | 0.0 |

### Judge `glm`

Win rate of the row condition against the column condition (wins / comparisons):

| vs | A | B | C | D |
|---|---|---|---|---|
| **A** | — | 0.00 (0.0/2) | 0.25 (0.5/2) | 0.00 (0.0/2) |
| **B** | 1.00 (2.0/2) | — | 0.00 (0.0/2) | 0.00 (0.0/2) |
| **C** | 0.75 (1.5/2) | 1.00 (2.0/2) | — | 0.50 (1.0/2) |
| **D** | 1.00 (2.0/2) | 1.00 (2.0/2) | 0.50 (1.0/2) | — |

Bradley-Terry strengths (normalized to sum 1; **no confidence intervals** —
with 2 tasks none would be meaningful):

| Rank | Condition | BT strength | Total wins |
|---|---|---|---|
| 1 | `D` | 0.5635 | 5.0 |
| 2 | `C` | 0.3745 | 4.5 |
| 3 | `B` | 0.0498 | 2.0 |
| 4 | `A` | 0.0122 | 0.5 |

## 3. Judge integrity

| Judge | Pairs | Decisive | Ties | Position-biased | Invalid evidence | Sanitize-leak |
|---|---|---|---|---|---|---|
| `fable` | 12 | 10 | 0 | 2 (17%) | 0 (0%) | 0 |
| `codex` | 12 | 12 | 0 | 0 (0%) | 0 (0%) | 0 |
| `glm` | 12 | 9 | 0 | 3 (25%) | 0 (0%) | 0 |

**Cross-judge agreement.** Of 12 pair(s) scored by all 3 requested judges,
7 agreed exactly (58%), and 7 of those were unanimous *and* decisive
(58% of comparable pairs). Unanimous decisive agreement across vendors is the
strongest signal this batch can produce; systematic divergence along the
conflict map below is reported as exactly that, not averaged away.

**Conflict map.** Conditions A, C, and D emit a Fable-authored final
document; condition B's final is Codex-revised (bouncer seat semantics: odd
passes review, even passes compose, so `--agents claude,codex` at two
bounces ends on Codex). Neither of the two strongest judges is neutral: the
fable-5 judge may favor A/C/D on style, and the gpt-5.5 judge may favor B for
the same reason in the opposite direction. That is why the glm-5.3-flash
judge is here — GLM enters generation only as one of three panel critics in
condition C and never composes or revises, so it carries no side in the
A/B/D comparisons. Per-judge results are presented side by side and never
adjudicated into a single score.

## 4. Length-bias check

| Judge | Longer doc won | Comparable decisive pairs | Rate |
|---|---|---|---|
| `fable` | 6 | 10 | 60% |
| `codex` | 7 | 12 | 58% |
| `glm` | 7 | 9 | 78% |

A rate near 50% is what an unbiased judge looks like; a rate well above it
means length, not quality, is doing the work. Pairs where the two documents
have identical word counts are excluded from the denominator.

Word counts of the sanitized documents, by condition:

| Condition | Mean words | Documents |
|---|---|---|
| `A` | 597 | 2 |
| `B` | 618 | 2 |
| `C` | 617 | 2 |
| `D` | 747 | 2 |

## 5. Exploratory (labeled non-evidence)

Nothing in this section was pre-registered. It is descriptive only and must
not be quoted as a result.

**Condition C (panel) standing.** Total wins across all its pairs, per judge:

| Judge | C wins | C comparisons |
|---|---|---|
| `fable` | 6.0 | 6 |
| `codex` | 6.0 | 6 |
| `glm` | 4.5 | 6 |

**Difficulty cuts** (primary judge `fable`, B-vs-A). With at most a
couple of tasks per difficulty band these are anecdotes, not cuts:

| Difficulty | Tasks | B wins | A wins | Other |
|---|---|---|---|---|
| easy | 1 | 0 | 0 | 1 |
| medium | 1 | 1 | 0 | 0 |

## 6. Process stats and cost

| Condition | Cells | Mean words | Mean wall s | Converged | Adjudicated | Stuck | GLM calls | Captured cost USD |
|---|---|---|---|---|---|---|---|---|
| `A` | 2 | 602 | 38 | 0 | 0 | 0 | 0 | 1.7504 |
| `B` | 2 | 626 | 184 | 2 | 0 | 0 | 0 | 3.2781 |
| `C` | 2 | 622 | 371 | 0 | 0 | 0 | 2 | 3.7898 |
| `D` | 2 | 752 | 162 | 2 | 0 | 0 | 0 | 4.8446 |

Costs sum any token sidecar `total_cost_usd` values. Claude reports that
field; the direct GLM and Kimi sidecars report tokens but no dollar price,
and Codex has no sidecar. The cost column is therefore a floor, not a total.

Judging cost is not itemized here: the judge CLIs are invoked in text/schema
mode without token capture. Judging volume is 12 pairs x 2 trials x
3 judge(s) at full coverage.

## 7. Honest limitations

- 2 selected tasks with automated judges produce **exploratory
  directional evidence**. This is not hard evidence and not proof. General
  claims about cross-AI bouncing need a larger held-out replication.
- Only the B-vs-A and B-vs-D comparisons were pre-registered. Everything in
  sections 2, 4, and 5 is secondary or exploratory and is labeled as such.
- No judge is condition-neutral on style. Two of the three share a vendor
  with a condition under test, in opposite directions (see the conflict map).
- Bradley-Terry strengths have no confidence intervals and should not be read
  as a ranking with a margin.
- The GLM quota ledger cannot see Z.AI's server-side window or GLM usage
  outside this benchmark, so a batch spread across days may have generation
  and judging runs with different effective rate limits.
- Sanitization is fail-closed but not omniscient: it removes the process
  artifacts and vendor names on the frozen banned-token list, and a novel
  tell would pass. The list is frozen per batch.
