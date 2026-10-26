#!/usr/bin/env python3
"""
Echo AI Toolkit — build the authoritative API index from the live Echo docs.

The docs bundle (https://echo-23.gitbook.io/angel/llms-full.txt) is the only
source of truth for what the Echo Universal API contains. This script reduces it
to a machine-readable index that `check_api.py` verifies the repo against.

Usage:
    curl -fsSL https://echo-23.gitbook.io/angel/llms-full.txt -o /tmp/echo-llms-full.txt
    python3 scripts/build_api_index.py /tmp/echo-llms-full.txt -o /tmp/echo-api-index.json

Output JSON:
    {
      "namespaced": ["process::read_uint64", "ui::add_checkbox", ...],
      "globals":    ["create_thread", "on_render", "build_view_cache", ...],
      "lines":      {"process::read_uint64": "uint64 process::read_uint64(uint64 address)"}
    }
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

CODE_BLOCK = re.compile(r"```(?:cpp|c\+\+)\n(.*?)```", re.S)
NAMESPACED = re.compile(r"\b([a-z][a-z0-9_]*)::([a-z][a-z0-9_]*)\s*\(")
# A bare global function declaration: `<type> name(`. Excludes namespace-qualified
# calls (the `::` fails the name match) and expressions (`v2.add(`).
GLOBAL = re.compile(r"^[A-Za-z_][\w:<>@*&\s]*?\s+([a-z_][a-z0-9_]*)\s*\(")
GLOBAL_SKIP = re.compile(r"^(?:funcdef|typedef|return|if|while|for|switch|//|#)")


def build(text: str) -> dict:
    namespaced: set[str] = set()
    globals_: set[str] = set()
    lines: dict[str, str] = {}

    for block in CODE_BLOCK.findall(text):
        for raw in block.split("\n"):
            line = raw.strip()
            if not line or line.startswith("//"):
                continue
            for ns, fn in NAMESPACED.findall(line):
                sym = f"{ns}::{fn}"
                namespaced.add(sym)
                lines.setdefault(sym, line.rstrip(";").strip())
            if "::" not in line and not GLOBAL_SKIP.match(line):
                m = GLOBAL.match(line)
                if m:
                    globals_.add(m.group(1))

    return {
        "namespaced": sorted(namespaced),
        "globals": sorted(globals_),
        "lines": {k: lines[k] for k in sorted(lines)},
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("docs", help="path to llms-full.txt")
    ap.add_argument("-o", "--out", default="-", help="output JSON path (default: stdout)")
    args = ap.parse_args()

    src = Path(args.docs)
    if not src.is_file() or src.stat().st_size == 0:
        print(f"docs bundle missing or empty: {src}", file=sys.stderr)
        return 1

    index = build(src.read_text(encoding="utf-8", errors="replace"))
    payload = json.dumps(index, indent=2) + "\n"
    if args.out == "-":
        sys.stdout.write(payload)
    else:
        Path(args.out).write_text(payload, encoding="utf-8")
    print(
        f"{len(index['namespaced'])} namespaced calls, {len(index['globals'])} globals",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
