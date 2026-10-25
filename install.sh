#!/usr/bin/env bash
# Echo AI Toolkit — one-command installer.
#
#   curl -fsSL https://raw.githubusercontent.com/NetVar1337/echo-ai-toolkit/main/install.sh | bash
#
# Installs the plugin into Claude Code and vendors its optional MCP dependencies.
# Safe to re-run: every step is idempotent.
set -euo pipefail

REPO="NetVar1337/echo-ai-toolkit"
MARKETPLACE="echo-ai-toolkit"
PLUGIN="echo-ai-toolkit"
DEPS="${HOME}/.local/share/echo-ai-toolkit"

say()  { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;35m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  ✗\033[0m %s\n' "$*" >&2; exit 1; }

command -v claude >/dev/null 2>&1 || die "claude CLI not found. Install Claude Code first: https://claude.com/claude-code"
command -v node    >/dev/null 2>&1 || die "node not found. Install Node.js 18+ first."
command -v git    >/dev/null 2>&1 || die "git not found."

say "Installing $PLUGIN plugin from marketplace $REPO"

# ── 1. marketplace ───────────────────────────────────────────────────────────
if claude plugin marketplace list 2>/dev/null | grep -q "$MARKETPLACE"; then
  ok "marketplace '$MARKETPLACE' already registered"
else
  claude plugin marketplace add "$REPO" || die "failed to add marketplace"
  ok "marketplace registered"
fi

# ── 2. plugin ───────────────────────────────────────────────────────────────
if claude plugin list 2>/dev/null | grep -q "$PLUGIN"; then
  ok "plugin '$PLUGIN' already installed"
else
  claude plugin install "$PLUGIN@$MARKETPLACE" || die "failed to install plugin"
  ok "plugin installed"
fi

# ── 3. optional MCP dependencies ────────────────────────────────────────────
# These are optional. The plugin works without them; they add extra search/analysis tools.
if [ "${SKIP_MCP:-0}" = "1" ]; then
  warn "SKIP_MCP=1 — skipping optional MCP dependencies"
else
  mkdir -p "$DEPS"

  if [ -f "$DEPS/mcp-gamehacking/dist/index.js" ]; then
    ok "mcp-gamehacking already built"
  else
    say "Vendoring mcp-gamehacking (this takes a minute)"
    if [ ! -d "$DEPS/mcp-gamehacking/.git" ]; then
      git clone --depth 1 https://github.com/1llu50ry/mcp-gamehacking "$DEPS/mcp-gamehacking" \
        || warn "clone failed — skipping mcp-gamehacking"
    fi
    if [ -d "$DEPS/mcp-gamehacking" ]; then
      (cd "$DEPS/mcp-gamehacking" && npm install --silent && npm run build --silent) \
        && ok "mcp-gamehacking built" || warn "build failed — skipping mcp-gamehacking"
    fi
  fi

  if [ -d "$DEPS/angel-menu-mcp/node_modules" ]; then
    ok "angel-menu-mcp already installed"
  else
    say "Vendoring angel-menu-mcp"
    if [ ! -d "$DEPS/angel-menu-mcp/.git" ]; then
      git clone --depth 1 https://github.com/Jozkah/angel-menu-mcp "$DEPS/angel-menu-mcp" \
        || warn "clone failed — skipping angel-menu-mcp"
    fi
    if [ -d "$DEPS/angel-menu-mcp" ]; then
      (cd "$DEPS/angel-menu-mcp" && npm install --silent) \
        && ok "angel-menu-mcp installed" || warn "install failed — skipping angel-menu-mcp"
    fi
  fi
fi

# ── 4. optional companions ───────────────────────────────────────────────────
if claude plugin marketplace list 2>/dev/null | grep -q '^ponytail'; then
  ok "ponytail already registered"
else
  claude plugin marketplace add DietrichGebert/ponytail >/dev/null 2>&1 \
    && claude plugin install ponytail@ponytail >/dev/null 2>&1 \
    && ok "ponytail installed (lazy-senior-dev mode)" \
    || warn "ponytail not installed — optional"
fi

cat <<'EOF'

────────────────────────────────────────────────────────────
  Echo AI Toolkit is ready.

  Next:
    1. Restart Claude Code (or run /reload-plugins)
    2. Type  /echo-help        to list the 12 agents
    3. Type  /echo-esp         to load ESP context
       ...or just describe your task — keywords auto-route.

  Templates:  templates/*.as  → copy into %AppData%\Roaming\scripts\
  Full API:   reference/api.md
────────────────────────────────────────────────────────────
EOF
