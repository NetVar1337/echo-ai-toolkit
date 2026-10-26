#!/usr/bin/env bash
# Mirror the mcp-gamehacking source tree into this repo's releases.
#
#   scripts/vendor_archive.sh              # download + split into dist-vendor/
#   scripts/vendor_archive.sh --upload     # ...then create the release
#
# Why not git: the tree is 18 GB (3.1 GB packed). GitHub blocks files over 100 MB
# and warns above 1 GB per repo, and every CI job would check it out. The mirror
# is byte-identical to GitHub's own tarball for the pinned commit, so there is
# nothing to build here — install.sh extracts it and runs npm ci against the
# package-lock inside it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
LOCK="$ROOT/tools.lock"
OUT="$ROOT/dist-vendor"
PART_SIZE="1500M"
UPLOAD=0
[ "${1:-}" = "--upload" ] && UPLOAD=1

SHA="$(awk '$1=="clone" && $2=="mcp-gamehacking" {print $4; exit}' "$LOCK")"
REPO="$(awk '$1=="clone" && $2=="mcp-gamehacking" {print $3; exit}' "$LOCK")"
[ -n "$SHA" ] || { echo "mcp-gamehacking is not pinned in tools.lock" >&2; exit 1; }

SHORT="${SHA:0:7}"
TAG="vendor-mcp-gamehacking-$SHORT"
NAME="mcp-gamehacking-$SHORT.tar.gz"
URL="https://codeload.github.com/$REPO/tar.gz/$SHA"

mkdir -p "$OUT"
if [ ! -s "$OUT/$NAME" ]; then
  echo "==> downloading $URL"
  # -C - resumes: this is a multi-GB transfer.
  curl -fL -C - -o "$OUT/$NAME" "$URL" || { echo "download failed" >&2; exit 1; }
fi

echo "==> splitting at $PART_SIZE"
rm -f "$OUT/$NAME".part*
( cd "$OUT" && split -b "$PART_SIZE" -d -a 2 "$NAME" "$NAME.part" )
ls -la "$OUT" | grep "$NAME"

{
  echo "# name url sha256"
  echo "# mcp-gamehacking: 18 GB tree / 3.1 GB packed — shipped as a release archive, not git."
  echo "# Rebuild with scripts/vendor_archive.sh; install.sh verifies every part."
  for f in "$OUT/$NAME".part*; do
    base="$(basename "$f")"
    echo "mcp-gamehacking https://github.com/NetVar1337/echo-ai-toolkit/releases/download/$TAG/$base $(sha256sum "$f" | cut -d' ' -f1)"
  done
} > "$ROOT/vendor/ARCHIVES"

echo "==> wrote vendor/ARCHIVES"
cat "$ROOT/vendor/ARCHIVES"

if [ "$UPLOAD" = "1" ]; then
  command -v gh >/dev/null || { echo "gh not installed" >&2; exit 1; }
  echo "==> creating release $TAG"
  gh release create "$TAG" "$OUT/$NAME".part* \
    --repo NetVar1337/echo-ai-toolkit \
    --title "Vendored mcp-gamehacking $SHORT" \
    --notes "Byte-identical mirror of 1llu50ry/mcp-gamehacking at $SHA, split into parts. install.sh verifies each part against vendor/ARCHIVES." \
    || exit 1
  echo "==> uploaded"
fi

python3 "$ROOT/scripts/vendor_manifest.py" --write
