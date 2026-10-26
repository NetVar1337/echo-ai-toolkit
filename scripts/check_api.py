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
import json
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
    (r"\bsleep\s*\(",                          "sleep() — not in the API; use a tick thread or a util::time_now() gate"),
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

# Third-party drop-ins register their own symbols and are not Echo API.
# Documented as external in skills/echo-ecosystem.
EXTERNAL_NAMESPACES = {"esp_layout"}

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


def load_index(api_index: Path | None) -> dict:
    """Load the JSON index produced by scripts/build_api_index.py."""
    if api_index is None or not api_index.is_file():
        return {"namespaced": [], "globals": [], "lines": {}}
    return json.loads(api_index.read_text(encoding="utf-8", errors="replace"))


def check_real_api(files: list[Path], root: Path, index: dict) -> list[tuple[str, int, str, str]]:
    """
    Flag `ns::fn(` calls that are not in the real API index.

    Only namespaces that Echo actually owns are checked, so ordinary C++/JS
    identifiers (std::string, React::Component) are never flagged.
    """
    known: set[str] = set(index.get("namespaced", []))
    if not known:
        return []

    namespaces = {ns for ns, _ in (k.split("::", 1) for k in known)}
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
                if ns not in namespaces or ns in EXTERNAL_NAMESPACES:
                    continue  # not an Echo namespace — ignore
                if f"{ns}::{fn}" not in known:
                    violations.append((r, n, f"{ns}::{fn}()", stripped[:120]))
    return violations


def _strip_source(text: str) -> str:
    """Drop comments and string bodies so brace/paren scanning cannot be fooled."""
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    return text


def _body(text: str, open_brace: int) -> tuple[str, int]:
    """Return (body, index just past the matching close brace)."""
    depth = 0
    for i in range(open_brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_brace + 1:i], i + 1
    return text[open_brace + 1:], len(text)


def _decl_names(region: str) -> set[str]:
    """
    Function names declared in a region: the identifier before a `(` that sits at
    brace and paren depth 0. Function bodies (depth 1) and parameter lists
    (paren depth > 0) are skipped, so `return vec2();` is not a declaration.
    """
    out: set[str] = set()
    braces = parens = 0
    for i, c in enumerate(region):
        if c == "{":
            braces += 1
        elif c == "}":
            braces = max(0, braces - 1)
        elif c == "(":
            if braces == 0 and parens == 0:
                j = i - 1
                while j >= 0 and region[j].isspace():
                    j -= 1
                k = j
                while k >= 0 and (region[k].isalnum() or region[k] == "_"):
                    k -= 1
                name = region[k + 1:j + 1]
                if re.fullmatch(r"[a-z_][a-z0-9_]*", name) and not region[:k + 1].rstrip().endswith("::"):
                    out.add(name)
            parens += 1
        elif c == ")":
            parens = max(0, parens - 1)
    return out


def parse_stub(path: Path) -> tuple[set[str], set[str], set[str]]:
    """
    Return (namespace calls, class methods, globals) declared by the compile stub.

    The stub is what every template is compiled against, so it must not contain a
    symbol the docs do not, and must contain every symbol the docs do.
    """
    text = _strip_source(path.read_text(encoding="utf-8", errors="replace"))
    text = re.sub(r"\b(?:funcdef|typedef)\b[^;]*;", "", text)

    namespaced: set[str] = set()
    methods: set[str] = set()
    masked = list(text)

    for m in re.finditer(r"\b(namespace|class)\s+([a-z0-9_]+)\s*\{", text):
        kind, name = m.group(1), m.group(2)
        body, end = _body(text, m.end() - 1)
        for decl in _decl_names(body):
            if kind == "namespace":
                namespaced.add(f"{name}::{decl}")
            elif decl != name:  # skip constructors: vec2() {}
                methods.add(f"{name}::{decl}")
        for i in range(m.end() - 1, end):
            masked[i] = " "

    return namespaced, methods, _decl_names("".join(masked))


def check_stub(stub: Path, index: dict) -> list[str]:
    """Compare the compile stub against the live API index, both directions."""
    documented = set(index.get("namespaced", []))
    documented_globals = set(index.get("globals", []))
    if not documented:
        return []

    namespaced, methods, globals_ = parse_stub(stub)
    problems: list[str] = []

    for sym in sorted(documented - namespaced - methods):
        problems.append(f"stub missing   {sym}()  — documented but not declared, so nothing compiles against it")

    for sym in sorted(namespaced - documented):
        if sym.split("::", 1)[0] in EXTERNAL_NAMESPACES:
            continue
        problems.append(f"stub invents   {sym}()  — declared but absent from the docs")

    for name in sorted(globals_ - documented_globals):
        problems.append(f"stub invents   {name}()  — global declared but absent from the docs")

    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description="Check that the toolkit only teaches the real Echo API.")
    ap.add_argument("--root", default=".", help="repo root (default: cwd)")
    ap.add_argument("--api-index", default=None, help="JSON index from scripts/build_api_index.py")
    ap.add_argument("--stub", default=None, help="compile stub to verify against the index")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    index = load_index(Path(args.api_index).resolve() if args.api_index else None)

    files = collect_files(root)
    if not files:
        print("no files to check", file=sys.stderr)
        return 0

    banned = check_banned(files, root)
    unknown = check_real_api(files, root, index)
    stub_problems = check_stub(Path(args.stub).resolve(), index) if args.stub else []

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

    if stub_problems:
        print(f"\n\033[1;31m✗ compile stub disagrees with the docs ({len(stub_problems)})\033[0m\n")
        for p in stub_problems:
            print(f"  {p}")
        print()

    if banned or unknown or stub_problems:
        print("The Echo Universal API is namespaced (process::, render::, ui::, ...).")
        print("See reference/_API_CONTRACT.md for the full old -> new mapping.")
        return 1

    print(f"\033[1;32m✓ API conformance OK\033[0m — {len(files)} files checked")
    return 0


if __name__ == "__main__":
    sys.exit(main())
