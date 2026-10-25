#!/usr/bin/env bash
# Build the AngelScript compile checker used by scripts/check_angelscript.py.
#
# Downloads the AngelScript SDK (2.38.0) and builds the checker against it.
# The checker compiles a script against an Echo API stub, so it validates the
# real AngelScript grammar without needing the Echo host.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${ANGELSCRIPT_WORK:-/tmp/echo-angelscript}"
AS_VERSION="2.38.0"
AS_ZIP="https://www.angelcode.com/angelscript/sdk/files/angelscript_${AS_VERSION}.zip"

if [ ! -d "$WORK/sdk/angelscript/include" ]; then
  mkdir -p "$WORK"
  echo "==> fetching AngelScript $AS_VERSION"
  curl -fsSL "$AS_ZIP" -o "$WORK/angelscript.zip"
  unzip -q -o "$WORK/angelscript.zip" -d "$WORK"
fi

SDK="$WORK/sdk"
echo "==> compiling the AngelScript library"
mkdir -p "$WORK/obj"
cd "$SDK/angelscript/source"
for f in *.cpp; do
  g++ -O2 -fPIC -fno-strict-aliasing -c "$f" -I"$SDK/angelscript/include" \
      -o "$WORK/obj/${f%.cpp}.o"
done
ar rcs "$WORK/libangelscript.a" "$WORK"/obj/*.o

echo "==> building the checker"
g++ -O2 -fno-strict-aliasing -o "$HERE/check" \
  "$HERE/check.cpp" \
  "$SDK/add_on/scriptarray/scriptarray.cpp" \
  "$SDK/add_on/scriptstdstring/scriptstdstring.cpp" \
  "$SDK/add_on/scriptstdstring/scriptstdstring_utils.cpp" \
  "$WORK/libangelscript.a" \
  -I"$SDK/angelscript/include" \
  -I"$SDK/add_on/scriptarray" \
  -I"$SDK/add_on/scriptstdstring"

echo "==> built $HERE/check"
