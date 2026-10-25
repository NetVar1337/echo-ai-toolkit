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
$Tier      = if ($env:ECHO_TIER) { $env:ECHO_TIER } else { 'full' }
$EchoHome  = if ($env:ECHO_HOME) { $env:ECHO_HOME } else { Join-Path $HOME '.local\share\echo-ai-toolkit' }
$BinDir    = Join-Path $EchoHome 'bin'
$RefDir    = Join-Path $EchoHome 'reference'

# An unknown tier must not silently mean "download everything".
if ($Tier -notin @('minimal','standard','full')) {
    Write-Host "`n! unknown ECHO_TIER='$Tier' - using standard" -ForegroundColor Magenta
    $Tier = 'standard'
}

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
    # A multi-GB clone can die partway and leave .git behind without a working tree.
    if ((Test-Path (Join-Path $dir '.git')) -and -not (Test-Path (Join-Path $dir 'package.json'))) {
        Sub "removing incomplete $name clone..."
        Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path (Join-Path $dir '.git'))) {
        git clone --depth 1 "https://github.com/$repo" $dir 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
            Fail $name 'clone failed (re-run to retry)'; return
        }
    }
    Push-Location $dir
    npm install --silent 2>&1 | Out-Null
    $hasBuild = $false
    try { $pkg = Get-Content package.json -Raw | ConvertFrom-Json; $hasBuild = $null -ne $pkg.scripts.build } catch {}
    if ($hasBuild) { npm run build --silent 2>&1 | Out-Null }
    Pop-Location
    if (Test-Path (Join-Path $dir $entry)) { Ok $name } else { Fail $name "expected $entry after install" }
}
if (($env:ECHO_SKIP_MCP -ne '1') -and (Have node) -and (Have npm)) {
    # mcp-gamehacking is part of a full install: 18 GB of skills on disk, ~3.1 GB
    # over the wire. Skip it with $env:ECHO_SKIP_GAMEHACKING = '1'.
    if ($env:ECHO_SKIP_GAMEHACKING -eq '1') {
        Skip 'mcp-gamehacking' 'ECHO_SKIP_GAMEHACKING=1'
    } else {
        Write-Host '    mcp-gamehacking is ~3.1 GB - this is the long step, give it time...'
        CloneBuildNode 'mcp-gamehacking' '1llu50ry/mcp-gamehacking' 'dist\index.js'
    }
    CloneBuildNode 'angel-menu-mcp' 'Jozkah/angel-menu-mcp' 'index.js'
} elseif ($env:ECHO_SKIP_MCP -eq '1') { Skip 'MCP servers' 'ECHO_SKIP_MCP=1' }
else { Skip 'MCP servers' 'Node 18+ required' }

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
    if (-not (Have bun)) {
        Sub 'installing Bun (needed by web-mv)...'
        try {
            Invoke-RestMethod -UseBasicParsing -Uri 'https://bun.sh/install.ps1' | Invoke-Expression
            $env:PATH = (Join-Path $HOME '.bun\bin') + ';' + $env:PATH
        } catch {}
        if (Have bun) { Ok "bun $(& bun --version 2>$null)" } else { Skip 'web-mv' 'Bun install failed (https://bun.sh)' }
    }
    if (Have bun) {
        $dir = Join-Path $EchoHome 'web-mv'
        if (-not (Test-Path (Join-Path $dir '.git'))) {
            git clone --depth 1 https://github.com/Jozkah/web-mv $dir 2>&1 | Out-Null
        }
        if (Test-Path $dir) {
            Push-Location (Join-Path $dir 'relay'); bun install 2>&1 | Out-Null; $rc = $LASTEXITCODE; Pop-Location
            if ($rc -eq 0) { Ok "web-mv (run: cd `"$dir\relay`"; bun run start)" } else { Fail 'web-mv' 'bun install failed' }
        } else { Fail 'web-mv' 'clone failed' }
    }

    # Reference docs — the value is the curated list, so fetch the README rather
    # than cloning. awesome-game-security is 3.19 GB on disk; its README is 435 KB.
    foreach ($pair in @(@('awesome-game-security','gmh5225/awesome-game-security'),
                        @('gamehacking-cheatsheet','ridpath/gamehacking-cheatsheet'))) {
        $name = $pair[0]; $out = Join-Path $RefDir "$name.md"
        if ((Test-Path $out) -and ((Get-Item $out).Length -gt 0)) { Ok "$name already fetched"; continue }
        try {
            Invoke-WebRequest -UseBasicParsing -Uri `
              "https://raw.githubusercontent.com/$($pair[1])/HEAD/README.md" `
              -OutFile $out -ErrorAction Stop
            Ok "$name ($((Get-Item $out).Length) bytes)"
        } catch { Fail $name 'download failed' }
    }
}

# ── 5. Pi coding agent ───────────────────────────────────────────────────────
if (TierAtLeast 'standard') {
    Say 'Pi coding agent'

    $piProfile = Join-Path $EchoHome 'pi'
    New-Item -ItemType Directory -Force -Path (Join-Path $piProfile 'prompts'), (Join-Path $piProfile 'skills') | Out-Null

    $repoSrc = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'pi'))) { Join-Path $PSScriptRoot 'pi' } else { $null }
    $base = "https://raw.githubusercontent.com/$Repo/main"

    if ($repoSrc) {
        foreach ($f in 'SYSTEM.md','APPEND_SYSTEM.md','AGENTS.md') {
            $s = Join-Path $repoSrc $f
            if (Test-Path $s) { Copy-Item $s (Join-Path $piProfile $f) -Force }
        }
        Get-ChildItem (Join-Path $repoSrc 'prompts') -Filter *.md -ErrorAction SilentlyContinue |
            ForEach-Object { Copy-Item $_.FullName (Join-Path $piProfile 'prompts') -Force }
        $skillSrc = Join-Path (Split-Path $repoSrc -Parent) 'skills'
        $echoSrc  = Join-Path $repoSrc 'bin\echo.ps1'
    } else {
        foreach ($f in 'SYSTEM.md','APPEND_SYSTEM.md','AGENTS.md') {
            try { Invoke-WebRequest -UseBasicParsing -Uri "$base/pi/$f" -OutFile (Join-Path $piProfile $f) -ErrorAction Stop } catch {}
        }
        foreach ($p in 'echo-api','echo-esp','echo-reverse','echo-verify') {
            try { Invoke-WebRequest -UseBasicParsing -Uri "$base/pi/prompts/$p.md" -OutFile (Join-Path $piProfile "prompts\$p.md") -ErrorAction Stop } catch {}
        }
        $skillSrc = Join-Path $HOME '.claude\plugins\marketplaces\echo-ai-toolkit\skills'
        $echoSrc  = $null
    }

    # Skills: Pi uses the same SKILL.md format, so they port directly.
    if (Test-Path $skillSrc) {
        Get-ChildItem $skillSrc -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $skillMd = Join-Path $_.FullName 'SKILL.md'
            if (Test-Path $skillMd) {
                $dest = Join-Path $piProfile "skills\$($_.Name)"
                New-Item -ItemType Directory -Force -Path $dest | Out-Null
                Copy-Item $skillMd (Join-Path $dest 'SKILL.md') -Force
            }
        }
    }
    $nSkills = (Get-ChildItem (Join-Path $piProfile 'skills') -Directory -ErrorAction SilentlyContinue).Count

    # MCP: reuse the same server set the toolkit writes.
    $mcpSrc = Join-Path $EchoHome 'mcp.json'
    if (Test-Path $mcpSrc) { Copy-Item $mcpSrc (Join-Path $piProfile 'mcp.json') -Force }

    @{ skills = @('./skills'); prompts = @('./prompts') } |
        ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $piProfile 'settings.json')

    Ok "pi profile -> $piProfile ($nSkills skills)"

    # Launcher.
    $launcher = Join-Path $BinDir 'echo.ps1'
    if ($echoSrc -and (Test-Path $echoSrc)) { Copy-Item $echoSrc $launcher -Force }
    if (Test-Path $launcher) { Ok "launcher -> $launcher" }

    # The launcher dispatches to these, so they must sit next to it.
    foreach ($s in 'echo-update.ps1','echo-doctor.ps1') {
        $srcS = if ($repoSrc) { Join-Path (Split-Path $repoSrc -Parent) "scripts\$s" } else { $null }
        if ($srcS -and (Test-Path $srcS)) { Copy-Item $srcS (Join-Path $BinDir $s) -Force }
    }

    # `echo` alias as a PowerShell function in the user profile.
    if ($env:ECHO_NO_ALIAS -ne '1') {
        $prof = $PROFILE.CurrentUserAllHosts
        $marker = '# echo-ai-toolkit: echo alias'
        $existing = if (Test-Path $prof) { Get-Content $prof -Raw } else { '' }
        if ($existing -notmatch [regex]::Escape($marker)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $prof -Parent) | Out-Null
            Add-Content -Path $prof -Value @"

$marker -> Pi with the Echo profile
# This shadows the built-in echo in interactive PowerShell sessions only.
# Remove these lines, or set `$env:ECHO_NO_ALIAS = '1' and re-run the installer.
function echo { & '$launcher' @args }
"@
            Ok "alias added to $prof (shadows the echo builtin - see the comment there)"
        } else { Ok 'echo alias already present' }
    } else { Skip 'echo alias' 'ECHO_NO_ALIAS=1' }

    if (Have pi) { Ok "pi $(& pi --version 2>&1 | Select-Object -First 1)" }
    else { Skip 'pi binary' 'install: irm https://pi.dev/install.ps1 | iex  (needs Node 22.19+)' }
}

# ── 6. Python reverse-engineering tooling ────────────────────────────────────
if (TierAtLeast 'standard') {
    Say 'Python reverse-engineering tooling'
    $py = if (Have python) { 'python' } elseif (Have py) { 'py' } else { $null }
    if (-not $py) { Skip 'Python tooling' 'python not found' }
    else {
        # A dedicated venv keeps the system Python untouched and sidesteps PEP 668.
        $venv = Join-Path $EchoHome 'venv'
        $venvPy = Join-Path $venv 'Scripts\python.exe'
        if (-not (Test-Path $venvPy)) {
            & $py -m venv $venv 2>&1 | Out-Null
        }
        if (Test-Path $venvPy) { Ok 'python venv ready' } else { $venvPy = $py; Skip 'python venv' 'venv creation failed - using system python' }

        # Triton — the PyPI package is "triton-library" (NOT "triton", which is OpenAI's GPU compiler).
        $hasTriton = $false
        try { & $venvPy -c 'import triton' 2>$null; $hasTriton = ($LASTEXITCODE -eq 0) } catch {}
        if ($hasTriton) { Ok 'triton already installed' }
        else {
            & $venvPy -m pip install --quiet --disable-pip-version-check triton-library 2>&1 | Out-Null
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
            Push-Location $vl; & $venvPy -m pip install --quiet -e . 2>&1 | Out-Null; $rc = $LASTEXITCODE; Pop-Location
            if ($rc -eq 0) { Ok 'vmp-lazy-unpack (pip -e)' } else { Skip 'vmp-lazy-unpack' 'pip -e failed' }
        }
    }
}

# ── 6. Compiler-built devirtualization stack ─────────────────────────────────
if (TierAtLeast 'full') {
    Say 'Compiler-built tooling (tier: full)'

    # The compiler-built tools need cmake / dotnet / LLVM. Install them rather
    # than skipping, so a full install actually finishes.
    function Install-Pkg($label, $wingetId) {
        if (Have winget) {
            Sub "installing $label via winget..."
            winget install --id $wingetId --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Ok "$label (winget)"; return $true }
        }
        if (Have choco) {
            Sub "installing $label via choco..."
            choco install -y $wingetId.Split('.')[-1] 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Ok "$label (choco)"; return $true }
        }
        Skip $label "install manually (winget install $wingetId)"
        return $false
    }
    if (-not (Have cmake))  { $null = Install-Pkg 'cmake' 'Kitware.CMake' }
    if (-not (Have dotnet)) { $null = Install-Pkg 'dotnet SDK 8' 'Microsoft.DotNet.SDK.8' }
    if (-not ((Have llvm-config) -or (Have opt))) { $null = Install-Pkg 'LLVM' 'LLVM.LLVM' }

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

    # LLVM is handled by Install-Pkg above (system package, never a source build).
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
        radare2     = [ordered]@{ command='r2pm'; args=@('-r','r2mcp'); description='radare2 MCP: disasm, decompile, search, analysis (install: r2pm -Uci r2mcp)' }
        ida         = [ordered]@{ command='uvx';  args=@('ida-mcp','stdio','--agent=echo'); description='IDA Pro MCP: decompile, rename, xref, structs (requires IDA 9.4+ with idalib)' }
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
