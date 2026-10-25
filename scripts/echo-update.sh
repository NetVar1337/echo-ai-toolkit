#!/usr/bin/env bash
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
set -uo pipefail

REPO="NetVar1337/echo-ai-toolkit"
PLUGIN="echo-ai-toolkit"
ECHO_HOME="${ECHO_HOME:-$HOME/.local/share/echo-ai-toolkit}"
BIN_DIR="$ECHO_HOME/bin"
PROFILE="$ECHO_HOME/pi"
REF_DIR="$ECHO_HOME/reference"

OK=(); SKIPPED=(); FAILED=()
say()  { printf '\n\033[1;33m==> %s\033[0m\n' "$*"; }
sub()  { printf '    %s\n' "$*"; }
ok()   { OK+=("$1");      printf '    \033[1;32mok\033[0m    %s\n' "$1"; }
skip() { SKIPPED+=("$1: $2"); printf '    \033[1;35mskip\033[0m  %s — %s\n' "$1" "$2"; }
fail() { FAILED+=("$1: $2");  printf '    \033[1;31mFAIL\033[0m  %s — %s\n' "$1" "$2"; }
have() { command -v "$1" >/dev/null 2>&1; }
to()   { local s="$1"; shift; timeout "$s" "$@" 2>/dev/null; }
CURL="curl -fsSL --connect-timeout 10 --max-time 120"

# ── argument parsing ─────────────────────────────────────────────────────────
PI_FLAGS=()
DO_TOOLS=0; DO_PROFILE=0; EXPLICIT=0
for a in "$@"; do
  case "$a" in
    --tools)         DO_TOOLS=1; EXPLICIT=1 ;;
    --profile)       DO_PROFILE=1; EXPLICIT=1 ;;
    --extensions|--self|--models|--all|--force)
                     PI_FLAGS+=("$a"); EXPLICIT=1 ;;
    -h|--help)
      awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"
      exit 0 ;;
    *)
      printf '\033[1;31munknown option: %s\033[0m\n' "$a" >&2
      printf 'run `echo update --help`\n' >&2
      exit 2 ;;
  esac
done

# No flags at all = everything.
if [ "$EXPLICIT" -eq 0 ]; then
  DO_TOOLS=1; DO_PROFILE=1; PI_FLAGS=(--all)
fi
# Resyncing the profile is always safe and cheap; do it unless the user asked
# for something Pi-only.
if [ ${#PI_FLAGS[@]} -gt 0 ] && [ "$DO_PROFILE" -eq 0 ] && [ "$DO_TOOLS" -eq 0 ]; then
  case " ${PI_FLAGS[*]} " in
    *" --self "*|*" --models "*) ;;   # Pi-only: leave the profile alone
    *) DO_PROFILE=1 ;;                # --extensions / --all: refresh the profile too
  esac
fi

printf '\n\033[1mEcho update\033[0m  %s\n' "$(date '+%Y-%m-%d %H:%M')"

# ── 1. toolkit plugin ────────────────────────────────────────────────────────
# Only when we are actually resyncing the profile or the tools. A Pi-only request
# (`--self`, `--models`) leaves the toolkit alone.
if [ "$DO_PROFILE" -eq 1 ] || [ "$DO_TOOLS" -eq 1 ]; then
  if have claude; then
    say "Toolkit plugin"
    if to 180 claude plugin marketplace update "$PLUGIN" >/dev/null; then
      ok "marketplace updated"
    else
      skip "marketplace" "update failed (offline?)"
    fi
    if to 180 claude plugin update "$PLUGIN" >/dev/null; then
      ok "plugin updated"
    else
      skip "plugin" "already current or update failed"
    fi
  else
    skip "toolkit plugin" "claude CLI not found"
  fi
fi

# ── 2. Echo profile ──────────────────────────────────────────────────────────
if [ "$DO_PROFILE" -eq 1 ]; then
  say "Echo profile"
  # Source of truth: the marketplace clone, which `marketplace update` just refreshed.
  SRC="$(ls -d "$HOME"/.claude/plugins/marketplaces/"$PLUGIN" 2>/dev/null | head -1)"
  if [ -n "$SRC" ] && [ -d "$SRC/pi" ]; then
    mkdir -p "$PROFILE/prompts" "$PROFILE/skills"
    for f in SYSTEM.md APPEND_SYSTEM.md AGENTS.md; do
      [ -f "$SRC/pi/$f" ] && cp -f "$SRC/pi/$f" "$PROFILE/$f"
    done
    cp -f "$SRC/pi"/prompts/*.md "$PROFILE/prompts/" 2>/dev/null
    local_n=0
    for d in "$SRC"/skills/*/; do
      [ -f "$d/SKILL.md" ] || continue
      name=$(basename "$d")
      mkdir -p "$PROFILE/skills/$name"
      cp -f "$d/SKILL.md" "$PROFILE/skills/$name/SKILL.md"
      local_n=$((local_n+1))
    done
    ok "profile resynced ($local_n skills, $(ls "$PROFILE"/prompts/*.md 2>/dev/null | wc -l) templates)"
  else
    skip "profile" "marketplace clone not found at ~/.claude/plugins/marketplaces/$PLUGIN"
  fi

  # Launcher refresh.
  if [ -n "$SRC" ] && [ -f "$SRC/pi/bin/echo" ]; then
    mkdir -p "$BIN_DIR"
    cp -f "$SRC/pi/bin/echo" "$BIN_DIR/echo"
    chmod +x "$BIN_DIR/echo"
    ok "launcher refreshed"
  fi
fi

# ── 3. Pi itself / extensions ────────────────────────────────────────────────
if [ ${#PI_FLAGS[@]} -gt 0 ]; then
  if have pi; then
    say "Pi ${PI_FLAGS[*]}"
    # shellcheck disable=SC2086
    if to 600 pi update "${PI_FLAGS[@]}"; then
      ok "pi update ${PI_FLAGS[*]}"
    else
      skip "pi update" "command failed (auth or network?)"
    fi
  else
    skip "pi update" "pi not installed"
  fi
fi

# ── 4. companion tools ───────────────────────────────────────────────────────
if [ "$DO_TOOLS" -eq 1 ]; then
  say "Companion tools"

  # Git clones: pull, then rebuild only where a build step exists.
  git_update() { # name [build-cmd]
    local name="$1" build="${2:-}" dir="$ECHO_HOME/$1"
    [ -d "$dir/.git" ] || { skip "$name" "not installed"; return; }
    if to 180 git -C "$dir" pull --ff-only --quiet; then
      local head; head=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
      if [ -n "$build" ]; then
        sub "rebuilding $name…"
        ( cd "$dir" && eval "$build" ) >/dev/null 2>&1 \
          && ok "$name @ $head (rebuilt)" || fail "$name" "rebuild failed"
      else
        ok "$name @ $head"
      fi
    else
      skip "$name" "git pull failed (local changes or offline)"
    fi
  }

  git_update mcp-gamehacking              'npm install --silent && npm run build --silent'
  git_update angel-menu-mcp               'npm install --silent'
  git_update VMProtect-devirtualization   ''
  git_update vmp-lazy-unpack              "$PROFILE/../venv/bin/python -m pip install --quiet -e . 2>/dev/null || python3 -m pip install --quiet -e . 2>/dev/null || true"
  git_update web-mv                       ''
  git_update VTIL-Core                    'cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release'
  git_update NoVmp                        'cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release'
  git_update vtil2                        'dotnet build -c Release'

  # Version-pinned binaries: re-fetch the current release asset.
  if [ -d "$BIN_DIR" ]; then
    case "$(uname -s)" in
      Linux)   asset="as_bundler" ;;
      MINGW*|MSYS*|CYGWIN*) asset="as_bundler.exe" ;;
      *)       asset="" ;;
    esac
    if [ -n "$asset" ]; then
      latest=$(curl -fsSL --connect-timeout 10 --max-time 30 \
        "https://api.github.com/repos/sinistercodes/as_bundler/releases/latest" 2>/dev/null \
        | grep -oE '"tag_name": *"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
      if [ -n "$latest" ] && $CURL "https://github.com/sinistercodes/as_bundler/releases/download/$latest/$asset" -o "$BIN_DIR/$asset"; then
        chmod +x "$BIN_DIR/$asset"; ok "as_bundler $latest"
      else
        skip "as_bundler" "release lookup failed"
      fi
    fi
  fi

  # Python packages in the venv.
  VENV_PY="$ECHO_HOME/venv/bin/python"
  if [ -x "$VENV_PY" ]; then
    if $VENV_PY -m pip install --quiet --disable-pip-version-check -U triton-library >/dev/null 2>&1; then
      ok "triton ($($VENV_PY -c 'import importlib.metadata as m;print(m.version("triton-library"))' 2>/dev/null))"
    else
      skip "triton" "pip -U failed"
    fi
  else
    skip "triton" "no venv"
  fi

  # Reference READMEs.
  if [ -d "$REF_DIR" ]; then
    for pair in "awesome-game-security:gmh5225/awesome-game-security" \
                "gamehacking-cheatsheet:ridpath/gamehacking-cheatsheet"; do
      name="${pair%%:*}"; repo="${pair#*:}"
      if $CURL "https://raw.githubusercontent.com/$repo/HEAD/README.md" -o "$REF_DIR/$name.md"; then
        ok "$name ($(wc -c < "$REF_DIR/$name.md") bytes)"
      else
        skip "$name" "download failed"
      fi
    done
  fi
fi

# ── summary ──────────────────────────────────────────────────────────────────
printf '\n\033[1m────────────────────────────────────────────────────────────\033[0m\n'
printf '  \033[1;32m%d updated\033[0m' "${#OK[@]}"
[ ${#SKIPPED[@]} -gt 0 ] && printf '   \033[1;35m%d skipped\033[0m' "${#SKIPPED[@]}"
[ ${#FAILED[@]}  -gt 0 ] && printf '   \033[1;31m%d failed\033[0m'  "${#FAILED[@]}"
printf '\n'
if [ ${#SKIPPED[@]} -gt 0 ]; then
  printf '\n  Skipped:\n'; for s in "${SKIPPED[@]}"; do printf '    · %s\n' "$s"; done
fi
if [ ${#FAILED[@]} -gt 0 ]; then
  printf '\n  Failed:\n';  for s in "${FAILED[@]}";  do printf '    · %s\n' "$s"; done
fi
printf '  \033[1m────────────────────────────────────────────────────────────\033[0m\n\n'
[ ${#FAILED[@]} -eq 0 ] || exit 1
