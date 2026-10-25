# Echo AI Toolkit — one-command installer (Windows / PowerShell)
#
#   irm https://raw.githubusercontent.com/NetVar1337/echo-ai-toolkit/main/install.ps1 | iex
#
# Installs the plugin into Claude Code and vendors its optional MCP dependencies.
# Safe to re-run: every step is idempotent.
$ErrorActionPreference = 'Stop'

$Repo       = 'NetVar1337/echo-ai-toolkit'
$Marketplace = 'echo-ai-toolkit'
$Plugin     = 'echo-ai-toolkit'
$Deps       = Join-Path $HOME '.local\share\echo-ai-toolkit'

function Say  { Write-Host "==> $args" -ForegroundColor Yellow }
function Ok   { Write-Host "  OK $args" -ForegroundColor Green }
function Warn { Write-Host "  !  $args" -ForegroundColor Magenta }
function Die  { Write-Host "  X  $args" -ForegroundColor Red; exit 1 }

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Die "claude CLI not found. Install Claude Code first: https://claude.com/claude-code"
}
if (-not (Get-Command node    -ErrorAction SilentlyContinue)) {
    Die "node not found. Install Node.js 18+ first."
}
if (-not (Get-Command git    -ErrorAction SilentlyContinue)) {
    Die "git not found."
}

Say "Installing $Plugin plugin from marketplace $Repo"

# ── 1. marketplace ───────────────────────────────────────────────────────────
$markets = claude plugin marketplace list 2>&1 | Out-String
if ($markets -match $Marketplace) {
    Ok "marketplace '$Marketplace' already registered"
} else {
    claude plugin marketplace add $Repo | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "failed to add marketplace" }
    Ok "marketplace registered"
}

# ── 2. plugin ───────────────────────────────────────────────────────────────
$installed = claude plugin list 2>&1 | Out-String
if ($installed -match $Plugin) {
    Ok "plugin '$Plugin' already installed"
} else {
    claude plugin install "$Plugin@$Marketplace" | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "failed to install plugin" }
    Ok "plugin installed"
}

# ── 3. optional MCP dependencies ────────────────────────────────────────────
if ($env:SKIP_MCP -eq '1') {
    Warn "SKIP_MCP=1 - skipping optional MCP dependencies"
} else {
    New-Item -ItemType Directory -Force -Path $Deps | Out-Null

    $gh = Join-Path $Deps 'mcp-gamehacking'
    if (Test-Path (Join-Path $gh 'dist\index.js')) {
        Ok "mcp-gamehacking already built"
    } else {
        Say "Vendoring mcp-gamehacking (this takes a minute)"
        if (-not (Test-Path (Join-Path $gh '.git'))) {
            git clone --depth 1 https://github.com/1llu50ry/mcp-gamehacking $gh | Out-Null
        }
        if (Test-Path $gh) {
            Push-Location $gh
            npm install --silent
            npm run build --silent
            Pop-Location
            Ok "mcp-gamehacking built"
        } else {
            Warn "clone failed - skipping mcp-gamehacking"
        }
    }

    $angel = Join-Path $Deps 'angel-menu-mcp'
    if (Test-Path (Join-Path $angel 'node_modules')) {
        Ok "angel-menu-mcp already installed"
    } else {
        Say "Vendoring angel-menu-mcp"
        if (-not (Test-Path (Join-Path $angel '.git'))) {
            git clone --depth 1 https://github.com/Jozkah/angel-menu-mcp $angel | Out-Null
        }
        if (Test-Path $angel) {
            Push-Location $angel
            npm install --silent
            Pop-Location
            Ok "angel-menu-mcp installed"
        } else {
            Warn "clone failed - skipping angel-menu-mcp"
        }
    }
}

# ── 4. optional companion ────────────────────────────────────────────────────
$markets = claude plugin marketplace list 2>&1 | Out-String
if ($markets -match 'ponytail') {
    Ok "ponytail already registered"
} else {
    claude plugin marketplace add DietrichGebert/ponytail | Out-Null
    claude plugin install ponytail@ponytail | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok "ponytail installed (lazy-senior-dev mode)" }
    else { Warn "ponytail not installed - optional" }
}

Write-Host @"

------------------------------------------------------------
  Echo AI Toolkit is ready.

  Next:
    1. Restart Claude Code (or run /reload-plugins)
    2. Type  /echo-help        to list the 12 agents
    3. Type  /echo-esp         to load ESP context
       ...or just describe your task - keywords auto-route.

  Templates:  templates\*.as  -> copy into %AppData%\Roaming\scripts\
  Full API:   reference\api.md
------------------------------------------------------------
"@
