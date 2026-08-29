if ($MyInvocation.InvocationName -eq '.') {
    [Console]::Error.WriteLine('glm: run this launcher; do not dot-source it into the caller shell.')
    return
}

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Stop-Glm {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message,

        [int] $ExitCode = 1
    )

    [Console]::Error.WriteLine("glm: $Message")
    exit $ExitCode
}

function Get-ZaiApiKey {
    $processKey = [Environment]::GetEnvironmentVariable('ZAI_API_KEY', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($processKey)) {
        return $processKey
    }

    # Parse only the named assignment. Executing or dot-sourcing .env.local
    # would import unrelated values into this process.
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $envFile = Join-Path $repoRoot '.env.local'
    if (-not [IO.File]::Exists($envFile)) {
        return $null
    }

    foreach ($line in [IO.File]::ReadLines($envFile)) {
        if ($line -notmatch '^\s*(?:export\s+)?ZAI_API_KEY\s*=\s*(.*)\s*$') {
            continue
        }

        $candidate = $Matches[1].Trim()
        if ($candidate.Length -ge 2) {
            $first = $candidate.Substring(0, 1)
            $last = $candidate.Substring($candidate.Length - 1, 1)
            if (($first -eq '"' -and $last -eq '"') -or
                ($first -eq "'" -and $last -eq "'")) {
                $candidate = $candidate.Substring(1, $candidate.Length - 2)
            }
        }

        return $candidate
    }

    return $null
}

$zaiApiKey = Get-ZaiApiKey
if ([string]::IsNullOrWhiteSpace($zaiApiKey)) {
    Stop-Glm 'ZAI_API_KEY is not set and was not found in the repository .env.local file.' 78
}

$claudeCommand = Get-Command -Name 'claude' -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -eq $claudeCommand) {
    Stop-Glm 'Claude CLI was not found on PATH. Install Claude Code before using this launcher.' 127
}

$configDir = Join-Path $HOME '.claude-glm'

# Run a fresh PowerShell process with a private environment block. This avoids
# even temporary ANTHROPIC_* or CLAUDE_CONFIG_DIR changes in the caller shell,
# while still letting PowerShell invoke Windows .cmd shims correctly.
$payload = @{
    ClaudePath = $claudeCommand.Source
    Arguments = @($args)
} | ConvertTo-Json -Compress -Depth 3
$payloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))

$childScript = @"
`$ProgressPreference = 'SilentlyContinue'
`$payloadJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$payloadBase64'))
`$invocation = `$payloadJson | ConvertFrom-Json
`$claudeArgs = @('--safe-mode', '--model', 'glm-5.3-flash') + @(`$invocation.Arguments)
& `$invocation.ClaudePath @claudeArgs
if (`$null -ne `$LASTEXITCODE) { exit `$LASTEXITCODE }
if (-not `$?) { exit 1 }
"@
$encodedChild = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))

$hostExecutable = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$startInfo = New-Object Diagnostics.ProcessStartInfo
$startInfo.FileName = $hostExecutable
$startInfo.Arguments = "-NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedChild"
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $false
@(
    'ANTHROPIC_API_KEY',
    'ANTHROPIC_CUSTOM_HEADERS',
    'CLAUDE_CODE_OAUTH_TOKEN',
    'CLAUDE_CODE_USE_BEDROCK',
    'CLAUDE_CODE_USE_VERTEX',
    'CLAUDE_CODE_USE_FOUNDRY'
) | ForEach-Object { $startInfo.EnvironmentVariables.Remove($_) }
$startInfo.EnvironmentVariables['ANTHROPIC_BASE_URL'] = 'https://api.z.ai/api/anthropic'
$startInfo.EnvironmentVariables['ANTHROPIC_AUTH_TOKEN'] = $zaiApiKey
$startInfo.EnvironmentVariables['CLAUDE_CONFIG_DIR'] = $configDir

$process = New-Object Diagnostics.Process
$process.StartInfo = $startInfo
try {
    [void] $process.Start()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
}
catch {
    Stop-Glm "failed to start the Claude CLI: $($_.Exception.Message)" 126
}
finally {
    $process.Dispose()
}

exit $exitCode
