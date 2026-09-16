param([Parameter(Mandatory=$true)][string]$RunRoot)
$ErrorActionPreference='Stop'
$started=(Get-Date).ToUniversalTime().ToString('o')
$exitCode=1
try {
    if(Test-Path Env:ANTHROPIC_API_KEY){throw 'ANTHROPIC_API_KEY must be unset'}
    & 'C:/Users/alan/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -u -B "$RunRoot/runtime/run.py" run --root $RunRoot
    $exitCode=$LASTEXITCODE
} catch { Write-Error $_ -ErrorAction Continue }
finally {
    @{started=$started;finished=(Get-Date).ToUniversalTime().ToString('o');supervisor_pid=$PID;exit_code=$exitCode}|ConvertTo-Json|Set-Content -LiteralPath "$RunRoot/controller.exit.json" -Encoding utf8
}
exit $exitCode
