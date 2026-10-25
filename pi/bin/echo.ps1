# echo — the Echo toolkit CLI (Windows / PowerShell)
#
#   echo                     start Pi with the Echo profile
#   echo <pi args…>          pass everything through to Pi
#   echo -- <pi args…>       force pass-through (for prompts that look like commands)
#
#   echo update [flags]      update toolkit, profile, Pi, and tools
#   echo doctor              verify what is installed
#   echo status              one-screen summary
#   echo tools               list installed companion tools
#   echo version             versions of everything
#   echo help                this message
#
# `echo update` flags: --extensions --self --models --all --force (Pi's own)
#                      --tools --profile (Echo's)
#
# The Pi profile lives in $env:ECHO_HOME\pi and is selected with
# PI_CODING_AGENT_DIR, so your normal `pi` configuration is left untouched.

$EchoHome  = if ($env:ECHO_HOME) { $env:ECHO_HOME } else { Join-Path $HOME '.local\share\echo-ai-toolkit' }
$ProfileDir = Join-Path $EchoHome 'pi'
$SelfDir   = $PSScriptRoot

function Have { param($c) $null -ne (Get-Command $c -ErrorAction SilentlyContinue) }
function Dim  { param($s) Write-Host $s -ForegroundColor Magenta -NoNewline }

function Show-Usage {
    Get-Content $PSCommandPath | Select-Object -Skip 1 |
        ForEach-Object { if ($_ -match '^#') { $_ -replace '^# ?', '' } else { break } } |
        Write-Host
}

function Invoke-Sibling($name) {
    foreach ($cand in @((Join-Path $SelfDir $name), (Join-Path $EchoHome "bin\$name"))) {
        if (Test-Path $cand) { & $cand @args; exit $LASTEXITCODE }
    }
    Write-Host "echo: $name not found next to this launcher" -ForegroundColor Red
    exit 1
}

function Show-Status {
    Write-Host ""
    Write-Host "Echo toolkit  $EchoHome" -ForegroundColor White
    Write-Host ""
    $prof = if (Test-Path (Join-Path $ProfileDir 'SYSTEM.md')) { 'ok' } else { 'missing' }
    $skills = (Get-ChildItem (Join-Path $ProfileDir 'skills') -Directory -ErrorAction SilentlyContinue).Count
    $prompts = (Get-ChildItem (Join-Path $ProfileDir 'prompts') -Filter *.md -ErrorAction SilentlyContinue).Count
    Write-Host ('  {0,-22} {1}' -f 'profile', $prof)
    Write-Host ('  {0,-22} {1}' -f 'skills', $skills)
    Write-Host ('  {0,-22} {1}' -f 'prompt templates', $prompts)
    Write-Host ('  {0,-22} {1}' -f 'launcher', (Join-Path $SelfDir (Split-Path $PSCommandPath -Leaf)))
    Write-Host ('  {0,-22} {1}' -f 'pi', $(if (Have pi) { (& pi --version 2>$null | Select-Object -First 1) } else { 'not installed' }))
    if (Have claude) {
        $p = ((claude plugin list 2>$null | Out-String) -split "`n" | Select-String 'echo-ai-toolkit@' | Select-Object -First 1)
        Write-Host ('  {0,-22} {1}' -f 'claude plugin', $(if ($p) { $p.ToString().Trim() } else { 'not installed' }))
    }
    Write-Host ""
    Write-Host "  Run 'echo doctor' for the full picture."
    Write-Host ""
}

function Show-Tools {
    Write-Host ""
    Write-Host "Companion tools" -ForegroundColor White
    Write-Host ""
    Write-Host ('  {0,-30} {1}' -f 'TOOL', 'STATUS')
    Write-Host ('  {0,-30} {1}' -f '----', '------')
    $rows = @(
        @('mcp-gamehacking',              'mcp-gamehacking\dist\index.js'),
        @('angel-menu-mcp',               'angel-menu-mcp\index.js'),
        @('as_bundler',                   'bin\as_bundler.exe'),
        @('esp_preview.as',               'reference\esp_preview.as'),
        @('web-mv',                       'web-mv\relay\node_modules'),
        @('VMProtect-devirtualization',   'VMProtect-devirtualization'),
        @('vmp-lazy-unpack',              'vmp-lazy-unpack'),
        @('VTIL-Core',                    'VTIL-Core'),
        @('NoVmp',                        'NoVmp'),
        @('vtil2',                        'vtil2'),
        @('awesome-game-security',        'reference\awesome-game-security.md'),
        @('gamehacking-cheatsheet',       'reference\gamehacking-cheatsheet.md')
    )
    foreach ($r in $rows) {
        $status = if (Test-Path (Join-Path $EchoHome $r[1])) { 'ok' } else { 'missing' }
        Write-Host ('  {0,-30} {1}' -f $r[0], $status)
    }
    Write-Host ""
    Write-Host "  Update with 'echo update --tools'"
    Write-Host ""
}

function Show-Version {
    Write-Host ""
    Write-Host ('  {0,-22} {1}' -f 'echo', '1.0.0')
    Write-Host ('  {0,-22} {1}' -f 'pi', $(if (Have pi) { (& pi --version 2>$null | Select-Object -First 1) } else { 'not installed' }))
    Write-Host ('  {0,-22} {1}' -f 'node', $(if (Have node) { & node -v } else { 'not installed' }))
    Write-Host ""
}

# ── dispatch ─────────────────────────────────────────────────────────────────
$rest = @($args)
if ($rest.Count -gt 0 -and $rest[0] -eq '--') {
    $rest = @($rest | Select-Object -Skip 1)
} elseif ($rest.Count -gt 0) {
    switch ($rest[0]) {
        'update'  { Invoke-Sibling 'echo-update.ps1' @($rest | Select-Object -Skip 1) }
        'doctor'  { Invoke-Sibling 'echo-doctor.ps1' @($rest | Select-Object -Skip 1) }
        'status'  { Show-Status; exit 0 }
        'tools'   { Show-Tools; exit 0 }
        { $_ -in 'version','--version','-V' } { Show-Version; exit 0 }
        { $_ -in 'help','--help','-h' }       { Show-Usage; exit 0 }
    }
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
