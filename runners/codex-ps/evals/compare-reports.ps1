<#
.SYNOPSIS
Compare two eval reports and flag regressions.

.DESCRIPTION
Reads raw-scores.json from two report directories and prints a diff table:
cases present in both, their before/after per-dimension scores, and a
regression count.

Exit 0 if no case regressed on Robustness; exit 1 otherwise.

.PARAMETER Before
Path to the older report dir (e.g. evals/reports/20260417-080000).

.PARAMETER After
Path to the newer report dir.

.PARAMETER Output
Optional markdown output path. If omitted, prints to stdout.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Before,

    [Parameter(Mandatory = $true)]
    [string]$After,

    [string]$Output = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Load-Scores([string]$ReportDir) {
    $p = Join-Path $ReportDir "raw-scores.json"
    if (-not (Test-Path -LiteralPath $p)) { throw "raw-scores.json missing in $ReportDir" }
    $list = Get-Content -Raw -LiteralPath $p | ConvertFrom-Json
    $map = @{}
    foreach ($e in @($list)) { $map[[string]$e.case_id] = $e }
    return $map
}

$beforeMap = Load-Scores -ReportDir $Before
$afterMap  = Load-Scores -ReportDir $After

$dimensions = @('robustness','convergence','plan_quality','execution_fidelity','verify_accuracy','cost','cross_ai_diversity')
$valueOf = @{ PASS = 3; PARTIAL = 2; FAIL = 1; 'N/A' = $null; '?' = 0 }

$caseIds = @($beforeMap.Keys + $afterMap.Keys | Sort-Object -Unique)
$rows = New-Object System.Collections.Generic.List[string]
$rows.Add("| Case | " + ($dimensions -join ' | ') + " |")
$rows.Add("|------|" + (($dimensions | ForEach-Object { '-' }) -join '|') + "|")

$regressions = 0
$robustnessRegressions = 0

foreach ($id in $caseIds) {
    $b = $beforeMap[$id]
    $a = $afterMap[$id]
    $cells = foreach ($d in $dimensions) {
        $bv = if ($b -and $b.scores -and $b.scores.PSObject.Properties.Name -contains $d) { [string]$b.scores.$d } else { '?' }
        $av = if ($a -and $a.scores -and $a.scores.PSObject.Properties.Name -contains $d) { [string]$a.scores.$d } else { '?' }
        $bn = $valueOf[$bv]; $an = $valueOf[$av]
        $indicator = ''
        if ($null -ne $bn -and $null -ne $an) {
            if ($an -lt $bn) {
                $indicator = '↓'
                $regressions++
                if ($d -eq 'robustness') { $robustnessRegressions++ }
            } elseif ($an -gt $bn) {
                $indicator = '↑'
            }
        }
        "$bv→$av $indicator".Trim()
    }
    $rows.Add("| $id | " + ($cells -join ' | ') + " |")
}

$body = @(
    "# Eval Comparison",
    "",
    "**Before:** ``$Before``  ",
    "**After:**  ``$After``",
    "",
    "**Regressions:** $regressions total, $robustnessRegressions on Robustness",
    "",
    "## Per-Case Dimension Diff",
    "",
    ($rows -join "`n"),
    "",
    "## Legend",
    "",
    "- `↓` regression (score dropped)",
    "- `↑` improvement",
    "- No arrow: unchanged"
) -join "`n"

if ($Output) {
    Set-Content -LiteralPath $Output -Value $body -Encoding UTF8
    Write-Host "wrote: $Output"
} else {
    Write-Host $body
}

if ($robustnessRegressions -gt 0) {
    Write-Host ""
    Write-Host "FAIL: $robustnessRegressions case(s) regressed on Robustness" -ForegroundColor Red
    exit 1
}
exit 0
