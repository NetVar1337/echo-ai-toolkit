#!/usr/bin/env bash
# echo update — thin shim. The implementation is scripts/echo.mjs (one copy for
# every platform), so this file only locates it and hands over.
#
#   echo update                 everything (toolkit + profile + pi --all + tools)
#   echo update --extensions    Pi packages/extensions only (+ profile resync)
#   echo update --self          the Pi binary only
#   echo update --models        Pi model catalogs only
#   echo update --all           Pi and its packages
#   echo update --tools         companion tools only (pinned refs + rebuild)
#   echo update --profile       resync the Echo profile only
#   echo update --lock          re-resolve tools.lock to upstream heads, then update
set -uo pipefail

ECHO_HOME="${ECHO_HOME:-$HOME/.local/share/echo-ai-toolkit}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

command -v node >/dev/null 2>&1 || {
  printf '\033[1;31mecho:\033[0m node not found — `echo update` needs Node 18+\n' >&2
  exit 1
}

for cand in "$SELF_DIR/echo.mjs" "$ECHO_HOME/bin/echo.mjs"; do
  [ -f "$cand" ] && exec node "$cand" update "$@"
done

printf '\033[1;31mecho:\033[0m echo.mjs not found next to this script\n' >&2
exit 1
