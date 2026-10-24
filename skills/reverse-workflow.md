# Reverse Engineering Workflow for Echo

End-to-end workflow: from binary to working Echo AngelScript. Integrates reverse-skill, REA, Zydis, and Unicorn.

---

## Decision tree: which tool first?

```
Have binary / game target
         │
         ├── Unity IL2CPP?
         │       └── REA global-metadata.dat analysis → class/method offsets → Echo proc.read
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

Convert an IDA/Binary Ninja function start into an Echo-ready `proc.scan_ida` pattern:

1. Take the first 12–20 unique bytes of the function (avoid prologues that compilers vary)
2. Replace all relative addresses and immediates that change with `?`
3. Test: scan returns exactly one match in the module

```angelscript
// Pattern format: space-separated hex bytes, ? = wildcard byte
uint64 result = proc.scan_ida("48 89 5C 24 ? 57 48 83 EC 20 48 8B F9", "game.exe");
if (result == 0) {
    alert("Pattern broken after patch");
    return false;
}
```

**Rule of thumb:** 10–16 bytes with ≥ 3 non-wildcard bytes between wildcards → uniquely identifies the function across typical game patches.

---

## Stage 3: Runtime struct recovery with Zydis

Use Echo's Zydis disassembler to extract struct offsets from a live process:

```angelscript
// Find the function that accesses the struct field you want
uint64 fn = proc.scan_ida("48 8B ? ? ? ? ? 48 85 ? 74 ?", "game.exe");

// Decode the function
array<instruction@>@ insns = disasm.decode_function(proc, fn);

for (uint i = 0; i < insns.length(); i++) {
    instruction@ ins = insns[i];
    // Look for memory operands with positive small offsets → struct field accesses
    // Pattern: MOV reg, [reg+0xNN] where 0xNN < 0x1000
    if (ins.mnemonic == "MOV" && ins.operands_str.find("[r") >= 0) {
        console_log(fmt("  {}: {} {}", ins.address, ins.mnemonic, ins.operands_str));
    }
}
```

Cross-reference: compare Zydis output with REA/IDA pseudocode to label offsets.

---

## Stage 4: Unicorn for obfuscated paths

When static analysis fails (OLLVM, VMProtect, custom XOR encrypt), emulate with Echo's Unicorn:

### OLLVM state machine trace

```angelscript
// 1. Find the entry of the obfuscated function via IDA sig
uint64 fn  = proc.scan_ida("...", "game.exe");

emulator@ emu = emulator(proc);
uint64 base   = proc.get_module("game.exe").base;
emu.mem_map(base, proc.get_module("game.exe").size, UC_PROT_ALL);

// Stack
emu.mem_map(0x7FF000000000, 0x10000, UC_PROT_ALL);
emu.reg_write(UC_X86_REG_RSP, 0x7FF000008000);

// Hook: record state variable transitions for OLLVM dispatcher
array<uint64> state_log;
emu.hook_code(@on_insn);
emu.start(fn, fn + 0x2000, 10000, 10000);

void on_insn(uint64 addr, uint size) {
    instruction@ ins = disasm.decode(proc, addr);
    // Log switch variable writes (typically: MOV [rsp+N], imm32 or MOV eax, imm32)
    if (ins.mnemonic == "MOV" && ins.operands_str.find("eax, ") == 0)
        state_log.push_back(emu.reg_read(UC_X86_REG_EAX));
}
// state_log now has the sequence of OLLVM states → map to real code blocks
```

### Encrypted pointer decrypt

```angelscript
// Emulate the decrypt function with the encrypted pointer as input
uint64 decrypt_fn = proc.scan_ida("<decrypt sig>", "game.exe");
emulator@ emu     = emulator(proc);
emu.mem_map(base, module_size, UC_PROT_ALL);
emu.mem_map(0x7FF000000000, 0x10000, UC_PROT_ALL);
emu.reg_write(UC_X86_REG_RSP, 0x7FF000008000);
emu.reg_write(UC_X86_REG_RCX, encrypted_ptr);   // arg0
emu.start(decrypt_fn, decrypt_fn + 0x400, 5000, 2000);
uint64 decrypted = emu.reg_read(UC_X86_REG_RAX);
```

---

## Stage 5: Patch update workflow

After a game update:

1. **Diff** — use mcp-gamehacking `binary-differ` subagent: `read_subagent("binary-differ")`
2. **Identify** changed functions — those whose first bytes changed
3. **Re-generate sigs** — take new unique bytes, replace addresses with `?`
4. **Single-line update** — change only the `proc.scan_ida()` argument string
5. **Verify** — read a known-good value (health ≈ 100 at spawn, entity count 1–50)

```angelscript
// Pattern update: change only this one string
uint64 entity_sys = proc.resolve_rip(
    proc.scan_ida("48 8B 0D ? ? ? ? 48 85 C9 74 ? 48", "client.dll"),  // ← update this
    3, 7
);
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
