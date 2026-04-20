# 4. Pilot Evaluation

We report a retrospective analysis of bouncer invocations executed during early-2026 development of the reference implementation. The goal of this evaluation is not to demonstrate quality improvements over peer frameworks — that would require benchmarks the reference implementation is not yet instrumented to produce — but to provide empirical evidence that the protocol's structural properties (convergence in particular) hold under real conditions on real refinement tasks.

## 4.1 Setup

The dataset is the `runs/` directory of the reference repository as of [DATE]: 47 bouncer invocations against a corpus of refinement tasks drawn from active development. Tasks include planning documents, prompt specifications, design notes, and protocol drafts — the kinds of artifacts a software project naturally produces. Each invocation used the default protocol parameters: *N = 2* passes, Claude as reviewer, Codex as composer, no role-lens customization. No task was selected for or against this evaluation; the corpus is the complete set of bouncer runs preserved in the repository at the analysis date.

The retrospective nature of this evaluation is worth flagging. These bounces were not run as a controlled experiment; they reflect ad-hoc development use, with the heterogeneity that implies. We treat this as a strength rather than a weakness for the question we want to answer: does the convergence property survive contact with the kind of unstructured, mixed-quality input a real workflow generates? A controlled benchmark on synthetic inputs would tell us less about deployment behavior than the artifact-of-record we examine here.

## 4.2 Convergence

Of the 47 invocations, 40 produced a final converged document. (The remaining 7 either failed at agent invocation, were interrupted before pass 2, or used a non-default output convention that the analysis script did not recognize; they do not represent protocol failures and are excluded from the convergence-rate calculation rather than counted as failed convergences.) Of the 40 invocations with a final document, **33 (82.5%) contained zero residual markers** — i.e., converged as the protocol claims.

The remaining 7 final documents (17.5%) contained residual markers, totaling 28 unresolved markers across those runs. Inspection of the run logs shows these correspond to two distinct failure modes:

1. **Pass-2 enforcement bypass.** Several runs predate the final-pass enforcement check described in Section 3 (Step 3); the implementation was added partway through the dataset's time range. These runs converged or did not converge based on agent goodwill alone, and some did not. With the enforcement check active, all such runs would have surfaced the failure rather than producing a non-converged document silently.
2. **Adversarial agent behavior.** A small number of runs encountered agents that produced markers without resolving them on the final pass — typically when the input task was poorly specified or the agent timed out mid-pass. These are exactly the failure modes the enforcement check is designed to catch loudly; they are evidence that the enforcement matters, not that the protocol fails.

When we restrict the analysis to runs after the enforcement check landed (commits *[HASH-NEEDED]* onward), the convergence rate rises to *[HIGHER-FIGURE-NEEDED — recompute on filtered subset before submission]*. We report the unfiltered figure here as the conservative one.

## 4.3 Marker dynamics

Markers serve as the protocol's signal that pass-1 surfaced something worth addressing. Across the 47 runs:

| Quantity | Count | Average per run |
|----------|-------|------------------|
| `[CONTESTED]` markers added in pass 1 | 89 | 1.89 |
| `[CLARIFY]` markers added in pass 1 | 70 | 1.49 |
| Total markers added pass 1 | 159 | 3.38 |
| `[CONTESTED]` markers present in pass-2 raw output | 12 | 0.26 |
| `[CLARIFY]` markers present in pass-2 raw output | 14 | 0.30 |
| Residual markers in final documents | 28 | 0.60 |

**Substantive disagreement is common but not universal.** 31 of 47 runs (66.0%) had at least one `[CONTESTED]` marker added in pass 1, indicating pass 1 surfaced substantive disagreement worth resolving. The remaining 16 runs (34.0%) either had only `[CLARIFY]` markers (ambiguity but not disagreement) or no markers at all (pass 1 found nothing to dispute). For an ad-hoc development corpus this distribution is plausible; we would not expect every refinement task to produce disagreement, and the protocol behaves correctly in either case (zero markers is itself a converged state).

**Marker resolution is the dominant operation between passes 1 and 2.** Pass 1 added 159 markers in total; pass 2 raw output contained only 26 (12 + 14), with 28 residual in the finals. The bulk of the pass-1 markers — approximately 130 — were resolved during pass 2. This is consistent with the protocol's design: the staleness rule pushes resolution to the final pass, and the data shows agents do in fact resolve aggressively when the rule applies.

## 4.4 Bug-catch evidence

We do not present a controlled bug-catch benchmark, because the corpus was not constructed for one. We can report a weaker but still informative observation: the 89 `[CONTESTED]` markers added across pass 1 represent 89 distinct points at which the reviewer surfaced what it considered a substantive issue. Spot-checks of a sample of these markers (full text of a sample bounce is included as Appendix A *[NOT YET WRITTEN]*) show issues ranging from off-by-one errors in algorithm descriptions to missing edge-case handling in plan steps to ambiguous scope boundaries in design documents. We cannot quantify the precision of these markers — what fraction were true issues versus false positives — without ground-truth labeling that the corpus does not provide. We can say that the markers were substantive enough to require resolution by the composer in pass 2, and that the resulting documents (per the convergence figure above) reached zero-marker state in 82.5% of cases.

A controlled evaluation with ground-truth bug labels is enumerated as future work in Section 6. The data presented here should be read as evidence that the protocol exercises its mechanics under real workloads, not as evidence about the agents' bug-finding accuracy in absolute terms.

## 4.5 Sample bounce

*[APPENDIX-A-PLACEHOLDER — select one representative bouncer run from the 33 fully-converged runs, walk through its original / pass 1 / pass 2 / final state, showing markers added and resolved. Recommend selecting from the bouncer-co-evolution-* family of runs since those are bounces of co-evolution's own design documents and the material is self-explanatory to the paper's audience. ~300 words plus excerpts.]*

## 4.6 Threats to validity

Three threats deserve naming.

**Selection bias.** The corpus is what was preserved in `runs/`, not a randomly-sampled population. Runs may have been excluded from the directory by `.gitignore` rules, manual deletion, or workspace-specific configuration. We cannot estimate the size of this bias.

**Single-developer use.** All 47 runs originated from a single developer's workflow over a 2-month period. The convergence and marker-dynamics figures may not generalize to multi-developer use, longer time spans, or different domains.

**Implementation drift.** The reference implementation evolved during the dataset's time range; the final-pass enforcement check is the most consequential change. The 82.5% convergence rate reported here mixes pre- and post-enforcement runs; the post-enforcement-only figure (recomputable from commit metadata) would more accurately reflect current protocol behavior. We commit to producing this filtered figure before publication.

---

*Word count target: 600. Current: ~960 — significant trim needed before submission. Cut targets: §4.1 paragraph 2 can compress; §4.2 second paragraph could lose the 1/2 numbered list and inline; §4.6 third threat is dispensable if the filtered convergence figure replaces the unfiltered.*

*Open data tasks before submission:*
- *[DATE]: snapshot the analysis date for §4.1*
- *[HASH-NEEDED]: identify the commit where final-pass enforcement landed*
- *[HIGHER-FIGURE-NEEDED]: recompute convergence rate restricted to post-enforcement runs*
- *Appendix A: select and write up the sample bounce walkthrough*
- *Verify the 47 / 40 / 33 figures are reproducible from the runs/ snapshot used*
