# Echo AI Toolkit — verify what is actually installed (Windows / PowerShell)
#
#   .\scripts\echo-doctor.ps1
#
# Read-only. Reports one line per tool: present, missing, or not applicable.
$ErrorActionPreference = 'Continue'

$EchoHome = if ($env:ECHO_HOME) { $env:ECHO_HOME } else { Join-Path $HOME '.local\share\echo-ai-toolkit' }

$script:Pass = 0; $script:Miss = 0; $script:Na = 0

function Have { param($c) $null -ne (Get-Command $c -ErrorAction SilentlyContinue) }

function Row($status, $label, $detail) {
    $tag = switch ($status) {
        'ok'   { $script:Pass++; Write-Host '  ok    ' -ForegroundColor Green   -NoNewline }
        'miss' { $script:Miss++; Write-Host '  MISS  ' -ForegroundColor Red     -NoNewline }
        'na'   { $script:Na++;   Write-Host '  n/a   ' -ForegroundColor Magenta -NoNewline }
    }
    Write-Host ('{0,-28} {1}' -f $label, $detail)
}

Write-Host "`nEcho AI Toolkit - doctor"
Write-Host "tools: $EchoHome`n"

Write-Host 'Plugin'
if (Have claude) {
    $list = (claude plugin list 2>&1 | Out-String)
    if ($list -match 'echo-ai-toolkit') { Row ok 'echo-ai-toolkit plugin' 'installed' }
    else { Row miss 'echo-ai-toolkit plugin' 'run install.ps1' }
    foreach ($p in 'ponytail','andrej-karpathy-skills') {
        if ($list -match [regex]::Escape($p)) { Row ok "$p plugin" '' } else { Row na "$p plugin" 'optional' }
    }
} else {
    Row miss 'claude CLI' 'https://claude.com/claude-code'
}

Write-Host "`nMCP servers"
if (Test-Path (Join-Path $EchoHome 'mcp.json')) { Row ok 'mcp.json' (Join-Path $EchoHome 'mcp.json') }
else { Row miss 'mcp.json' 'run install.ps1' }

if (Test-Path (Join-Path $EchoHome 'mcp-gamehacking\dist\index.js')) { Row ok 'mcp-gamehacking' 'built' }
elseif (Test-Path (Join-Path $EchoHome 'mcp-gamehacking')) { Row miss 'mcp-gamehacking' 'cloned but not built' }
else { Row miss 'mcp-gamehacking' 'not installed' }

if (Test-Path (Join-Path $EchoHome 'angel-menu-mcp\index.js')) { Row ok 'angel-menu-mcp' 'installed' }
else { Row miss 'angel-menu-mcp' 'not installed' }

if (Have npx) { Row ok 'rea (npx)' 'installs on first use' } else { Row miss 'rea (npx)' 'needs Node' }

Write-Host "`nEcho tooling"
if (Test-Path (Join-Path $EchoHome 'bin\as_bundler.exe')) { Row ok 'as_bundler' (Join-Path $EchoHome 'bin\as_bundler.exe') }
else { Row miss 'as_bundler' 'not installed' }

$esp = Join-Path $env:APPDATA 'scripts\esp_preview.as'
if (Test-Path $esp) { Row ok 'esp_preview.as' $esp }
elseif (Test-Path (Join-Path $EchoHome 'reference\esp_preview.as')) { Row ok 'esp_preview.as' (Join-Path $EchoHome 'reference\esp_preview.as') }
else { Row miss 'esp_preview.as' 'not installed' }

if (Have code) {
    if ((code --list-extensions 2>&1 | Out-String) -match 'echo-angelscript-lsp') { Row ok 'echo-angelscript-lsp' 'VS Code extension' }
    else { Row miss 'echo-angelscript-lsp' 'not installed' }
} else { Row na 'echo-angelscript-lsp' 'VS Code not on PATH' }

if (Have bun) {
    if (Test-Path (Join-Path $EchoHome 'web-mv\relay\node_modules')) { Row ok 'web-mv' 'bun install done' }
    else { Row miss 'web-mv' 'run install.ps1' }
} else { Row na 'web-mv' 'needs Bun' }

Write-Host "`nPython tooling"
$py = if (Have python) { 'python' } elseif (Have py) { 'py' } else { $null }
if ($py) {
    $hasTriton = $false
    try { & $py -c 'import triton' 2>$null; $hasTriton = ($LASTEXITCODE -eq 0) } catch {}
    if ($hasTriton) { Row ok 'triton' 'installed' } else { Row miss 'triton' 'pip install triton-library' }

    foreach ($d in 'VMProtect-devirtualization','vmp-lazy-unpack') {
        if (Test-Path (Join-Path $EchoHome $d)) { Row ok $d 'cloned' } else { Row miss $d 'not installed' }
    }
} else { Row na 'python tooling' 'python not found' }

Write-Host "`nCompiler-built tooling"
foreach ($d in 'VTIL-Core','NoVmp','vtil2') {
    if (Test-Path (Join-Path $EchoHome $d)) { Row ok $d 'source' } else { Row na $d 'tier: full' }
}
if ((Have llvm-config) -or (Have opt)) { Row ok 'LLVM' 'present' } else { Row na 'LLVM' 'only for Triton LLVM interface' }

Write-Host "`nReference docs"
foreach ($d in 'gamehacking-cheatsheet','awesome-game-security') {
    if (Test-Path (Join-Path $EchoHome "reference\$d")) { Row ok $d 'cloned' } else { Row miss $d 'not installed' }
}

Write-Host ''
Write-Host ("  {0} ok   {1} missing   {2} not applicable`n" -f $script:Pass, $script:Miss, $script:Na)
if ($script:Miss -eq 0) { Write-Host '  Everything present.'; exit 0 }
Write-Host '  Run .\install.ps1 to fill the gaps ($env:ECHO_TIER="full" for the compiler-built tools).'
exit 0
