#!/usr/bin/env python3
"""
AngelScript compile check for the Echo AI Toolkit.

Two passes:

1. TEMPLATES (strict) — every `templates/*.as` is a complete script a user loads
   into Echo. Each MUST compile against the real AngelScript 2.x grammar.
2. DOC BLOCKS (grammar only) — the ```angelscript blocks in the docs are often
   fragments (a signature list, a snippet without its surrounding function), so
   they cannot be compiled standalone. Only high-signal GRAMMAR errors are
   reported — the ones that mean the snippet could never run.

Requires an AngelScript SDK build and an Echo API stub. See scripts/README.md.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

# ── grammar errors that always mean "this snippet is wrong" ──────────────────
# Fragments legitimately produce "Unexpected token 'if'" (top-level statement),
# "No matching symbol" (identifier defined elsewhere) and similar.
GRAMMAR_ERRORS = [
    "Instead found identifier",           # `struct Foo {` — struct is not a keyword
    "Unexpected token '}'",               # fixed-size array as a class member
    "can use &inout",                    # bare `&` reference on a primitive
    "Instead found reserved keyword",     # `out`, `in`, ...
    "Illegal operation on this datatype", # `x is not null`
    "Can't implicitly convert",           # type mismatch
    "Invalid use of 'in'",
    "Expected ')'",
    "Expected ';'",
    "Duplicate function",
]


def extract_blocks(path: Path):
    """Yield (start_line, source) for each ```angelscript block."""
    lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
    inblock = False
    lang = ""
    start = 0
    body: list[str] = []
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("```"):
            if not inblock:
                inblock = True
                lang = stripped[3:]
                start = i
                body = []
            else:
                inblock = False
                if lang == "angelscript":
                    yield start, "\n".join(body)
            continue
        if inblock:
            body.append(line)


def run_checker(checker: str, workdir: str, source: str, stub: str) -> tuple[int, str]:
    fd, tmp = tempfile.mkstemp(suffix=".as", dir=workdir)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(source)
    try:
        env = dict(os.environ, ECHO_STUB=stub)
        proc = subprocess.run(
            [checker, tmp], capture_output=True, text=True, cwd=workdir, timeout=120, env=env
        )
        return proc.returncode, proc.stdout.strip()
    finally:
        os.unlink(tmp)


def check_templates(root: Path, checker: str, workdir: str, stub: str) -> int:
    failures = 0
    templates = sorted((root / "templates").glob("*.as"))
    for path in templates:
        code, out = run_checker(checker, workdir, path.read_text(encoding="utf-8"), stub)
        if code == 0 and "BUILD OK" in out:
            print(f"  ok    {path.relative_to(root)}")
        else:
            failures += 1
            print(f"  FAIL  {path.relative_to(root)}")
            for line in out.splitlines()[:3]:
                print(f"          {line}")
    print(f"\ntemplates: {len(templates) - failures}/{len(templates)} compile")
    return failures


def check_docs(root: Path, checker: str, workdir: str, stub: str) -> int:
    targets: list[Path] = []
    targets += sorted((root / "agents").glob("*.md"))
    targets += sorted((root / "skills").glob("*/SKILL.md"))
    for extra in ("reference/api.md", "reference/offsets.md", "llms.txt", "prompts/system-prompt.md"):
        p = root / extra
        if p.is_file():
            targets.append(p)

    failures = 0
    checked = 0
    for path in targets:
        for start, src in extract_blocks(path):
            if not src.strip():
                continue
            checked += 1
            code, out = run_checker(checker, workdir, src, stub)
            if code == 0 and "BUILD OK" in out:
                continue
            for line in out.splitlines():
                if any(marker in line for marker in GRAMMAR_ERRORS):
                    failures += 1
                    print(f"  FAIL  {path.relative_to(root)}:{start}: {line.strip()}")
                    break
    print(f"\ndoc blocks: {checked - failures}/{checked} free of grammar errors")
    return failures


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", default=".", help="repo root")
    ap.add_argument("--checker", required=True, help="path to the AngelScript check binary")
    ap.add_argument("--workdir", required=True, help="scratch dir for the temp sources")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    stub = str(Path(args.checker).resolve().parent / "echo_stub.as")
    print("templates:")
    a = check_templates(root, args.checker, args.workdir, stub)
    print("\ndocs:")
    b = check_docs(root, args.checker, args.workdir, stub)

    if a or b:
        print("\nAngelScript compile check FAILED")
        return 1
    print("\nAngelScript compile check OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
