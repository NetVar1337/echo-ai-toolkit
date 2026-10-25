#!/usr/bin/env bash
# Echo AI Toolkit — one-command installer.
#
#   curl -fsSL https://raw.githubusercontent.com/NetVar1337/echo-ai-toolkit/main/install.sh | bash
#
# Installs the Claude Code plugin plus every companion tool, skipping anything
# whose prerequisite is missing on this machine. Safe to re-run: every step is
# idempotent.
#
# Tiers (ECHO_TIER, default "standard"):
#   minimal   plugin + MCP servers                      (Node only)
#   standard  + Echo tooling, Python tooling, docs      (Node + Python)
#   full      + compiler-built tools, LLVM, web-mv      (Node + Python + compilers)
set -uo pipefail

REPO="NetVar1337/echo-ai-toolkit"
PLUGIN="echo-ai-toolkit"
TIER="${ECHO_TIER:-standard}"
ECHO_HOME="${ECHO_HOME:-$HOME/.local/share/echo-ai-toolkit}"
BIN_DIR="$ECHO_HOME/bin"
REF_DIR="$ECHO_HOME/reference"

# An unknown tier must not silently mean "download everything".
case "$TIER" in
  minimal|standard|full) ;;
  *) printf '\n\033[1;35m! unknown ECHO_TIER="%s" — using standard\033[0m\n' "$TIER"; TIER=standard ;;
esac

# ── reporting ────────────────────────────────────────────────────────────────
OK=(); SKIPPED=(); FAILED=()
say()  { printf '\n\033[1;33m==> %s\033[0m\n' "$*"; }
sub()  { printf '    %s\n' "$*"; }
ok()   { OK+=("$1");      printf '    \033[1;32mok\033[0m    %s\n' "$1"; }
skip() { SKIPPED+=("$1: $2"); printf '    \033[1;35mskip\033[0m  %s — %s\n' "$1" "$2"; }
fail() { FAILED+=("$1: $2");  printf '    \033[1;31mFAIL\033[0m  %s — %s\n' "$1" "$2"; }
have() { command -v "$1" >/dev/null 2>&1; }
# Wrap anything that can block on a remote process or a stalled connection.
to() { local secs="$1"; shift; timeout "$secs" "$@" 2>/dev/null; }
CURL="curl -fsSL --connect-timeout 10 --max-time 120"

tier_at_least() {
  case "$TIER" in
    minimal)  [ "$1" = "minimal" ] ;;
    standard) [ "$1" = "minimal" ] || [ "$1" = "standard" ] ;;
    full)     : ;;
    *)        : ;;
  esac
}

# ── 0. prerequisites ─────────────────────────────────────────────────────────
say "Checking prerequisites"
have claude || { printf '\n\033[1;31mclaude CLI not found.\033[0m Install Claude Code first: https://claude.com/claude-code\n' >&2; exit 1; }
ok "claude CLI"
have node && ok "node $(node -v 2>/dev/null)" || skip "node" "not found — MCP servers need Node 18+"
have git  && ok "git"                          || skip "git"  "not found — tool clones need git"
have python3 && ok "python3 $(python3 -V 2>&1 | cut -d' ' -f2)" || skip "python3" "not found — Python tooling skipped"
have npm  && ok "npm"                          || skip "npm"  "not found"

mkdir -p "$ECHO_HOME" "$BIN_DIR" "$REF_DIR"

# ── 1. the plugin ────────────────────────────────────────────────────────────
say "Installing the $PLUGIN plugin"
if to 60 claude plugin marketplace list | grep -q "$PLUGIN"; then
  ok "marketplace already registered"
else
  to 120 claude plugin marketplace add "$REPO" >/dev/null \
    && ok "marketplace registered" || fail "marketplace" "could not add $REPO"
fi
if to 60 claude plugin list | grep -q "$PLUGIN"; then
  ok "plugin already installed"
else
  to 180 claude plugin install "$PLUGIN@$PLUGIN" >/dev/null \
    && ok "plugin installed" || fail "plugin" "install failed"
fi

# ── 2. Claude Code companion plugins ─────────────────────────────────────────
say "Claude Code companion plugins"
add_plugin() { # name marketplace
  if to 60 claude plugin list | grep -q "^  .* $1@"; then
    ok "$1 already installed"; return
  fi
  if to 120 claude plugin marketplace add "$2" >/dev/null; then
    if to 180 claude plugin install "$1@$3" >/dev/null; then ok "$1"; else skip "$1" "install failed"; fi
  else
    skip "$1" "marketplace $2 unreachable"
  fi
}
add_plugin ponytail  "DietrichGebert/ponytail"                  ponytail
add_plugin andrej-karpathy-skills "forrestchang/andrej-karpathy-skills" karpathy-skills

# ── 3. MCP servers ───────────────────────────────────────────────────────────
say "MCP servers"
have node && have npm || skip "MCP servers" "Node 18+ required"

clone_build_node() { # name repo entry
  local name="$1" repo="$2" entry="$3" dir="$ECHO_HOME/$1"
  if [ -f "$dir/$entry" ]; then ok "$name already built"; return; fi
  if [ ! -d "$dir/.git" ]; then
    sub "cloning $name…"
    git clone --depth 1 "https://github.com/$repo" "$dir" >/dev/null 2>&1 \
      || { fail "$name" "clone failed"; return; }
  fi
  sub "building $name (npm install + build — this is the slow step, a few minutes)…"
  ( cd "$dir" \
      && npm install --silent >/dev/null 2>&1 \
      && { node -e "process.exit(require('./package.json').scripts?.build?0:1)" 2>/dev/null \
             && npm run build --silent >/dev/null 2>&1 || true; } ) \
    || { fail "$name" "npm install failed"; return; }
  [ -f "$dir/$entry" ] && ok "$name" || fail "$name" "expected $entry after install"
}

if have node && have npm && [ "${ECHO_SKIP_MCP:-0}" != "1" ]; then
  # mcp-gamehacking carries an 18 GB skills library (8259 files). Never fetch that
  # without asking: opt in with ECHO_WITH_GAMEHACKING=1.
  if [ "${ECHO_WITH_GAMEHACKING:-0}" = "1" ]; then
    sub "mcp-gamehacking is ~3.1 GB on disk — this takes a while…"
    clone_build_node mcp-gamehacking 1llu50ry/mcp-gamehacking dist/index.js
  else
    skip "mcp-gamehacking" "~3.1 GB of content — re-run with ECHO_WITH_GAMEHACKING=1 to install"
  fi
  clone_build_node angel-menu-mcp Jozkah/angel-menu-mcp index.js
elif [ "${ECHO_SKIP_MCP:-0}" = "1" ]; then
  skip "MCP servers" "ECHO_SKIP_MCP=1"
fi

# ── 4. Echo-side tooling ─────────────────────────────────────────────────────
if tier_at_least standard; then
say "Echo tooling"

# as_bundler — prebuilt release binaries, no toolchain needed.
AS_BUNDLER_VER="v1.5.0"
install_as_bundler() {
  case "$(uname -s)" in
    Linux)   asset="as_bundler";     out="$BIN_DIR/as_bundler" ;;
    MINGW*|MSYS*|CYGWIN*) asset="as_bundler.exe"; out="$BIN_DIR/as_bundler.exe" ;;
    *)       skip "as_bundler" "no prebuilt binary for $(uname -s)"; return ;;
  esac
  [ -x "$out" ] && { ok "as_bundler already installed"; return; }
  $CURL "https://github.com/sinistercodes/as_bundler/releases/download/$AS_BUNDLER_VER/$asset" -o "$out" \
    && chmod +x "$out" && ok "as_bundler $AS_BUNDLER_VER" || fail "as_bundler" "download failed"
}
install_as_bundler

# echo-esp-preview — a single AngelScript drop-in file.
install_esp_preview() {
  local target
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) target="${APPDATA:-$HOME/AppData/Roaming}/scripts/esp_preview.as" ;;
    *)                    target="$REF_DIR/esp_preview.as" ;;
  esac
  mkdir -p "$(dirname "$target")"
  $CURL "https://raw.githubusercontent.com/speedsunderscore/echo-esp-preview/HEAD/esp_preview.as" -o "$target" \
    && ok "esp_preview.as -> $target" || fail "esp_preview" "download failed"
}
install_esp_preview

# echo-angelscript-lsp — VS Code extension (.vsix inside a release zip).
install_lsp() {
  local ver="0.0.10" tmp
  have code || { skip "echo-angelscript-lsp" "VS Code 'code' CLI not on PATH"; return; }
  if to 20 code --list-extensions | grep -qi 'echo-angelscript-lsp'; then
    ok "echo-angelscript-lsp already installed"; return
  fi
  tmp="$(mktemp -d)"
  $CURL "https://github.com/speedsunderscore/echo-angelscript-lsp/releases/download/$ver/echo-angelscript-lsp-$ver.zip" -o "$tmp/lsp.zip" \
    || { fail "echo-angelscript-lsp" "download failed"; rm -rf "$tmp"; return; }
  unzip -qo "$tmp/lsp.zip" -d "$tmp" 2>/dev/null || { fail "echo-angelscript-lsp" "unzip failed"; rm -rf "$tmp"; return; }
  local vsix; vsix="$(find "$tmp" -name '*.vsix' | head -1)"
  [ -n "$vsix" ] || { fail "echo-angelscript-lsp" "no .vsix in archive"; rm -rf "$tmp"; return; }
  to 120 code --install-extension "$vsix" --force \
    && ok "echo-angelscript-lsp $ver" \
    || skip "echo-angelscript-lsp" "code --install-extension failed — if 'code' is not VS Code (e.g. code-oss), install the .vsix manually: $vsix"
  rm -rf "$tmp"
}
install_lsp

# web-mv — Bun relay + SolidJS UI (source only; no releases published).
install_web_mv() {
  local dir="$ECHO_HOME/web-mv"
  if ! have bun; then
    skip "web-mv" "Bun not installed (https://bun.sh)"; return
  fi
  if [ ! -d "$dir/.git" ]; then
    git clone --depth 1 https://github.com/Jozkah/web-mv "$dir" >/dev/null 2>&1 \
      || { fail "web-mv" "clone failed"; return; }
  fi
  ( cd "$dir/relay" && bun install >/dev/null 2>&1 ) \
    && ok "web-mv (run: cd $dir/relay && bun run start)" || fail "web-mv" "bun install failed"
}
install_web_mv

# Reference docs — the value is the curated list itself, so fetch the README
# rather than cloning. awesome-game-security is 3.19 GB on disk; its README is
# 435 KB and contains everything an AI needs from it.
fetch_doc() { # name repo
  local out="$REF_DIR/$1.md"
  [ -s "$out" ] && { ok "$1 already fetched"; return; }
  $CURL "https://raw.githubusercontent.com/$2/HEAD/README.md" -o "$out" \
    && [ -s "$out" ] && ok "$1 ($(wc -c < "$out") bytes)" || fail "$1" "download failed"
}
fetch_doc awesome-game-security  gmh5225/awesome-game-security
fetch_doc gamehacking-cheatsheet ridpath/gamehacking-cheatsheet
fi

# ── 5. Python reverse-engineering tooling ────────────────────────────────────
if tier_at_least standard; then
say "Python reverse-engineering tooling"
have python3 || skip "Python tooling" "python3 not found"

if have python3; then
  # Many distros (Kali, Debian, Arch) refuse a system-wide pip install (PEP 668).
  # A dedicated venv is the portable answer and keeps the system Python untouched.
  VENV="$ECHO_HOME/venv"
  PIP=""
  if [ -x "$VENV/bin/python" ]; then
    PIP="$VENV/bin/python -m pip"
    ok "python venv already present"
  elif python3 -m venv "$VENV" >/dev/null 2>&1; then
    PIP="$VENV/bin/python -m pip"
    ok "python venv created ($VENV)"
  else
    # No venv support (missing ensurepip). Fall back to --user, then system.
    if python3 -m pip install --user --quiet --disable-pip-version-check pip >/dev/null 2>&1; then
      PIP="python3 -m pip install --user"
      ok "python (--user fallback)"
    else
      PIP="python3 -m pip"
      skip "python venv" "ensurepip unavailable — falling back to system pip"
    fi
  fi

  # Normalise: PIP is a command prefix; append install args after it.
  pip_install() { # label package
    $PIP install --quiet --disable-pip-version-check "$2" >/dev/null 2>&1 \
      && ok "$1" || skip "$1" "pip install $2 failed"
  }

  # Triton — symbolic execution. The PyPI package is "triton-library" (NOT "triton",
  # which is OpenAI's GPU compiler).
  if "$VENV/bin/python" -c 'import triton' >/dev/null 2>&1 || python3 -c 'import triton' >/dev/null 2>&1; then
    ok "triton already installed"
  else
    pip_install "triton (symbolic execution)" triton-library
  fi

  clone_py() { # name repo
    local dir="$ECHO_HOME/$1"
    if [ -d "$dir/.git" ]; then ok "$1 already cloned"; return; fi
    git clone --depth 1 "https://github.com/$2" "$dir" >/dev/null 2>&1 \
      && ok "$1" || fail "$1" "clone failed"
  }
  clone_py VMProtect-devirtualization JonathanSalwan/VMProtect-devirtualization
  clone_py vmp-lazy-unpack             x86rc/vmp-lazy-unpack

  # vmp-lazy-unpack is a Python package: install it editable so `py -m unpack` works.
  if [ -d "$ECHO_HOME/vmp-lazy-unpack" ]; then
    ( cd "$ECHO_HOME/vmp-lazy-unpack" && $PIP install --quiet -e . >/dev/null 2>&1 ) \
      && ok "vmp-lazy-unpack (pip -e)" || skip "vmp-lazy-unpack" "pip -e failed (Windows-only tool)"
  fi

  [ -x "$VENV/bin/python" ] && sub "use the venv: source $VENV/bin/activate"
fi
fi

# ── 6. Compiler-built devirtualization stack ─────────────────────────────────
if tier_at_least full; then
say "Compiler-built tooling (tier: full)"

# VTIL-Core / NoVmp — C++ via CMake. NoVmp vendors VTIL-Core as a submodule.
build_cmake() { # name repo submodules
  local name="$1" repo="$2" subs="${3:-}" dir="$ECHO_HOME/$1"
  have cmake || { skip "$name" "cmake not found"; return; }
  if [ ! -d "$dir/.git" ]; then
    git clone --depth 1 $subs "https://github.com/$repo" "$dir" >/dev/null 2>&1 \
      || { fail "$name" "clone failed"; return; }
  fi
  ( cd "$dir" && cmake -B build -DCMAKE_BUILD_TYPE=Release >/dev/null 2>&1 \
      && cmake --build build --config Release -j >/dev/null 2>&1 ) \
    && ok "$name" || skip "$name" "cmake build failed (needs a C++ toolchain)"
}
build_cmake VTIL-Core vtil-project/VTIL-Core
build_cmake NoVmp     can1357/NoVmp        "--recurse-submodules --shallow-submodules"

# vtil2 — .NET 8.
if have dotnet; then
  if [ ! -d "$ECHO_HOME/vtil2/.git" ]; then
    git clone --depth 1 https://github.com/pop-rip/vtil2 "$ECHO_HOME/vtil2" >/dev/null 2>&1
  fi
  if [ -d "$ECHO_HOME/vtil2" ]; then
    ( cd "$ECHO_HOME/vtil2" && dotnet build -c Release >/dev/null 2>&1 ) \
      && ok "vtil2" || skip "vtil2" "dotnet build failed"
  fi
else
  skip "vtil2" "dotnet (.NET 8 SDK) not found"
fi

# LLVM — only for Triton's LLVM interface and OLLVM passes. Never build from source:
# use the platform package.
if have llvm-config || have opt; then
  ok "LLVM already present"
else
  case "$(uname -s)" in
    Darwin) have brew && { brew install llvm >/dev/null 2>&1 && ok "LLVM (brew)" || skip "LLVM" "brew install failed"; } || skip "LLVM" "brew not found" ;;
    Linux)  if have apt-get; then
              sudo apt-get install -y llvm >/dev/null 2>&1 && ok "LLVM (apt)" || skip "LLVM" "apt install failed (try: sudo apt install llvm)"
            else skip "LLVM" "no apt-get — install LLVM manually"; fi ;;
    *)      skip "LLVM" "install LLVM manually (winget install LLVM.LLVM)" ;;
  esac
fi
fi

# ── 7. write .mcp.json ───────────────────────────────────────────────────────
say "Writing .mcp.json"
GH_ENTRY="$ECHO_HOME/mcp-gamehacking/dist/index.js"
AM_ENTRY="$ECHO_HOME/angel-menu-mcp/index.js"
{
  printf '{\n  "mcpServers": {\n'
  first=1
  add_server() { # name command args-json description
    [ $first -eq 1 ] || printf ',\n'
    first=0
    printf '    "%s": {\n      "command": "%s",\n      "args": %s,\n      "description": "%s"\n    }' \
      "$1" "$2" "$3" "$4"
  }
  add_server gamehacking node "[\"$GH_ENTRY\"]" "mcp-gamehacking: 4100+ game hacking skills, 75 specialist agents, 19+ MCP tools"
  add_server rea npx '["-y","rea-agents"]' "REA: Reverse Engineer Anything — Unity IL2CPP, Godot, native binaries, APK, WASM, firmware"
  add_server angel-menu node "[\"$AM_ENTRY\"]" "Echo overlay menu control: list_features, get_feature, set_feature, connection_status"
  printf '\n  }\n}\n'
} > "$ECHO_HOME/mcp.json"
ok ".mcp.json -> $ECHO_HOME/mcp.json"

# ── summary ──────────────────────────────────────────────────────────────────
printf '\n\033[1m────────────────────────────────────────────────────────────\033[0m\n'
printf '  \033[1;32m%d installed\033[0m' "${#OK[@]}"
[ ${#SKIPPED[@]} -gt 0 ] && printf '   \033[1;35m%d skipped\033[0m' "${#SKIPPED[@]}"
[ ${#FAILED[@]}  -gt 0 ] && printf '   \033[1;31m%d failed\033[0m'  "${#FAILED[@]}"
printf '\n'
if [ ${#SKIPPED[@]} -gt 0 ]; then
  printf '\n  Skipped:\n'
  for s in "${SKIPPED[@]}"; do printf '    · %s\n' "$s"; done
fi
if [ ${#FAILED[@]} -gt 0 ]; then
  printf '\n  Failed:\n'
  for s in "${FAILED[@]}"; do printf '    · %s\n' "$s"; done
fi

cat <<EOF

  Next:
    1. Restart Claude Code (or run /reload-plugins)
    2. Type  /echo-help        to list the 12 agents
    3. Type  /echo-esp         to load ESP context
       ...or just describe your task — keywords auto-route.

  Tools are in $ECHO_HOME
  Verify at any time:  ./scripts/echo-doctor.sh
  Templates: templates/*.as  →  %AppData%\\Roaming\\scripts\\
  Full API:  reference/api.md
EOF
printf '  \033[1m────────────────────────────────────────────────────────────\033[0m\n\n'

[ ${#FAILED[@]} -eq 0 ] || exit 1
