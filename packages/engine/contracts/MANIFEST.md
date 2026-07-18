# Contract Kit Manifest

This directory is a byte-identical extraction of the co-evolution repo's
cross-agent contract surface: bounce/dev-review prompt templates, the
review-verdict JSON schema, the eval runner contracts, the bounce-scoring
thresholds, and the eval fixture corpora. Every file under `contracts/` is a
verbatim copy of an in-repo source — content is never edited during
extraction. Any commentary on a source file's status (e.g. calibration state,
upstream lock) is recorded here, in this manifest, rather than in the copied
file itself.

- **Extraction date:** 2026-07-17
- **Source commit:** `9a49ee0f55662372050b84a7d1fc460da0131235` (branch
  `rebuild/phase-0`, worktree `rebuild-phase-0`). This is the commit at
  extraction time in a shared multi-worker worktree; concurrent workers may
  advance HEAD further on unrelated paths (`.planning/rebuild/**`), but none
  of the source paths listed below were touched by any commit after this one
  as of extraction.
- **Verifier:** `packages/engine/contracts/verify-manifest.mjs` — recomputes
  every digest below against both the `contracts/` copy and the original
  in-repo source and fails closed (exit 1) on any drift. Run it with
  `node packages/engine/contracts/verify-manifest.mjs`.
- **Hashing is line-ending-normalized (as of fix-08b).** Every digest below
  is computed with all CR (0x0D) bytes stripped before hashing, both for
  individual files and for each file that feeds an aggregate directory
  digest. This was added after CI run 29629259173 failed on ubuntu-latest and
  macos-latest, but only on `fixtures/golden-scorer/09-cross-ai-rubber-stamp`
  and `10-cross-ai-genuine-bounce` — the only two entries whose fixture trees
  contain `*.txt` files, which `.gitattributes` leaves on the generic
  `* text=auto` rule (everything else in this manifest is `.md`/`.json`/
  `.yaml`, all pinned `eol=lf`). Windows checkouts smudge those LF-stored
  blobs to CRLF via `core.autocrlf`; POSIX checkout runners do not. The
  source and its `contracts/` copy always agreed with each other on a given
  platform — the failure was this manifest's expected digest, captured on a
  Windows checkout, disagreeing with what POSIX runners compute for the same,
  unchanged blobs. This kit's job is CONTENT drift detection; end-of-line
  fidelity belongs to git's own filters/`.gitattributes`, not to this
  verifier.

## Annotations (apply to the copies below, source files are untouched)

- **`thresholds/bounce-thresholds.yaml` is a NON-GATING baseline.** It was
  copied as-is from `evals/bounce-thresholds.yaml` pending recalibration
  against the rebuilt engine; nothing in the new engine should treat these
  numbers as an enforced gate until that recalibration lands. This
  annotation lives here, not in the file, because the file content must stay
  byte-identical to its source.
- **`runner-contracts/RUNNER-CONTRACT.md` and
  `runner-contracts/BOUNCE-RUNNER-CONTRACT.md` are upstream-locked.** They
  define the runner I/O contract consumed by `runners/codex-ps/` (a frozen
  reference tree per the repo's own `CLAUDE.md`) and by `evals/`. Changes to
  the *meaning* of these contracts follow the version-bump rules defined
  upstream in those same documents (see each file's own versioning section)
  — this extraction does not relax or reinterpret that process, it just
  gives the new engine package a local, hash-verified copy to build against.
- **`fixtures/golden-scorer/` was copied from `runners/codex-ps/`, a
  read-only reference tree.** Nothing was written back into
  `runners/codex-ps/` during this extraction (`git status --porcelain
  runners/codex-ps` is empty — verified at extraction time and re-checked by
  CI via the drift check below).

## Digest table

Individual files are the SHA-256 hex digest of file bytes with all CR (0x0D)
bytes stripped first (see the line-ending-normalization note above). The two
recursive fixture trees (`fixtures/bounce-runs/`, `fixtures/golden-scorer/`)
are recorded as one **aggregate digest per top-level fixture directory**:
every file within is hashed individually, sorted by relative path, formatted
as `<sha256>  <relative-path>\n` lines, concatenated, and that blob is hashed
again with SHA-256. `verify-manifest.mjs` implements this exact algorithm
(`aggregateDigest()`) so the two never drift apart by construction.

### templates/agent-bouncer/

| Source | Dest | SHA-256 |
|---|---|---|
| `agent-bouncer/templates/bounce-protocol.md` | `contracts/templates/agent-bouncer/bounce-protocol.md` | `5920b293a7ba0441f13998161e8b0c677eeb9be0f85e05a57355ff1fa9270bf9` |
| `agent-bouncer/templates/role-composer.md` | `contracts/templates/agent-bouncer/role-composer.md` | `eefbb6d532e7a0d11f558f7e01d8f72557f9f62e5b172a621135434a21001468` |
| `agent-bouncer/templates/role-reviewer.md` | `contracts/templates/agent-bouncer/role-reviewer.md` | `2e7441b27d5af317b30aca358b37653a9f062665c52a172c8cf537160f4c967e` |

### templates/co-evolve/

| Source | Dest | SHA-256 |
|---|---|---|
| `templates/co-evolve/adjudicate.md` | `contracts/templates/co-evolve/adjudicate.md` | `cd64f5281f4f4b786d08392875d0cb6c67904f98d922e216b2fd089f20fe280a` |
| `templates/co-evolve/chain-critique-adversarial.md` | `contracts/templates/co-evolve/chain-critique-adversarial.md` | `9691fcceee38266b4d1ed343baa919017b8044c8939a92490e77bffb85ecc398` |
| `templates/co-evolve/chain-critique.md` | `contracts/templates/co-evolve/chain-critique.md` | `4d402bdc0c83bd9b918f1ca4871607f593d74d7b451c8c0036b1030e49f695da` |
| `templates/co-evolve/chain-defend.md` | `contracts/templates/co-evolve/chain-defend.md` | `5e561aca7b0e954e00c7128e45fe6f56f07191d9cb63763cd4c87081969faff5` |
| `templates/co-evolve/chain-tighten.md` | `contracts/templates/co-evolve/chain-tighten.md` | `efacc284ef0c1119e47e04198d1b65cb6e3eb2289a700e262134b46951a40fa6` |
| `templates/co-evolve/role-composer-light.md` | `contracts/templates/co-evolve/role-composer-light.md` | `fe0ef319323caef4038a5404d9f3ed64577b26344c235d546cfa6d2dcc78edb4` |
| `templates/co-evolve/role-reviewer-adversarial.md` | `contracts/templates/co-evolve/role-reviewer-adversarial.md` | `2c0264621b18dd2f8479bc3e153651ddc2362b19a4b98dfae2afdeb48eaf61dd` |
| `templates/co-evolve/role-reviewer-light.md` | `contracts/templates/co-evolve/role-reviewer-light.md` | `fb76e68386f31169d335db645f726cbf83abb522171c706a0b428afb0e686c6b` |

### templates/dev-review/

Note: `dev-review/bounce-protocol.md` is byte-identical to
`agent-bouncer/bounce-protocol.md` above (same digest) — the source repo
keeps these two in sync deliberately (see root `CLAUDE.md`), this is not a
copy error.

| Source | Dest | SHA-256 |
|---|---|---|
| `skills/dev-review/templates/bounce-prompt-portable.md` | `contracts/templates/dev-review/bounce-prompt-portable.md` | `8f98814695d08d8ae9d1054ae1adafc9bad45fafbcdd06c932f0d4a1244407d2` |
| `skills/dev-review/templates/bounce-protocol.md` | `contracts/templates/dev-review/bounce-protocol.md` | `5920b293a7ba0441f13998161e8b0c677eeb9be0f85e05a57355ff1fa9270bf9` |
| `skills/dev-review/templates/dev-prompt-codex.md` | `contracts/templates/dev-review/dev-prompt-codex.md` | `0b493742a0157ce3321f825c51c2e9adbbba1124cbe4bd5659eafdb0cfa266c5` |
| `skills/dev-review/templates/dev-prompt-opus.md` | `contracts/templates/dev-review/dev-prompt-opus.md` | `0ffc180a54ffa38715e9e374ed89e634f4504d42d4be77557e1857eaf62ad306` |
| `skills/dev-review/templates/review-prompt-codex.md` | `contracts/templates/dev-review/review-prompt-codex.md` | `f5d24f7a259e0f4113416d89f1c851f3e42cf6a0af77256694e25c6946416be4` |
| `skills/dev-review/templates/review-prompt-opus.md` | `contracts/templates/dev-review/review-prompt-opus.md` | `f47bd58235c255380bb8bbf733b6a4f92e590df3fa5760d25fd123020785379d` |

### schemas/

| Source | Dest | SHA-256 |
|---|---|---|
| `skills/dev-review/schemas/review-verdict.json` | `contracts/schemas/review-verdict.json` | `6bd9d58c7fb85190bd0a5cbd4879bcef0906d6d9ca3cfee6c32c328039527c26` |

### runner-contracts/ (upstream-locked, see annotation above)

| Source | Dest | SHA-256 |
|---|---|---|
| `evals/RUNNER-CONTRACT.md` | `contracts/runner-contracts/RUNNER-CONTRACT.md` | `13209382457ca4b1e856da4c4d43259988a7fb56b8201a5b8657e695cbf909a4` |
| `evals/BOUNCE-RUNNER-CONTRACT.md` | `contracts/runner-contracts/BOUNCE-RUNNER-CONTRACT.md` | `d236967accd8b1f2a792a0d410770e3dd00b94354643ac89206b818ad31d1b5e` |

### thresholds/ (non-gating baseline, see annotation above)

| Source | Dest | SHA-256 |
|---|---|---|
| `evals/bounce-thresholds.yaml` | `contracts/thresholds/bounce-thresholds.yaml` | `1de3404cd66964320bfc1de0e5aeb81c5f05fc4dfa58007b184b36e81f23d5da` |

### fixtures/cases/

| Source | Dest | SHA-256 |
|---|---|---|
| `evals/cases/01-trivial-task.yaml` | `contracts/fixtures/cases/01-trivial-task.yaml` | `95a099336221d1741972a2618ec4e4b35152e37064ec00042dc07247fc34e2d9` |
| `evals/cases/02-simple-md-edit.yaml` | `contracts/fixtures/cases/02-simple-md-edit.yaml` | `f00ade73c940908a31b4fdfa004de17a29d29cf05cc6e10544220747281391e7` |
| `evals/cases/03-contested-decision.yaml` | `contracts/fixtures/cases/03-contested-decision.yaml` | `1d6ea064244cd93846c7650d012f672e78e77540cc5a61aeda85a72317258340` |
| `evals/cases/04-hallucination-trap.yaml` | `contracts/fixtures/cases/04-hallucination-trap.yaml` | `e4407b7f906a06bd73b8db8f594baddb7f01e18f5f43e3cf3278da44c0c42545` |
| `evals/cases/05-ambiguous-task.yaml` | `contracts/fixtures/cases/05-ambiguous-task.yaml` | `0f4abdbdffa8eb181a398a6aba69b7fd3758e4d988904e28ee19df60048cc7ec` |
| `evals/cases/06-multi-file-refactor.yaml` | `contracts/fixtures/cases/06-multi-file-refactor.yaml` | `3135155f84d1f3ca8a99da2c6ef9d84458c1b984730d1e1282294ede66a6c989` |
| `evals/cases/07-real-doc-bounce.yaml` | `contracts/fixtures/cases/07-real-doc-bounce.yaml` | `ee510539bacff3742d7f5dc84498434b40aee1c5744a940463d503c88870424e` |
| `evals/cases/08-real-code-refactor.yaml` | `contracts/fixtures/cases/08-real-code-refactor.yaml` | `3f53da95711d0dcdb6633b6d9e67d7f0c8a57438dd319ff39ca31e965af83cc0` |
| `evals/cases/09-real-python-refactor.yaml` | `contracts/fixtures/cases/09-real-python-refactor.yaml` | `f289bfaa101a906e30857d69c0c9a82d42b6cdf6dd1fa6db06afa5b0838bbc4c` |
| `evals/cases/defaults.yaml` | `contracts/fixtures/cases/defaults.yaml` | `446f2358e928b4e3c4d296d9874b28ad939d71ef13011129aca72add780272a5` |

### fixtures/bounce-runs/ (aggregate digest per fixture dir)

| Source dir | Dest dir | Files | Aggregate SHA-256 |
|---|---|---|---|
| `evals/tests/fixtures/bounce-runs/deleted-with-section/` | `contracts/fixtures/bounce-runs/deleted-with-section/` | 6 | `b6f1f109411b5f3f12b56c2dc91492e29f1b4a2a0ac300c18780d3d7ac18a5d5` |
| `evals/tests/fixtures/bounce-runs/expired-at-final/` | `contracts/fixtures/bounce-runs/expired-at-final/` | 7 | `535d3b5a03f13f817be014d62a8a0b2441226bfcc320969db3e241b805139dff` |
| `evals/tests/fixtures/bounce-runs/resolved-with-edit/` | `contracts/fixtures/bounce-runs/resolved-with-edit/` | 6 | `58bf32bcb4918b6257011ad3df7677e7c480dd411e0a9a7f82704aa0e4b865cd` |
| `evals/tests/fixtures/bounce-runs/rubber-stamp/` | `contracts/fixtures/bounce-runs/rubber-stamp/` | 6 | `5eb30a24dd1fda0a9dd26d91314a1189d4dbfd7f4c2007c1a67b230abcace6a6` |

### fixtures/golden-scorer/ (aggregate digest per fixture dir; source is the read-only `runners/codex-ps/` tree)

| Source dir | Dest dir | Files | Aggregate SHA-256 |
|---|---|---|---|
| `runners/codex-ps/evals/tests/fixtures/01-all-pass/` | `contracts/fixtures/golden-scorer/01-all-pass/` | 6 | `4a8c891ecc556bab1c48f5e148b41c16e926cee3a50863fb21fdfcb78854fc29` |
| `runners/codex-ps/evals/tests/fixtures/02-robustness-fail/` | `contracts/fixtures/golden-scorer/02-robustness-fail/` | 5 | `85e8464aa4396b27653f9ade7614f01224ea07cf3e3c79e0ad6296e7817dce40` |
| `runners/codex-ps/evals/tests/fixtures/03-convergence-partial/` | `contracts/fixtures/golden-scorer/03-convergence-partial/` | 6 | `3102e9d810c15b98705a9cd20a88a433d6e3854760aa379018ed90f2aed3e05f` |
| `runners/codex-ps/evals/tests/fixtures/04-plan-quality-fail/` | `contracts/fixtures/golden-scorer/04-plan-quality-fail/` | 6 | `abee4ed1fada187c388cafa46872dc3a458110d88bed1adcdff5e3b0b0d76427` |
| `runners/codex-ps/evals/tests/fixtures/05-exec-fidelity-mismatch/` | `contracts/fixtures/golden-scorer/05-exec-fidelity-mismatch/` | 6 | `b172f3e732f7b23b55437a078af14f59d8a10c02191147cce66dfab52f30e21f` |
| `runners/codex-ps/evals/tests/fixtures/06-verify-catches-hallucination/` | `contracts/fixtures/golden-scorer/06-verify-catches-hallucination/` | 6 | `ea81613e43892b380310a83d435c9e6f314858c1e57767f643428c3ccc27d7c5` |
| `runners/codex-ps/evals/tests/fixtures/07-verify-misses-hallucination/` | `contracts/fixtures/golden-scorer/07-verify-misses-hallucination/` | 6 | `dba36acbe457c70256594c7538038b1cb51a200094126e16ee8e308621ff610c` |
| `runners/codex-ps/evals/tests/fixtures/08-unparseable-verdict/` | `contracts/fixtures/golden-scorer/08-unparseable-verdict/` | 6 | `8ee7b1c0a86df0bb012919d0fe1de73ef28f1b6993daaebe55cf43ef8786651d` |
| `runners/codex-ps/evals/tests/fixtures/09-cross-ai-rubber-stamp/` | `contracts/fixtures/golden-scorer/09-cross-ai-rubber-stamp/` | 8 | `095260f9c509ff608814949daccbc0160470e34ee0595b4b30fb1240c57fdcbe` |
| `runners/codex-ps/evals/tests/fixtures/10-cross-ai-genuine-bounce/` | `contracts/fixtures/golden-scorer/10-cross-ai-genuine-bounce/` | 8 | `6040da15b459420a8bbb6231072f7ecee2bb262ead17622d8235b8a25369cecf` |

## Totals

- 31 individually-hashed files
- 14 aggregate fixture directories (4 + 10) covering 88 files total: 25 in
  `bounce-runs/` (6+7+6+6, per-dir counts above) and 63 in `golden-scorer/`
  (6+5+6+6+6+6+6+6+8+8, per-dir counts above)
- 45 manifest entries total, all verified OK at extraction time
