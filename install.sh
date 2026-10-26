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
TIER="${ECHO_TIER:-full}"
ECHO_HOME="${ECHO_HOME:-$HOME/.local/share/echo-ai-toolkit}"
BIN_DIR="$ECHO_HOME/bin"
REF_DIR="$ECHO_HOME/reference"

# An unknown tier must not silently mean "download everything".
case "$TIER" in
  minimal|standard|full) ;;
  *) printf '\n\033[1;35m! unknown ECHO_TIER="%s" — using standard\033[0m\n' "$TIER"; TIER=standard ;;
esac

# Where the repo lives. When run via `curl | bash` there is no repo, so fetch the
# Pi profile files instead of copying them.
REPO_SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
[ -d "$REPO_SRC/pi" ] || REPO_SRC=""

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

# ── tool lock ────────────────────────────────────────────────────────────────
# tools.lock pins every external artifact, so two installs are the same software.
# The repo copy wins; under `curl | bash` there is none, so fetch it.
LOCK="$ECHO_HOME/tools.lock"
mkdir -p "$ECHO_HOME"
if [ -n "$REPO_SRC" ] && [ -f "$REPO_SRC/tools.lock" ]; then
  cp -f "$REPO_SRC/tools.lock" "$LOCK" 2>/dev/null
fi
if [ ! -s "$LOCK" ]; then
  $CURL "https://raw.githubusercontent.com/$REPO/main/tools.lock" -o "$LOCK" 2>/dev/null
fi
[ -s "$LOCK" ] || printf '\033[1;35m! tools.lock unavailable — falling back to branch heads\033[0m\n'

lock_pin() { # kind name → pin (sha / version / sha256)
  [ -s "$LOCK" ] || return 0
  awk -v k="$1" -v n="$2" '$1==k && $2==n {print $4; exit}' "$LOCK"
}
lock_ref() { # kind name → ref (repo, package, or url)
  [ -s "$LOCK" ] || return 0
  awk -v k="$1" -v n="$2" '$1==k && $2==n {print $3; exit}' "$LOCK"
}

verify_sha() { # file expected-sha256
  local want="$2" got=""
  [ -n "$want" ] || return 0
  if have sha256sum; then got=$(sha256sum "$1" 2>/dev/null | cut -d' ' -f1)
  elif have shasum;  then got=$(shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1)
  else return 0; fi   # no hasher: pinning still pins the URL, integrity is best-effort
  [ "$got" = "$want" ]
}

fetch_asset() { # name url out [sha256]
  $CURL "$2" -o "$3" || { fail "$1" "download failed"; return 1; }
  if ! verify_sha "$3" "$4"; then
    rm -f "$3"; fail "$1" "sha256 mismatch — upstream asset changed"; return 1
  fi
}

clone_at() { # name repo dir [submodules]
  local name="$1" repo="$2" dir="$3" subs="${4:-0}" sha
  sha="$(lock_pin clone "$name")"
  if [ -z "$sha" ]; then
    sub "cloning $name (branch head — not in tools.lock)…"
    git clone --depth 1 "https://github.com/$repo" "$dir" >/dev/null 2>&1
    return $?
  fi
  sub "cloning $name @ ${sha:0:7}…"
  mkdir -p "$dir" || return 1
  git -C "$dir" init -q >/dev/null 2>&1 || { fail "$name" "git init failed"; return 1; }
  git -C "$dir" remote add origin "https://github.com/$repo" 2>/dev/null \
    || git -C "$dir" remote set-url origin "https://github.com/$repo"
  git -C "$dir" fetch -q --depth 1 origin "$sha" >/dev/null 2>&1 \
    || { fail "$name" "fetch ${sha:0:7} failed (pinned commit unreachable)"; return 1; }
  git -C "$dir" checkout -q FETCH_HEAD >/dev/null 2>&1 \
    || { fail "$name" "checkout ${sha:0:7} failed"; return 1; }
  if [ "$subs" = "1" ]; then
    git -C "$dir" submodule update --init --recursive --depth 1 >/dev/null 2>&1 || true
  fi
  return 0
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
  # A multi-GB clone can die partway and leave .git behind without a working tree.
  # Treat "has .git but no package.json" as a broken clone and start over.
  if [ -d "$dir/.git" ] && [ ! -f "$dir/package.json" ]; then
    sub "removing incomplete $name clone…"
    rm -rf "$dir"
  fi
  if [ ! -d "$dir/.git" ]; then
    sub "cloning $name…"
    if ! clone_at "$name" "$repo" "$dir"; then
      rm -rf "$dir"
      return
    fi
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
  # mcp-gamehacking is part of a full install: 18 GB of skills on disk, ~3.1 GB
  # over the wire. Skip it with ECHO_SKIP_GAMEHACKING=1.
  if [ "${ECHO_SKIP_GAMEHACKING:-0}" = "1" ]; then
    skip "mcp-gamehacking" "ECHO_SKIP_GAMEHACKING=1"
  else
    sub "mcp-gamehacking is ~3.1 GB — this is the long step, give it time…"
    clone_build_node mcp-gamehacking 1llu50ry/mcp-gamehacking dist/index.js
  fi
  clone_build_node angel-menu-mcp Jozkah/angel-menu-mcp index.js
elif [ "${ECHO_SKIP_MCP:-0}" = "1" ]; then
  skip "MCP servers" "ECHO_SKIP_MCP=1"
fi

# ── 4. Echo-side tooling ─────────────────────────────────────────────────────
if tier_at_least standard; then
say "Echo tooling"

# as_bundler — prebuilt release binaries, no toolchain needed.
install_as_bundler() {
  local asset out
  case "$(uname -s)" in
    Linux)   asset="as_bundler";     out="$BIN_DIR/as_bundler" ;;
    MINGW*|MSYS*|CYGWIN*) asset="as_bundler.exe"; out="$BIN_DIR/as_bundler.exe" ;;
    *)       skip "as_bundler" "no prebuilt binary for $(uname -s)"; return ;;
  esac
  [ -x "$out" ] && { ok "as_bundler already installed"; return; }
  local url sha
  url="$(lock_ref asset "$asset")"; sha="$(lock_pin asset "$asset")"
  [ -n "$url" ] || { skip "as_bundler" "not in tools.lock"; return; }
  fetch_asset as_bundler "$url" "$out" "$sha" \
    && chmod +x "$out" && ok "as_bundler $(basename "$(dirname "$url")")"
}
install_as_bundler

# echo-esp-preview — a single AngelScript drop-in file.
install_esp_preview() {
  local target url sha
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) target="${APPDATA:-$HOME/AppData/Roaming}/scripts/esp_preview.as" ;;
    *)                    target="$REF_DIR/esp_preview.as" ;;
  esac
  mkdir -p "$(dirname "$target")"
  url="$(lock_ref raw esp_preview.as)"; sha="$(lock_pin raw esp_preview.as)"
  [ -n "$url" ] || { skip "esp_preview" "not in tools.lock"; return; }
  fetch_asset esp_preview "$url" "$target" "$sha" && ok "esp_preview.as -> $target"
}
install_esp_preview

# echo-angelscript-lsp — VS Code extension (.vsix inside a release zip).
install_lsp() {
  local zip_name="echo-angelscript-lsp-0.0.10.zip" url sha tmp
  have code || { skip "echo-angelscript-lsp" "VS Code 'code' CLI not on PATH"; return; }
  if to 20 code --list-extensions | grep -qi 'echo-angelscript-lsp'; then
    ok "echo-angelscript-lsp already installed"; return
  fi
  url="$(lock_ref asset "$zip_name")"; sha="$(lock_pin asset "$zip_name")"
  [ -n "$url" ] || { skip "echo-angelscript-lsp" "not in tools.lock"; return; }
  tmp="$(mktemp -d)"
  fetch_asset echo-angelscript-lsp "$url" "$tmp/lsp.zip" "$sha" \
    || { rm -rf "$tmp"; return; }
  unzip -qo "$tmp/lsp.zip" -d "$tmp" 2>/dev/null || { fail "echo-angelscript-lsp" "unzip failed"; rm -rf "$tmp"; return; }
  local vsix; vsix="$(find "$tmp" -name '*.vsix' | head -1)"
  [ -n "$vsix" ] || { fail "echo-angelscript-lsp" "no .vsix in archive"; rm -rf "$tmp"; return; }
  to 120 code --install-extension "$vsix" --force \
    && ok "echo-angelscript-lsp 0.0.10" \
    || skip "echo-angelscript-lsp" "code --install-extension failed — if 'code' is not VS Code (e.g. code-oss), install the .vsix manually: $vsix"
  rm -rf "$tmp"
}
install_lsp

# web-mv — Bun relay + SolidJS UI (source only; no releases published).
install_web_mv() {
  local dir="$ECHO_HOME/web-mv"
  # web-mv needs Bun; install it rather than skipping, so a full install is complete.
  if ! have bun; then
    sub "installing Bun (needed by web-mv)…"
    if have curl; then
      curl -fsSL https://bun.sh/install 2>/dev/null | bash >/dev/null 2>&1
      [ -x "$HOME/.bun/bin/bun" ] && export PATH="$HOME/.bun/bin:$PATH"
    fi
    if ! have bun; then skip "web-mv" "Bun install failed (https://bun.sh)"; return; fi
    ok "bun $(bun --version 2>/dev/null)"
  fi
  if [ ! -d "$dir/.git" ]; then
    clone_at web-mv Jozkah/web-mv "$dir" || { fail "web-mv" "clone failed"; return; }
  fi
  ( cd "$dir/relay" && bun install >/dev/null 2>&1 ) \
    && ok "web-mv (run: cd $dir/relay && bun run start)" || fail "web-mv" "bun install failed"
}
install_web_mv

# Reference docs — the value is the curated list itself, so fetch the README
# rather than cloning. awesome-game-security is 3.19 GB on disk; its README is
# 435 KB and contains everything an AI needs from it.
fetch_doc() { # name — URL and sha256 come from tools.lock
  local out="$REF_DIR/$1.md" url sha
  [ -s "$out" ] && { ok "$1 already fetched"; return; }
  url="$(lock_ref raw "$1.md")"; sha="$(lock_pin raw "$1.md")"
  [ -n "$url" ] || { skip "$1" "not in tools.lock"; return; }
  fetch_asset "$1" "$url" "$out" "$sha" && [ -s "$out" ] \
    && ok "$1 ($(wc -c < "$out") bytes)"
}
fetch_doc awesome-game-security
fetch_doc gamehacking-cheatsheet
fi

# ── 5. Pi coding agent ───────────────────────────────────────────────────────
if tier_at_least standard; then
say "Pi coding agent"

# Pi is a separate harness. The profile is plain Markdown and useful on its own,
# so always write it; the `pi` binary itself is optional.
install_pi() {
  local profile="$ECHO_HOME/pi" src="$REPO_SRC/pi"

  mkdir -p "$profile/prompts" "$profile/skills"

  # With a local repo, copy. Under `curl | bash` there is none, so fetch.
  if [ -n "$src" ] && [ -d "$src" ]; then
    for f in SYSTEM.md APPEND_SYSTEM.md AGENTS.md; do
      [ -f "$src/$f" ] && cp -f "$src/$f" "$profile/$f"
    done
    cp -f "$src"/prompts/*.md "$profile/prompts/" 2>/dev/null
    local d name n=0
    for d in "$REPO_SRC"/skills/*/; do
      [ -f "$d/SKILL.md" ] || continue
      name=$(basename "$d")
      mkdir -p "$profile/skills/$name"
      cp -f "$d/SKILL.md" "$profile/skills/$name/SKILL.md"
      n=$((n+1))
    done
    [ -f "$src/bin/echo" ] && cp -f "$src/bin/echo" "$BIN_DIR/echo"
  else
    local base="https://raw.githubusercontent.com/$REPO/main"
    for f in SYSTEM.md APPEND_SYSTEM.md AGENTS.md; do
      $CURL "$base/pi/$f" -o "$profile/$f"
    done
    for p in echo-api echo-esp echo-reverse echo-verify; do
      $CURL "$base/pi/prompts/$p.md" -o "$profile/prompts/$p.md"
    done
    $CURL "$base/pi/bin/echo" -o "$BIN_DIR/echo"
    local n=0
    # Skills are fetched from the marketplace clone the plugin manager keeps.
    local skill_src
    skill_src="$(ls -d "$HOME"/.claude/plugins/marketplaces/echo-ai-toolkit/skills 2>/dev/null | head -1)"
    if [ -n "$skill_src" ] && [ -d "$skill_src" ]; then
      local d name
      for d in "$skill_src"/*/; do
        [ -f "$d/SKILL.md" ] || continue
        name=$(basename "$d")
        mkdir -p "$profile/skills/$name"
        cp -f "$d/SKILL.md" "$profile/skills/$name/SKILL.md"
        n=$((n+1))
      done
    fi
  fi
  chmod +x "$BIN_DIR/echo" 2>/dev/null

  # The launcher dispatches to these, so they must sit next to it.
  for s in echo.mjs echo-update.sh echo-doctor.sh; do
    if [ -f "$REPO_SRC/scripts/$s" ]; then
      cp -f "$REPO_SRC/scripts/$s" "$BIN_DIR/$s" && chmod +x "$BIN_DIR/$s"
    else
      $CURL "https://raw.githubusercontent.com/$REPO/main/scripts/$s" -o "$BIN_DIR/$s" 2>/dev/null \
        && chmod +x "$BIN_DIR/$s"
    fi
  done

  # MCP: reuse the same server set the toolkit writes.
  [ -f "$ECHO_HOME/mcp.json" ] && cp -f "$ECHO_HOME/mcp.json" "$profile/mcp.json"

  # settings.json — resource paths, resolved from the agent dir.
  cat > "$profile/settings.json" <<'JSON'
{
  "skills": ["./skills"],
  "prompts": ["./prompts"]
}
JSON

  ok "pi profile -> $profile ($(ls "$profile/skills" 2>/dev/null | wc -l) skills, $(ls "$profile/prompts" 2>/dev/null | wc -l) prompt templates)"
  [ -x "$BIN_DIR/echo" ] && ok "launcher -> $BIN_DIR/echo"

  # 6. `echo` alias. This shadows the shell builtin in interactive shells only.
  if [ "${ECHO_NO_ALIAS:-0}" != "1" ] && [ -n "${HOME:-}" ]; then
    local rc=""
    case "${SHELL:-}" in
      */zsh)  rc="$HOME/.zshrc" ;;
      */bash) rc="$HOME/.bashrc" ;;
    esac
    if [ -n "$rc" ] && [ -f "$rc" ] && ! grep -q 'echo-ai-toolkit: echo alias' "$rc" 2>/dev/null; then
      {
        printf '\n# echo-ai-toolkit: echo alias -> Pi with the Echo profile\n'
        printf '# This shadows the shell builtin in interactive shells only.\n'
        printf '# Remove these lines, or set ECHO_NO_ALIAS=1 and re-run the installer.\n'
        printf "alias echo='%s/echo'\n" "$BIN_DIR"
      } >> "$rc"
      ok "alias added to $rc (shadows the echo builtin — see the comment there)"
    else
      skip "echo alias" "${rc:-no rc file} — add manually: alias echo='$BIN_DIR/echo'"
    fi
  else
    skip "echo alias" "ECHO_NO_ALIAS=1 or no \$HOME"
  fi

  # 7. Is Pi itself present?
  if have pi; then
    ok "pi $(pi --version 2>/dev/null | head -1)"
  else
    skip "pi binary" "install: curl -fsSL https://pi.dev/install.sh | sh  (needs Node 22.19+)"
  fi
}
install_pi
fi

# ── 6. Python reverse-engineering tooling ────────────────────────────────────
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
  # which is OpenAI's GPU compiler). Version comes from tools.lock.
  TRITON="triton-library"
  TRITON_VER="$(lock_pin pip triton-library)"
  [ -n "$TRITON_VER" ] && TRITON="triton-library==$TRITON_VER"
  if "$VENV/bin/python" -c 'import triton' >/dev/null 2>&1 || python3 -c 'import triton' >/dev/null 2>&1; then
    ok "triton already installed"
  else
    pip_install "triton (symbolic execution)" "$TRITON"
  fi

  clone_py() { # name repo
    local dir="$ECHO_HOME/$1"
    if [ -d "$dir/.git" ]; then ok "$1 already cloned"; return; fi
    clone_at "$1" "$2" "$dir" && ok "$1"
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

# The compiler-built tools need cmake / dotnet / LLVM. Install them rather than
# skipping, so a full install actually finishes. Best-effort: a failure is a skip.
pkg_install() { # label pkg-apt pkg-brew pkg-winget
  local label="$1" apt="$2" brew_p="$3" winget_p="$4"
  if have apt-get && have sudo; then
    sub "installing $label via apt…"
    sudo -n apt-get install -y "$apt" >/dev/null 2>&1 && { ok "$label (apt)"; return 0; }
  fi
  if have brew; then
    sub "installing $label via brew…"
    brew install "$brew_p" >/dev/null 2>&1 && { ok "$label (brew)"; return 0; }
  fi
  if have winget && [ -n "$winget_p" ]; then
    winget install --id "$winget_p" --silent --accept-package-agreements --accept-source-agreements >/dev/null 2>&1 \
      && { ok "$label (winget)"; return 0; }
  fi
  skip "$label" "install manually (apt: $apt / brew: $brew_p${winget_p:+ / winget: $winget_p})"
  return 1
}

have cmake  || pkg_install cmake  cmake  cmake  Kitware.CMake
have dotnet || pkg_install "dotnet SDK 8" dotnet-sdk-8.0 dotnet Microsoft.DotNet.SDK.8
{ have llvm-config || have opt; } || pkg_install LLVM llvm llvm LLVM.LLVM

# VTIL-Core / NoVmp — C++ via CMake. NoVmp vendors VTIL-Core as a submodule.
build_cmake() { # name repo submodules
  local name="$1" repo="$2" subs="${3:-0}" dir="$ECHO_HOME/$1"
  have cmake || { skip "$name" "cmake not found"; return; }
  if [ ! -d "$dir/.git" ]; then
    clone_at "$name" "$repo" "$dir" "$subs" || { fail "$name" "clone failed"; return; }
  fi
  ( cd "$dir" && cmake -B build -DCMAKE_BUILD_TYPE=Release >/dev/null 2>&1 \
      && cmake --build build --config Release -j >/dev/null 2>&1 ) \
    && ok "$name" || skip "$name" "cmake build failed (needs a C++ toolchain)"
}
build_cmake VTIL-Core vtil-project/VTIL-Core
build_cmake NoVmp     can1357/NoVmp        1

# vtil2 — .NET 8.
if have dotnet; then
  if [ ! -d "$ECHO_HOME/vtil2/.git" ]; then
    clone_at vtil2 pop-rip/vtil2 "$ECHO_HOME/vtil2" >/dev/null 2>&1
  fi
  if [ -d "$ECHO_HOME/vtil2" ]; then
    ( cd "$ECHO_HOME/vtil2" && dotnet build -c Release >/dev/null 2>&1 ) \
      && ok "vtil2" || skip "vtil2" "dotnet build failed"
  fi
else
  skip "vtil2" "dotnet (.NET 8 SDK) not found"
fi

# LLVM is handled by pkg_install above (system package, never a source build).
fi

# ── 7. write .mcp.json ───────────────────────────────────────────────────────
say "Writing .mcp.json"
GH_ENTRY="$ECHO_HOME/mcp-gamehacking/dist/index.js"
AM_ENTRY="$ECHO_HOME/angel-menu-mcp/index.js"
REA_ARG="rea-agents"
REA_VER="$(lock_pin npm rea-agents)"
[ -n "$REA_VER" ] && REA_ARG="rea-agents@$REA_VER"
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
  add_server rea npx "[\"-y\",\"$REA_ARG\"]" "REA: Reverse Engineer Anything — Unity IL2CPP, Godot, native binaries, APK, WASM, firmware"
  add_server angel-menu node "[\"$AM_ENTRY\"]" "Echo overlay menu control: list_features, get_feature, set_feature, connection_status"
  add_server radare2 r2pm '["-r","r2mcp"]' "radare2 MCP: disasm, decompile, search, analysis (install: r2pm -Uci r2mcp)"
  add_server ida uvx '["ida-mcp","stdio","--agent=echo"]' "IDA Pro MCP: decompile, rename, xref, structs (requires IDA 9.4+ with idalib)"
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
