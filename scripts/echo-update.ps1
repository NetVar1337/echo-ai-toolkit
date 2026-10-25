# echo update — update the toolkit, the Pi profile, Pi itself, and the companion tools.
#
#   echo update                 everything (toolkit + profile + pi --all + tools)
#   echo update --extensions    Pi packages/extensions only (+ profile resync)
#   echo update --self          the Pi binary only
#   echo update --models        Pi model catalogs only
#   echo update --all           Pi and its packages (same as `pi update --all`)
#   echo update --tools         companion tools only (git pull + rebuild)
#   echo update --profile       resync the Echo profile from the toolkit only
#
# Flags Pi understands are passed straight through: --self --extensions --models
# --all --force. Two flags are ours: --tools and --profile.
$ErrorActionPreference = 'Continue'

$Repo      = 'NetVar1337/echo-ai-toolkit'
$Plugin    = 'echo-ai-toolkit'
$EchoHome  = if ($env:ECHO_HOME) { $env:ECHO_HOME } else { Join-Path $HOME '.local\share\echo-ai-toolkit' }
$BinDir    = Join-Path $EchoHome 'bin'
$ProfileDir = Join-Path $EchoHome 'pi'
$RefDir    = Join-Path $EchoHome 'reference'

$script:OK = @(); $script:Skipped = @(); $script:Failed = @()

function Say  { Write-Host "`n==> $args" -ForegroundColor Yellow }
function Sub  { Write-Host "    $args" }
function Ok   { param($m) $script:OK += $m;      Write-Host "    OK     $m" -ForegroundColor Green }
function Skip { param($m,$r) $script:Skipped += "${m}: $r"; Write-Host "    skip   $m - $r" -ForegroundColor Magenta }
function Fail { param($m,$r) $script:Failed += "${m}: $r";  Write-Host "    FAIL   $m - $r" -ForegroundColor Red }
function Have { param($c) $null -ne (Get-Command $c -ErrorAction SilentlyContinue) }

# ── argument parsing ─────────────────────────────────────────────────────────
$piFlags = @(); $doTools = $false; $doProfile = $false; $explicit = $false
foreach ($a in $args) {
    switch -Regex ($a) {
        '^--tools$'      { $doTools = $true;   $explicit = $true; continue }
        '^--profile$'    { $doProfile = $true; $explicit = $true; continue }
        '^--(extensions|self|models|all|force)$' { $piFlags += $a; $explicit = $true; continue }
        '^(-h|--help)$'  {
            Get-Content $PSCommandPath | Select-Object -Skip 1 |
                ForEach-Object { if ($_ -match '^#') { $_ -replace '^# ?','' } else { break } } |
                Write-Host
            exit 0
        }
        default {
            Write-Host "unknown option: $a" -ForegroundColor Red
            Write-Host "run 'echo update --help'"
            exit 2
        }
    }
}

if (-not $explicit) { $doTools = $true; $doProfile = $true; $piFlags = @('--all') }
if ($piFlags.Count -gt 0 -and -not $doProfile -and -not $doTools) {
    if ($piFlags -notcontains '--self' -and $piFlags -notcontains '--models') { $doProfile = $true }
}

Write-Host "`nEcho update  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor White

# ── 1. toolkit plugin ────────────────────────────────────────────────────────
# Only when resyncing the profile or the tools. A Pi-only request (--self,
# --models) leaves the toolkit alone.
if ($doProfile -or $doTools) {
    if (Have claude) {
        Say 'Toolkit plugin'
        $null = claude plugin marketplace update $Plugin 2>&1
        if ($LASTEXITCODE -eq 0) { Ok 'marketplace updated' } else { Skip 'marketplace' 'update failed (offline?)' }
        $null = claude plugin update $Plugin 2>&1
        if ($LASTEXITCODE -eq 0) { Ok 'plugin updated' } else { Skip 'plugin' 'already current or update failed' }
    } else { Skip 'toolkit plugin' 'claude CLI not found' }
}

# ── 2. Echo profile ──────────────────────────────────────────────────────────
if ($doProfile) {
    Say 'Echo profile'
    $src = Join-Path $HOME ".claude\plugins\marketplaces\$Plugin"
    if (Test-Path (Join-Path $src 'pi')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $ProfileDir 'prompts'), (Join-Path $ProfileDir 'skills') | Out-Null
        foreach ($f in 'SYSTEM.md','APPEND_SYSTEM.md','AGENTS.md') {
            $s = Join-Path $src "pi\$f"
            if (Test-Path $s) { Copy-Item $s (Join-Path $ProfileDir $f) -Force }
        }
        Get-ChildItem (Join-Path $src 'pi\prompts') -Filter *.md -ErrorAction SilentlyContinue |
            ForEach-Object { Copy-Item $_.FullName (Join-Path $ProfileDir 'prompts') -Force }
        $n = 0
        Get-ChildItem (Join-Path $src 'skills') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $skillMd = Join-Path $_.FullName 'SKILL.md'
            if (Test-Path $skillMd) {
                $dest = Join-Path $ProfileDir "skills\$($_.Name)"
                New-Item -ItemType Directory -Force -Path $dest | Out-Null
                Copy-Item $skillMd (Join-Path $dest 'SKILL.md') -Force
                $n++
            }
        }
        $np = (Get-ChildItem (Join-Path $ProfileDir 'prompts') -Filter *.md -ErrorAction SilentlyContinue).Count
        Ok "profile resynced ($n skills, $np templates)"

        $launcher = Join-Path $src 'pi\bin\echo.ps1'
        if (Test-Path $launcher) {
            New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
            Copy-Item $launcher (Join-Path $BinDir 'echo.ps1') -Force
            Ok 'launcher refreshed'
        }
    } else {
        Skip 'profile' "marketplace clone not found at $src"
    }
}

# ── 3. Pi itself / extensions ────────────────────────────────────────────────
if ($piFlags.Count -gt 0) {
    if (Have pi) {
        Say "Pi $($piFlags -join ' ')"
        & pi update @piFlags
        if ($LASTEXITCODE -eq 0) { Ok "pi update $($piFlags -join ' ')" } else { Skip 'pi update' 'command failed (auth or network?)' }
    } else { Skip 'pi update' 'pi not installed' }
}

# ── 4. companion tools ───────────────────────────────────────────────────────
if ($doTools) {
    Say 'Companion tools'

    function Update-Git($name, [string]$build) {
        $dir = Join-Path $EchoHome $name
        if (-not (Test-Path (Join-Path $dir '.git'))) { Skip $name 'not installed'; return }
        Push-Location $dir
        git pull --ff-only --quiet 2>&1 | Out-Null
        $pulled = ($LASTEXITCODE -eq 0)
        $head = (git rev-parse --short HEAD 2>$null)
        if (-not $pulled) { Pop-Location; Skip $name 'git pull failed (local changes or offline)'; return }
        if ($build) {
            Sub "rebuilding $name..."
            Invoke-Expression $build 2>&1 | Out-Null
            $rc = $LASTEXITCODE
            Pop-Location
            if ($rc -eq 0) { Ok "$name @ $head (rebuilt)" } else { Fail $name 'rebuild failed' }
        } else { Pop-Location; Ok "$name @ $head" }
    }

    Update-Git 'mcp-gamehacking'            'npm install --silent; npm run build --silent'
    Update-Git 'angel-menu-mcp'             'npm install --silent'
    Update-Git 'VMProtect-devirtualization' ''
    Update-Git 'vmp-lazy-unpack'            ''
    Update-Git 'web-mv'                     ''
    Update-Git 'VTIL-Core'                  'cmake -B build -DCMAKE_BUILD_TYPE=Release; cmake --build build --config Release'
    Update-Git 'NoVmp'                      'cmake -B build -DCMAKE_BUILD_TYPE=Release; cmake --build build --config Release'
    Update-Git 'vtil2'                      'dotnet build -c Release'

    # Version-pinned binary.
    try {
        $rel = Invoke-RestMethod -UseBasicParsing -Uri `
            'https://api.github.com/repos/sinistercodes/as_bundler/releases/latest' -ErrorAction Stop
        $tag = $rel.tag_name
        $out = Join-Path $BinDir 'as_bundler.exe'
        Invoke-WebRequest -UseBasicParsing -Uri `
            "https://github.com/sinistercodes/as_bundler/releases/download/$tag/as_bundler.exe" `
            -OutFile $out -ErrorAction Stop
        Ok "as_bundler $tag"
    } catch { Skip 'as_bundler' 'release lookup or download failed' }

    # Python packages in the venv.
    $venvPy = Join-Path $EchoHome 'venv\Scripts\python.exe'
    if (Test-Path $venvPy) {
        & $venvPy -m pip install --quiet --disable-pip-version-check -U triton-library 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Ok 'triton' } else { Skip 'triton' 'pip -U failed' }
    } else { Skip 'triton' 'no venv' }

    # Reference READMEs.
    foreach ($pair in @(@('awesome-game-security','gmh5225/awesome-game-security'),
                        @('gamehacking-cheatsheet','ridpath/gamehacking-cheatsheet'))) {
        try {
            $out = Join-Path $RefDir "$($pair[0]).md"
            New-Item -ItemType Directory -Force -Path $RefDir | Out-Null
            Invoke-WebRequest -UseBasicParsing -Uri `
                "https://raw.githubusercontent.com/$($pair[1])/HEAD/README.md" -OutFile $out -ErrorAction Stop
            Ok "$($pair[0]) ($((Get-Item $out).Length) bytes)"
        } catch { Skip $pair[0] 'download failed' }
    }
}

# ── summary ──────────────────────────────────────────────────────────────────
Write-Host "`n------------------------------------------------------------"
Write-Host ("  {0} updated" -f $script:OK.Count) -ForegroundColor Green -NoNewline
if ($script:Skipped.Count) { Write-Host ("   {0} skipped" -f $script:Skipped.Count) -ForegroundColor Magenta -NoNewline }
if ($script:Failed.Count)  { Write-Host ("   {0} failed"  -f $script:Failed.Count)  -ForegroundColor Red -NoNewline }
Write-Host ''
if ($script:Skipped.Count) { Write-Host "`n  Skipped:"; $script:Skipped | ForEach-Object { Write-Host "    . $_" } }
if ($script:Failed.Count)  { Write-Host "`n  Failed:";  $script:Failed  | ForEach-Object { Write-Host "    . $_" } }
Write-Host "------------------------------------------------------------`n"

if ($script:Failed.Count) { exit 1 }
