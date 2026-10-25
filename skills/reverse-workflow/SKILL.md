---
name: reverse-workflow
description: End-to-end reverse-engineering workflow for Echo: from an unknown binary to a working AngelScript script — tool decision tree, signature generation, Zydis-based analysis, Unicorn emulation of candidate paths, and patch workflows. Use when taking an unfamiliar binary from raw bytes to a working script.
---

# Reverse Engineering Workflow for Echo

End-to-end workflow: from binary to working Echo AngelScript. Integrates reverse-skill, REA, Zydis, and Unicorn.

---

## Decision tree: which tool first?

```
Have binary / game target
         │
         ├── Unity IL2CPP?
         │       └── REA global-metadata.dat analysis → class/method offsets → Echo process::read_*
         │
         ├── Unreal Engine (UE4/UE5)?
         │       └── Run Dumper-7 → CppSDK → read offsets from headers → echo-sdk agent
         │
         ├── Godot?
         │       └── REA Godot PCK analysis
         │
         ├── Source 2?
         │       └── cs2-offset-dumper + echo-esp / echo-memory patterns
         │
         ├── Native binary (obfuscated/encrypted)?
         │       ├── Light obfuscation (no VM): reverse-skill ida-reverse or radare2 → sigs
         │       └── Heavy (OLLVM/VMProtect): Unicorn trace → echo-reverse agent
         │
         ├── Android APK?
         │       └── REA inspect_apk_signature + IL2CPP or smali RE
         │
         └── WASM?
                 └── REA inspect_wasm_artifact
```

---

## Stage 1: Static analysis

### reverse-skill routing matrix

| Task | reverse-skill entry |
|---|---|
| Finding offsets in a PE binary | `skills/ida-reverse/` or `skills/radare2/` |
| Binary Ninja HLIL struct recovery | `skills/binary-ninja-reverse/` |
| OLLVM deobfuscation | `skills/reverse-engineering/references/ollvm-deobfuscation.md` |
| Patch diff / N-day offset tracking | `skills/patch-diff-exploit/` |
| Anti-cheat driver analysis | `skills/malware-analysis/` + `skills/edr-bypass-re/` |
| .NET / Unity Mono assembly | `skills/dotnet-reverse/` |

**Always gate**: `skills/ops/scope.md` authorization check before acting on any target.

### REA (Reverse Engineer Anything) MCP

Install: `npm install --global rea-agents && npx rea-agents setup`

```
REA targets and tools:
  Unity IL2CPP (versions 24–39) → class/method name → offset
  Godot PCK                     → resource and scene extraction
  Native binary                 → Hopper/Ghidra/IDA pseudocode + symbols
  Android APK                   → inspect_apk_signature, manifest, smali
  WASM                          → inspect_wasm_artifact → exports, imports, memory layout
  HAR/pcap/mitmdump              → HTTP/WebSocket protocol reverse
  SQLite                        → schema + table browsing
  Firmware                      → partition table, filesystem extraction
```

---

## Stage 2: Signature generation

Convert an IDA/Binary Ninja function start into an Echo-ready `process::find_signature` pattern:

1. Take the first 12–20 unique bytes of the function (avoid prologues that compilers vary)
2. Replace all relative addresses and immediates that change with `?`
3. Test: scan returns exactly one match in the module

```angelscript
// Pattern format: space-separated hex bytes, ? = wildcard byte
uint64 base = process::get_module_base("game.exe");
if (base == 0) return false;

uint64 result = process::find_signature(base, "48 89 5C 24 ? 57 48 83 EC 20 48 8B F9");
if (result == 0) {
    alert::show("Pattern broken after patch");
    return false;
}
```

**Rule of thumb:** 10–16 bytes with ≥ 3 non-wildcard bytes between wildcards → uniquely identifies the function across typical game patches.

---

## Stage 3: Runtime struct recovery with Zydis

Use Echo's Zydis disassembler to extract struct offsets from a live process:

```angelscript
uint64 base = process::get_module_base("game.exe");
if (base == 0) return false;

// Find the function that accesses the struct field you want
uint64 fn = process::find_signature(base, "48 8B ? ? ? ? ? 48 85 ? 74 ?");
if (fn == 0) return false;

// Decode the function
array<uint8>@ bytes = process::read_bytes(fn, 0x400);
if (bytes is null) return false;

array<disasm_insn@> insns;
if (!zydis::disasm(bytes, fn, insns)) return false;

for (uint i = 0; i < insns.length(); i++) {
    disasm_insn@ ins = insns[i];

    // Look for memory operands with positive small offsets → struct field accesses
    // Pattern: MOV reg, [reg+0xNN] where 0xNN < 0x1000
    for (uint8 opIdx = 0; opIdx < ins.operand_count_visible; opIdx++) {
        disasm_operand op = ins.get_op(opIdx);
        if (op.type != op_type::mem) continue;
        if (!op.mem_has_disp) continue;
        if (op.mem_disp <= 0 || op.mem_disp >= 0x1000) continue;

        console::log("  " + util::to_hex(ins.runtime_address) + ": " + ins.text +
                     " disp=" + util::to_hex(uint64(op.mem_disp)));
    }
}
```

Cross-reference: compare Zydis output with REA/IDA pseudocode to label offsets.

---

## Stage 4: Unicorn for obfuscated paths

When static analysis fails (OLLVM, VMProtect, custom XOR encrypt), emulate with Echo's Unicorn:

### OLLVM state machine trace

```angelscript
// Shared state for the OLLVM dispatcher trace.
// States are appended to a file: AngelScript cannot resize a global array.
uint64 g_state_count = 0;

bool on_insn(uint64 h, uint64 addr, uint32 size) {
    // zydis::disasm takes an array handle, so read the instruction bytes from
    // the target process — the emulator runs the module at its real base.
    array<uint8>@ raw = process::read_bytes(addr, size);
    if (raw is null) return true;

    array<disasm_insn@> insns;
    if (!zydis::disasm(raw, addr, insns)) return true;

    // Log switch variable writes (typically: MOV [rsp+N], imm32 or MOV eax, imm32)
    if (insns.length() == 0) return true;
    string text = insns[0].text;
    if (text.find("mov eax, ") == 0 || text.find("mov rax, ") == 0) {
        uint64 state = 0;
        uc::reg_read64(h, x86_reg::rax, state);
        g_state_count++;
        file::append("ollvm_states.txt", util::to_hex(state) + "\n");
    }
    return true;   // false would stop emulation
}

bool trace_ollvm(string sig) {
    // 1. Find the entry of the obfuscated function via IDA sig
    uint64 base = process::get_module_base("game.exe");
    if (base == 0) return false;

    uint64 fn = process::find_signature(base, sig);
    if (fn == 0) return false;

    // 2. Emulator backed by the attached process: pages fault in on demand,
    //    so the real module image is emulated without copying it.
    uint64 h = uc::create_process();
    if (h == 0) return false;

    // Stack: setup_stack maps it, sets rsp, and plants a return address that
    // halts emulation when the function returns.
    uint64 stop_addr = 0x7FF000020000;
    uc::mem_map(h, stop_addr, 0x1000, uc::prot::all);
    uc::setup_stack(h, 0x7FF000000000, 0x10000, stop_addr);

    // 3. Hook: record state variable transitions for the OLLVM dispatcher
    uc::hook_code(h, @on_insn);
    int err = uc::start(h, fn, fn + 0x2000, 10000, 0);
    uc::close(h);

    // ollvm_states.txt now holds the sequence of OLLVM states → map to real code blocks
    console::log("OLLVM states traced: " + util::to_hex(g_state_count));
    return err == uc::error::ok;
}
```

### Encrypted pointer decrypt

```angelscript
// Emulate the decrypt function with the encrypted pointer as input.
bool decrypt_pointer(string sig, uint64 encrypted_ptr, uint64 &out decrypted) {
    uint64 base = process::get_module_base("game.exe");
    if (base == 0) return false;

    uint64 decrypt_fn = process::find_signature(base, sig);
    if (decrypt_fn == 0) return false;

    // Emulator backed by the attached process — pages fault in on demand.
    uint64 h = uc::create_process();
    if (h == 0) return false;

    uint64 stop_addr = 0x7FF000020000;
    uc::mem_map(h, stop_addr, 0x1000, uc::prot::all);
    uc::setup_stack(h, 0x7FF000000000, 0x10000, stop_addr);

    uc::reg_write64(h, x86_reg::rcx, encrypted_ptr);   // arg0

    uc::start(h, decrypt_fn, decrypt_fn + 0x400, 5000, 0);

    decrypted = 0;
    uc::reg_read64(h, x86_reg::rax, decrypted);
    uc::close(h);
    return true;
}
```

---

## Stage 5: Patch update workflow

After a game update:

1. **Diff** — use mcp-gamehacking `binary-differ` subagent: `read_subagent("binary-differ")`
2. **Identify** changed functions — those whose first bytes changed
3. **Re-generate sigs** — take new unique bytes, replace addresses with `?`
4. **Single-line update** — change only the `process::find_signature()` argument string
5. **Verify** — read a known-good value (health ≈ 100 at spawn, entity count 1–50)

```angelscript
// Pattern update: change only this one string
uint64 client_base = process::get_module_base("client.dll");
if (client_base == 0) return false;

uint64 hit = process::find_signature(client_base, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 48");  // ← update this
if (hit == 0) return false;

uint64 entity_sys = process::get_relative_address(hit, 3, 7);
```

---

## Stage 6: Evidence standard (from security ops)

For each found offset, record in script header comment:

```angelscript
// offsets from Dumper-7 v1.38, game build 1.38.0.0 (2025-10-15)
// GEntitySystem sig: "48 8B 0D ? ? ? ? 48 85 C9 74 ?" → client.dll+0xABC123 (RIP+3/7)
// OFF_HEALTH 0x330: confirmed via Zydis decode of PlayerPawn::TakeDamage function
```

This survives the next patch: you know what to re-verify and where the original evidence was.

---

## mcp-gamehacking RE subagents

```
read_subagent("offset-finder")       # cross-ref offsets from community sources
read_subagent("pattern-scanner")     # generate and validate IDA-style patterns
read_subagent("binary-differ")       # diff binaries across game patches
read_subagent("struct-recovery")     # recover struct layout from memory dumps
read_subagent("code-analyzer")       # classify techniques, mitigations
get_agent_briefing("reverse-engineer")   # full RE methodology briefing
```
