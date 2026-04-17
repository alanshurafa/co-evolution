# Yaml.ps1 — dependency check + thin YAML helpers
# Relies on powershell-yaml module. Fails fast with install instructions.

function Ensure-YamlModule {
    if (-not (Get-Module -Name powershell-yaml)) {
        $available = Get-Module -ListAvailable -Name powershell-yaml
        if (-not $available) {
            throw @"
Module 'powershell-yaml' is not installed.

Install it with:
  Install-Module -Name powershell-yaml -Scope CurrentUser -Force

Then re-run this script.
"@
        }
        Import-Module powershell-yaml -ErrorAction Stop | Out-Null
    }
}

function Read-YamlFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Ensure-YamlModule

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "YAML file not found: $Path"
    }

    $raw = Get-Content -Raw -LiteralPath $Path
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @{}
    }

    try {
        $result = ConvertFrom-Yaml -Yaml $raw -Ordered
    } catch {
        throw "Failed to parse YAML '$Path': $($_.Exception.Message)"
    }

    if ($null -eq $result) { return @{} }
    return $result
}

function Merge-HashtablesDeep {
    # Deep-merge two hashtables. $override wins on conflict. Non-hashtable values are replaced wholesale (lists are NOT concatenated).
    param(
        [Parameter(Mandatory = $true)]
        $Base,
        [Parameter(Mandatory = $true)]
        $Override
    )

    # Normalize: treat PSCustomObject and IDictionary alike
    function _IsMap($v) {
        return ($v -is [System.Collections.IDictionary]) -or ($v -is [pscustomobject] -and $false)
    }

    if (-not (_IsMap $Base))     { return $Override }
    if (-not (_IsMap $Override)) { return $Override }

    $result = [ordered]@{}
    foreach ($k in $Base.Keys)     { $result[$k] = $Base[$k] }
    foreach ($k in $Override.Keys) {
        if ($result.Contains($k) -and (_IsMap $result[$k]) -and (_IsMap $Override[$k])) {
            $result[$k] = Merge-HashtablesDeep -Base $result[$k] -Override $Override[$k]
        } else {
            $result[$k] = $Override[$k]
        }
    }
    return $result
}
