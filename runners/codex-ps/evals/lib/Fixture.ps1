# Fixture.ps1 — create and tear down isolated working directories for eval runs.
#
# Each eval case gets a fresh directory under evals/fixtures/tmp/{case-id}-{ts}/
# that contains a COPY of the runner's scripts/templates/schemas so the runner
# can derive its repo root from its own script location without touching the
# real codex-co-evolution repo. Any seed files declared by the case are written
# inside the fixture before the runner is invoked.

function New-Fixture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,       # the real codex-co-evolution repo root

        [Parameter(Mandatory = $true)]
        [string]$CaseId,

        [Parameter(Mandatory = $true)]
        [string]$RunTimestamp,

        [object]$SeedFiles = $null,  # list of @{ path; content } maps

    [object]$CopyFrom = $null    # list of @{ source; dest } maps — copy an external file in
    )

    $fixtureBase = Join-Path $ProjectRoot "evals/fixtures/tmp"
    $null = New-Item -ItemType Directory -Path $fixtureBase -Force

    $fixtureDir = Join-Path $fixtureBase ("{0}-{1}" -f $CaseId, $RunTimestamp)
    if (Test-Path -LiteralPath $fixtureDir) {
        Remove-Item -LiteralPath $fixtureDir -Recurse -Force
    }
    $null = New-Item -ItemType Directory -Path $fixtureDir -Force

    # Copy the runner's execution surface into the fixture
    foreach ($sub in @('scripts', 'templates', 'schemas')) {
        $src = Join-Path $ProjectRoot $sub
        if (Test-Path -LiteralPath $src) {
            Copy-Item -Path $src -Destination $fixtureDir -Recurse -Force
        }
    }

    # Initialize a git repo in the fixture so execute/verify phases have git.
    # Git often prints to stderr (LF/CRLF warnings, hint lines) which PS 5.1 treats
    # as NativeCommandError under strict mode — wrap in a saved-pref block.
    Push-Location $fixtureDir
    $prevErr = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & git -c core.autocrlf=false -c advice.detachedHead=false init --quiet 2>&1 | Out-Null
        & git config user.email "eval@codex-co-evolution.local" 2>&1 | Out-Null
        & git config user.name "Eval Harness" 2>&1 | Out-Null
        & git config core.autocrlf false 2>&1 | Out-Null
    } finally {
        $ErrorActionPreference = $prevErr
        Pop-Location
    }

    $touchedAny = $false

    # Seed files (inline content)
    if ($SeedFiles) {
        foreach ($seed in $SeedFiles) {
            $relPath = $seed.path
            $content = $seed.content
            if (-not $relPath) { continue }

            $target = Join-Path $fixtureDir $relPath
            $parent = Split-Path -Parent $target
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                $null = New-Item -ItemType Directory -Path $parent -Force
            }
            Set-Content -LiteralPath $target -Value ($content -as [string]) -Encoding UTF8
            $touchedAny = $true
        }
    }

    # Copy external files (e.g. a real doc from a sibling repo for a bounce-only case)
    if ($CopyFrom) {
        foreach ($c in $CopyFrom) {
            $src = $c.source
            $dst = $c.dest
            if (-not $src -or -not $dst) { continue }
            if (-not (Test-Path -LiteralPath $src)) {
                throw "copy_from source not found: $src"
            }
            $target = Join-Path $fixtureDir $dst
            $parent = Split-Path -Parent $target
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                $null = New-Item -ItemType Directory -Path $parent -Force
            }
            Copy-Item -LiteralPath $src -Destination $target -Force
            $touchedAny = $true
        }
    }

    if ($touchedAny) {
        # Commit seed so execute's delta tracking sees a clean baseline
        Push-Location $fixtureDir
        $prevErr = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & git add -A 2>&1 | Out-Null
            & git commit -m "seed" --quiet 2>&1 | Out-Null
        } finally {
            $ErrorActionPreference = $prevErr
            Pop-Location
        }
    }

    return $fixtureDir
}

function Remove-Fixture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FixtureDir,

        [bool]$Keep = $false
    )

    if ($Keep) {
        Write-Host "  (fixture preserved at $FixtureDir)"
        return
    }

    if (Test-Path -LiteralPath $FixtureDir) {
        # Windows sometimes refuses to remove read-only .git objects; chmod them
        Get-ChildItem -LiteralPath $FixtureDir -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
        Remove-Item -LiteralPath $FixtureDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Copy-RunArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FixtureDir,

        [Parameter(Mandatory = $true)]
        [string]$DestDir
    )

    $runsRoot = Join-Path $FixtureDir ".co-evolution/runs"
    if (-not (Test-Path -LiteralPath $runsRoot)) {
        throw "No run directory produced in fixture: $runsRoot"
    }

    # The runner always creates a single run dir per invocation — pick the newest
    $runDir = Get-ChildItem -LiteralPath $runsRoot -Directory | Sort-Object Name | Select-Object -Last 1
    if (-not $runDir) {
        throw "Runs root exists but is empty: $runsRoot"
    }

    if (Test-Path -LiteralPath $DestDir) {
        Remove-Item -LiteralPath $DestDir -Recurse -Force
    }
    $null = New-Item -ItemType Directory -Path $DestDir -Force
    Copy-Item -Path (Join-Path $runDir.FullName "*") -Destination $DestDir -Recurse -Force

    return $runDir.Name
}
