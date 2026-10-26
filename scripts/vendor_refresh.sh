#!/usr/bin/env bash
# Refresh vendor/ from the pins in tools.lock, then re-record the manifest.
#
#   scripts/vendor_refresh.sh              # everything except the archive
#   scripts/vendor_refresh.sh VTIL-Core    # one entry
#
# The installers never call this: they install from vendor/. This is the
# maintainer path for moving a pin.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
LOCK="$ROOT/tools.lock"
VENDOR="$ROOT/vendor"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pin() { awk -v n="$1" '$1=="clone" && $2==n {print $4; exit}' "$LOCK"; }
repo() { awk -v n="$1" '$1=="clone" && $2==n {print $3; exit}' "$LOCK"; }

fetch_at() { # dir repo sha
  local dir="$1" r="$2" sha="$3"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "https://github.com/$r" 2>/dev/null \
    || git -C "$dir" remote set-url origin "https://github.com/$r"
  git -C "$dir" fetch -q --depth 1 origin "$sha" || return 1
  git -C "$dir" checkout -q FETCH_HEAD || return 1
}

vendor_tree() { # name → vendor subpath
  case "$1" in
    mcp-gamehacking)               echo "mcp/mcp-gamehacking" ;;
    angel-menu-mcp)                echo "mcp/angel-menu-mcp" ;;
    *)                             echo "tools/$1" ;;
  esac
}

ONLY="${1:-}"

for name in $(awk '$1=="clone" {print $2}' "$LOCK"); do
  [ -n "$ONLY" ] && [ "$name" != "$ONLY" ] && continue
  if [ "$name" = "mcp-gamehacking" ]; then
    echo "skip  $name — 3.1 GB; shipped as a release archive, see scripts/vendor_archive.sh"
    continue
  fi
  sha="$(pin "$name")"; r="$(repo "$name")"; sub="$(vendor_tree "$name")"
  echo "fetch $name @ ${sha:0:7} -> vendor/$sub"
  rm -rf "${WORK:?}/$name"
  if ! fetch_at "$WORK/$name" "$r" "$sha"; then
    echo "FAIL  $name: could not fetch ${sha:0:7}" >&2
    continue
  fi
  # Submodules are inlined at the commits the tree pins, so builds work offline.
  if [ -f "$WORK/$name/.gitmodules" ]; then
    git -C "$WORK/$name" submodule update --init --recursive --depth 1 >/dev/null 2>&1 || true
  fi
  rm -rf "$VENDOR/$sub"
  mkdir -p "$VENDOR/$sub"
  ( cd "$WORK/$name" && tar -cf - --exclude=.git --exclude=.gitmodules . ) | ( cd "$VENDOR/$sub" && tar -xf - )
done

# Binaries, READMEs, npm tarball and the Python lock come from the same pins.
if [ -z "$ONLY" ]; then
  echo "note  bin/, scripts/, docs/, plugins/, npm/, python/ are refreshed by hand"
  echo "      (release assets, raw files and package locks — see vendor/README.md)"
fi

python3 "$ROOT/scripts/vendor_manifest.py" --write
