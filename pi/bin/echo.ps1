# echo — the Echo toolkit CLI (Windows / PowerShell)
#
#   echo                     start Pi with the Echo profile
#   echo <pi args…>          pass everything through to Pi
#   echo -- <pi args…>       force pass-through (for prompts that look like commands)
#
#   echo update [flags]      update toolkit, profile, Pi, and the pinned tools
#   echo doctor              verify what is installed
#   echo status              one-screen summary
#   echo tools               list installed companion tools
#   echo version             versions of everything
#   echo help                this message
#
# `echo update` flags: --extensions --self --models --all --force (Pi's own)
#                      --tools --profile --lock (Echo's)
#
# The Pi profile lives in $env:ECHO_HOME\pi and is selected with
# PI_CODING_AGENT_DIR, so your normal `pi` configuration is left untouched.
# The subcommands live in echo.mjs — one implementation for every platform.
$ErrorActionPreference = 'Continue'

$EchoHome   = if ($env:ECHO_HOME) { $env:ECHO_HOME } else { Join-Path $HOME '.local\share\echo-ai-toolkit' }
$ProfileDir = Join-Path $EchoHome 'pi'
$SelfDir    = $PSScriptRoot

function Have { param($c) $null -ne (Get-Command $c -ErrorAction SilentlyContinue) }

function Find-Cli {
    foreach ($cand in @((Join-Path $SelfDir 'echo.mjs'),
                        (Join-Path $SelfDir '..\..\scripts\echo.mjs'),
                        (Join-Path $EchoHome 'bin\echo.mjs'))) {
        if (Test-Path $cand) { return $cand }
    }
    return $null
}

$rest = @($args)
if ($rest.Count -gt 0 -and $rest[0] -eq '--') {
    $rest = @($rest | Select-Object -Skip 1)
} elseif ($rest.Count -gt 0 -and $rest[0] -in @('update','doctor','status','tools','version','--version','-V','help','--help','-h')) {
    $cmd  = $rest[0]
    $tail = @($rest | Select-Object -Skip 1)
    $cli = Find-Cli
    if (-not $cli) { Write-Host 'echo: echo.mjs not found (re-run the installer)' -ForegroundColor Red; exit 1 }
    if (-not (Have node)) { Write-Host 'echo: node not found - the CLI needs Node 18+' -ForegroundColor Red; exit 1 }
    & node $cli $cmd @tail
    exit $LASTEXITCODE
}

# ── default: launch Pi ───────────────────────────────────────────────────────
if (-not (Have pi)) {
    Write-Host @'
echo: `pi` is not installed.

  powershell -c "irm https://pi.dev/install.ps1 | iex"
  # or: npm install -g --ignore-scripts @earendil-works/pi-coding-agent

Pi needs Node.js 22.19 or newer. Everything else still works:
  echo doctor    verify the toolkit
  echo update    update everything
'@ -ForegroundColor Red
    exit 127
}

if (-not (Test-Path (Join-Path $ProfileDir 'SYSTEM.md'))) {
    Write-Host "echo: Echo profile missing at $ProfileDir" -ForegroundColor Red
    Write-Host "Re-run the toolkit installer, or:  echo update --profile"
    exit 1
}

$env:PI_CODING_AGENT_DIR = $ProfileDir

$piArgs = @('--system-prompt', (Join-Path $ProfileDir 'SYSTEM.md'))
$append = Join-Path $ProfileDir 'APPEND_SYSTEM.md'
if (Test-Path $append) { $piArgs += @('--append-system-prompt', $append) }

& pi @piArgs @rest
exit $LASTEXITCODE
