<#
.SYNOPSIS
Tier 1 unit tests for score-run.ps1.

.DESCRIPTION
Iterates canned fixtures under evals/tests/fixtures/*/. For each fixture it
invokes the scorer with the fixture's case.yaml + run/ directory, then compares
the resulting per-dimension scores to the EXPECTED.json map. Any mismatch
fails the test suite.

Fixture layout:
  evals/tests/fixtures/<name>/
    case.yaml              # case spec (merged with defaults.yaml)
    run/
      state.json
      plan.md
      verdict.json         # optional
      outputs/             # optional — for cross_ai_diversity
    EXPECTED.json          # { "scores": { "robustness": "PASS", ... } }

Exit code:
  0 — all fixtures passed
  1 — one or more fixtures failed
#>
param(
    [string]$FixturesDir = "",
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $FixturesDir) {
    $FixturesDir = Join-Path $PSScriptRoot "fixtures"
}

$EvalsRoot = Split-Path -Parent $PSScriptRoot
$ScoreRunPath = Join-Path $EvalsRoot "score-run.ps1"
$DefaultsFile = Join-Path $EvalsRoot "cases/defaults.yaml"

if (-not (Test-Path -LiteralPath $FixturesDir)) {
    throw "Fixtures directory not found: $FixturesDir"
}
if (-not (Test-Path -LiteralPath $ScoreRunPath)) {
    throw "score-run.ps1 not found: $ScoreRunPath"
}

$fixtures = @(Get-ChildItem -LiteralPath $FixturesDir -Directory | Sort-Object Name)
if ($fixtures.Count -eq 0) {
    throw "No fixtures found under $FixturesDir"
}

$dimensions = @('robustness','convergence','plan_quality','execution_fidelity','verify_accuracy','cost','cross_ai_diversity')

$passCount = 0
$failCount = 0
$failures = New-Object System.Collections.Generic.List[string]

foreach ($fx in $fixtures) {
    $name = $fx.Name
    $caseFile = Join-Path $fx.FullName "case.yaml"
    $runDir   = Join-Path $fx.FullName "run"
    $expectedFile = Join-Path $fx.FullName "EXPECTED.json"

    foreach ($p in @($caseFile, $runDir, $expectedFile)) {
        if (-not (Test-Path -LiteralPath $p)) {
            $failures.Add("[$name] missing $p")
            $failCount++
            continue
        }
    }

    $expected = Get-Content -Raw -LiteralPath $expectedFile -Encoding UTF8 | ConvertFrom-Json
    if (-not $expected.PSObject.Properties.Name -contains 'scores') {
        $failures.Add("[$name] EXPECTED.json missing 'scores' key")
        $failCount++
        continue
    }

    # Invoke the scorer — capture the returned ordered hashtable
    $actual = $null
    try {
        $actual = & $ScoreRunPath -CaseFile $caseFile -RunDir $runDir -DefaultsFile $DefaultsFile -OutputDir $runDir 6>&1 |
            Where-Object { $_ -is [System.Collections.IDictionary] } |
            Select-Object -Last 1
    } catch {
        Write-Host "FAIL  $name" -ForegroundColor Red
        Write-Host "        scorer threw: $($_.Exception.Message)" -ForegroundColor Red
        $failures.Add("[$name] scorer threw: $($_.Exception.Message)")
        $failCount++
        continue
    }

    if (-not $actual) {
        # Fall back to reading the written scores.json
        $scoresPath = Join-Path $runDir "scores.json"
        if (Test-Path -LiteralPath $scoresPath) {
            $actual = Get-Content -Raw -LiteralPath $scoresPath -Encoding UTF8 | ConvertFrom-Json
        } else {
            $failures.Add("[$name] scorer returned no result and no scores.json")
            $failCount++
            continue
        }
    }

    $caseMismatches = New-Object System.Collections.Generic.List[string]
    foreach ($dim in $expected.scores.PSObject.Properties.Name) {
        $expectedVal = [string]$expected.scores.$dim
        $actualVal   = $null
        if ($actual -is [System.Collections.IDictionary]) {
            if ($actual.Contains('scores') -and $actual.scores -is [System.Collections.IDictionary] -and $actual.scores.Contains($dim)) {
                $actualVal = [string]$actual.scores[$dim]
            }
        } else {
            if ($actual.PSObject.Properties.Name -contains 'scores' -and $actual.scores.PSObject.Properties.Name -contains $dim) {
                $actualVal = [string]$actual.scores.$dim
            }
        }
        if ($actualVal -ne $expectedVal) {
            $caseMismatches.Add("${dim}: expected '$expectedVal', got '$actualVal'")
        }
    }

    if ($caseMismatches.Count -eq 0) {
        $passCount++
        if ($Verbose) { Write-Host "PASS  $name" -ForegroundColor Green }
    } else {
        $failCount++
        Write-Host "FAIL  $name" -ForegroundColor Red
        foreach ($m in $caseMismatches) { Write-Host "        $m" -ForegroundColor Red }
        $failures.Add("[$name] " + ($caseMismatches -join '; '))
    }
}

Write-Host ""
Write-Host ("Results: {0} passed, {1} failed ({2} fixtures total)" -f $passCount, $failCount, $fixtures.Count)

if ($failCount -gt 0) {
    exit 1
}
Write-Host "OK" -ForegroundColor Green
exit 0
