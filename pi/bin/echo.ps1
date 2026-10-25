# echo — launch Pi with the Echo profile (Windows / PowerShell)
#
#   echo                     interactive session
#   echo -p "query"          print mode
#   echo --help              pass anything straight through to pi
#
# Both prompt files are passed explicitly with Pi's own flags, so they apply even
# if file discovery changes:
#   --system-prompt         replaces Pi's default prompt
#   --append-system-prompt  appended to it (repeatable)
#
# The profile lives in $env:ECHO_HOME\pi and is selected with
# PI_CODING_AGENT_DIR, so your normal `pi` configuration is left untouched.

$EchoHome = if ($env:ECHO_HOME) { $env:ECHO_HOME } else { Join-Path $HOME '.local\share\echo-ai-toolkit' }
$ProfileDir = Join-Path $EchoHome 'pi'

if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
    Write-Host @'
echo: `pi` is not installed.

  powershell -c "irm https://pi.dev/install.ps1 | iex"
  # or: npm install -g --ignore-scripts @earendil-works/pi-coding-agent

Pi needs Node.js 22.19 or newer.
'@ -ForegroundColor Red
    exit 127
}

if (-not (Test-Path (Join-Path $ProfileDir 'SYSTEM.md'))) {
    Write-Host "echo: Echo profile missing at $ProfileDir" -ForegroundColor Red
    Write-Host "Re-run the toolkit installer, or: `$env:ECHO_HOME='$EchoHome'; .\install.ps1"
    exit 1
}

$env:PI_CODING_AGENT_DIR = $ProfileDir

$piArgs = @('--system-prompt', (Join-Path $ProfileDir 'SYSTEM.md'))
$append = Join-Path $ProfileDir 'APPEND_SYSTEM.md'
if (Test-Path $append) { $piArgs += @('--append-system-prompt', $append) }

& pi @piArgs @args
exit $LASTEXITCODE
