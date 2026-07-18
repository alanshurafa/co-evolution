# Corpus Preservation Manifest — 2026-07-17

WP-02: non-destructive copy-out of the measurement corpus ahead of the
co-evolution rebuild. Source trees are gitignored/untracked and live only on
this disk; this manifest documents that a verified copy now also exists under
`Admin/archives/`. Nothing in the source trees was modified or deleted.

## Paths

| Tree | Source | Destination |
|---|---|---|
| runs | `C:\Users\alan\Project\co-evolution\runs` | `C:\Users\alan\Project\Admin\archives\co-evolution-corpus-20260717\runs` |
| evals reports | `C:\Users\alan\Project\co-evolution\evals\reports` | `C:\Users\alan\Project\Admin\archives\co-evolution-corpus-20260717\evals-reports` |

## Method

PowerShell robocopy per tree:

```
robocopy <src> <dst> /E /R:2 /W:2 /NFL /NDL /NP
```

| Tree | Robocopy exit code | Result |
|---|---|---|
| runs | 1 | Success (1 = files copied; 0 mismatches, 0 failed) |
| evals reports | 1 | Success (1 = files copied; 0 mismatches, 0 failed) |

Robocopy's own summary for `runs`: Dirs 299 total / 298 copied / 1 skipped
(the destination root, which robocopy treats as already-existing since it was
pre-created), Files 3471 total / 3471 copied / 0 mismatch / 0 failed, Bytes
51.38 m / 51.38 m. For `evals reports`: Dirs 1 total / 0 copied / 1 skipped
(same reason), Files 1/1, Bytes 27.5 k / 27.5 k.

## Independent verification

Computed separately from robocopy's own summary, via `Get-ChildItem -Recurse
-File | Measure-Object -Property Length -Sum` on both sides (traversal
verified error-free, 0 skipped paths; long paths are enabled on this machine
and the deepest source path was only 195 characters, so no path-length
truncation risk).

**Top-level run-dir count** (`runs` tree only):

| Side | Count |
|---|---|
| Source | 296 |
| Destination | 296 |

**Anomaly**: the work order expected roughly 302 top-level run dirs and ~14k
files. Actual measured counts are 296 top-level dirs and 3471 files (both
sides agree with each other exactly — this is not a copy problem, the
original ~302/~14k figures in the brief were just stale estimates). Reporting
the real numbers as instructed rather than reconciling to the expected ones.

**Per-tree file counts and byte totals:**

| Tree | Side | Files | Bytes |
|---|---|---|---|
| runs | Source | 3471 | 53,879,601 |
| runs | Destination | 3471 | 53,879,601 |
| evals reports | Source | 1 | 28,208 |
| evals reports | Destination | 1 | 28,208 |

All four counts match exactly between source and destination.

**Calibration report**: `bounce-calibration-2026-07-06.md` confirmed present
by name in both `evals\reports` (source) and `evals-reports` (destination).
It is in fact the sole file in that tree on both sides.

## Listing digests

Computed via Git Bash: `find . -type f -printf '%P %s\n' | sort | sha256sum`
run from the root of each tree (relative path + size per file, sorted, hashed).

| Tree | Source digest | Destination digest | Match |
|---|---|---|---|
| runs | `97430c591e81afc21c3ab8a23502f6c7b9619cb42e4b931db72ce7a695196d61` | `97430c591e81afc21c3ab8a23502f6c7b9619cb42e4b931db72ce7a695196d61` | Yes |
| evals reports | `2ef7acc59514fd4507e71182a80d07b58fd9780b0921aff6185d6cf7b2d86e3b` | `2ef7acc59514fd4507e71182a80d07b58fd9780b0921aff6185d6cf7b2d86e3b` | Yes |

## Outcome

Both trees copied and independently verified via three separate methods
(robocopy's own summary, PowerShell recursive count/byte totals, and a
sorted path+size SHA-256 digest) with full agreement across all of them.
Source trees were only read, never modified or deleted.
