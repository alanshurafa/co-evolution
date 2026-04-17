<#
.SYNOPSIS
Run the codex-co-evolution eval harness across a set of cases.

.DESCRIPTION
For each selected case:
 1. Creates an isolated fixture directory (evals/fixtures/tmp/{case}-{ts}/)
    containing a copy of scripts/ templates/ schemas/ from the real repo.
 2. Seeds any files declared by the case.
 3. Invokes scripts/run-co-evolution.ps1 inside the fixture with the case's
    runner flags.
 4. Copies the produced .co-evolution/runs/{run-id}/ into
    evals/reports/{timestamp}/runs/{case-id}/.
 5. Scores the run via score-run.ps1.
 6. After every case: renders evals/reports/{ts}/report.md and writes
    raw-scores.json.

Exit code 0 only if every case PASSes on the Robustness dimension.

.PARAMETER Cases
Comma-separated list of case ids to run (default: all YAML files in cases/).

.PARAMETER Validate
If set, does NOT invoke the runner — only validates that every case YAML loads,
defaults merge cleanly, and every fixture can be created + destroyed.
Useful for Phase B.5.

.PARAMETER KeepFixtures
If set, keeps fixture directories after the run (debug aid).

.PARAMETER SkipScoring
If set, runs the cases but does not render a report (use when experimenting).
#>
param(
    [string]$Cases = "",
    [switch]$Validate,
    [switch]$KeepFixtures,
    [switch]$SkipScoring,

    # Tier 2 harness test: copy a canned run directory into the fixture instead of
    # invoking the real runner. Bypasses LLM cost entirely. Supply an absolute path
    # to a directory that contains a full run (state.json, plan.md, outputs/, etc.).
    [string]$FakeRunner = "",

    # Tier 4 seeded regression test: use an alternate runner .ps1 for this invocation
    # (e.g. a deliberately-broken copy). The harness still copies scripts/ templates/
    # schemas/ into the fixture, but then overwrites the runner with the provided file.
    [string]$UseRunner = "",

    # Tier 3 variance: run each selected case N times sequentially. The report
    # includes one row per (case, iteration). Useful for measuring LLM noise.
    [int]$Repeat = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$EvalsRoot   = $PSScriptRoot
$CasesDir    = Join-Path $EvalsRoot "cases"
$ReportsDir  = Join-Path $EvalsRoot "reports"
$DefaultsFile = Join-Path $CasesDir "defaults.yaml"

. (Join-Path $EvalsRoot "lib/Yaml.ps1")
. (Join-Path $EvalsRoot "lib/Fixture.ps1")

Ensure-YamlModule

# --- Select cases -----------------------------------------------------------
$allCaseFiles = Get-ChildItem -LiteralPath $CasesDir -Filter '*.yaml' -File |
    Where-Object { $_.Name -ne 'defaults.yaml' } |
    Sort-Object Name

if ($Cases) {
    $wanted = $Cases -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $caseFiles = $allCaseFiles | Where-Object {
        $id = [IO.Path]::GetFileNameWithoutExtension($_.Name)
        ($wanted -contains $id) -or (@($wanted | Where-Object { $id.StartsWith($_) })).Count -gt 0
    }
} else {
    $caseFiles = $allCaseFiles
}

if (-not $caseFiles -or @($caseFiles).Count -eq 0) {
    throw "No cases matched selection: '$Cases'. Available: $($allCaseFiles.Name -join ', ')"
}

Write-Host ("Cases to run: {0}" -f (($caseFiles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) }) -join ', '))

# --- Prepare report dir -----------------------------------------------------
$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportDir = Join-Path $ReportsDir $runTimestamp
if (-not $Validate) {
    $null = New-Item -ItemType Directory -Path $reportDir -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $reportDir "runs") -Force
}

$rawScores = New-Object System.Collections.Generic.List[object]
$perCaseResults = New-Object System.Collections.Generic.List[object]

# --- Load defaults once -----------------------------------------------------
$defaults = if (Test-Path -LiteralPath $DefaultsFile) { Read-YamlFile -Path $DefaultsFile } else { @{} }

# --- Iterate cases ----------------------------------------------------------
foreach ($caseFile in $caseFiles) {
    $caseId = [IO.Path]::GetFileNameWithoutExtension($caseFile.Name)
    Write-Host ""
    Write-Host ("=== Case: {0} ===" -f $caseId)

    $caseRaw = Read-YamlFile -Path $caseFile.FullName
    $case = Merge-HashtablesDeep -Base $defaults -Override $caseRaw

    # Extract setup once
    $seedFiles = @(); $copyFrom = @()
    if ($case.Contains('setup') -and $case.setup -is [System.Collections.IDictionary]) {
        if ($case.setup.Contains('seed_files')) { $seedFiles = @($case.setup.seed_files) }
        if ($case.setup.Contains('copy_from'))  { $copyFrom  = @($case.setup.copy_from)  }
    }

    if ($Validate) {
        # Validation mode: check case loads, fixture creates & destroys clean.
        Write-Host "  validate: yaml loaded"
        $fixtureDir = $null
        try {
            $fixtureDir = New-Fixture -ProjectRoot $ProjectRoot -CaseId $caseId -RunTimestamp $runTimestamp -SeedFiles $seedFiles -CopyFrom $copyFrom
            Write-Host "  validate: fixture created: $fixtureDir"
        } finally {
            if ($fixtureDir) { Remove-Fixture -FixtureDir $fixtureDir -Keep:$false }
            Write-Host "  validate: fixture removed"
        }
        continue
    }

    # --- Execution mode — loop for -Repeat ---
    if ($Repeat -lt 1) { $Repeat = 1 }

    for ($iter = 1; $iter -le $Repeat; $iter++) {
        $iterSuffix = if ($Repeat -gt 1) { "-iter{0:d2}" -f $iter } else { "" }
        $caseIterId = $caseId + $iterSuffix
        $fixtureDir = $null
        $caseDestDir = Join-Path $reportDir "runs/$caseIterId"
        $caseResult = [ordered]@{
            case_id = $caseIterId
            status  = 'unknown'
            error   = $null
            scores  = $null
            run_id  = $null
            started_at = (Get-Date -Format "o")
        }

        try {
            $fixtureDir = New-Fixture -ProjectRoot $ProjectRoot -CaseId $caseIterId -RunTimestamp $runTimestamp -SeedFiles $seedFiles -CopyFrom $copyFrom
            Write-Host "  fixture: $fixtureDir"

            # Optional: substitute an alternate runner (used by Tier 4 seeded regressions)
            if ($UseRunner) {
                if (-not (Test-Path -LiteralPath $UseRunner)) {
                    throw "-UseRunner path not found: $UseRunner"
                }
                $targetRunner = Join-Path $fixtureDir "scripts/run-co-evolution.ps1"
                Copy-Item -LiteralPath $UseRunner -Destination $targetRunner -Force
                Write-Host "  using alternate runner: $UseRunner"
            }

            # Build runner flags from merged case
            $task       = [string]$case.runner.task
            $composer   = if ($case.runner.Contains('composer'))   { [string]$case.runner.composer }   else { 'codex' }
            $reviewer   = if ($case.runner.Contains('reviewer'))   { [string]$case.runner.reviewer }   else { 'codex' }
            $executor   = if ($case.runner.Contains('executor'))   { [string]$case.runner.executor }   else { 'codex' }
            $bounces    = if ($case.runner.Contains('bounces'))    { [string]$case.runner.bounces }    else { 'auto' }
            $verify     = if ($case.runner.Contains('verify'))     { [bool]$case.runner.verify }       else { $true }
            $autonomous = if ($case.runner.Contains('autonomous')) { [bool]$case.runner.autonomous }   else { $true }

            Write-Host ("  runner: composer={0} reviewer={1} executor={2} bounces={3} verify={4} iter={5}/{6}" -f $composer,$reviewer,$executor,$bounces,$verify,$iter,$Repeat)

            if ($FakeRunner) {
                # Tier 2 integration test: copy a pre-captured run dir into the fixture
                # instead of spawning the runner. Bypasses all LLM cost.
                if (-not (Test-Path -LiteralPath $FakeRunner)) {
                    throw "-FakeRunner source not found: $FakeRunner"
                }
                $fakeRunsRoot = Join-Path $fixtureDir ".co-evolution/runs"
                $null = New-Item -ItemType Directory -Path $fakeRunsRoot -Force
                $fakeDest = Join-Path $fakeRunsRoot ("fake-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
                Copy-Item -LiteralPath $FakeRunner -Destination $fakeDest -Recurse -Force
                Write-Host "  fake-runner: copied $FakeRunner -> $fakeDest"
                $caseResult.exit_code = 0
            } else {
                $runnerPath = Join-Path $fixtureDir "scripts/run-co-evolution.ps1"

                # Build a single -Command string. Passing booleans via Start-Process ArgumentList
                # stringifies them as "True"/"False" which the runner rejects; the colon-switch
                # syntax (-Verify:$true) avoids that by letting PowerShell parse inside the child.
                $escapedTask = $task.Replace("'", "''")
                $verifyTok     = if ($verify)     { '$true' } else { '$false' }
                $autonomousTok = if ($autonomous) { '$true' } else { '$false' }
                $cmd = @"
& '$runnerPath' -Task '$escapedTask' -Composer $composer -Reviewer $reviewer -Executor $executor -Bounces '$bounces' -Verify:$verifyTok -Autonomous:$autonomousTok
"@
                $runnerArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-Command', $cmd)

                $stdoutPath = Join-Path $reportDir "runs/$caseIterId.stdout.log"
                $stderrPath = Join-Path $reportDir "runs/$caseIterId.stderr.log"
                $null = New-Item -ItemType Directory -Path (Split-Path $stdoutPath -Parent) -Force

                $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $runnerArgs `
                    -WorkingDirectory $fixtureDir -NoNewWindow -Wait -PassThru `
                    -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

                $caseResult.exit_code = $proc.ExitCode
            }

            # Copy run artifacts regardless of exit code (fail-open on artifact capture)
            try {
                $runId = Copy-RunArtifacts -FixtureDir $fixtureDir -DestDir $caseDestDir
                $caseResult.run_id = $runId
            } catch {
                $caseResult.error = "artifact copy failed: $($_.Exception.Message)"
                $caseResult.status = 'fail'
                throw
            }

            # Score it
            if (-not $SkipScoring) {
                $scoreResult = & (Join-Path $EvalsRoot "score-run.ps1") `
                    -CaseFile $caseFile.FullName `
                    -DefaultsFile $DefaultsFile `
                    -RunDir $caseDestDir `
                    -OutputDir $caseDestDir
                $caseResult.scores = $scoreResult.scores
                $caseResult.composite = $scoreResult.composite
            }
            $caseResult.status = if ($caseResult.exit_code -eq 0) { 'ok' } else { 'runner_nonzero_exit' }

        } catch {
            $caseResult.status = 'fail'
            $caseResult.error = $_.Exception.Message
            $caseResult.error_trace = "$($_.ScriptStackTrace)"
            $caseResult.error_location = "$($_.InvocationInfo.PositionMessage)"
            Write-Host ("  ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
            if ($_.InvocationInfo.ScriptName) {
                Write-Host ("  AT:    {0}:{1}" -f $_.InvocationInfo.ScriptName,$_.InvocationInfo.ScriptLineNumber) -ForegroundColor Red
            }
        } finally {
            $caseResult.finished_at = (Get-Date -Format "o")
            # On failure, preserve the fixture so we can diagnose later.
            $shouldKeep = $KeepFixtures.IsPresent -or ($caseResult.status -eq 'fail')
            if ($fixtureDir) { Remove-Fixture -FixtureDir $fixtureDir -Keep:$shouldKeep }
            $rawScores.Add($caseResult)
        }
    }  # end for $iter
}  # end foreach $caseFile

if ($Validate) {
    Write-Host ""
    Write-Host "Validation complete: all cases loaded and all fixtures round-tripped." -ForegroundColor Green
    return
}

# --- Write raw scores -------------------------------------------------------
$rawPath = Join-Path $reportDir "raw-scores.json"
$rawScores | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath $rawPath -Encoding UTF8
Write-Host ""
Write-Host ("raw scores: {0}" -f $rawPath)

# --- Render report ----------------------------------------------------------
if (-not $SkipScoring) {
    $templatePath = Join-Path $EvalsRoot "report-template.md"
    $reportPath = Join-Path $reportDir "report.md"
    & (Join-Path $EvalsRoot "lib/Report.ps1") -RawScoresPath $rawPath -TemplatePath $templatePath -ReportPath $reportPath
    Write-Host ("report:     {0}" -f $reportPath)
}

# --- Exit code --------------------------------------------------------------
$robustFails = @($rawScores | Where-Object {
    ($_.status -eq 'fail') -or
    ($_.scores -and ($_.scores.robustness -eq 'FAIL'))
}).Count

Write-Host ""
if ($robustFails -gt 0) {
    Write-Host ("FAILURE: {0} case(s) failed on Robustness." -f $robustFails) -ForegroundColor Red
    exit 1
} else {
    Write-Host "OK: all cases passed Robustness." -ForegroundColor Green
    exit 0
}
