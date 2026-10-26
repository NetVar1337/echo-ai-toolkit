#!/usr/bin/env python3
"""
Vendored dependency manifest — write and verify.

vendor/ holds every external artifact the installer would otherwise fetch, so an
install never trusts a third-party host for bytes. MANIFEST.json records the
sha256 of every file plus the upstream repo, commit and license it came from.

    python3 scripts/vendor_manifest.py --write    # after refreshing vendor/
    python3 scripts/vendor_manifest.py --check    # CI: tree must match exactly
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VENDOR = ROOT / "vendor"
MANIFEST = VENDOR / "MANIFEST.json"
CHECKSUMS = VENDOR / "CHECKSUMS.sha256"

# Upstream provenance. `license` is the SPDX id upstream declares, or "NONE"
# when the repo has no license file — see vendor/README.md before redistributing.
SOURCES = [
    {"path": "mcp/angel-menu-mcp", "repo": "Jozkah/angel-menu-mcp",
     "commit": "a96533e983256ad0917a8192ad43c11fac5979cd", "license": "MIT"},
    {"path": "tools/VTIL-Core", "repo": "vtil-project/VTIL-Core",
     "commit": "9ebee8e890a3a8923cc41f07821f740910e7c9b2", "license": "BSD-3-Clause"},
    {"path": "tools/NoVmp", "repo": "can1357/NoVmp",
     "commit": "6c23c9a335f70e8d5ed6299668fd802f2314c896", "license": "GPL-3.0"},
    {"path": "tools/NoVmp/VTIL-Core", "repo": "vtil-project/VTIL-Core",
     "commit": "25861ca20e93b48cae746292e1a1108bbd5ee09c", "license": "BSD-3-Clause"},
    {"path": "tools/NoVmp/linux-pe", "repo": "can1357/linux-pe",
     "commit": "30aae563eda7c6808ed4a376abee6bfd1a46f00a", "license": "NONE"},
    {"path": "tools/vtil2", "repo": "pop-rip/vtil2",
     "commit": "242d331fdbe4e596fe79234f2abea2aa8de87e21", "license": "BSD-3-Clause"},
    {"path": "tools/vmp-lazy-unpack", "repo": "x86rc/vmp-lazy-unpack",
     "commit": "66f64f6f83e3104735dbfffbd18bfa768ecd4346", "license": "NONE"},
    {"path": "tools/VMProtect-devirtualization", "repo": "JonathanSalwan/VMProtect-devirtualization",
     "commit": "d2b26d66db59e341f179c7e326246d28c4d25491", "license": "NONE"},
    {"path": "tools/signature-doctor", "repo": "b4rzY/Signature-Doctor",
     "commit": "19fda46d86a4e142a547c375a4cc85cd68a963c5", "license": "NONE"},
    {"path": "tools/web-mv", "repo": "Jozkah/web-mv",
     "commit": "73c4a0b971f4fb30851656331d049636545fa599", "license": "NONE"},
    {"path": "plugins/ponytail", "repo": "DietrichGebert/ponytail",
     "commit": "pinned-by-lock", "license": "MIT"},
    {"path": "plugins/andrej-karpathy-skills", "repo": "multica-ai/andrej-karpathy-skills",
     "commit": "pinned-by-lock", "license": "NONE"},
    {"path": "bin", "repo": "sinistercodes/as_bundler + speedsunderscore/echo-angelscript-lsp",
     "commit": "release assets", "license": "see upstream"},
    {"path": "scripts", "repo": "speedsunderscore/echo-esp-preview",
     "commit": "f3f3834963df28623aa353dac507b7c8362a7a7c", "license": "NONE"},
    {"path": "docs", "repo": "gmh5225/awesome-game-security + ridpath/gamehacking-cheatsheet",
     "commit": "pinned-by-lock", "license": "see upstream"},
    {"path": "npm", "repo": "npm:rea-agents@6.8.0",
     "commit": "npm tarball + lockfile", "license": "see upstream"},
    {"path": "python", "repo": "PyPI: triton-library, pefile, capstone, unicorn",
     "commit": "requirements.lock (sha256 per artifact)", "license": "see upstream"},
]

# Generated or machine-local files that must never be vendored.
SKIP_NAMES = {".git", "node_modules", "__pycache__", ".DS_Store", "MANIFEST.json", "CHECKSUMS.sha256"}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def walk() -> list[Path]:
    out = []
    for p in sorted(VENDOR.rglob("*")):
        if any(part in SKIP_NAMES for part in p.parts):
            continue
        if p.is_file():
            out.append(p)
    return out


def build() -> dict:
    files = {}
    for p in walk():
        files[p.relative_to(VENDOR).as_posix()] = {"sha256": sha256(p), "size": p.stat().st_size}
    return {
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "sources": SOURCES,
        "files": files,
    }


def write() -> int:
    data = build()
    MANIFEST.write_text(json.dumps(data, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    # sha256sum -c format, so the installer can verify a single file without Python.
    CHECKSUMS.write_text(
        "".join(f"{f['sha256']}  {name}\n" for name, f in sorted(data["files"].items())),
        encoding="utf-8",
    )
    total = sum(f["size"] for f in data["files"].values())
    print(f"wrote {MANIFEST.relative_to(ROOT)} — {len(data['files'])} files, {total / 1e6:.1f} MB")
    return 0


def check() -> int:
    if not MANIFEST.is_file():
        print("vendor/MANIFEST.json missing — run scripts/vendor_manifest.py --write", file=sys.stderr)
        return 1
    recorded = json.loads(MANIFEST.read_text(encoding="utf-8"))["files"]
    actual = {p.relative_to(VENDOR).as_posix(): p for p in walk()}

    changed = [n for n in sorted(set(recorded) & set(actual)) if sha256(actual[n]) != recorded[n]["sha256"]]
    missing = [n for n in sorted(set(recorded) - set(actual))]
    extra = [n for n in sorted(set(actual) - set(recorded))]

    for n in changed[:20]:
        print(f"  changed  vendor/{n}")
    for n in missing[:20]:
        print(f"  missing  vendor/{n}")
    for n in extra[:20]:
        print(f"  extra    vendor/{n}")

    if changed or missing or extra:
        print(
            f"\n✗ vendor/ does not match MANIFEST.json "
            f"({len(changed)} changed, {len(missing)} missing, {len(extra)} extra)"
        )
        print("  If the change is intentional: python3 scripts/vendor_manifest.py --write")
        return 1

    print(f"✓ vendor/ matches MANIFEST.json — {len(actual)} files")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true", help="regenerate MANIFEST.json")
    ap.add_argument("--check", action="store_true", help="verify vendor/ against MANIFEST.json")
    args = ap.parse_args()
    if args.write:
        return write()
    if args.check:
        return check()
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
