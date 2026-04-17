<#
.SYNOPSIS
Score a single co-evolution run against a case spec.

.DESCRIPTION
Reads the run artifacts (state.json, plan.md, verdict.json, outputs/) and
produces a per-dimension score map: PASS | PARTIAL | FAIL | N/A for each of
seven dimensions. Writes a machine-readable scores.json to -OutputDir and
returns the same structure on stdout.

Dimensions:
- cross_ai_diversity   (N/A when case.runner.composer == .reviewer)
- convergence
- plan_quality
- execution_fidelity
- verify_accuracy
- cost
- robustness

.PARAMETER CaseFile
Path to the case YAML (already merged with defaults.yaml, or raw — the scorer
tolerates both).

.PARAMETER RunDir
Path to the captured run directory (contains state.json, plan.md, outputs/, etc).

.PARAMETER DefaultsFile
Path to defaults.yaml; merged under the case if present.

.PARAMETER OutputDir
Where to write scores.json. Defaults to $RunDir.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$CaseFile,

    [Parameter(Mandatory = $true)]
    [string]$RunDir,

    [string]$DefaultsFile = "",

    [string]$OutputDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib/Yaml.ps1")

if (-not $OutputDir) { $OutputDir = $RunDir }

# --- Load merged case spec --------------------------------------------------
$case = Read-YamlFile -Path $CaseFile
if ($DefaultsFile -and (Test-Path -LiteralPath $DefaultsFile)) {
    $defaults = Read-YamlFile -Path $DefaultsFile
    $case = Merge-HashtablesDeep -Base $defaults -Override $case
}

function Get-CaseValue {
    # Navigate a nested path through either an IDictionary (from YAML load) or a
    # PSCustomObject (from ConvertFrom-Json on state.json / verdict.json).
    param($Map, [string[]]$Path, $Fallback = $null)
    $node = $Map
    foreach ($key in $Path) {
        if ($null -eq $node) { return $Fallback }
        if ($node -is [System.Collections.IDictionary]) {
            if ($node.Contains($key)) { $node = $node[$key] } else { return $Fallback }
        } elseif ($node -is [pscustomobject]) {
            $propNames = @($node.PSObject.Properties.Name)
            if ($propNames -contains $key) { $node = $node.$key } else { return $Fallback }
        } else {
            return $Fallback
        }
    }
    if ($null -eq $node) { return $Fallback }
    return $node
}

# --- Load run artifacts -----------------------------------------------------
$stateJsonPath = Join-Path $RunDir "state.json"
if (-not (Test-Path -LiteralPath $stateJsonPath)) {
    throw "state.json not found at: $stateJsonPath"
}
$state = Get-Content -Raw -LiteralPath $stateJsonPath | ConvertFrom-Json

$planPath = Join-Path $RunDir "plan.md"
$planText = if (Test-Path -LiteralPath $planPath) { Get-Content -Raw -LiteralPath $planPath } else { "" }

$verdictPath = Join-Path $RunDir "verdict.json"
$verdict = $null
if (Test-Path -LiteralPath $verdictPath) {
    try {
        $verdict = Get-Content -Raw -LiteralPath $verdictPath | ConvertFrom-Json
    } catch {
        $verdict = "__unparseable__"
    }
}

$outputsDir = Join-Path $RunDir "outputs"

# --- Helpers ----------------------------------------------------------------
function Get-FilesFromPlan {
    param([string]$Plan)
    $section = $null
    $m = [regex]::Match($Plan, '(?ms)^##\s+Files to Change\s*$(.*?)(^##\s+|\Z)')
    if ($m.Success) { $section = $m.Groups[1].Value }
    if (-not $section) { return ,@() }

    $files = @()
    foreach ($line in $section -split "`r?`n") {
        $trim = $line.Trim()
        if (-not $trim) { continue }
        # match "- `path` ..."  or "- path ..."
        $m2 = [regex]::Match($trim, '^\-\s+`([^`]+)`')
        if ($m2.Success) { $files += $m2.Groups[1].Value; continue }
        $m3 = [regex]::Match($trim, '^\-\s+([^\s\(\)]+)')
        if ($m3.Success -and $m3.Groups[1].Value -ne '(no') { $files += $m3.Groups[1].Value }
    }
    return ,@($files | Where-Object { $_ } | Sort-Object -Unique)
}

function Jaccard {
    param([string[]]$A, [string[]]$B)
    if ((-not $A -or $A.Count -eq 0) -and (-not $B -or $B.Count -eq 0)) { return 1.0 }
    $setA = [System.Collections.Generic.HashSet[string]]::new([string[]]$A)
    $setB = [System.Collections.Generic.HashSet[string]]::new([string[]]$B)
    $inter = [System.Collections.Generic.HashSet[string]]::new($setA)
    $null = $inter.IntersectWith($setB)
    $union = [System.Collections.Generic.HashSet[string]]::new($setA)
    $null = $union.UnionWith($setB)
    if ($union.Count -eq 0) { return 0.0 }
    return [double]$inter.Count / [double]$union.Count
}

function LevenshteinRatio {
    # Normalized similarity 0..1 — 1.0 means identical.
    # Converts to char arrays up front because under Set-StrictMode -Version Latest
    # on PS 5.1, [string][index] access can throw IndexOutOfRangeException even for
    # valid indices. ToCharArray() materializes into a proper [char[]] that indexes
    # cleanly under strict mode.
    param([string]$A, [string]$B)
    if (-not $A) { $A = "" }
    if (-not $B) { $B = "" }
    $n = $A.Length; $m = $B.Length
    $max = [Math]::Max($n, $m)
    if ($max -eq 0) { return 1.0 }
    # For large strings this is too slow; cap to first 4000 chars
    $cap = 4000
    if ($n -gt $cap) { $A = $A.Substring(0, $cap); $n = $cap }
    if ($m -gt $cap) { $B = $B.Substring(0, $cap); $m = $cap }
    $ca = $A.ToCharArray()
    $cb = $B.ToCharArray()
    $d = New-Object 'int[,]' ($n + 1), ($m + 1)
    for ($i = 0; $i -le $n; $i++) { $d[$i, 0] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[0, $j] = $j }
    for ($i = 1; $i -le $n; $i++) {
        $im1 = $i - 1
        for ($j = 1; $j -le $m; $j++) {
            $jm1 = $j - 1
            $cost = if ($ca[$im1] -eq $cb[$jm1]) { 0 } else { 1 }
            $a = $d[$im1, $j]    + 1
            $b = $d[$i,   $jm1]  + 1
            $c = $d[$im1, $jm1]  + $cost
            $d[$i, $j] = [Math]::Min([Math]::Min($a, $b), $c)
        }
    }
    $dist = $d[$n, $m]
    return 1.0 - ([double]$dist / [double][Math]::Max($n, $m))
}

function Get-PhaseInvocationCounts {
    # Infer CLI invocations per provider from state.history phase transitions.
    # v1 heuristic: assume one invocation per phase entry where a model would be called
    # (compose, bounce-*, arbitrate, execute, verify-*, fix-*). Partition by roles.
    param($State, $Case)

    $composer = Get-CaseValue $Case @('runner','composer') 'codex'
    $reviewer = Get-CaseValue $Case @('runner','reviewer') 'codex'
    $executor = Get-CaseValue $Case @('runner','executor') 'codex'

    $counts = @{ codex = 0; claude = 0; ollama = 0 }
    foreach ($entry in @($State.history)) {
        $phase = [string]$entry.phase
        $provider = switch -Regex ($phase) {
            '^compose'       { $composer; break }
            '^bounce'        {
                # bounce alternates reviewer/resolver; split 50/50 across composer/reviewer for v1
                if ($composer -eq $reviewer) { $composer } else { '_alternating_' }
                break
            }
            '^arbitrate'     { $composer; break }
            '^execute'       { $executor; break }
            '^verify'        { 'codex'; break }  # review uses codex regardless (see runner)
            '^fix'           { $executor; break }
            default          { $null }
        }
        if ($provider -eq '_alternating_') {
            # attribute half to each, but we only have integer counts; attribute to reviewer
            $counts[$reviewer]++
        } elseif ($provider) {
            if (-not $counts.ContainsKey($provider)) { $counts[$provider] = 0 }
            $counts[$provider]++
        }
    }
    return $counts
}

function Get-ProviderOutputBytes {
    param([string]$OutputsDir, $Case)
    # Approximate — sum output.txt sizes for phases, attribute by role-of-phase.
    if (-not (Test-Path -LiteralPath $OutputsDir)) { return @{ codex = 0; claude = 0 } }

    $composer = Get-CaseValue $Case @('runner','composer') 'codex'
    $executor = Get-CaseValue $Case @('runner','executor') 'codex'

    $bytes = @{ codex = 0; claude = 0 }
    Get-ChildItem -LiteralPath $OutputsDir -File -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.Name
        $provider = 'codex'
        if ($name -like 'compose*') { $provider = $composer }
        elseif ($name -like 'execute*' -or $name -like 'fix-*') { $provider = $executor }
        elseif ($name -like 'verify-*') { $provider = 'codex' }
        if (-not $bytes.ContainsKey($provider)) { $bytes[$provider] = 0 }
        $bytes[$provider] += [int64]$_.Length
    }
    return $bytes
}

# --- Score each dimension ---------------------------------------------------
$scores = [ordered]@{}
$details = [ordered]@{}

# Robustness
$robust = 'PASS'
$status = [string]$state.status
if ($status -ne 'completed') {
    $robust = 'FAIL'
}
# Any log with an unhandled exception?
$hadException = $false
if (Test-Path -LiteralPath $outputsDir) {
    Get-ChildItem -LiteralPath $outputsDir -Filter '*.log' -ErrorAction SilentlyContinue | ForEach-Object {
        $c = Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue
        if ($c -match '(?im)\bUnhandledException\b|\bFullyQualifiedErrorId\b.*\bRuntimeException\b') {
            $hadException = $true
        }
    }
}
if ($hadException -and $robust -eq 'PASS') { $robust = 'PARTIAL' }
$scores.robustness = $robust
$details.robustness = @{ status = $status; had_exception = $hadException }

# Convergence
# Two independent checks:
#   1. Final marker count must be 0 (the "markers converged" axiom).
#   2. If the case config expects bounces > 0, state.history must actually show
#      a bounce-* phase. Otherwise "converged in 0 bounces" is indistinguishable
#      from "bypassed the bounce step entirely" (Tier 4 regression A finding).
$finalMarkers = [int](Get-CaseValue $state @('marker_counts','total') 0)
$convergence = 'FAIL'
if ($finalMarkers -eq 0) { $convergence = 'PASS' }
elseif ($finalMarkers -le 2) { $convergence = 'PARTIAL' }

# Structural bounce check
$requestedBounces = Get-CaseValue $case @('runner','bounces') 'auto'
$expectsBounces = $true
if ($requestedBounces -is [int]) {
    if ([int]$requestedBounces -le 0) { $expectsBounces = $false }
} elseif ([string]$requestedBounces -eq '0') {
    $expectsBounces = $false
}
# The runner writes a "bounce" phase to state.history BEFORE entering the loop,
# so history alone can't distinguish "loop ran 0 times" from "loop ran normally".
# Use the outputs directory as the structural signal: each iteration of the
# bounce loop writes outputs/bounce-NN.txt. No bounce-NN.txt files == loop never
# actually ran a pass (Tier 4 regression A). Fall back to the history check for
# fixtures that don't ship an outputs/ directory.
$bouncePhasesRan = $false
if (Test-Path -LiteralPath $outputsDir) {
    $bounceOutputs = @(Get-ChildItem -LiteralPath $outputsDir -Filter 'bounce-*.txt' -File -ErrorAction SilentlyContinue)
    if ($bounceOutputs.Count -gt 0) { $bouncePhasesRan = $true }
}
if (-not $bouncePhasesRan -and $state.PSObject.Properties.Name -contains 'history' -and $state.history) {
    foreach ($h in @($state.history)) {
        # Only 'bounce-NN' style phase entries (not the outer 'bounce' wrapper) prove a pass happened.
        if ([string]$h.phase -match '^bounce-\d+$') { $bouncePhasesRan = $true; break }
    }
}
$bounceStructuralOk = $true
if ($expectsBounces -and -not $bouncePhasesRan) {
    $convergence = 'FAIL'
    $bounceStructuralOk = $false
}

$scores.convergence = $convergence
$details.convergence = @{
    marker_counts = $state.marker_counts
    expects_bounces = $expectsBounces
    bounce_phases_ran = $bouncePhasesRan
    structural_ok = $bounceStructuralOk
}

# Plan quality
$minWords = [int](Get-CaseValue $case @('expectations','plan_quality','min_word_count') 120)
$headingGroups = Get-CaseValue $case @('expectations','plan_quality','must_contain_any') @(@('Plan','Approach','Strategy'), @('Risks','Concerns','Caveats'))
$words = @($planText -split '\s+' | Where-Object { $_ }).Count
$hasTodo = $planText -match '\b(TODO|TBD|FIXME)\b'
$headingsOk = $true
foreach ($group in $headingGroups) {
    $matched = $false
    foreach ($h in $group) {
        if ($planText -match ("(?m)^#+\s+" + [regex]::Escape($h))) { $matched = $true; break }
    }
    if (-not $matched) { $headingsOk = $false; break }
}
$planQuality = 'PASS'
if ($words -lt $minWords -or -not $headingsOk) { $planQuality = 'FAIL' }
elseif ($hasTodo) { $planQuality = 'PARTIAL' }
$scores.plan_quality = $planQuality
$details.plan_quality = @{ words = $words; min = $minWords; headings_ok = $headingsOk; has_todo_stub = $hasTodo }

# Execution fidelity
$planFiles = @(Get-FilesFromPlan -Plan $planText)
$changedFiles = @()
if ($state.PSObject.Properties.Name -contains 'changed_files' -and $state.changed_files) {
    # Wrap in @() to survive PS 5.1 pipeline-collapsing single-element arrays to scalars.
    $changedFiles = @(@($state.changed_files) | Where-Object { $_ })
}
$minJaccard = [double](Get-CaseValue $case @('expectations','execution_fidelity','min_jaccard') 0.5)
$jac = Jaccard -A $planFiles -B $changedFiles
$fidelity = 'FAIL'
if ($jac -ge $minJaccard) { $fidelity = 'PASS' }
elseif ($jac -ge ($minJaccard * 0.6)) { $fidelity = 'PARTIAL' }
# Special case: no-op plan and no changes → PASS
if (($planFiles.Count -eq 0) -and ($changedFiles.Count -eq 0)) { $fidelity = 'PASS' }
$scores.execution_fidelity = $fidelity
$details.execution_fidelity = @{ plan_files = $planFiles; changed_files = $changedFiles; jaccard = [Math]::Round($jac, 3) }

# Verify accuracy
$expected = Get-CaseValue $case @('expectations','verify_accuracy') $null
$verifyScore = 'N/A'
$verifyDetails = @{ verdict = $null; expected = $expected }
if ($expected) {
    if ($verdict -eq '__unparseable__') {
        $verifyScore = 'FAIL'
        $verifyDetails.reason = 'verdict.json unparseable'
    } elseif ($null -eq $verdict) {
        $verifyScore = 'FAIL'
        $verifyDetails.reason = 'no verdict.json (verify not run?)'
    } else {
        $verifyDetails.verdict = $verdict.verdict
        $mustCatch = [bool](Get-CaseValue $case @('expectations','verify_accuracy','must_catch_issue') $false)
        $keywords = @(Get-CaseValue $case @('expectations','verify_accuracy','issue_keywords') @())
        $allowedVerdicts = @(Get-CaseValue $case @('expectations','verify_accuracy','allow_verdict') @('APPROVED','REVISE'))

        $verdictOk = $allowedVerdicts -contains [string]$verdict.verdict
        $issuesText = ""
        if ($verdict.PSObject.Properties.Name -contains 'issues' -and $verdict.issues) {
            $issuesText = ($verdict.issues | ForEach-Object { ($_ | ConvertTo-Json -Compress -Depth 4) }) -join "`n"
        }
        $keywordHit = if ($keywords.Count -eq 0) { $true } else {
            $hit = $false
            foreach ($kw in $keywords) {
                if ($issuesText -match [regex]::Escape([string]$kw)) { $hit = $true; break }
            }
            $hit
        }

        if ($mustCatch) {
            if (([string]$verdict.verdict -eq 'REVISE') -and $keywordHit) { $verifyScore = 'PASS' }
            elseif (([string]$verdict.verdict -eq 'REVISE')) { $verifyScore = 'PARTIAL' }
            else { $verifyScore = 'FAIL' }
        } else {
            if ($verdictOk) { $verifyScore = 'PASS' } else { $verifyScore = 'FAIL' }
        }
        $verifyDetails.keyword_hit = $keywordHit
    }
}
$scores.verify_accuracy = $verifyScore
$details.verify_accuracy = $verifyDetails

# Cost
$maxWall = [int](Get-CaseValue $case @('expectations','cost','max_wall_clock_seconds') 900)
$wall = 0
if ($state.started_at -and $state.updated_at) {
    try {
        $start = [DateTime]::Parse($state.started_at)
        $end = [DateTime]::Parse($state.updated_at)
        $wall = [int]($end - $start).TotalSeconds
    } catch { }
}
$invocations = Get-PhaseInvocationCounts -State $state -Case $case
$providerBytes = Get-ProviderOutputBytes -OutputsDir $outputsDir -Case $case
$cost = 'PASS'
if ($wall -gt $maxWall) { $cost = 'PARTIAL' }
if ($wall -gt ($maxWall * 1.5)) { $cost = 'FAIL' }
$scores.cost = $cost
$details.cost = @{ wall_clock_seconds = $wall; max = $maxWall; invocations = $invocations; provider_bytes = $providerBytes }

# Cross-AI diversity
$composer = [string](Get-CaseValue $case @('runner','composer') 'codex')
$reviewer = [string](Get-CaseValue $case @('runner','reviewer') 'codex')
$crossAi = 'N/A'
$crossDetails = @{ composer = $composer; reviewer = $reviewer }
if ($composer -ne $reviewer) {
    $composeOut = Join-Path $outputsDir "compose.txt"
    $firstBounce = Get-ChildItem -LiteralPath $outputsDir -Filter 'bounce-*.txt' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
    if ((Test-Path -LiteralPath $composeOut) -and $firstBounce) {
        $composeText = Get-Content -Raw -LiteralPath $composeOut
        $bounceText = Get-Content -Raw -LiteralPath $firstBounce.FullName
        $similarity = LevenshteinRatio -A $composeText -B $bounceText
        $minEdit = [double](Get-CaseValue $case @('expectations','cross_ai_diversity','min_edit_distance') 0.15)
        $changeRatio = 1.0 - $similarity
        $crossDetails.similarity = [Math]::Round($similarity, 3)
        $crossDetails.change_ratio = [Math]::Round($changeRatio, 3)
        $crossDetails.min_edit = $minEdit
        if ($changeRatio -ge $minEdit) { $crossAi = 'PASS' }
        elseif ($changeRatio -ge ($minEdit * 0.5)) { $crossAi = 'PARTIAL' }
        else { $crossAi = 'FAIL' }
    } else {
        $crossAi = 'FAIL'
        $crossDetails.reason = 'missing compose or first bounce output'
    }
}
$scores.cross_ai_diversity = $crossAi
$details.cross_ai_diversity = $crossDetails

# Composite
$weight = @{
    cross_ai_diversity = 1
    convergence = 1
    plan_quality = 1
    execution_fidelity = 1
    verify_accuracy = 1
    cost = 1
    robustness = 2
}
$valueOf = @{ PASS = 1.0; PARTIAL = 0.5; FAIL = 0.0; 'N/A' = $null }
$sumW = 0.0; $sumS = 0.0
foreach ($k in $scores.Keys) {
    $v = $valueOf[$scores[$k]]
    if ($null -eq $v) { continue }
    $w = $weight[$k]
    $sumW += $w; $sumS += $w * $v
}
$composite = if ($sumW -gt 0) { [Math]::Round($sumS / $sumW, 3) } else { 0 }

# --- Write scores.json ------------------------------------------------------
$result = [ordered]@{
    case_id = [string](Get-CaseValue $case @('id') 'unknown')
    title   = [string](Get-CaseValue $case @('title') '')
    run_id  = [string]$state.run_id
    scores  = $scores
    composite = $composite
    details = $details
    scored_at = (Get-Date -Format "o")
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    $null = New-Item -ItemType Directory -Path $OutputDir -Force
}
$scoresPath = Join-Path $OutputDir "scores.json"
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $scoresPath -Encoding UTF8

Write-Host ("[{0}] composite={1}  {2}" -f $result.case_id, $composite, (($scores.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '))

return $result
