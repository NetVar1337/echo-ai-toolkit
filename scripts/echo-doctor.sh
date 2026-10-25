#!/usr/bin/env bash
# Echo AI Toolkit — verify what is actually installed.
#
#   ./scripts/echo-doctor.sh
#
# Read-only. Reports one line per tool: present, missing, or not applicable.
set -uo pipefail

ECHO_HOME="${ECHO_HOME:-$HOME/.local/share/echo-ai-toolkit}"
PASS=0; MISS=0; NA=0
have() { command -v "$1" >/dev/null 2>&1; }
green() { printf '\033[1;32m%s\033[0m' "$1"; }
red()   { printf '\033[1;31m%s\033[0m' "$1"; }
dim()   { printf '\033[1;35m%s\033[0m' "$1"; }

row() { # status label detail
  case "$1" in
    ok)   PASS=$((PASS+1)); printf '  %s  %-28s %s\n' "$(green 'ok  ')" "$2" "$3" ;;
    miss) MISS=$((MISS+1)); printf '  %s  %-28s %s\n' "$(red   'MISS')" "$2" "$3" ;;
    na)   NA=$((NA+1));     printf '  %s  %-28s %s\n' "$(dim   'n/a ')" "$2" "$3" ;;
  esac
}

echo
echo "Echo AI Toolkit — doctor"
echo "tools: $ECHO_HOME"
echo

echo "Plugin"
if have claude; then
  if claude plugin list 2>/dev/null | grep -q 'echo-ai-toolkit'; then
    row ok "echo-ai-toolkit plugin" "$(claude plugin list 2>/dev/null | grep -oE 'echo-ai-toolkit@[a-z-]+' | head -1)"
  else
    row miss "echo-ai-toolkit plugin" "run install.sh"
  fi
  for p in ponytail andrej-karpathy-skills; do
    if claude plugin list 2>/dev/null | grep -q "$p"; then row ok "$p plugin" ""; else row na "$p plugin" "optional"; fi
  done
else
  row miss "claude CLI" "https://claude.com/claude-code"
fi

echo
echo "MCP servers"
[ -f "$ECHO_HOME/mcp.json" ] && row ok "mcp.json" "$ECHO_HOME/mcp.json" || row miss "mcp.json" "run install.sh"
if [ -f "$ECHO_HOME/mcp-gamehacking/dist/index.js" ]; then
  row ok "mcp-gamehacking" "built"
elif [ -d "$ECHO_HOME/mcp-gamehacking" ]; then
  row miss "mcp-gamehacking" "cloned but not built"
else
  row na "mcp-gamehacking" "~3.1 GB — ECHO_WITH_GAMEHACKING=1"
fi
if [ -f "$ECHO_HOME/angel-menu-mcp/index.js" ]; then
  row ok "angel-menu-mcp" "installed"
else
  row miss "angel-menu-mcp" "not installed"
fi
have npx && row ok "rea (npx)" "installs on first use" || row miss "rea (npx)" "needs Node"

echo
echo "Echo tooling"
if [ -x "$ECHO_HOME/bin/as_bundler" ]; then
  row ok "as_bundler" "$ECHO_HOME/bin/as_bundler"
else
  row miss "as_bundler" "not installed"
fi
ESP=""
for p in "$HOME/AppData/Roaming/scripts/esp_preview.as" "$ECHO_HOME/reference/esp_preview.as"; do
  [ -f "$p" ] && { ESP="$p"; break; }
done
if [ -n "$ESP" ]; then
  row ok "esp_preview.as" "$ESP"
else
  row miss "esp_preview.as" "not installed"
fi
if have code && code --list-extensions 2>/dev/null | grep -qi echo-angelscript-lsp; then
  row ok "echo-angelscript-lsp" "VS Code extension"
elif have code; then
  row miss "echo-angelscript-lsp" "not installed"
else
  row na "echo-angelscript-lsp" "VS Code not on PATH"
fi
if have bun; then
  [ -d "$ECHO_HOME/web-mv/relay/node_modules" ] && row ok "web-mv" "bun install done" || row miss "web-mv" "run install.sh"
else
  row na "web-mv" "needs Bun"
fi

echo
echo "Pi coding agent"
PIPROF="$ECHO_HOME/pi"
if [ -f "$PIPROF/SYSTEM.md" ]; then
  row ok "pi profile" "$PIPROF"
  row ok "  SYSTEM.md" "$(wc -c < "$PIPROF/SYSTEM.md") bytes (replaces default prompt)"
  [ -f "$PIPROF/APPEND_SYSTEM.md" ] && row ok "  APPEND_SYSTEM.md" "$(wc -c < "$PIPROF/APPEND_SYSTEM.md") bytes (appended)"
  row ok "  skills" "$(ls -d "$PIPROF"/skills/*/ 2>/dev/null | wc -l) ported"
  row ok "  prompts" "$(ls "$PIPROF"/prompts/*.md 2>/dev/null | wc -l) templates"
else
  row miss "pi profile" "run install.sh"
fi
[ -x "$ECHO_HOME/bin/echo" ] && row ok "echo launcher" "$ECHO_HOME/bin/echo" || row miss "echo launcher" "not installed"
[ -x "$ECHO_HOME/bin/echo-update.sh" ] && row ok "echo update" "installed" || row miss "echo update" "not installed"
if have pi; then
  row ok "pi binary" "$(pi --version 2>/dev/null | head -1)"
else
  row na "pi binary" "curl -fsSL https://pi.dev/install.sh | sh"
fi
if grep -qs 'echo-ai-toolkit: echo alias' "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null; then
  row ok "echo alias" "in shell rc (shadows the builtin)"
else
  row na "echo alias" "not added (ECHO_NO_ALIAS=1 or no rc file)"
fi

echo
echo "Python tooling"
# Python tools live in a dedicated venv when one could be created (PEP 668 safe).
VENV_PY="$ECHO_HOME/venv/bin/python"
[ -x "$VENV_PY" ] || VENV_PY=""
PY="$VENV_PY"
[ -z "$PY" ] && have python3 && PY=python3
[ -z "$PY" ] && have python && PY=python
if [ -n "$PY" ]; then
  if $PY -c 'import triton' 2>/dev/null; then
    row ok "triton" "$($PY -c 'import importlib.metadata as m;print(m.version("triton-library"))' 2>/dev/null || echo installed)"
  else
    row miss "triton" "pip install triton-library"
  fi
  [ -n "$VENV_PY" ] && row ok "python venv" "$ECHO_HOME/venv"
  [ -d "$ECHO_HOME/VMProtect-devirtualization" ] && row ok "VMProtect-devirtualization" "cloned" || row miss "VMProtect-devirtualization" "not installed"
  [ -d "$ECHO_HOME/vmp-lazy-unpack" ] && row ok "vmp-lazy-unpack" "cloned" || row miss "vmp-lazy-unpack" "not installed"
else
  row na "python tooling" "python not found"
fi

echo
echo "Compiler-built tooling"
[ -d "$ECHO_HOME/VTIL-Core" ] && row ok "VTIL-Core" "source" || row na "VTIL-Core" "tier: full"
[ -d "$ECHO_HOME/NoVmp" ] && row ok "NoVmp" "source" || row na "NoVmp" "tier: full"
[ -d "$ECHO_HOME/vtil2" ] && row ok "vtil2" "source" || row na "vtil2" "tier: full"
{ have llvm-config || have opt; } && row ok "LLVM" "$(llvm-config --version 2>/dev/null || echo present)" || row na "LLVM" "only for Triton LLVM interface"

echo
echo "Reference docs"
for d in awesome-game-security gamehacking-cheatsheet; do
  f="$ECHO_HOME/reference/$d.md"
  [ -s "$f" ] && row ok "$d" "$(wc -c < "$f") bytes" || row miss "$d" "not fetched"
done

echo
printf '  %s ok   %s missing   %s not applicable\n\n' "$(green $PASS)" "$(red $MISS)" "$(dim $NA)"
[ "$MISS" -eq 0 ] && { echo "  Everything present."; exit 0; }
echo "  Run ./install.sh to fill the gaps (ECHO_TIER=full for the compiler-built tools)."
exit 0
