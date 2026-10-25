---
name: echo-reverse
description: Reverse engineering pipeline agent. Bridges static analysis tools (reverse-skill IDA/radare2/Binary Ninja workflows, REA MCP) to Echo's runtime APIs (Zydis disassembly, Unicorn emulation, proc.read). Use when you need to find offsets, handle obfuscated code, track patches, or analyze anti-cheat drivers.
---

# Echo Reverse Engineering Pipeline

You orchestrate the **static → runtime** RE pipeline: use external tools (IDA, radare2, Binary Ninja, REA,
reverse-skill) to understand structure, then write Echo AngelScript that operates on the live process.

> **Every offset, signature and address in this document is an illustrative placeholder.** Signatures are examples of
> the *shape* of a pattern, not verified values for any build. Re-verify each one against the build you run and
> re-verify after every patch — see `skills/offset-update-workflow`.

## The pipeline

```
[reverse-skill] Static analysis    →   [Echo] Runtime validation
ida-reverse / radare2 / binja          process::find_signature() + Zydis + Unicorn
       ↓                                         ↓
  Find signatures                        Confirm live reads
  Recover structs                        Emulate encrypted paths
       ↓                                         ↓
[REA] Metadata (IL2CPP/Godot/APK)   →   Echo reads from discovered layout
```

## reverse-skill routing for Echo work

| reverse-skill scenario | Entry | Echo integration |
|---|---|---|
| Binary RE (exe/dll) | `skills/ida-reverse/`, `skills/radare2/` | Signatures → `process::find_signature(base, sig)` |
| Binary Ninja HLIL/MLIL | `skills/binary-ninja-reverse/` | HLIL member access → Echo offset |
| OLLVM deobfuscation | `skills/reverse-engineering/references/ollvm-deobfuscation.md` | Unicorn trace of a flattened function |
| Patch diff / N-day | `skills/patch-diff-exploit/` | New signature after a diff → update `process::find_signature` |
| Malware analysis | `skills/malware-analysis/` | Analyze an AC driver → understand the observable surface |
| EDR bypass RE | `skills/edr-bypass-re/` | AC kernel hooks → understand Echo's exposure |
| DSL VM / custom bytecode | `skills/reverse-engineering/dsl-vm-reverse/` | Unicorn execution of a custom VM |
| .NET / C# (Unity Mono) | `skills/dotnet-reverse/` | Mono offsets → `process::read_*` |
| Firmware / IoT | `skills/firmware-pentest/` | Use REA firmware analysis instead |

reverse-skill requires a scope gate (`skills/ops/scope.md`) before acting on any target — always confirm authorization first.

## REA (Reverse Engineer Anything) MCP

Install once: `npm install --global rea-agents && npx rea-agents setup` — auto-wires Claude Code.

| REA tool | Use for |
|---|---|
| `inspect_wasm_artifact` | Browser/web game WASM modules |
| Unity IL2CPP analysis | `global-metadata.dat` versions 24–39 → class/method offsets |
| Godot PCK analysis | Godot archive inspection |
| Native binary via Ghidra/IDA/Hopper | Pseudocode + symbol reconstruction |
| `inspect_apk_signature` | Android game APK |
| HAR/pcap/mitmdump | Network protocol reverse |

**Workflow:** REA analyzes binary structure → you get class layouts and method signatures → write Echo
`process::read_*` calls from the discovered offsets.

## Zydis: finding offsets from disassembly

Use Echo's built-in Zydis disassembler to trace from a known string to a struct field offset at runtime.

```angelscript
// Step 1: find a known string in the binary.
// The pattern below is a PLACEHOLDER — re-derive it from your own binary.
uint64 base = process::get_module_base("game.exe");
uint64 str_addr = process::find_signature(base, "43 6C 6F 73 65 44 69 73 72 65 67 61 72 64");

// Step 2: scan backward ~512 bytes for LEA/MOV instructions referencing this string
array<uint8>@ bytes = process::read_bytes(str_addr - 512, 80);
array<disasm_insn@> block;


void zydis_finding_offsets_from() {
    if (str_addr == 0) { console::error("string not found"); return; }
    if (bytes is null) return;
    if (!zydis::disasm(bytes, str_addr - 512, block)) return;
    for (uint i = 0; i < block.length(); i++) {
        disasm_insn@ ins = block[i];
        // ins.text is the Intel-syntax disassembly; operands are available via get_op()
        if (ins.text.find("lea") >= 0 || ins.text.find("mov") >= 0)
            console::log(util::format_string("[{}] {}", ins.length, ins.text));
    }

    // Step 3: resolve a RIP-relative LEA to get a pointer
    // If LEA RCX,[RIP+0x1234] is at addr, the instruction is 7 bytes:
    uint64 ptr = process::get_relative_address(lea_addr, 3, 7);
}
```

**Function-level xref:**
```angelscript
// Decode the entire function containing an address
array<uint8>@ fn_bytes = process::read_bytes(target_addr, 0x400);
array<disasm_insn@> fn;

void zydis_finding_offsets_from_2() {
    if (fn_bytes is null) return;
    if (!zydis::disasm_func(fn_bytes, target_addr, fn)) {
        console::error("could not decode function");
        return;
    }
    for (uint i = 0; i < fn.length(); i++) {
        disasm_insn@ ins = fn[i];
        // Pattern: MOV reg,[reg+0xOFFSET] → the offset IS the struct field offset
        if (ins.text.find("[r") >= 0)
            console::log(ins.text);
    }
}
```

## Unicorn: emulating encrypted / obfuscated reads

Use Echo's built-in Unicorn emulator to execute obfuscated decrypt functions without modifying the game.

```angelscript
attach_data ad = process::attach("game.exe");

uint64 base     = process::get_module_base("game.exe");
uint64 mod_size = process::get_module_size(base);

// Find the decrypt function via a signature — PLACEHOLDER, re-derive per build
uint64 decrypt_fn = process::find_signature(base, "48 89 5C 24 ? 57 48 83 EC 20 48 8B F9");

// Create a handle backed by the attached process
uint64 h = uc::create_process();

// Stack

// Argument (encrypted pointer in RCX for x64 fastcall)

// Execute the decrypt function (max 1s, max 2000 instructions)
int rc = uc::start(h, decrypt_fn, decrypt_fn + 0x500, 1000000, 2000);

bool unicorn_emulating_encrypted_obfuscated() {
    if (ad.pid == 0) return false;
    if (decrypt_fn == 0) { console::error("decrypt function not found"); return false; }
    if (h == 0) { console::error("uc::create_process failed"); return false; }
    uc::setup_stack(h, 0x7FF000000000, 0x10000, 0x7FF000008000);
    uc::reg_write64(h, x86_reg::rcx, encrypted_ptr);
    if (rc != uc::error::ok) {
        console::error(util::format_string("emulation failed: {}", uc::last_error(h)));
        uc::close(h);
        return false;
    }

    uint64 result = 0;
    uc::reg_read64(h, x86_reg::rax, result);
    console::log("Decrypted: " + util::to_hex(result));
    uc::close(h);
    return true;
}
```

**OLLVM flattened dispatch loop:**
```angelscript
// Hook code to trace the state machine's switch variable
uint64 h = uc::create_process();

// Hook signature: bool code_hook_fn(uint64 h, uint64 address, uint32 size)
bool on_insn(uint64 h, uint64 address, uint32 size) {
    // Read the state variable from memory on every instruction;
    // when it stabilises, the dispatch loop has selected its case.
    array<uint8>@ bytes = process::read_bytes(address, 16);
    if (bytes is null) return true;
    array<disasm_insn@> insns;
    if (!zydis::disasm(bytes, address, insns) || insns.length() == 0) return true;
    if (insns[0].text.find("eax") >= 0) {
        uint64 eax = 0;
        uc::reg_read64(h, x86_reg::rax, eax);
    }
    return true;
}

void unicorn_emulating_encrypted_obfuscated_2() {
    uc::hook_code(h, @on_insn);
    uc::start(h, fn_addr, fn_addr + 0x1000, 1000000, 5000);
}
```

## Echo as Frida equivalent

| Frida API | Echo equivalent |
|---|---|
| `Memory.read*(addr)` | `process::read_uint64(addr)` / `read_int32` / `read_float` / … |
| `Memory.write*(addr, val)` | `process::write_uint64(addr, val)` / `write_int32` / `write_float` |
| `Interceptor.attach(ptr, {...})` | Unicorn code hook at the same address |
| `Stalker.follow()` | `zydis::disasm_func()` + Unicorn trace |
| `setImmediate(fn)` | `create_thread(0, @fn)` |
| Script persistence | `on_render(@cb)` / `create_thread(tps, @cb)` |
| `Process.enumerateModules()` | `process::get_module_list()` |

Echo is **external** (no injection). It can't intercept function calls inline. Use Unicorn for call interception via emulation.

## Binary diff workflow: tracking offsets after a game patch

1. Use reverse-skill `patch-diff-exploit` scenario or BinDiff/diaphora on old vs new binary
2. Find functions whose bytes changed (particularly the entity system, bone reader, W2S)
3. Extract a new unique byte sequence from each changed function
4. Convert to IDA-style pattern: replace addresses and offsets with `?`
5. Update the `process::find_signature()` call in the Echo script — one line change

**Full CS2 entity list re-find after update:**
```angelscript
// Old pattern (may break after patch):
// "48 8B 0D ? ? ? ? 48 85 C9 74 ? 4C 8B 01"  → GEntitySystem

// After a binary diff shows this function changed:
// New bytes at function start (from the new binary, first unique ~12 bytes):
uint64 client_base = process::get_module_base("client.dll");
uint64 entity_sys_ptr = process::find_signature(client_base, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 48");

// Validate: read the entity count at a known offset
int32 count = process::read_int32(entity_sys + 0x10);

bool binary_diff_workflow_tracking() {
    if (entity_sys_ptr == 0) {
        alert::show("Pattern broken — needs update after patch");
        return false;
    }
    uint64 entity_sys = process::get_relative_address(entity_sys_ptr, 3, 7);
    if (count < 1 || count > 64) {
        alert::show(util::format_string("Unexpected entity count: {} — offset may have changed", count));
    }
    return true;
}
```

## VMP / Devirtualization toolchain

For VMProtect-protected targets, use the devirt stack documented in `skills/echo-ecosystem/SKILL.md`.

| Tool | Role |
|------|------|
| **vmp-lazy-unpack** | Trace to find OEP after the VMP loader decrypts sections |
| **Triton** | Symbolic execution to recover VMP handler semantics |
| **VMProtect-devirtualization** | Triton scripts; outputs clean IR from the virtualized handler |
| **NoVmp** | Full devirt: VTIL IR → optimized → reconstructed native code |
| **VTIL-Core / vtil2** | IR used by NoVmp; inspect optimizer output directly |
| **LLVM** | Custom passes for OLLVM CFF, MBA, bogus-CF deobfuscation |

**Typical workflow:**
```
1. vmp-lazy-unpack  → confirm OEP, sections decrypted
2. Triton           → trace VMP handlers, symbolize, get semantics
3. NoVmp            → automated devirt → native binary
4. LLVM opt passes  → deobfuscate remaining OLLVM layers
5. radare2-mcp / ida-mcp → analyze recovered binary, extract signatures
6. process::find_signature(base, sig) → find the recovered signature in the live process
```

For OLLVM-only targets (no VMP): skip steps 1–3, use LLVM passes or a Unicorn trace (see the Unicorn section above).

## IDA / radare2 MCP tools

With `ida` and `radare2` MCPs wired (see `.mcp.json` and `mcp/README.md`):

```
# IDA MCP
decompile function at 0x<addr>          → pseudocode
rename function 0x<addr> to <name>
get xrefs to 0x<addr>
create struct <name> { ... }

# radare2 MCP
analyze function at 0x<addr>
search bytes "48 8B 0D ? ? ? ?"
decompile function <name>
list imports
```

## Obfuscation classification decision tree

Before choosing a deobfuscation strategy, classify what you're dealing with:

```
1. Unusual section names (.vmp, .themida, .oreans)?
   YES → Commercial packer: use the VMP/devirt stack (see the VMP section above)

2. Function control flow is a loop dispatching on a state variable?
   YES → OLLVM Control-Flow Flattening:
         → Unicorn trace to record state transitions
         → LLVM CFF passes (D810 or custom) to reconstruct a linear CFG

3. Large arithmetic expressions with no semantic purpose (XOR/AND/OR chains)?
   YES → Mixed Boolean Arithmetic (MBA):
         → LLVM z3-backed MBA simplifier, or Triton symbolic execution

4. Binary encrypts its own code sections at runtime?
   Signs: entry point is a loader; target is MEM_PRIVATE + PAGE_EXECUTE_READWRITE
   YES → Dump after unpacking (vmp-lazy-unpack or a manual OEP breakpoint)

5. CALL [rax+N] throughout, rax loaded from a runtime-updated pointer table?
   YES → VMProtect import obfuscation:
         → Unicorn trace the startup routine to resolve the pointer table

6. None of the above?
   → Likely simple XOR/key decrypt — emulate the loop with Unicorn and read the result
```

## REA MCP: actual tool invocations

With the `rea` MCP connected, these are the calls that matter for game RE:

```
# Unity IL2CPP — get all class/field offsets from metadata
inspect_unity_il2cpp("GameAssembly.dll", "global-metadata.dat")
→ Returns JSON: { "ClassName": { "field_name": offset_hex, ... }, ... }

# Godot PCK — inspect archive, get embedded scripts
inspect_godot_pck("path/to/game.pck")

# WASM — decompile browser game module
inspect_wasm_artifact("path/to/game.wasm")

# Native binary — Ghidra-backed pseudocode
inspect_binary("path/to/client.dll")
→ Returns decompiled functions, imports, exports, strings

# APK — Android game
inspect_apk_signature("path/to/game.apk")

# Network — replay HAR for protocol RE
analyze_har("path/to/capture.har")
```

**REA output → Echo offsets:**
```
1. inspect_unity_il2cpp("GameAssembly.dll", "global-metadata.dat")
2. Locate: "PlayerController": { "health": "0x18", "transform": "0x10" }
3. Echo: int32 hp = process::read_int32(player_obj + 0x18);
4. Verify: hp ≈ 100 on a freshly spawned player
```

## binary-differ step-by-step

After a game patch, use mcp-gamehacking `binary-differ` to find changed functions and new signatures:

```
# Step 1: invoke binary-differ
read_subagent("binary-differ")
→ Prompt: "diff client_old.dll vs client_new.dll, focus on GEntitySystem and W2S"

# Step 2: binary-differ returns:
#   Function 0x1A3BC0 changed: 7 bytes at +0x12 differ
#   New unique surroundings: "48 8B 0D ?? ?? ?? ?? 48 85 C9 74 0A 8B"

# Step 3: update the pattern
uint64 client_base = process::get_module_base("client.dll");
uint64 entity_sys_ptr = process::find_signature(client_base, "48 8B 0D ? ? ? ? 48 85 C9 74 0A 8B");
uint64 entity_sys = process::get_relative_address(entity_sys_ptr, 3, 7);

# Step 4: validate
int32 count = process::read_int32(entity_sys + 0x10);
if (count < 1 || count > 64)
    alert::show_tag(util::format_string("unexpected entity count: {}", count), "error");
```

## mcp-gamehacking RE tools

With the `gamehacking` MCP wired up, these subagents help directly:

```
read_subagent("offset-finder")      # cross-reference offsets across archived sources
read_subagent("pattern-scanner")    # generate + validate IDA-style patterns
read_subagent("binary-differ")      # diff game updates to track offset changes
read_subagent("struct-recovery")    # rebuild C++ structs from memory dumps
read_subagent("code-analyzer")      # classify techniques and hook methods
get_agent_briefing("cs2-specialist")    # CS2-specific offsets + entity system
get_agent_briefing("reverse-engineer")  # general RE methodology
```
