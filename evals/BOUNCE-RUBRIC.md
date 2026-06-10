# Bounce-Quality Rubric

The scoring rubric for the **document bouncer** (`co-evolve-bouncer.sh`) — the
counterpart to the dev-review code-pipeline scorer (`evals/score-run.sh`). It
defines how to tell, from a run's artifacts, whether a bounce *behaved* well.

Designed by co-evolving the question itself, then verified against the real
`runs/<id>/` artifact layout. The thresholds below are **initial estimates** —
recalibrate on the first ~50 scored runs before treating any as a hard gate.
This is the spec for a forthcoming `evals/score-bounce.sh`.

## What it scores

Score from `runs/<id>/` artifacts: `original-input.md` (before), `working.md`
(after / final), the named final copy, `.bounce-pass-N-clean.md`, the role raw
outputs, `pass-N-stderr.log`, and `run.log`. Standard bounce = reviewer →
composer (2 passes); chain = critique → defend → tighten (3 passes).

The rubric must catch: marker removal by section deletion, additive sprawl,
rubber-stamp passes, bypassed loops, and destructive topical rewrite.

| Dimension | What it measures | Computation (from artifact files) | Pass threshold | Auto? |
|-----------|------------------|-----------------------------------|----------------|-------|
| **Loop execution + marker receipts** | The bounce actually ran, and markers were resolved rather than ignored. | Parse `run.log`; verify the expected non-empty `.bounce-pass-N-clean.md` and role raw outputs exist. Count `[CONTESTED]`/`[CLARIFY]` markers (outside code fences) in `original-input.md`, each pass, and `working.md`. Track marker-bearing regions by nearest heading + text fingerprint. | Expected passes exist (2 standard, 3 chain); no clean pass empty; final marker count = 0; marker regions show edits in later passes while keeping their heading. Zero-marker inputs: `working.md` differs from the baseline and introduces no unresolved markers. | yes |
| **Structural + anchor preservation** | The final doesn't silently delete sections or weaken concrete claims. | Normalize markdown for the baseline (`original-input.md`) and `working.md`; compare heading tree + "anchors" (numbers, units, comparison operators, code/path tokens, quoted terms, requirement modals like *must*/*shall*). | 100% of marker-adjacent / required headings retained; ≥90% of H2/H3 headings retained or merged under the same parent; ≥90% of anchors retained — deleting or weakening a numeric/comparison anchor fails. | yes (proxy) |
| **Scope discipline** | The bounce tightens without ballooning. | Word-count and heading-count deltas from baseline to `working.md`; classify mode from `run.log`. | Bounce-only / chain: word ratio 0.55–1.15, heading ratio 0.75–1.25. Compose / vanilla: word ratio 0.70–1.30, heading ratio 0.70–1.50. Outside the band fails. | yes |
| **Material engagement without churn** | Agents made real edits — not a rubber-stamp, not an arbitrary rewrite. | Normalized token-edit ratio between consecutive `.bounce-pass-N-clean.md` outputs (ignoring whitespace-only changes), paired with structural preservation. | ≥1 pass with a token-change ratio ≥0.03 (or ≥25 tokens for short docs); no single pass replaces >60% of tokens unless structural preservation still passes (high edit + failed preservation = churn). | yes |

## What it deliberately does NOT score

**Net quality lift** — whether the document is genuinely *better* — is **not
automatable**. The four dimensions above confirm the bounce behaved correctly;
they cannot confirm the output is an improvement. Judge net quality lift by blind
human sampling of input/output pairs, and use it only to calibrate the thresholds
above.
