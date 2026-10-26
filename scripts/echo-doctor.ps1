# echo doctor — thin shim. The implementation is scripts/echo.mjs (one copy for
# every platform). Read-only.
$ErrorActionPreference = 'Continue'

$EchoHome = if ($env:ECHO_HOME) { $env:ECHO_HOME } else { Join-Path $HOME '.local\share\echo-ai-toolkit' }
$SelfDir  = $PSScriptRoot

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host 'echo: node not found - `echo doctor` needs Node 18+' -ForegroundColor Red
    exit 1
}

foreach ($cand in @((Join-Path $SelfDir 'echo.mjs'), (Join-Path $EchoHome 'bin\echo.mjs'))) {
    if (Test-Path $cand) { & node $cand doctor @args; exit $LASTEXITCODE }
}

Write-Host 'echo: echo.mjs not found next to this script' -ForegroundColor Red
exit 1
