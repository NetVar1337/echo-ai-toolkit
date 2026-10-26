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
function Sub  { param($m) Write-Host "    . $m" -ForegroundColor Cyan }
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

# ── tool lock ────────────────────────────────────────────────────────────────
# tools.lock pins every external artifact, so two installs are the same software.
$Lock = Join-Path $EchoHome 'tools.lock'
New-Item -ItemType Directory -Force -Path $EchoHome | Out-Null
$repoLock = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'tools.lock' } else { $null }
if ($repoLock -and (Test-Path $repoLock)) { Copy-Item -Force $repoLock $Lock }
$SrcRoot = if ($Vendor) { Split-Path $Vendor -Parent } else { $null }
if (-not (Test-Path $Lock) -and $SrcRoot -and (Test-Path (Join-Path $SrcRoot 'tools.lock'))) {
    Copy-Item (Join-Path $SrcRoot 'tools.lock') $Lock -Force
}
if (-not (Test-Path $Lock)) { Write-Host '    ! tools.lock unavailable - falling back to branch heads' -ForegroundColor Magenta }

function LockField($kind, $name, $index) {
    if (-not (Test-Path $Lock)) { return '' }
    foreach ($line in Get-Content $Lock) {
        if (-not $line.Trim() -or $line -match '^\s*#') { continue }
        $f = $line -split '\s+'
        if ($f.Count -ge 4 -and $f[0] -eq $kind -and $f[1] -eq $name) { return $f[$index] }
    }
    return ''
}
function LockPin($kind, $name) { return (LockField $kind $name 3) }
function LockRef($kind, $name) { return (LockField $kind $name 2) }

function VerifySha($path, $want) {
    if (-not $want) { return $true }
    try { $got = (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLower() } catch { return $true }
    return $got -eq $want.ToLower()
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

# ── 1. vendored toolchain ────────────────────────────────────────────────────
# Every tool installs from vendor/ in this repo. Nothing below fetches a
# third-party repository, release asset or README.
Say 'Vendored toolchain'
$Vendor = $null
$repoVendor = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'vendor' } else { $null }
if ($repoVendor -and (Test-Path $repoVendor)) {
    $Vendor = $repoVendor
    Ok "vendor/ from the checkout"
} else {
    $ref = if ($env:ECHO_REF) { $env:ECHO_REF } else { 'main' }
    $src = Join-Path $EchoHome 'src'
    New-Item -ItemType Directory -Force -Path $src | Out-Null
    $tar = Join-Path $src 'toolkit.tar.gz'
    try {
        Sub "fetching $Repo@$ref (this repo - the only download)..."
        Invoke-WebRequest -UseBasicParsing -Uri "https://codeload.github.com/$Repo/tar.gz/refs/heads/$ref" -OutFile $tar -ErrorAction Stop
        tar -xzf $tar -C $src 2>&1 | Out-Null
        Remove-Item $tar -Force -ErrorAction SilentlyContinue
        $Vendor = (Get-ChildItem $src -Directory -Filter 'echo-ai-toolkit-*' |
                   ForEach-Object { Join-Path $_.FullName 'vendor' } |
                   Where-Object { Test-Path $_ } | Select-Object -First 1)
    } catch {}
    if ($Vendor -and (Test-Path $Vendor)) { Ok 'vendor/ fetched' }
    else { Fail 'vendor' 'could not fetch this repo - clone it and run .\install.ps1' }
}

function VendorPath($sub) {
    if (-not $Vendor) { return $null }
    $p = Join-Path $Vendor $sub
    if (Test-Path $p) { return $p }
    return $null
}

function VendorVerify($name, $sub) {
    $sums = Join-Path $Vendor 'CHECKSUMS.sha256'
    if (-not (Test-Path $sums)) { return $true }
    $want = (Select-String -Path $sums -Pattern ("  " + [regex]::Escape($sub) + '$') -SimpleMatch:$false |
             Select-Object -First 1)
    if (-not $want) { return $true }
    $expected = ($want.Line -split '\s+')[0]
    $actual = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Vendor $sub)).Hash.ToLower()
    if ($actual -eq $expected.ToLower()) { return $true }
    Fail $name "checksum mismatch in vendor/$sub"
    return $false
}

function VendorCopy($sub, $dest) {
    $src = VendorPath $sub
    if (-not $src) { Skip (Split-Path $sub -Leaf) 'not in vendor/'; return $false }
    if (-not $dest.StartsWith($EchoHome)) { Fail (Split-Path $sub -Leaf) "refusing to replace $dest"; return $false }
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Path (Join-Path $src '*') -Destination $dest -Recurse -Force
    return $true
}

function VendorFile($sub, $dest) {
    $src = VendorPath $sub
    if (-not $src) { Skip (Split-Path $sub -Leaf) 'not in vendor/'; return $false }
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    Copy-Item -Path $src -Destination $dest -Force
    return (VendorVerify (Split-Path $sub -Leaf) $sub)
}

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
# Both are vendored in vendor/plugins/ and served by this repo's own marketplace.
function AddVendoredPlugin($name) {
    $list = (claude plugin list 2>&1 | Out-String)
    if ($list -match [regex]::Escape("$name@")) { Ok "$name already installed"; return }
    $null = claude plugin install "$name@$Plugin" 2>&1
    if ($LASTEXITCODE -eq 0) { Ok "$name (vendored)" } else { Skip $name "install from $Plugin marketplace failed" }
}
AddVendoredPlugin 'ponytail'
AddVendoredPlugin 'andrej-karpathy-skills' 

# ── 3. MCP servers ───────────────────────────────────────────────────────────
Say 'MCP servers'
function CloneBuildNode($name, $repo, $entry) {
    $dir = Join-Path $EchoHome $name
    if ((Test-Path (Join-Path $dir $entry)) -and (Test-Path (Join-Path $dir 'node_modules'))) {
        Ok "$name already installed"; return
    }
    if (-not (VendorCopy $repo $dir)) {
        Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
        return
    }
    Push-Location $dir
    npm ci --omit=dev --silent 2>&1 | Out-Null
    Pop-Location
    if (Test-Path (Join-Path $dir $entry)) { Ok $name } else { Fail $name "expected $entry after install" }
}

# mcp-gamehacking ships as a split archive in this repo's releases: 3.1 GB of git
# is over GitHub's practical repo size, and every checkout would pay for it.
function Install-McpGamehacking {
    $dir = Join-Path $EchoHome 'mcp-gamehacking'
    $entry = Join-Path $dir 'dist\index.js'
    if (Test-Path $entry) { Ok 'mcp-gamehacking already installed'; return }
    if (VendorPath 'mcp/mcp-gamehacking') {
        if (VendorCopy 'mcp/mcp-gamehacking' $dir) { Ok 'mcp-gamehacking (vendored in-tree)' }
        return
    }
    $meta = if ($Vendor) { Join-Path $Vendor 'ARCHIVES' } else { $null }
    if (-not $meta -or -not (Test-Path $meta)) { Fail 'mcp-gamehacking' 'vendor/ARCHIVES missing'; return }
    $tmp = Join-Path $EchoHome 'src\mcp-gamehacking'
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $parts = Get-Content $meta | Where-Object { $_ -and $_ -notmatch '^#' } |
             ForEach-Object { $f = $_ -split '\s+'; if ($f[0] -eq 'mcp-gamehacking') { [pscustomobject]@{ Url = $f[1]; Sha = $f[2] } } } |
             Sort-Object Url
    if (-not $parts) { Fail 'mcp-gamehacking' 'no archive parts listed in vendor/ARCHIVES'; return }
    $n = 0
    foreach ($part in $parts) {
        $n++
        Sub "downloading archive part $n of $($parts.Count)..."
        $out = Join-Path $tmp ('part{0:D2}' -f $n)
        try { Invoke-WebRequest -UseBasicParsing -Uri $part.Url -OutFile $out -ErrorAction Stop }
        catch { Fail 'mcp-gamehacking' "part $n download failed"; return }
        if (-not (VerifySha $out $part.Sha)) { Fail 'mcp-gamehacking' "part $n checksum mismatch"; return }
    }
    $archive = Join-Path $tmp 'archive.tar.gz'
    $fs = [System.IO.File]::Create($archive)
    foreach ($part in (Get-ChildItem $tmp -Filter 'part*' | Sort-Object Name)) {
        $bytes = [System.IO.File]::ReadAllBytes($part.FullName)
        $fs.Write($bytes, 0, $bytes.Length)
    }
    $fs.Close()
    tar -xzf $archive -C $tmp 2>&1 | Out-Null
    $inner = Get-ChildItem $tmp -Directory -Filter 'mcp-gamehacking*' | Select-Object -First 1
    if (-not $inner) { Fail 'mcp-gamehacking' 'archive layout unexpected'; return }
    if (Test-Path $dir) { Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue }
    Move-Item $inner.FullName $dir
    # The archive is the upstream source tree; build here against the vendored lock.
    if (-not (Test-Path $entry) -and (Have npm)) {
        Sub 'building mcp-gamehacking (npm ci + build)...'
        Push-Location $dir
        npm ci --silent 2>&1 | Out-Null
        try { $pkg = Get-Content package.json -Raw | ConvertFrom-Json; if ($pkg.scripts.build) { npm run build --silent 2>&1 | Out-Null } } catch {}
        Pop-Location
    }
    if (Test-Path $entry) { Ok 'mcp-gamehacking (verified archive)' } else { Fail 'mcp-gamehacking' "missing $entry" }
}
if (($env:ECHO_SKIP_MCP -ne '1') -and (Have node) -and (Have npm)) {
    # mcp-gamehacking is part of a full install: 18 GB of skills on disk, ~3.1 GB
    # over the wire. Skip it with $env:ECHO_SKIP_GAMEHACKING = '1'.
    if ($env:ECHO_SKIP_GAMEHACKING -eq '1') {
        Skip 'mcp-gamehacking' 'ECHO_SKIP_GAMEHACKING=1'
    } else {
        Install-McpGamehacking
    }
    CloneBuildNode 'angel-menu-mcp' 'mcp/angel-menu-mcp' 'index.js'
} elseif ($env:ECHO_SKIP_MCP -eq '1') { Skip 'MCP servers' 'ECHO_SKIP_MCP=1' }
else { Skip 'MCP servers' 'Node 18+ required' }

# ── 4. Echo-side tooling ─────────────────────────────────────────────────────
if (TierAtLeast 'standard') {
    Say 'Echo tooling'

    # as_bundler — prebuilt release binary, pinned with a sha256 in tools.lock.
    $AsOut = Join-Path $BinDir 'as_bundler.exe'
    if (Test-Path $AsOut) { Ok 'as_bundler already installed' }
    elseif (VendorFile 'bin/as_bundler.exe' $AsOut) { Ok 'as_bundler (vendored)' }

    # echo-esp-preview — single AngelScript drop-in, straight into the Echo scripts dir.
    $scripts = Join-Path $env:APPDATA 'scripts'
    New-Item -ItemType Directory -Force -Path $scripts | Out-Null
    if (VendorFile 'scripts/esp_preview.as' (Join-Path $scripts 'esp_preview.as')) {
        Ok "esp_preview.as -> $scripts"
    }

    # echo-angelscript-lsp — VS Code extension.
    if (-not (Have code)) { Skip 'echo-angelscript-lsp' "VS Code 'code' CLI not on PATH" }
    elseif ((code --list-extensions 2>&1 | Out-String) -match 'echo-angelscript-lsp') {
        Ok 'echo-angelscript-lsp already installed'
    } else {
        $tmp = Join-Path $env:TEMP "echo-lsp-$(Get-Random)"
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $zip = Join-Path $tmp 'lsp.zip'
            if (-not (VendorFile 'bin/echo-angelscript-lsp-0.0.10.zip' $zip)) { throw 'not in vendor/' }
            Expand-Archive -Path $zip -DestinationPath $tmp -Force
            $vsix = Get-ChildItem $tmp -Filter *.vsix -Recurse | Select-Object -First 1
            if ($vsix) {
                code --install-extension $vsix.FullName --force 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { Ok 'echo-angelscript-lsp 0.0.10' } else { Fail 'echo-angelscript-lsp' 'install failed' }
            } else { Fail 'echo-angelscript-lsp' 'no .vsix in archive' }
        } catch { Fail 'echo-angelscript-lsp' 'download failed' }
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }

    # Signature-Doctor — offset & signature health dashboard (http://127.0.0.1:3210).
    $sdDir = Join-Path $EchoHome 'signature-doctor'
    if (Test-Path (Join-Path $sdDir 'node_modules\ws\package.json')) {
        Ok 'signature-doctor already installed'
    } elseif (-not (Have node)) {
        Skip 'signature-doctor' 'Node 22+ required'
    } else {
        if (-not (Test-Path (Join-Path $sdDir '.git'))) {
            $null = VendorCopy 'tools/signature-doctor' $sdDir
        }
        if (Test-Path $sdDir) {
            Push-Location $sdDir
            npm ci --no-audit --no-fund --silent 2>&1 | Out-Null
            $rc = $LASTEXITCODE
            Pop-Location
            if ($rc -eq 0) { Ok "signature-doctor  →  node `"$sdDir\server\index.mjs`"  (http://127.0.0.1:3210)" }
            else { Fail 'signature-doctor' 'npm ci failed' }
        } else { Fail 'signature-doctor' 'clone failed' }
    }

    # web-mv — Bun relay + SolidJS UI (source only; no releases published).
    if (-not (Have bun)) {
        Sub 'installing Bun (needed by web-mv)...'
        try {
            # bun ships its own installer; the version it lands is checked against
            # the pin below, so a substituted binary is visible rather than silent.
            Invoke-RestMethod -UseBasicParsing -Uri 'https://bun.sh/install.ps1' | Invoke-Expression
            $env:PATH = (Join-Path $HOME '.bun\bin') + ';' + $env:PATH
        } catch {}
        if (Have bun) {
            $got = (& bun --version 2>$null)
            $want = LockPin 'toolver' 'bun'
            if ($want -and ($got -ne $want)) { Skip 'bun' "installed $got, pinned $want" }
            else { Ok "bun $got" }
        } else { Skip 'web-mv' 'Bun install failed (https://bun.sh)' }
    }
    if (Have bun) {
        $dir = Join-Path $EchoHome 'web-mv'
        $null = VendorCopy 'tools/web-mv' $dir
        if (Test-Path $dir) {
            Push-Location (Join-Path $dir 'relay'); bun install --frozen-lockfile 2>&1 | Out-Null; $rc = $LASTEXITCODE; Pop-Location
            if ($rc -eq 0) { Ok "web-mv (run: cd `"$dir\relay`"; bun run start)" } else { Fail 'web-mv' 'bun install failed' }
        } else { Fail 'web-mv' 'clone failed' }
    }

    # Reference docs — the value is the curated list, so fetch the README rather
    # than cloning. awesome-game-security is 3.19 GB on disk; its README is 435 KB.
    foreach ($name in @('awesome-game-security','gamehacking-cheatsheet')) {
        $out = Join-Path $RefDir "$name.md"
        if ((Test-Path $out) -and ((Get-Item $out).Length -gt 0)) { Ok "$name already fetched"; continue }
        if (VendorFile "docs/$name.md" $out) { Ok "$name ($((Get-Item $out).Length) bytes)" }
    }
}

# ── 5. Pi coding agent ───────────────────────────────────────────────────────
if (TierAtLeast 'standard') {
    Say 'Pi coding agent'

    $piProfile = Join-Path $EchoHome 'pi'
    New-Item -ItemType Directory -Force -Path (Join-Path $piProfile 'prompts'), (Join-Path $piProfile 'skills') | Out-Null

    $repoSrc = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'pi'))) { Join-Path $PSScriptRoot 'pi' }
               elseif ($SrcRoot -and (Test-Path (Join-Path $SrcRoot 'pi'))) { Join-Path $SrcRoot 'pi' }
               else { $null }

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
        $skillSrc = $null
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
    foreach ($s in 'echo.mjs','echo-update.ps1','echo-doctor.ps1') {
        $srcS = if ($repoSrc) { Join-Path (Split-Path $repoSrc -Parent) "scripts\$s" } else { $null }
        $dstS = Join-Path $BinDir $s
        if ($srcS -and (Test-Path $srcS)) { Copy-Item $srcS $dstS -Force }
        elseif ($SrcRoot -and (Test-Path (Join-Path $SrcRoot "scripts\$s"))) {
            Copy-Item (Join-Path $SrcRoot "scripts\$s") $dstS -Force
        }
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
            $req = if ($Vendor) { Join-Path $Vendor 'python\requirements.lock' } else { $null }
            if (-not $req -or -not (Test-Path $req)) { Skip 'triton' 'vendor/python/requirements.lock missing' }
            else {
                & $venvPy -m pip install --quiet --disable-pip-version-check --require-hashes -r $req 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { Ok 'triton, capstone, pefile, unicorn (hash-pinned)' }
                else { Skip 'python packages' 'pip --require-hashes failed (no matching wheel?)' }
            }
        }

        foreach ($pair in @(@('VMProtect-devirtualization','JonathanSalwan/VMProtect-devirtualization'),
                            @('vmp-lazy-unpack','x86rc/vmp-lazy-unpack'))) {
            $name = $pair[0]; $dir = Join-Path $EchoHome $name
            if ((Test-Path $dir) -and (Get-ChildItem $dir -ErrorAction SilentlyContinue)) { Ok "$name already installed" }
            elseif (VendorCopy "tools/$name" $dir) { Ok "$name (vendored)" }
        }

        # vmp-lazy-unpack is a Python package: install editable so `py -m unpack` works.
        $vl = Join-Path $EchoHome 'vmp-lazy-unpack'
        if (Test-Path $vl) {
            Push-Location $vl; & $venvPy -m pip install --quiet --no-deps -e . 2>&1 | Out-Null; $rc = $LASTEXITCODE; Pop-Location
            if ($rc -eq 0) { Ok 'vmp-lazy-unpack (pip -e)' } else { Skip 'vmp-lazy-unpack' 'pip -e failed' }
        }
    }
}

# ── 7. Compiler-built devirtualization stack ──────────────────────────────────
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
        if (-not (Test-Path $dir) -or -not (Get-ChildItem $dir -ErrorAction SilentlyContinue)) {
            if (-not (VendorCopy $repo $dir)) { return }
        }
        if (-not (Test-Path $dir)) { Fail $name 'clone failed'; return }
        Push-Location $dir
        cmake -B build -DCMAKE_BUILD_TYPE=Release 2>&1 | Out-Null
        cmake --build build --config Release 2>&1 | Out-Null
        $rc = $LASTEXITCODE
        Pop-Location
        if ($rc -eq 0) { Ok $name } else { Skip $name 'cmake build failed (needs a C++ toolchain)' }
    }
    BuildCMake 'VTIL-Core' 'tools/VTIL-Core' @()
    BuildCMake 'NoVmp' 'tools/NoVmp' @()

    # vtil2 — .NET 8.
    if (-not (Have dotnet)) { Skip 'vtil2' 'dotnet (.NET 8 SDK) not found' }
    else {
        $dir = Join-Path $EchoHome 'vtil2'
        if (-not (Test-Path $dir) -or -not (Get-ChildItem $dir -ErrorAction SilentlyContinue)) { $null = VendorCopy 'tools/vtil2' $dir }
        if (Test-Path $dir) {
            # The repo root holds several projects; build the solution explicitly.
            Push-Location $dir; dotnet build VTIL-Core.sln -c Release 2>&1 | Out-Null; $rc = $LASTEXITCODE; Pop-Location
            if ($rc -eq 0) { Ok 'vtil2' } else { Skip 'vtil2' 'dotnet build failed' }
        }
    }

    # LLVM is handled by Install-Pkg above (system package, never a source build).
}

# ── 8. write mcp.json ────────────────────────────────────────────────────────
Say 'Writing mcp.json'
$ghEntry = (Join-Path $EchoHome 'mcp-gamehacking\dist\index.js') -replace '\\','/'
$amEntry = (Join-Path $EchoHome 'angel-menu-mcp\index.js') -replace '\\','/'
# rea-agents: installed from the vendored tarball with npm ci against the vendored
# lockfile, so the MCP server is hash-pinned and needs no npx resolution at runtime.
$reaEntry = $null
$reaDir = Join-Path $EchoHome 'rea'
$reaTarget = Join-Path $reaDir 'node_modules\rea-agents\scripts\rea.mjs'
if ((Have node) -and (Have npm)) {
    if (Test-Path $reaTarget) { $reaEntry = $reaTarget; Ok 'rea already installed' }
    elseif (VendorCopy 'npm/rea' $reaDir) {
        Push-Location $reaDir; npm ci --silent 2>&1 | Out-Null; $rc = $LASTEXITCODE; Pop-Location
        if ($rc -eq 0 -and (Test-Path $reaTarget)) { $reaEntry = $reaTarget; Ok 'rea-agents (vendored, hash-pinned)' }
        else { Fail 'rea' 'npm ci failed' }
    }
}
$reaVer = LockPin 'npm' 'rea-agents' 
$reaServer = if ($reaEntry) {
    [ordered]@{ command='node'; args=@($reaEntry); description='REA: Reverse Engineer Anything - Unity IL2CPP, Godot, native binaries, APK, WASM, firmware' }
} else {
    [ordered]@{ command='npx'; args=@('-y',"rea-agents@$reaVer"); description='REA: Reverse Engineer Anything - vendored install unavailable, falling back to npx' }
}
$mcp = [ordered]@{
    mcpServers = [ordered]@{
        gamehacking = [ordered]@{ command='node'; args=@($ghEntry); description='mcp-gamehacking: 4100+ game hacking skills, 75 specialist agents, 19+ MCP tools' }
        rea         = $reaServer
        'angel-menu'= [ordered]@{ command='node'; args=@($amEntry); description='Echo overlay menu control: list_features, get_feature, set_feature, connection_status' }
        radare2     = [ordered]@{ command='r2pm'; args=@('-r','r2mcp'); description='radare2 MCP: disasm, decompile, search, analysis (install: r2pm -Uci r2mcp)' }
        ida         = [ordered]@{ command='uvx';  args=@('ida-mcp','stdio','--agent=echo'); description='IDA Pro MCP: decompile, rename, xref, structs (requires IDA 9.4+ with idalib)' }
    }
}
$mcpPath = Join-Path $EchoHome 'mcp.json'
$mcp | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $mcpPath
Ok "mcp.json -> $mcpPath"

# ── 9. register MCP servers with Claude Code ─────────────────────────────────
Say 'Registering MCP servers with Claude Code'
function Register-Mcp {
    param([string]$mcpName, [string[]]$cmdArgs)
    $list = (claude mcp list 2>&1 | Out-String)
    if ($list -match "(?m)^\s*$([regex]::Escape($mcpName))\b") { Ok "MCP $mcpName already registered"; return }
    $null = claude mcp add --scope user $mcpName @cmdArgs 2>&1
    if ($LASTEXITCODE -eq 0) { Ok "MCP $mcpName registered" } else { Skip "MCP $mcpName" 'registration failed — add manually from mcp.json' }
}
if (Test-Path (Join-Path $EchoHome 'mcp-gamehacking\dist\index.js')) {
    Register-Mcp 'gamehacking' @('node', ($ghEntry -replace '/','\\'))
}
Register-Mcp 'rea' @('npx', '-y', 'rea-agents')
if (Test-Path (Join-Path $EchoHome 'angel-menu-mcp\index.js')) {
    Register-Mcp 'angel-menu' @('node', ($amEntry -replace '/','\\'))
}
if (Have r2pm) { Register-Mcp 'radare2' @('r2pm', '-r', 'r2mcp') }
Register-Mcp 'ida' @('uvx', 'ida-mcp', 'stdio', '--agent=echo')

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

$sdDir2 = Join-Path $EchoHome 'signature-doctor'
Write-Host @"

  Next:
    1. Restart Claude Code (or run /reload-plugins)
    2. Type  /echo-help        to list the 12 agents
    3. Type  /echo-esp         to load ESP context
       ...or just describe your task - keywords auto-route.

  Signature Doctor (offset/sig health dashboard):
    node "$sdDir2\server\index.mjs"  -->  http://127.0.0.1:3210

  Tools are in $EchoHome
  Verify at any time:  .\scripts\echo-doctor.ps1
  Templates: templates\*.as  ->  %AppData%\Roaming\scripts\
  Full API:  reference\api.md
------------------------------------------------------------
"@

if ($script:Failed.Count) { exit 1 }
