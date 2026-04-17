<#
Render evals/reports/{ts}/report.md from raw-scores.json + report-template.md.

Template placeholders:
  {{TIMESTAMP}}        — report generation time
  {{CASE_COUNT}}       — total cases
  {{PASS_COUNT}}       — cases with status=ok AND robustness=PASS
  {{FAIL_COUNT}}       — cases that failed (any reason)
  {{COMPOSITE_AVG}}    — mean composite score across cases that produced scores
  {{CASE_TABLE}}       — markdown table of case_id | composite | per-dim | status
  {{DETAILS_SECTIONS}} — per-case detail block
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$RawScoresPath,

    [Parameter(Mandatory = $true)]
    [string]$TemplatePath,

    [Parameter(Mandatory = $true)]
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$raw = Get-Content -Raw -LiteralPath $RawScoresPath -Encoding UTF8 | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $TemplatePath)) {
    throw "Report template not found: $TemplatePath"
}
$template = Get-Content -Raw -LiteralPath $TemplatePath -Encoding UTF8

$dimensionOrder = @(
    'robustness','convergence','plan_quality','execution_fidelity','verify_accuracy','cost','cross_ai_diversity'
)
$shortNames = @{
    robustness='Rob'; convergence='Conv'; plan_quality='Plan'; execution_fidelity='Exec'
    verify_accuracy='Ver'; cost='Cost'; cross_ai_diversity='XAI'
}

function Emoji($v) {
    switch ($v) {
        'PASS'    { '+' }
        'PARTIAL' { '~' }
        'FAIL'    { 'X' }
        'N/A'     { '-' }
        default   { '?' }
    }
}

$caseRows = New-Object System.Collections.Generic.List[string]
$detailBlocks = New-Object System.Collections.Generic.List[string]
$compositeSum = 0.0; $compositeN = 0
$passCount = 0; $failCount = 0

$header = "| Case | " + (($dimensionOrder | ForEach-Object { $shortNames[$_] }) -join ' | ') + " | Composite | Status |"
$sep    = "|------|" + (($dimensionOrder | ForEach-Object { '---' }) -join '|') + "|-----------|--------|"
$caseRows.Add($header)
$caseRows.Add($sep)

foreach ($entry in @($raw)) {
    $id = [string]$entry.case_id
    $status = [string]$entry.status
    $scores = $entry.scores
    $composite = if ($entry.PSObject.Properties.Name -contains 'composite') { $entry.composite } else { $null }

    $cells = foreach ($dim in $dimensionOrder) {
        $v = if ($scores -and $scores.PSObject.Properties.Name -contains $dim) { [string]$scores.$dim } else { '?' }
        "$(Emoji $v) $v"
    }
    $compCell = if ($null -ne $composite) { ("{0:F2}" -f $composite) } else { '--' }

    $statusCell = switch ($status) {
        'ok' { 'ok' }
        'runner_nonzero_exit' { 'exit!=0' }
        'fail' { 'FAIL' }
        default { $status }
    }

    $caseRows.Add("| $id | " + ($cells -join ' | ') + " | $compCell | $statusCell |")

    if ($null -ne $composite) {
        $compositeSum += [double]$composite
        $compositeN++
    }
    if ($status -eq 'ok' -and $scores -and $scores.robustness -eq 'PASS') { $passCount++ }
    else { $failCount++ }

    # Detail block
    $dbuf = New-Object System.Collections.Generic.List[string]
    $dbuf.Add("### $id")
    $dbuf.Add("")
    $dbuf.Add("- **Status:** $status")
    if ($entry.PSObject.Properties.Name -contains 'run_id' -and $entry.run_id) {
        $dbuf.Add("- **Run ID:** $($entry.run_id)")
    }
    if ($entry.PSObject.Properties.Name -contains 'error' -and $entry.error) {
        $dbuf.Add("- **Error:** ``$($entry.error)``")
    }
    if ($scores) {
        $dbuf.Add("")
        $dbuf.Add("| Dimension | Score |")
        $dbuf.Add("|-----------|-------|")
        foreach ($dim in $dimensionOrder) {
            $v = if ($scores.PSObject.Properties.Name -contains $dim) { [string]$scores.$dim } else { '?' }
            $dbuf.Add("| $dim | $v |")
        }
    }
    $dbuf.Add("")
    $detailBlocks.Add(($dbuf -join "`n"))
}

$compositeAvg = if ($compositeN -gt 0) { "{0:F2}" -f ($compositeSum / $compositeN) } else { "n/a" }
$caseCount = @($raw).Count

$rendered = $template
$rendered = $rendered -replace [regex]::Escape('{{TIMESTAMP}}'),    (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
$rendered = $rendered -replace [regex]::Escape('{{CASE_COUNT}}'),   [string]$caseCount
$rendered = $rendered -replace [regex]::Escape('{{PASS_COUNT}}'),   [string]$passCount
$rendered = $rendered -replace [regex]::Escape('{{FAIL_COUNT}}'),   [string]$failCount
$rendered = $rendered -replace [regex]::Escape('{{COMPOSITE_AVG}}'),$compositeAvg
$rendered = $rendered -replace [regex]::Escape('{{CASE_TABLE}}'),   (($caseRows -join "`n"))
$rendered = $rendered -replace [regex]::Escape('{{DETAILS_SECTIONS}}'), (($detailBlocks -join "`n`n"))

Set-Content -LiteralPath $ReportPath -Value $rendered -Encoding UTF8
Write-Host "report rendered: $ReportPath"
