<#
Tier 2 smoke test: run the harness in -Validate mode and assert it succeeds.

Validate mode exercises the whole YAML load + fixture round-trip path for every
case in evals/cases/ without making any LLM calls. A green result here means
defaults.yaml merges cleanly, every case file parses, and every fixture (seed
files + copy_from sources) can be created and destroyed on this machine.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$evalsRoot = Split-Path -Parent $PSScriptRoot
$harness = Join-Path $evalsRoot "run-evals.ps1"

if (-not (Test-Path -LiteralPath $harness)) {
    throw "run-evals.ps1 not found at $harness"
}

Write-Host "Running: $harness -Validate"
& $harness -Validate
$code = $LASTEXITCODE

if ($null -eq $code) { $code = 0 }

if ($code -ne 0) {
    Write-Host "FAIL  run-evals.ps1 -Validate exited with code $code" -ForegroundColor Red
    exit 1
}

Write-Host "OK  harness validate passed" -ForegroundColor Green
exit 0
