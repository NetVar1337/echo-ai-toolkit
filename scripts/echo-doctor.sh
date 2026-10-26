#!/usr/bin/env bash
# echo doctor — thin shim. The implementation is scripts/echo.mjs (one copy for
# every platform). Read-only: reports one line per tool.
set -uo pipefail

ECHO_HOME="${ECHO_HOME:-$HOME/.local/share/echo-ai-toolkit}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

command -v node >/dev/null 2>&1 || {
  printf '\033[1;31mecho:\033[0m node not found — `echo doctor` needs Node 18+\n' >&2
  exit 1
}

for cand in "$SELF_DIR/echo.mjs" "$ECHO_HOME/bin/echo.mjs"; do
  [ -f "$cand" ] && exec node "$cand" doctor "$@"
done

printf '\033[1;31mecho:\033[0m echo.mjs not found next to this script\n' >&2
exit 1
