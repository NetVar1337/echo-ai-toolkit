#!/usr/bin/env bash
# Build the mcp-gamehacking archive that install.sh downloads.
#
#   scripts/vendor_archive.sh              # build parts into dist-vendor/
#   scripts/vendor_archive.sh --upload     # build, then create the release
#
# Why an archive and not git: the upstream tree is 18 GB on disk / 3.1 GB packed.
# GitHub blocks files over 100 MB and warns above 1 GB per repo, and every CI job
# would check the whole library out. The archive lives in this repo's releases,
# and vendor/ARCHIVES pins each part by sha256.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
LOCK="$ROOT/tools.lock"
OUT="$ROOT/dist-vendor"
WORK="$(mktemp -d)"
PART_SIZE="1500M"
UPLOAD=0
[ "${1:-}" = "--upload" ] && UPLOAD=1

SHA="$(awk '$1=="clone" && $2=="mcp-gamehacking" {print $4; exit}' "$LOCK")"
REPO="$(awk '$1=="clone" && $2=="mcp-gamehacking" {print $3; exit}' "$LOCK")"
[ -n "$SHA" ] || { echo "mcp-gamehacking is not pinned in tools.lock" >&2; exit 1; }

SHORT="${SHA:0:7}"
TAG="vendor-mcp-gamehacking-$SHORT"
NAME="mcp-gamehacking-$SHORT.tar.gz"

echo "==> fetching $REPO @ $SHORT"
mkdir -p "$WORK/src"
git -C "$WORK/src" init -q
git -C "$WORK/src" remote add origin "https://github.com/$REPO"
git -C "$WORK/src" fetch -q --depth 1 origin "$SHA" || { echo "fetch failed" >&2; exit 1; }
git -C "$WORK/src" checkout -q FETCH_HEAD || { echo "checkout failed" >&2; exit 1; }

echo "==> building (npm ci + build) so the install needs no npm"
( cd "$WORK/src" && npm ci --silent >/dev/null 2>&1 \
    && { node -e "process.exit(require('./package.json').scripts?.build?0:1)" 2>/dev/null \
           && npm run build --silent >/dev/null 2>&1 || true; } ) \
  || { echo "build failed — ship the source tree instead" >&2; }

echo "==> archiving"
mkdir -p "$OUT"
rm -f "$OUT/$NAME".part*
# The archive's top-level directory is what install.sh moves into place.
mv "$WORK/src" "$WORK/mcp-gamehacking"
tar -czf "$OUT/$NAME" -C "$WORK" mcp-gamehacking

echo "==> splitting at $PART_SIZE"
( cd "$OUT" && split -b "$PART_SIZE" -d -a 2 "$NAME" "$NAME.part" )
ls -la "$OUT"

{
  echo "# name url sha256"
  echo "# mcp-gamehacking: 3.1 GB of git / 18 GB tree, shipped as a release archive."
  echo "# Rebuild with scripts/vendor_archive.sh; install.sh verifies every part."
  for f in "$OUT/$NAME".part*; do
    base="$(basename "$f")"
    sha="$(sha256sum "$f" | cut -d' ' -f1)"
    echo "mcp-gamehacking https://github.com/NetVar1337/echo-ai-toolkit/releases/download/$TAG/$base $sha"
  done
} > "$ROOT/vendor/ARCHIVES"

echo
echo "wrote vendor/ARCHIVES:"
cat "$ROOT/vendor/ARCHIVES"

if [ "$UPLOAD" = "1" ]; then
  command -v gh >/dev/null || { echo "gh not installed" >&2; exit 1; }
  echo "==> creating release $TAG"
  gh release create "$TAG" "$OUT/$NAME".part* \
    --repo NetVar1337/echo-ai-toolkit \
    --title "Vendored mcp-gamehacking $SHORT" \
    --notes "Split archive of 1llu50ry/mcp-gamehacking at $SHA, built with npm ci + build. install.sh verifies each part against vendor/ARCHIVES." \
    || exit 1
  echo "==> upload done"
fi

python3 "$ROOT/scripts/vendor_manifest.py" --write
