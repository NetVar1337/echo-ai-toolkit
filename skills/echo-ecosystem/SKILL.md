---
name: echo-ecosystem
description: External tools that complement Echo API development: angel-menu-mcp for overlay menu control, echo-esp-preview for layout previewing, echo-angelscript-lsp for editor autocomplete, as_bundler for bundling and obfuscation, web-mv for browser-based memory viewing, plus the binary-analysis and VMP-devirtualization toolchain.
---

# Echo Ecosystem Tools

External tools that complement Echo API development: menu control, ESP layout previewing, AngelScript tooling, binary analysis MCPs, and the VMP/devirtualization stack.

---

## UI / Menu

### web-mv (cy-gnus/web-mv)
Browser-based memory viewer for the Echo agent API. Reads live game state via Echo's HTTP agent lane.

- Default lane: `/agent-ui` → `ws://127.0.0.1:9010/agent-ui`
- Install: `npm install` (TypeScript/HTML/CSS)
- Branch `feat/menu-control-lane` (Jozkah/web-mv): adds **Menu Control** tab using `/agent-ext` lane with `ui_list`, `ui_get`, `ui_set` RPC verbs; supports `HOST=0.0.0.0` for phone/LAN access

### angel-menu-mcp (Jozkah/angel-menu-mcp)
MCP server that lets Claude enumerate and toggle an Angel overlay's in-game menu over WebSocket.

```bash
npm install
claude mcp add angel-menu -- node /path/to/angel-menu-mcp/index.js
```

Tools: `list_features`, `get_feature`, `set_feature`, `connection_status`

> Danger controls (aim assist, chams, no-recoil) require a human "ARM danger controls" click on the PC before Claude can toggle them.

---

## AngelScript Tooling

### echo-angelscript-lsp (speedsunderscore/echo-angelscript-lsp)
VS Code extension for AngelScript targeting the Echo API. ~1900 bundled symbols.

- Features: syntax + semantic highlighting, autocompletion, hover docs, go-to-definition, find refs, real-time errors, cross-file analysis, bundler
- Install: `code --install-extension echo-angelscript-lsp-0.0.1.vsix`

### as_bundler (sinistercodes/as_bundler)
AngelScript bundler, validator, and minifier. Build: CMake + C++ compiler.

```bash
as_bundler [OPTIONS] <dir|file.as>
  -o file            output path
  --strip / -s       remove comment-only lines
  --obfuscate / -O   rename identifiers
  --remove-newlines  minify
  --scramble-strings XOR-encrypt string literals as hash-map lookups
  -D MACRO           define preprocessor macro
```

Built-in macros: `__BUILD_TIMESTAMP_STR__`, `__BUILD_UNIX_TS__`, `STRHASH("text")`, `STRHASH64("text")`

---

## ESP Layout

### echo-esp-preview (speedsunderscore/echo-esp-preview)
Drop-in `esp_preview.as` providing a `g_preview` global object and an `esp_layout` namespace.
Register elements once in `bool main()`; query positions at render time. No game-specific types.

The registration and query calls live on the **`g_preview` class**; the `esp_layout` namespace
only holds layout constants plus `bar_rect` / `label_bar_offset` / `anchor_for_side`. These
calls belong to the third-party drop-in library, not to the Echo API — the library declares
the `label_info_t`, `bar_info_t`, `image_info_t` and `box_info_t` types. (`color` is an
Echo API type, not a library one.)

```angelscript
// SIDE_TOP/SIDE_RIGHT/SIDE_BOTTOM/SIDE_LEFT are your own constants: 0 = top,
// 1 = right, 2 = bottom, 3 = left.
int g_name_id   = 0;
int g_health_id = 0;
int g_icon_id   = 0;

// Register once, from bool main():
bool main() {
    g_preview.register_bounding_box(g_box_enabled, g_box_col, g_box_col_occluded);

    g_name_id = g_preview.register_label(
        "name", g_name_enabled, g_name_col, g_name_col_occluded,
        SIDE_TOP, fonts::TAHOMA, 13);          // font_size is an int

    g_health_id = g_preview.register_bar(
        g_bar_enabled, g_bar_col, g_bar_col_occluded, SIDE_LEFT);

    g_icon_id = g_preview.register_image(g_icon_enabled, g_icon_tex, SIDE_TOP, 32);

    g_preview.load("esp_preview.json");
    return true;
}

// Query at render time — the getters return the info type BY VALUE:
void draw_preview() {
    label_info_t info = g_preview.get_label_info(g_name_id);
    bar_info_t   bar  = g_preview.get_bar_info(g_health_id);
    box_info_t   box  = g_preview.get_box_info();
    image_info_t img  = g_preview.get_image_info(g_icon_id);
}
```

See `templates/esp-preview.as` for a working starter.

---

## Binary Analysis MCPs

### radare2-mcp (radareorg/radare2-mcp)
Official radare2 MCP stdio server. Written in C.

```bash
r2pm -Uci r2mcp   # install
# .mcp.json entry: { "command": "r2pm", "args": ["-r", "r2mcp"] }
```

Capabilities: disassemble, decompile (r2ghidra/r2dec), search bytes/strings, analyze functions, list imports/exports, apply patches. Supports HTTP mode (`-H port`), per-session multiplexing, readonly mode.

### ida-mcp (HexRaysSA/ida-mcp)
Official Hex-Rays IDA MCP Server. Requires IDA 9.4+ with idalib + Python 3.11+.

```bash
# Install via Claude Code marketplace:
claude plugin marketplace add HexRaysSA/claude-marketplace
claude plugin install ida-mcp@HexRaysSA

# Or uvx stdio config:
# { "command": "uvx", "args": ["--exclude-newer=1s", "ida-mcp", "stdio", "--agent=my-agent"] }
```

Capabilities: decompile functions, rename symbols, add comments, query xrefs, manage structs/enums, set breakpoints (IDA debugger).

### SuperGhidra (yuatemycat/SuperGhidra)
Ghidra Python tools with daemon, SQLite cache, and MCP topic support.

- Daemon: `127.0.0.1:5073`
- Packages: `core` (daemon + IPC), `formats` (ELF/PE/Mach-O, MSVC RTTI, Serialize() tracing), `lifters` (ARM64→P-code, Z3 checker), `diff` (cross-version function matching), `acceleration` (WGPU shaders for ARM64 patterns), `integrations` (APK↔JNI, LLM naming)
- License: AGPL-3.0

---

## VMP / Devirtualization Stack

### NoVmp (can1357/NoVmp)
VMProtect devirtualization tool. Lifts VMP-obfuscated functions to VTIL IR, runs optimizer passes, and reconstructs native x86-64 code.

```bash
mkdir build && cd build
cmake .. && cmake --build .
novmp <target.exe>          # outputs devirtualized binary
```

### VTIL-Core (vtil-project/VTIL-Core)
Virtual-machine Translation Intermediate Language. C++ library for representing VM-lifted code as IR with optimizer passes (dead code elimination, constant folding, register coalescing).

- Used by NoVmp as its IR backend
- Build: CMake

### vtil2 (pop-rip/vtil2)
VTIL v2 — redesigned IR. Cleaner block/instruction representation; intended successor to VTIL-Core.

### Triton (JonathanSalwan/Triton)
Dynamic binary analysis framework with symbolic execution, taint analysis, and SMT solving.

```python
from triton import TritonContext, ARCH, MODE, Instruction
ctx = TritonContext(ARCH.X86_64)
ctx.setMode(MODE.ALIGNED_MEMORY, True)

ctx.symbolizeRegister(ctx.registers.rax)

inst = Instruction(bytes.fromhex("48 89 c8"))   # mov rax, rcx
ctx.processing(inst)

sym = ctx.getSymbolicRegister(ctx.registers.rax)
print(ctx.getAstContext().unroll(sym.getAst()))
```

Key APIs: `taintRegister`, `getSymbolicRegisterValue`, `getPathPredicate`, `getSolver` (Z3), `liftToLLVM`.

### VMProtect-devirtualization (JonathanSalwan/VMProtect-devirtualization)
Python scripts using Triton to devirtualize VMProtect-protected functions. Demonstrates tracing VMP handler execution with symbolic execution and recovering original semantics.

### vmp-lazy-unpack (x86rc/vmp-lazy-unpack)
VMP lazy section unpacker. Traces execution to identify the Original Entry Point after VMProtect's loader has run and decrypted the original code.

---

## LLVM (llvm/llvm-project)
Compiler infrastructure for IR-based binary analysis and deobfuscation.

**For Echo / RE work:**
- `opt` passes: write custom LLVM IR passes to deobfuscate OLLVM control-flow flattening, MBA expressions, bogus control flow
- `llc`: lower lifted IR back to x86-64 assembly
- Integration points: RetDec, McSema, Binary Ninja's LLVM lifting, Triton's `liftToLLVM`

```bash
# Run a custom deobfuscation pass:
opt -load-pass-plugin=./MyPass.so -passes=my-deobfuscate input.ll -o output.ll
llc -march=x86-64 output.ll -o output.s
```

**OLLVM deobfuscation pipeline:**
1. Lift target function to LLVM IR (Binary Ninja LLVM backend or McSema)
2. Run `-passes=mem2reg,instcombine,simplifycfg` to normalize
3. Apply custom CFF pass: identify dispatcher block, remove fake edges, reconnect real CFG
4. Lower back to x86-64 with `llc -march=x86-64`
