# Echo AI Toolkit — one-command installer (Windows / PowerShell)
#
#   irm https://raw.githubusercontent.com/NetVar1337/echo-ai-toolkit/main/install.ps1 | iex
#
# Installs the Claude Code plugin plus every companion tool, skipping anything
# whose prerequisite is missing on this machine. Safe to re-run: every step is
# idempotent.
#
# Tiers ($env:ECHO_TIER, default "standard"):
#   minimal   plugin + MCP servers                      (Node only)
#   standard  + Echo tooling, Python tooling, docs      (Node + Python)
#   full      + compiler-built tools, LLVM, web-mv      (Node + Python + compilers)
$ErrorActionPreference = 'Continue'

$Repo      = 'NetVar1337/echo-ai-toolkit'
$Plugin    = 'echo-ai-toolkit'
$Tier      = if ($env:ECHO_TIER) { $env:ECHO_TIER } else { 'standard' }
$EchoHome  = if ($env:ECHO_HOME) { $env:ECHO_HOME } else { Join-Path $HOME '.local\share\echo-ai-toolkit' }
$BinDir    = Join-Path $EchoHome 'bin'
$RefDir    = Join-Path $EchoHome 'reference'

$script:OK = @(); $script:Skipped = @(); $script:Failed = @()

function Say  { Write-Host "`n==> $args" -ForegroundColor Yellow }
function Ok   { param($m) $script:OK += $m;      Write-Host "    OK     $m" -ForegroundColor Green }
function Skip { param($m,$r) $script:Skipped += "${m}: $r"; Write-Host "    skip   $m - $r" -ForegroundColor Magenta }
function Fail { param($m,$r) $script:Failed += "${m}: $r";  Write-Host "    FAIL   $m - $r" -ForegroundColor Red }
function Have { param($c) $null -ne (Get-Command $c -ErrorAction SilentlyContinue) }

function TierAtLeast($t) {
    switch ($Tier) {
        'minimal'  { return $t -eq 'minimal' }
        'standard' { return $t -in @('minimal','standard') }
        default    { return $true }
    }
}

# ── 0. prerequisites ─────────────────────────────────────────────────────────
Say 'Checking prerequisites'
if (-not (Have claude)) {
    Write-Host "`nclaude CLI not found. Install Claude Code first: https://claude.com/claude-code" -ForegroundColor Red
    exit 1
}
Ok 'claude CLI'
if (Have node) { Ok "node $(& node -v)" } else { Skip 'node' 'not found - MCP servers need Node 18+' }
if (Have git)  { Ok 'git' } else { Skip 'git' 'not found - tool clones need git' }
if (Have python) { Ok "python $(& python -V 2>&1)" } elseif (Have py) { Ok 'py launcher' } else { Skip 'python' 'not found - Python tooling skipped' }
if (Have npm)  { Ok 'npm' } else { Skip 'npm' 'not found' }

New-Item -ItemType Directory -Force -Path $EchoHome, $BinDir, $RefDir | Out-Null

# ── 1. the plugin ────────────────────────────────────────────────────────────
Say "Installing the $Plugin plugin"
$markets = (claude plugin marketplace list 2>&1 | Out-String)
if ($markets -match [regex]::Escape($Plugin)) {
    Ok 'marketplace already registered'
} elseif ((claude plugin marketplace add $Repo 2>&1 | Out-String) -notmatch 'Failed|error') {
    Ok 'marketplace registered'
} else { Fail 'marketplace' "could not add $Repo" }

$installed = (claude plugin list 2>&1 | Out-String)
if ($installed -match [regex]::Escape($Plugin)) {
    Ok 'plugin already installed'
} elseif ((claude plugin install "$Plugin@$Plugin" 2>&1 | Out-String) -notmatch 'Failed|error') {
    Ok 'plugin installed'
} else { Fail 'plugin' 'install failed' }

# ── 2. Claude Code companion plugins ─────────────────────────────────────────
Say 'Claude Code companion plugins'
function AddPlugin($name, $marketplace, $pluginId) {
    $list = (claude plugin list 2>&1 | Out-String)
    if ($list -match [regex]::Escape("$name@")) { Ok "$name already installed"; return }
    $null = claude plugin marketplace add $marketplace 2>&1
    if ($LASTEXITCODE -ne 0) { Skip $name "marketplace $marketplace unreachable"; return }
    $null = claude plugin install "$pluginId@$pluginId" 2>&1
    if ($LASTEXITCODE -eq 0) { Ok $name } else { Skip $name 'install failed' }
}
AddPlugin 'ponytail' 'DietrichGebert/ponytail' 'ponytail'
AddPlugin 'andrej-karpathy-skills' 'forrestchang/andrej-karpathy-skills' 'andrej-karpathy-skills'

# ── 3. MCP servers ───────────────────────────────────────────────────────────
Say 'MCP servers'
function CloneBuildNode($name, $repo, $entry) {
    $dir = Join-Path $EchoHome $name
    if (Test-Path (Join-Path $dir $entry)) { Ok "$name already built"; return }
    if (-not (Test-Path (Join-Path $dir '.git'))) {
        git clone --depth 1 "https://github.com/$repo" $dir 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail $name 'clone failed'; return }
    }
    Push-Location $dir
    npm install --silent 2>&1 | Out-Null
    npm run build --silent 2>&1 | Out-Null
    Pop-Location
    if (Test-Path (Join-Path $dir $entry)) { Ok $name } else { Fail $name "expected $entry after build" }
}
if ((Have node) -and (Have npm)) {
    CloneBuildNode 'mcp-gamehacking' '1llu50ry/mcp-gamehacking' 'dist\index.js'
    CloneBuildNode 'angel-menu-mcp'  'Jozkah/angel-menu-mcp'    'index.js'
} else { Skip 'MCP servers' 'Node 18+ required' }

# ── 4. Echo-side tooling ─────────────────────────────────────────────────────
if (TierAtLeast 'standard') {
    Say 'Echo tooling'

    # as_bundler — prebuilt release binary.
    $AsOut = Join-Path $BinDir 'as_bundler.exe'
    if (Test-Path $AsOut) { Ok 'as_bundler already installed' }
    else {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri `
              'https://github.com/sinistercodes/as_bundler/releases/download/v1.5.0/as_bundler.exe' `
              -OutFile $AsOut -ErrorAction Stop
            Ok 'as_bundler v1.5.0'
        } catch { Fail 'as_bundler' 'download failed' }
    }

    # echo-esp-preview — single AngelScript drop-in, straight into the Echo scripts dir.
    try {
        $scripts = Join-Path $env:APPDATA 'scripts'
        New-Item -ItemType Directory -Force -Path $scripts | Out-Null
        Invoke-WebRequest -UseBasicParsing -Uri `
          'https://raw.githubusercontent.com/speedsunderscore/echo-esp-preview/HEAD/esp_preview.as' `
          -OutFile (Join-Path $scripts 'esp_preview.as') -ErrorAction Stop
        Ok "esp_preview.as -> $scripts"
    } catch { Fail 'esp_preview' 'download failed' }

    # echo-angelscript-lsp — VS Code extension.
    if (-not (Have code)) { Skip 'echo-angelscript-lsp' "VS Code 'code' CLI not on PATH" }
    elseif ((code --list-extensions 2>&1 | Out-String) -match 'echo-angelscript-lsp') {
        Ok 'echo-angelscript-lsp already installed'
    } else {
        $tmp = Join-Path $env:TEMP "echo-lsp-$(Get-Random)"
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $zip = Join-Path $tmp 'lsp.zip'
            Invoke-WebRequest -UseBasicParsing -Uri `
              'https://github.com/speedsunderscore/echo-angelscript-lsp/releases/download/0.0.10/echo-angelscript-lsp-0.0.10.zip' `
              -OutFile $zip -ErrorAction Stop
            Expand-Archive -Path $zip -DestinationPath $tmp -Force
            $vsix = Get-ChildItem $tmp -Filter *.vsix -Recurse | Select-Object -First 1
            if ($vsix) {
                code --install-extension $vsix.FullName --force 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { Ok 'echo-angelscript-lsp 0.0.10' } else { Fail 'echo-angelscript-lsp' 'install failed' }
            } else { Fail 'echo-angelscript-lsp' 'no .vsix in archive' }
        } catch { Fail 'echo-angelscript-lsp' 'download failed' }
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }

    # web-mv — Bun relay + SolidJS UI (source only; no releases published).
    if (-not (Have bun)) { Skip 'web-mv' 'Bun not installed (https://bun.sh)' }
    else {
        $dir = Join-Path $EchoHome 'web-mv'
        if (-not (Test-Path (Join-Path $dir '.git'))) {
            git clone --depth 1 https://github.com/Jozkah/web-mv $dir 2>&1 | Out-Null
        }
        if (Test-Path $dir) {
            Push-Location (Join-Path $dir 'relay'); bun install 2>&1 | Out-Null; $rc = $LASTEXITCODE; Pop-Location
            if ($rc -eq 0) { Ok "web-mv (run: cd `"$dir\relay`"; bun run start)" } else { Fail 'web-mv' 'bun install failed' }
        } else { Fail 'web-mv' 'clone failed' }
    }

    # Reference repos — offline copies of the two big knowledge bases.
    foreach ($pair in @(@('gamehacking-cheatsheet','ridpath/gamehacking-cheatsheet'),
                        @('awesome-game-security','gmh5225/awesome-game-security'))) {
        $name = $pair[0]; $dir = Join-Path $RefDir $name
        if (Test-Path (Join-Path $dir '.git')) { Ok "$name already cloned"; continue }
        git clone --depth 1 "https://github.com/$($pair[1])" $dir 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Ok $name } else { Fail $name 'clone failed' }
    }
}

# ── 5. Python reverse-engineering tooling ────────────────────────────────────
if (TierAtLeast 'standard') {
    Say 'Python reverse-engineering tooling'
    $py = if (Have python) { 'python' } elseif (Have py) { 'py' } else { $null }
    if (-not $py) { Skip 'Python tooling' 'python not found' }
    else {
        # Triton — the PyPI package is "triton-library" (NOT "triton", which is OpenAI's GPU compiler).
        $hasTriton = $false
        try { & $py -c 'import triton' 2>$null; $hasTriton = ($LASTEXITCODE -eq 0) } catch {}
        if ($hasTriton) { Ok 'triton already installed' }
        else {
            & $py -m pip install --quiet --disable-pip-version-check triton-library 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Ok 'triton (symbolic execution)' } else { Skip 'triton' 'pip install failed' }
        }

        foreach ($pair in @(@('VMProtect-devirtualization','JonathanSalwan/VMProtect-devirtualization'),
                            @('vmp-lazy-unpack','x86rc/vmp-lazy-unpack'))) {
            $name = $pair[0]; $dir = Join-Path $EchoHome $name
            if (Test-Path (Join-Path $dir '.git')) { Ok "$name already cloned" }
            else {
                git clone --depth 1 "https://github.com/$($pair[1])" $dir 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { Ok $name } else { Fail $name 'clone failed' }
            }
        }

        # vmp-lazy-unpack is a Python package: install editable so `py -m unpack` works.
        $vl = Join-Path $EchoHome 'vmp-lazy-unpack'
        if (Test-Path $vl) {
            Push-Location $vl; & $py -m pip install --quiet -e . 2>&1 | Out-Null; $rc = $LASTEXITCODE; Pop-Location
            if ($rc -eq 0) { Ok 'vmp-lazy-unpack (pip -e)' } else { Skip 'vmp-lazy-unpack' 'pip -e failed' }
        }
    }
}

# ── 6. Compiler-built devirtualization stack ─────────────────────────────────
if (TierAtLeast 'full') {
    Say 'Compiler-built tooling (tier: full)'

    function BuildCMake($name, $repo, [string[]]$extra) {
        $dir = Join-Path $EchoHome $name
        if (-not (Have cmake)) { Skip $name 'cmake not found'; return }
        if (-not (Test-Path (Join-Path $dir '.git'))) {
            $args = @('clone','--depth','1') + $extra + @("https://github.com/$repo", $dir)
            & git @args 2>&1 | Out-Null
        }
        if (-not (Test-Path $dir)) { Fail $name 'clone failed'; return }
        Push-Location $dir
        cmake -B build -DCMAKE_BUILD_TYPE=Release 2>&1 | Out-Null
        cmake --build build --config Release 2>&1 | Out-Null
        $rc = $LASTEXITCODE
        Pop-Location
        if ($rc -eq 0) { Ok $name } else { Skip $name 'cmake build failed (needs a C++ toolchain)' }
    }
    BuildCMake 'VTIL-Core' 'vtil-project/VTIL-Core' @()
    BuildCMake 'NoVmp' 'can1357/NoVmp' @('--recurse-submodules','--shallow-submodules')

    # vtil2 — .NET 8.
    if (-not (Have dotnet)) { Skip 'vtil2' 'dotnet (.NET 8 SDK) not found' }
    else {
        $dir = Join-Path $EchoHome 'vtil2'
        if (-not (Test-Path (Join-Path $dir '.git'))) { git clone --depth 1 https://github.com/pop-rip/vtil2 $dir 2>&1 | Out-Null }
        if (Test-Path $dir) {
            Push-Location $dir; dotnet build -c Release 2>&1 | Out-Null; $rc = $LASTEXITCODE; Pop-Location
            if ($rc -eq 0) { Ok 'vtil2' } else { Skip 'vtil2' 'dotnet build failed' }
        }
    }

    # LLVM — only for Triton's LLVM interface and OLLVM passes. Never build from source.
    if ((Have llvm-config) -or (Have opt)) { Ok 'LLVM already present' }
    elseif (Have winget) {
        winget install --id LLVM.LLVM --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Ok 'LLVM (winget)' } else { Skip 'LLVM' 'winget install failed' }
    } else { Skip 'LLVM' 'install LLVM manually (winget install LLVM.LLVM)' }
}

# ── 7. write mcp.json ────────────────────────────────────────────────────────
Say 'Writing mcp.json'
$ghEntry = (Join-Path $EchoHome 'mcp-gamehacking\dist\index.js') -replace '\\','/'
$amEntry = (Join-Path $EchoHome 'angel-menu-mcp\index.js') -replace '\\','/'
$mcp = [ordered]@{
    mcpServers = [ordered]@{
        gamehacking = [ordered]@{ command='node'; args=@($ghEntry); description='mcp-gamehacking: 4100+ game hacking skills, 75 specialist agents, 19+ MCP tools' }
        rea         = [ordered]@{ command='npx';  args=@('-y','rea-agents'); description='REA: Reverse Engineer Anything - Unity IL2CPP, Godot, native binaries, APK, WASM, firmware' }
        'angel-menu'= [ordered]@{ command='node'; args=@($amEntry); description='Echo overlay menu control: list_features, get_feature, set_feature, connection_status' }
    }
}
$mcpPath = Join-Path $EchoHome 'mcp.json'
$mcp | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $mcpPath
Ok "mcp.json -> $mcpPath"

# ── summary ──────────────────────────────────────────────────────────────────
Write-Host "`n------------------------------------------------------------"
Write-Host ("  {0} installed" -f $script:OK.Count) -ForegroundColor Green -NoNewline
if ($script:Skipped.Count) { Write-Host ("   {0} skipped" -f $script:Skipped.Count) -ForegroundColor Magenta -NoNewline }
if ($script:Failed.Count)  { Write-Host ("   {0} failed"  -f $script:Failed.Count)  -ForegroundColor Red -NoNewline }
Write-Host ''
if ($script:Skipped.Count) {
    Write-Host "`n  Skipped:"
    $script:Skipped | ForEach-Object { Write-Host "    . $_" }
}
if ($script:Failed.Count) {
    Write-Host "`n  Failed:"
    $script:Failed | ForEach-Object { Write-Host "    . $_" }
}

Write-Host @"

  Next:
    1. Restart Claude Code (or run /reload-plugins)
    2. Type  /echo-help        to list the 12 agents
    3. Type  /echo-esp         to load ESP context
       ...or just describe your task - keywords auto-route.

  Tools are in $EchoHome
  Verify at any time:  .\scripts\echo-doctor.ps1
  Templates: templates\*.as  ->  %AppData%\Roaming\scripts\
  Full API:  reference\api.md
------------------------------------------------------------
"@

if ($script:Failed.Count) { exit 1 }
