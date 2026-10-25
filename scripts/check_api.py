#!/usr/bin/env python3
"""
Echo AI Toolkit — API conformance checker.

Fails the build if the docs teach API that does not exist in the real Echo
Universal API. The repo previously shipped an entire invented API
(`proc.read<T>()`, `proc.scan_ida()`, `renderer.draw_rect_filled()`, ...),
so this guard exists to stop it creeping back.

Usage:
    python3 scripts/check_api.py [--api-index PATH] [--root PATH]

Exit codes:
    0 — clean
    1 — violations found
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# ── the invented API that must never appear again ────────────────────────────
# Each entry: (pattern, human name)
BANNED: list[tuple[str, str]] = [
    (r"\bproc\.read\s*<",                      "proc.read<T>() template reads"),
    (r"\bproc\.read_string\s*\(",              "proc.read_string()"),
    (r"\bproc\.read_wstring\s*\(",             "proc.read_wstring()"),
    (r"\bproc\.write\s*<",                     "proc.write<T>() template writes"),
    (r"\bproc\.scan_ida\s*\(",                  "proc.scan_ida()"),
    (r"\bproc\.scan\s*\(",                      "proc.scan()"),
    (r"\bproc\.scan_string\s*\(",               "proc.scan_string()"),
    (r"\bproc\.resolve_rip\s*\(",               "proc.resolve_rip()"),
    (r"\bproc\.get_module\s*\(",                "proc.get_module()"),
    (r"\bproc\.get_modules\s*\(",               "proc.get_modules()"),
    (r"\bproc\.get_export\s*\(",                "proc.get_export()"),
    (r"\bproc\.query_regions\s*\(",             "proc.query_regions()"),
    (r"\bproc\.is_running\s*\(",                "proc.is_running()"),
    (r"\bproc\.disasm_range\s*\(",              "proc.disasm_range()"),
    (r"\bproc\.valid\b",                        "proc.valid"),
    (r"\brenderer\.draw_rect_filled\s*\(",      "renderer.draw_rect_filled()"),
    (r"\brenderer\.draw_rect_outlined\s*\(",    "renderer.draw_rect_outlined()"),
    (r"\brenderer\.draw_rect_gradient\s*\(",    "renderer.draw_rect_gradient()"),
    (r"\brenderer\.draw_circle_filled\s*\(",    "renderer.draw_circle_filled()"),
    (r"\brenderer\.draw_circle\s*\(",           "renderer.draw_circle()"),
    (r"\brenderer\.draw_line\s*\(",             "renderer.draw_line()"),
    (r"\brenderer\.draw_text\s*\(",             "renderer.draw_text()"),
    (r"\brenderer\.draw_polyline\s*\(",         "renderer.draw_polyline()"),
    (r"\brenderer\.draw_convex_poly\s*\(",      "renderer.draw_convex_poly()"),
    (r"\brenderer\.draw_concave_poly\s*\(",     "renderer.draw_concave_poly()"),
    (r"\brenderer\.draw_triangle_filled\s*\(",  "renderer.draw_triangle_filled()"),
    (r"\brenderer\.draw_hue_bar_static\s*\(",   "renderer.draw_hue_bar_static()"),
    (r"\brenderer\.draw_hue_bar\s*\(",          "renderer.draw_hue_bar()"),
    (r"\brenderer\.measure_text\s*\(",          "renderer.measure_text()"),
    (r"\brenderer\.text_outlined\s*\(",         "renderer.text_outlined()"),
    (r"\brenderer\.text\s*\(",                  "renderer.text()"),
    (r"\brenderer\.rect_outlined\s*\(",         "renderer.rect_outlined()"),
    (r"\brenderer\.rect_gradient\s*\(",         "renderer.rect_gradient()"),
    (r"\brenderer\.rect\s*\(",                  "renderer.rect()"),
    (r"\brenderer\.circle\s*\(",                "renderer.circle()"),
    (r"\brenderer\.line\s*\(",                  "renderer.line()"),
    (r"\brenderer\.triangle\s*\(",              "renderer.triangle()"),
    (r"\brenderer\.width\s*\(",                 "renderer.width()"),
    (r"\brenderer\.height\s*\(",                "renderer.height()"),
    (r"\bmenu\.add_tab\s*\(",                   "menu.add_tab()"),
    (r"\bmenu\.checkbox\s*\(",                  "menu.checkbox()"),
    (r"\bmenu\.slider_float\s*\(",              "menu.slider_float()"),
    (r"\bmenu\.save_config\s*\(",               "menu.save_config()"),
    (r"\bmenu\.register\s*\(",                  "menu.register()"),
    (r"\bmath\.calc_fov\s*\(",                  "math.calc_fov()"),
    (r"\bmath\.smooth_angles\s*\(",             "math.smooth_angles()"),
    (r"\bmath\.lerp\s*\(",                      "math.lerp()"),
    (r"\bemu\.emu_start\s*\(",                  "emu.emu_start()"),
    (r"\bemu\.",                               "emu.* namespace"),
    (r"\binput\.key_down\s*\(",                 "input.key_down()"),
    (r"\bmouse\.move\s*\(",                     "mouse.move()"),
    (r"\bmouse\.button\s*\(",                   "mouse.button()"),
    (r"\bconsole\.log\s*\(",                    "console.log()"),
    (r"\balert\.show\s*\(",                     "alert.show()"),
    (r"\bsource2\.w2s\s*\(",                    "source2.w2s()"),
    (r"\bunreal\.w2s\s*\(",                     "unreal.w2s()"),
    (r"\bunity\.w2s\s*\(",                      "unity.w2s()"),
    (r"\bmutex\s*\(\s*\)",                      "mutex()"),
    (r"\bvoid\s+main\s*\(\s*\)",                "void main()"),
]

# ── AngelScript language semantics that the docs must not get wrong ──────────
# Ground truth: https://www.angelcode.com/angelscript/sdk/docs/manual/doc_datatypes_arrays.html
# AngelScript has no built-in array — the host registers one. The registered
# array's methods are camelCase; the snake_case spellings below do not exist.
BANNED_LANGUAGE: list[tuple[str, str]] = [
    (r"\.push_back\s*\(",                        "array.push_back() — the method is insertLast()"),
    (r"\.pop_back\s*\(",                         "array.pop_back() — the method is removeLast()"),
    (r"\.insert_at\s*\(",                        "array.insert_at() — the method is insertAt()"),
    (r"\.remove_at\s*\(",                        "array.remove_at() — the method is removeAt()"),
    (r"\.sort\s*\(\s*\)",                        "array.sort() with no argument — use sortAsc()/sortDesc()"),
    (r"\bstruct\s+[A-Z]\w*\s*\{",                "struct — AngelScript script classes are declared with `class`"),
    (r"\bvoid\s*\(\s*\)\s*@",                    "void()@ — a function-handle type must come from a declared funcdef"),
]

# Files that legitimately quote the old API (the correction contract documents it).
ALLOW_BANNED_IN = {
    "reference/_API_CONTRACT.md",
    "scripts/check_api.py",
}

TEXT_SUFFIXES = {".md", ".as", ".txt", ".tsx", ".ts", ".json"}


def collect_files(root: Path) -> list[Path]:
    skip_dirs = {".git", "node_modules", "dist", "vendor", ".claude"}
    out: list[Path] = []
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if any(part in skip_dirs for part in p.parts):
            continue
        if p.suffix.lower() not in TEXT_SUFFIXES:
            continue
        out.append(p)
    return sorted(out)


def rel(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def code_block_lines(lines: list[str]) -> list[tuple[int, str]]:
    """
    Return (line_number, text) for lines inside fenced code blocks.

    Only shipped code is checked for the invented API. Prose that *names* a wrong
    API to warn against it ("`void main()` does not compile") is legitimate and
    must not trip the guard.
    """
    out: list[tuple[int, str]] = []
    in_block = False
    for n, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("```"):
            in_block = not in_block
            continue
        if in_block:
            out.append((n, line))
    return out


def strip_inline_code(text: str) -> str:
    """
    Remove single-backtick inline code spans.

    Prose inside a code block often uses inline backticks to *name* a wrong API in
    order to warn against it ("`void main()` does not compile"). Those mentions are
    documentation, not shipped code, so they must not trip the guard.
    """
    return re.sub(r"`[^`]*`", " ", text)


def check_banned(files: list[Path], root: Path) -> list[tuple[str, int, str, str]]:
    violations = []
    for path in files:
        r = rel(path, root)
        if r in ALLOW_BANNED_IN:
            continue
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for n, line in code_block_lines(lines):
            scan = strip_inline_code(line)
            for pattern, label in BANNED:
                if re.search(pattern, scan, re.IGNORECASE):
                    violations.append((r, n, label, line.strip()[:120]))
            for pattern, label in BANNED_LANGUAGE:
                if re.search(pattern, scan):
                    violations.append((r, n, label, line.strip()[:120]))
    return violations


def check_real_api(files: list[Path], root: Path, api_index: Path | None) -> list[tuple[str, int, str, str]]:
    """
    Flag `ns::fn(` calls that are not in the real API index.

    Only namespaces that Echo actually owns are checked, so ordinary C++/JS
    identifiers (std::string, React::Component) are never flagged.
    """
    if api_index is None or not api_index.is_file():
        return []

    known: set[str] = set()
    for line in api_index.read_text(encoding="utf-8", errors="replace").splitlines():
        # The index lines look like:
        #   array<uint8>@ process::read_bytes(uint64 address, uint32 size)
        #   bool value = ui::get(checkbox)
        # Match on the call token anywhere in the line so overloads and
        # assignment-prefixed forms are both captured.
        for m in re.finditer(r"\b([a-z][a-z0-9_]*::[a-z][a-z0-9_]*)\s*\(", line):
            known.add(m.group(1))
    if not known:
        return []

    namespaces = {ns for ns, _ in (k.split("::", 1) for k in known)}
    # Third-party drop-in namespaces are not part of the Echo API and are
    # documented as external (see skills/echo-ecosystem).
    external = {"esp_layout"}
    call_re = re.compile(r"\b([a-z][a-z0-9_]*)::([a-z][a-z0-9_]*)\s*\(")

    violations = []
    for path in files:
        r = rel(path, root)
        if r in ALLOW_BANNED_IN:
            continue
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for n, line in code_block_lines(lines):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            scan = strip_inline_code(line)
            for ns, fn in call_re.findall(scan):
                if ns not in namespaces or ns in external:
                    continue  # not an Echo namespace — ignore
                if f"{ns}::{fn}" not in known:
                    violations.append((r, n, f"{ns}::{fn}()", stripped[:120]))
    return violations


def main() -> int:
    ap = argparse.ArgumentParser(description="Check that the toolkit only teaches the real Echo API.")
    ap.add_argument("--root", default=".", help="repo root (default: cwd)")
    ap.add_argument("--api-index", default=None, help="path to the real API signature index")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    api_index = Path(args.api_index).resolve() if args.api_index else None

    files = collect_files(root)
    if not files:
        print("no files to check", file=sys.stderr)
        return 0

    banned = check_banned(files, root)
    unknown = check_real_api(files, root, api_index)

    if banned:
        print(f"\n\033[1;31m✗ {len(banned)} invented-API usage(s) found\033[0m\n")
        for r, n, label, text in banned:
            print(f"  {r}:{n}  {label}")
            print(f"      {text}")
        print()

    if unknown:
        print(f"\n\033[1;31m✗ {len(unknown)} call(s) not found in the real Echo API\033[0m\n")
        for r, n, label, text in unknown:
            print(f"  {r}:{n}  {label}")
            print(f"      {text}")
        print()

    if banned or unknown:
        print("The Echo Universal API is namespaced (process::, render::, ui::, ...).")
        print("See reference/_API_CONTRACT.md for the full old -> new mapping.")
        return 1

    print(f"\033[1;32m✓ API conformance OK\033[0m — {len(files)} files checked")
    return 0


if __name__ == "__main__":
    sys.exit(main())
