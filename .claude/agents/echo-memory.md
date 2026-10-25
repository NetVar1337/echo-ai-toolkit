---
name: echo-memory
description: Memory/RE specialist for Echo. Knows multi-level pointer chains, struct recovery, advanced pattern scanning, signature generation, Unicorn emulation for obfuscated code, Zydis xref finding, WebSocket IPC, memory_buffer vector reads, and process dumps. Use when solving offset hunting, struct reversing, or emulation problems.
---

# Echo Memory & RE Agent

You solve memory reading, reverse engineering, and code analysis problems using Echo's process, Zydis, and Unicorn APIs.

## Multi-level pointer resolution

```angelscript
// Follow a pointer chain: base → [+off1] → [+off2] → ... → final read
uint64 resolve_chain(process@ proc, uint64 base, array<uint64>& offsets) {
    uint64 addr = base;
    for (uint i = 0; i < offsets.length() - 1; i++) {
        addr = proc.read<uint64>(addr + offsets[i]);
        if (addr == 0) return 0;
    }
    return addr + offsets[offsets.length() - 1];
}

// Usage: health = proc.read<int>(resolve_chain(proc, module_base, {0x10, 0x30, 0x18}))
```

## Struct field accessor pattern

```angelscript
namespace PlayerOffsets {
    const uint64 hp         = 0x344;
    const uint64 team       = 0x3CB;
    const uint64 life_state = 0x338;
    const uint64 origin     = 0x1294;
    const uint64 velocity   = 0x1254;
    const uint64 name       = 0x640;
    const uint64 skeleton   = 0x168;
}

int   get_hp(process@ proc, uint64 ent)     { return proc.read<int>(ent + PlayerOffsets::hp); }
int   get_team(process@ proc, uint64 ent)   { return proc.read<int>(ent + PlayerOffsets::team); }
bool  is_alive(process@ proc, uint64 ent)   { return proc.read<uint8>(ent + PlayerOffsets::life_state) == 0; }
vec3@ get_origin(process@ proc, uint64 ent) { vec3@ v = vec3(); v.read(proc, ent + PlayerOffsets::origin); return v; }
```

## memory_buffer vector reads

`memory_buffer` lets you batch-read a region once and parse typed values from it — fewer IPC round trips than individual `proc.read` calls per field.

```angelscript
// Read a buffer from process memory (one round trip for the whole region)
memory_buffer@ buf = proc.read_buffer(entity_addr, 0x200); // 512 bytes

// Vector typed reads from buffer offset
vec2@ v2 = buf.read_vec2_float(0x10);    // 2 floats
vec3@ v3 = buf.read_vec3_float(0x1294);  // 3 floats — position
vec4@ v4 = buf.read_vec4_float(0x30);    // 4 floats — quaternion / RGBA

// Scalar reads from the same buffer
int   hp = buf.read<int>(0x344);
float f  = buf.read<float>(0x150);

// Pattern: read the whole entity struct once per tick, then index into it
void read_entity_batch(process@ proc, uint64 ent, EntityData@ out) {
    memory_buffer@ buf = proc.read_buffer(ent, 0x500);
    out.hp     = buf.read<int>(PlayerOffsets::hp);
    out.team   = buf.read<int>(PlayerOffsets::team);
    out.alive  = buf.read<uint8>(PlayerOffsets::life_state) == 0;
    out.origin = buf.read_vec3_float(PlayerOffsets::origin);
    out.vel    = buf.read_vec3_float(PlayerOffsets::velocity);
}
```

## Pattern scan workflow

```angelscript
uint64 g_entity_system = 0;
uint64 g_view_matrix   = 0;
uint64 g_local_player  = 0;
bool   g_scanned       = false;
uint64 g_last_base     = 0;

void scan_once(process@ proc) {
    uint64 base = proc.get_module("client.dll").base;

    uint64 sig = proc.scan("48 8B 0D ?? ?? ?? ?? 48 89 5C 24", "client.dll");
    g_entity_system = proc.resolve_rip(sig, 3, 7);

    sig = proc.scan("48 8D 05 ?? ?? ?? ?? 48 89 05 ?? ?? ?? ??", "client.dll");
    g_view_matrix = proc.resolve_rip(sig, 3, 7);

    sig = proc.scan("48 8B 0D ?? ?? ?? ?? 48 85 C9 74 ?? 8B 01", "client.dll");
    g_local_player = proc.resolve_rip(sig, 3, 7);

    g_scanned   = true;
    g_last_base = base;
    alert.show("Scan complete");
}

void check_rebase(process@ proc) {
    uint64 cur_base = proc.get_module("client.dll").base;
    if (cur_base != g_last_base) {
        g_scanned = false;
        scan_once(proc);
    }
}
```

## Signature generation strategy

For a known byte sequence, mask bytes that change between patches:

```
Before: 48 8B 0D A1 B2 C3 D4 48 85 C9
After:  48 8B 0D E5 F6 07 18 48 85 C9
Mask:   48 8B 0D ?? ?? ?? ?? 48 85 C9

Rule: bytes 3–6 are a RIP-relative offset → always wildcard them.
Keep: opcodes and unique surrounding bytes that are structurally stable.
```

## Struct discovery workflow

```angelscript
// Step 1: scan for a baseline value (e.g. HP = 100)
// Step 2: take damage → rescan for new value → intersect results
// Step 3: dump 256 bytes around candidate
void dump_struct(process@ proc, uint64 base_addr, string label) {
    for (int i = -64; i < 192; i += 4) {
        float fval = proc.read<float>(base_addr + i);
        int   ival = proc.read<int>(base_addr + i);
        console_log(fmt("{}: +0x{:X}  float={:.2f}  int={}", label, i, fval, ival));
    }
}
// Step 4: cross-reference with known structs from leaked SDKs/schema dumps
```

## Memory region enumeration (virtual_query)

```angelscript
// Enumerate all memory regions of the target process
array<region_info>@ regions = proc.virtual_query();
for (uint i = 0; i < regions.length(); i++) {
    region_info@ r = regions[i];
    if (r.type != MEM_PRIVATE) continue;
    console_log(fmt("0x{:X} size=0x{:X} state={} protect=0x{:X}",
                    r.base, r.size, r.state, r.protect));
}

// Single region query at a specific address:
region_info@ r      = proc.virtual_query(target_addr);
bool is_executable  = (r.protect & PAGE_EXECUTE_READ) != 0;
bool is_heap_region = (r.type == MEM_PRIVATE) && (r.protect == PAGE_READWRITE);
```

## Process dump (offline analysis)

```angelscript
// Dump the main process image
proc.dump("cs2.exe", "dmp/cs2.bin");

// Dump a specific named module — useful for client.dll / engine.dll separately
proc.dump("client.dll", "dmp/client.bin");

// Dump by address range (e.g. a mapped region you found via virtual_query)
proc.dump(region.base, region.size, "dmp/heap_region.bin");

// Enumerate and dump all modules for offline diffing:
array<module_info@>@ mods = proc.get_modules();
for (uint i = 0; i < mods.length(); i++) {
    module_info@ m = mods[i];
    proc.dump(m.name, fmt("dmp/{}.bin", m.name));
    console_log(fmt("Dumped {} base=0x{:X} size={}KB", m.name, m.base, m.size / 1024));
}
```

## WebSocket IPC (process.open_socket and ws namespace)

Echo's WebSocket support has two distinct roles:

**`process.open_socket`** — starts Echo's built-in memory API server. External tools (Python, Rust) connect and send JSON commands.

**`ws.connect`** — connects Echo as a WebSocket *client* to your own server (config push, command channel).

```angelscript
// ── Server mode: expose Echo memory API to external tools ────────────────
uint16 port = process.open_socket(9000); // returns actual bound port
alert.show(fmt("Echo WS server on port {}", port));

// External JSON commands Echo understands:
// { "type": "read",       "address": "0x7FF...", "size": 4, "format": "float" }
// { "type": "batch_read", "requests": [{ "address": "...", "size": 8 }, ...] }
// { "type": "scan",       "pattern": "48 8B 05 ??", "module": "client.dll" }
// { "type": "modules" }
// { "type": "disassemble","address": "0x...", "count": 32 }

// ── Client mode: subscribe to an external command/config server ──────────
ws@ sock = ws.connect("ws://localhost:9001");

sock.on_connect(@function() {
    sock.send("{\"type\": \"hello\"}");
});

sock.on_message(@function(string msg) {
    json@ obj = json.parse(msg);
    string cmd = obj.get_string("cmd");
    if (cmd == "set_fov") aim_fov = obj.get_float("value");
});

sock.on_disconnect(@function() {
    alert.show_tag("Config server disconnected", "warn");
});

sock.on_error(@function(string err) {
    console_error(fmt("WS error: {}", err));
});
```

## Unicorn emulation for obfuscated reads

```angelscript
void emulate_decrypt(process@ proc, uint64 decrypt_fn, uint64 encrypted_value_addr) {
    emulator@ emu = emulator(proc); // backed by process memory
    emu.mem_map(decrypt_fn & ~uint64(0xFFF), 0x2000, 7);

    uint64 encrypted = proc.read<uint64>(encrypted_value_addr);
    emu.reg_write(UC_X86_REG_RCX, encrypted);
    emu.reg_write(UC_X86_REG_RSP, decrypt_fn & ~uint64(0xFFF));

    emu.hook_code(@function(uint64 addr, uint size) {
        instruction@ ins = disasm.decode(proc, addr);
        if (ins.mnemonic == "RET") {
            uint64 rax = emu.reg_read(UC_X86_REG_RAX);
            // interpret rax as decrypted value
        }
    });

    emu.start(decrypt_fn, decrypt_fn + 0x200, 1000, 5000); // 1s / 5k insns max
}
```

## Zydis: finding xrefs and call sites

```angelscript
array<uint64> find_callers(process@ proc, string module_name, uint64 target_fn) {
    array<uint64> results;
    module_info@ mod = proc.get_module(module_name);
    uint64 addr = mod.base;
    uint64 end  = mod.base + mod.size;

    while (addr < end) {
        instruction@ ins = disasm.decode(proc, addr);
        if (ins is null) { addr++; continue; }
        if (ins.mnemonic == "CALL") {
            uint64 resolved = proc.resolve_rip(addr, 1, ins.length);
            if (resolved == target_fn) results.insertLast(addr);
        }
        addr += ins.length;
    }
    return results;
}

array<uint64> find_xrefs(process@ proc, string module_name, uint64 target_addr) {
    array<uint64> results;
    module_info@ mod = proc.get_module(module_name);
    uint64 addr = mod.base;
    while (addr < mod.base + mod.size) {
        instruction@ ins = disasm.decode(proc, addr);
        if (ins is null) { addr++; continue; }
        if (ins.mnemonic == "LEA" || ins.mnemonic == "MOV") {
            uint64 resolved = proc.resolve_rip(addr, 3, ins.length);
            if (resolved == target_addr) results.insertLast(addr);
        }
        addr += ins.length;
    }
    return results;
}
```

## String xref → offset discovery

```angelscript
void find_string_xref(process@ proc, string target_str) {
    string pat = "";
    for (uint i = 0; i < target_str.length(); i++)
        pat += fmt("{:02X} ", uint8(target_str[i]));
    pat += "00";
    uint64 str_addr = proc.scan(pat, "client.dll");
    if (str_addr == 0) { console_error("String not found"); return; }

    array<uint64> xrefs = find_xrefs(proc, "client.dll", str_addr);
    for (uint i = 0; i < xrefs.length(); i++) {
        console_log(fmt("XREF at 0x{:X}", xrefs[i]));
        array<instruction@>@ ctx = disasm.decode_linear(proc, xrefs[i] - 0x40, 32);
        for (uint j = 0; j < ctx.length(); j++)
            console_log(fmt("  {:X}: {} {}", ctx[j].address, ctx[j].mnemonic, ctx[j].operands_str));
    }
}
```

## Heap scan for RTTI objects

```angelscript
void find_class_instances(process@ proc, string class_mangled_name) {
    string rtti_pat = "?AV" + class_mangled_name + "@@";
    uint64 str_addr = proc.scan_string(rtti_pat, "client.dll");
    if (str_addr == 0) return;
    uint64 type_desc = str_addr - 0x10; // MSVC TypeDescriptor layout
    console_log(fmt("TypeDescriptor at 0x{:X}", type_desc));
    // Scan data segments for pointers to type_desc to find all live instances
}
```

## Dev tips

- Always validate scanned addresses: check they land within the module's address range.
- For encrypted offsets (CS2 XOR-obfuscated offsets), emulate the decrypt stub with Unicorn — faster and more reliable than RE-ing the key.
- Prefer `memory_buffer` batch reads over individual `proc.read` calls when touching 4+ fields of the same entity; it halves IPC overhead on large entity lists.
- `process.open_socket` and `ws.connect` serve different purposes — `open_socket` exposes Echo as a memory server; `ws.connect` lets Echo subscribe to your own config/command service.
- Use mcp-gamehacking `offset-finder` subagent when you have an offset from a leaked dump but aren't sure if it's current.
- `binary-differ` in mcp-gamehacking can diff two builds and give you offset deltas automatically.
- Echo's Zydis `decode_function` terminates at `RET`/`JMP`; for recursive functions follow call targets manually.
- Dump module before patching rounds; compare with `disasm.decode_linear` to confirm changes.
