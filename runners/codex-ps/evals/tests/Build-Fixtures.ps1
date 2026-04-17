<#
Generate Tier 1 scorer test fixtures from inline specs.

Each spec describes the minimal fields needed to trigger a specific scoring
behaviour. Common elements (valid state.json envelope, plausible plan text) are
defaulted.

Usage:
  powershell.exe -File evals/tests/Build-Fixtures.ps1 [-Force]

-Force overwrites existing fixture files; without it, existing files are left alone.
#>
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Join-Path $PSScriptRoot "fixtures"
New-Item -ItemType Directory -Path $root -Force | Out-Null

$goodPlan = @"
# Plan

## Goal
Make the small, clearly-scoped edit described in the task.

## Implementation Steps
1. Read the target file and locate the lines to change.
2. Apply the edit described in the plan.
3. Save and leave any other files alone.

## Files to Change
- ``README.md`` -- apply the edit described above

## Validation
Re-open the file and confirm the change is present.

## Risks
- The edit is local; nothing else should break.
"@

$tinyPlan = "Short."

$goodState = @{
    run_id = "fixture-run"
    task = "fixture task"
    composer = "codex"
    reviewer = "codex"
    executor = "codex"
    max_bounces = 1
    verify = $true
    autonomous = $true
    status = "completed"
    status_detail = "Runner completed successfully."
    current_phase = "verify"
    marker_counts = @{ contested = 0; clarify = 0; total = 0 }
    changed_files = @("README.md")
    verify_verdict = "APPROVED"
    started_at = "2026-04-17T09:00:00.0000000-04:00"
    updated_at = "2026-04-17T09:02:30.0000000-04:00"
    completed_at = "2026-04-17T09:02:30.0000000-04:00"
    history = @(
        @{ phase="compose"; status="running"; detail=""; timestamp="2026-04-17T09:00:00.0000000-04:00" },
        @{ phase="bounce"; status="running"; detail=""; timestamp="2026-04-17T09:00:30.0000000-04:00" },
        @{ phase="bounce-01"; status="running"; detail=""; timestamp="2026-04-17T09:00:45.0000000-04:00" },
        @{ phase="execute"; status="running"; detail=""; timestamp="2026-04-17T09:01:30.0000000-04:00" },
        @{ phase="verify"; status="running"; detail=""; timestamp="2026-04-17T09:02:00.0000000-04:00" }
    )
}

$goodCase = @"
id: ID_PLACEHOLDER
title: Tier 1 fixture
runner:
  task: 'fixture task'
  composer: codex
  reviewer: codex
  executor: codex
  bounces: 1
  verify: true
  autonomous: true
expectations:
  plan_quality:
    min_word_count: 40
  execution_fidelity:
    min_jaccard: 0.9
  verify_accuracy:
    allow_verdict: ['APPROVED','REVISE']
  cost:
    max_wall_clock_seconds: 600
"@

$approvedVerdict = @"
{
  "verdict": "APPROVED",
  "confidence": 95,
  "summary": "Clean change.",
  "issues": [],
  "scope_creep_detected": false,
  "iteration_notes": ""
}
"@

function DeepClone {
    param($x)
    if ($null -eq $x) { return $null }
    if ($x -is [hashtable]) {
        $c = @{}
        foreach ($k in $x.Keys) { $c[$k] = DeepClone $x[$k] }
        return $c
    }
    if ($x -is [object[]]) {
        return @($x | ForEach-Object { DeepClone $_ })
    }
    return $x
}

function Write-FixtureFile([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        Write-Host "  skip (exists):  $Path"
        return
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
    Write-Host "  wrote:          $Path"
}

# Each fixture spec: @{ name; caseExtra (yaml snippet or $null); stateOverride; planOverride; verdict; outputs; expected }
$specs = @(
    @{
        name = "02-robustness-fail"
        stateOverride = @{ status = "running"; current_phase = "verify"; completed_at = $null }
        planOverride = $goodPlan
        verdict = $null
        expected = @{ robustness="FAIL"; convergence="PASS"; plan_quality="PASS"; execution_fidelity="PASS"; verify_accuracy="FAIL"; cost="PASS"; cross_ai_diversity="N/A" }
    },
    @{
        name = "03-convergence-partial"
        stateOverride = @{ marker_counts = @{ contested = 1; clarify = 0; total = 1 } }
        planOverride = $goodPlan
        verdict = $approvedVerdict
        expected = @{ robustness="PASS"; convergence="PARTIAL"; plan_quality="PASS"; execution_fidelity="PASS"; verify_accuracy="PASS"; cost="PASS"; cross_ai_diversity="N/A" }
    },
    @{
        name = "04-plan-quality-fail"
        # Empty changed_files to isolate the plan_quality dimension (otherwise a
        # tiny plan + real changes would also correctly fail execution_fidelity).
        stateOverride = @{ changed_files = @() }
        planOverride = $tinyPlan
        verdict = $approvedVerdict
        expected = @{ robustness="PASS"; convergence="PASS"; plan_quality="FAIL"; execution_fidelity="PASS"; verify_accuracy="PASS"; cost="PASS"; cross_ai_diversity="N/A" }
    },
    @{
        name = "05-exec-fidelity-mismatch"
        # Plan says a.ps1; state.changed_files=[b.ps1] => jaccard 0 => FAIL
        stateOverride = @{ changed_files = @("b.ps1") }
        planOverride = $goodPlan.Replace('``README.md``', '``a.ps1``')
        verdict = $approvedVerdict
        expected = @{ robustness="PASS"; convergence="PASS"; plan_quality="PASS"; execution_fidelity="FAIL"; verify_accuracy="PASS"; cost="PASS"; cross_ai_diversity="N/A" }
    },
    @{
        name = "06-verify-catches-hallucination"
        caseExtraExpectations = @"
  verify_accuracy:
    must_catch_issue: true
    issue_keywords: ['RetryAsync','does not exist']
"@
        stateOverride = @{ verify_verdict = "REVISE" }
        planOverride = $goodPlan
        verdict = @"
{
  "verdict": "REVISE",
  "confidence": 88,
  "summary": "The code calls RetryAsync which does not exist on HttpClient.",
  "issues": [
    { "severity": "high", "file": "src/Get-Data.ps1", "line": 2, "description": "RetryAsync is not a member of HttpClient; this will throw at runtime.", "suggestion": "Implement retry with Polly or a custom loop." }
  ],
  "scope_creep_detected": false,
  "iteration_notes": ""
}
"@
        expected = @{ robustness="PASS"; convergence="PASS"; plan_quality="PASS"; execution_fidelity="PASS"; verify_accuracy="PASS"; cost="PASS"; cross_ai_diversity="N/A" }
    },
    @{
        name = "07-verify-misses-hallucination"
        caseExtraExpectations = @"
  verify_accuracy:
    must_catch_issue: true
    issue_keywords: ['RetryAsync','does not exist']
"@
        stateOverride = @{ verify_verdict = "APPROVED" }
        planOverride = $goodPlan
        verdict = $approvedVerdict
        expected = @{ robustness="PASS"; convergence="PASS"; plan_quality="PASS"; execution_fidelity="PASS"; verify_accuracy="FAIL"; cost="PASS"; cross_ai_diversity="N/A" }
    },
    @{
        name = "08-unparseable-verdict"
        stateOverride = @{ verify_verdict = "" }
        planOverride = $goodPlan
        verdict = "{not json at all"
        expected = @{ robustness="PASS"; convergence="PASS"; plan_quality="PASS"; execution_fidelity="PASS"; verify_accuracy="FAIL"; cost="PASS"; cross_ai_diversity="N/A" }
    },
    @{
        name = "09-cross-ai-rubber-stamp"
        # Mixed agents so cross-AI is scored. Compose ~= bounce-01 (near-identical).
        caseExtraRunner = @"
  composer: claude
  reviewer: codex
"@
        stateOverride = @{ composer = "claude"; reviewer = "codex" }
        planOverride = $goodPlan
        verdict = $approvedVerdict
        outputs = @{
            "compose.txt"   = "The plan proposes one edit to README.md with a short validation step. No risks identified."
            "bounce-01.txt" = "The plan proposes one edit to README.md with a short validation step. No risks identified."
        }
        expected = @{ robustness="PASS"; convergence="PASS"; plan_quality="PASS"; execution_fidelity="PASS"; verify_accuracy="PASS"; cost="PASS"; cross_ai_diversity="FAIL" }
    },
    @{
        name = "10-cross-ai-genuine-bounce"
        caseExtraRunner = @"
  composer: claude
  reviewer: codex
"@
        stateOverride = @{ composer = "claude"; reviewer = "codex" }
        planOverride = $goodPlan
        verdict = $approvedVerdict
        outputs = @{
            "compose.txt"   = "The plan proposes one edit to README.md with a validation step and notes on scope."
            "bounce-01.txt" = "After review: rewrote the plan to be sharper. The single README change is clear but add an explicit risk about pre-commit hooks blocking an unsigned commit, and rename the section to Verification rather than Validation. Also include an explicit pre-check that README.md exists before editing so the runner does not silently fail when the file path is wrong. The approach remains one-file but the expectations section now spells out what success looks like precisely."
        }
        expected = @{ robustness="PASS"; convergence="PASS"; plan_quality="PASS"; execution_fidelity="PASS"; verify_accuracy="PASS"; cost="PASS"; cross_ai_diversity="PASS" }
    }
)

foreach ($spec in $specs) {
    Write-Host "=== $($spec.name) ==="
    $dir = Join-Path $root $spec.name
    New-Item -ItemType Directory -Path (Join-Path $dir "run/outputs") -Force | Out-Null

    # Build case.yaml by mutating the good template
    $case = $goodCase.Replace('ID_PLACEHOLDER', $spec.name)
    if ($spec.ContainsKey('caseExtraRunner')) {
        # Insert runner override: replace composer/reviewer lines
        $case = $case -replace '(?m)^\s*composer: codex\s*$', ''
        $case = $case -replace '(?m)^\s*reviewer: codex\s*$', ''
        $case = $case -replace '(?m)^runner:\s*$', ("runner:" + "`n" + $spec.caseExtraRunner)
    }
    if ($spec.ContainsKey('caseExtraExpectations')) {
        # If the extra block redefines verify_accuracy, strip the template's default
        # verify_accuracy subsection first so we don't emit duplicate keys.
        if ($spec.caseExtraExpectations -match '(?m)^\s*verify_accuracy:') {
            $case = $case -replace "(?ms)^\s*verify_accuracy:\s*\n(?:\s{4,}.*\n?)+", ""
        }
        $case += "`n" + $spec.caseExtraExpectations + "`n"
    }
    Write-FixtureFile -Path (Join-Path $dir "case.yaml") -Content $case

    # Build state.json by merging overrides
    $state = DeepClone $goodState
    foreach ($k in $spec.stateOverride.Keys) { $state[$k] = $spec.stateOverride[$k] }
    $stateJson = $state | ConvertTo-Json -Depth 10
    Write-FixtureFile -Path (Join-Path $dir "run/state.json") -Content $stateJson

    # Plan
    Write-FixtureFile -Path (Join-Path $dir "run/plan.md") -Content $spec.planOverride

    # Verdict
    if ($null -ne $spec.verdict) {
        Write-FixtureFile -Path (Join-Path $dir "run/verdict.json") -Content $spec.verdict
    }

    # Outputs (for cross-AI fixtures)
    if ($spec.ContainsKey('outputs')) {
        foreach ($fname in $spec.outputs.Keys) {
            Write-FixtureFile -Path (Join-Path $dir "run/outputs/$fname") -Content $spec.outputs[$fname]
        }
    }

    # Expected
    $expected = @{ scores = $spec.expected } | ConvertTo-Json -Depth 5
    Write-FixtureFile -Path (Join-Path $dir "EXPECTED.json") -Content $expected
}

Write-Host ""
Write-Host "Done. Run Test-Scorer.ps1 to verify."
