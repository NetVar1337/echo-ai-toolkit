---
name: echo-memory
description: Memory/RE specialist for Echo. Knows multi-level pointer chains, struct recovery, advanced pattern scanning, signature generation, Unicorn emulation for obfuscated code, Zydis xref finding, WebSocket IPC, memory_buffer vector reads, and process dumps. Use when solving offset hunting, struct reversing, or emulation problems.
---

# Echo Memory & RE Agent

You solve memory reading, reverse engineering, and code analysis problems using Echo's process, Zydis, and Unicorn APIs.

> **Every offset, signature and address in this document is an illustrative placeholder.** Re-verify against the build
> you actually run and re-verify after every patch — see `skills/offset-update-workflow`.

## Multi-level pointer resolution

```angelscript
// Follow a pointer chain: base → [+off1] → [+off2] → ... → final read
uint64 resolve_chain(uint64 base, const array<uint64> &in offsets) {
    uint64 addr = base;
    for (uint i = 0; i < offsets.length() - 1; i++) {
        addr = process::read_uint64(addr + offsets[i]);
        if (addr == 0) return 0;
    }
    return addr + offsets[offsets.length() - 1];
}

// Usage: health = process::read_int32(resolve_chain(module_base, {0x10, 0x30, 0x18}))
```

## Struct field accessor pattern

```angelscript
// Offsets below are PLACEHOLDERS — re-verify per game build.
namespace PlayerOffsets {
    const uint64 hp         = 0x344;
    const uint64 team       = 0x3CB;
    const uint64 life_state = 0x338;
    const uint64 origin     = 0x1294;
    const uint64 velocity   = 0x1254;
    const uint64 name       = 0x640;
    const uint64 skeleton   = 0x168;
}

int  get_hp(uint64 ent)    { return process::read_int32(ent + PlayerOffsets::hp); }
int  get_team(uint64 ent)  { return process::read_int32(ent + PlayerOffsets::team); }
bool is_alive(uint64 ent)  { return process::read_uint8(ent + PlayerOffsets::life_state) == 0; }
vec3 get_origin(uint64 ent) {
    vec3 v;
    v.read_float(ent + PlayerOffsets::origin);
    return v;
}
```

## memory_buffer vector reads

`memory_buffer` lets you batch-read a region once and parse typed values from it — fewer round trips than
one read per field.

```angelscript
// Read a buffer from process memory (one round trip for the whole region)
memory_buffer@ buf = process::read_buffer(entity_addr, 0x200); // 512 bytes

// Vector typed reads from a buffer offset
vec2 v2 = buf.read_vec2_float(0x10);    // 2 floats
vec3 v3 = buf.read_vec3_float(0x1294);  // 3 floats — position
vec4 v4 = buf.read_vec4_float(0x30);    // 4 floats — quaternion / RGBA

// Scalar reads from the same buffer
int32 hp = buf.read_int32(0x344);
float f  = buf.read_float(0x150);

// Pattern: read the whole entity struct once per tick, then index into it
void read_entity_batch(uint64 ent, EntityData@ dest) {
    memory_buffer@ buf = process::read_buffer(ent, 0x500);
    if (buf is null) return;
    dest.hp     = buf.read_int32(PlayerOffsets::hp);
    dest.team   = buf.read_int32(PlayerOffsets::team);
    dest.alive  = buf.read_uint8(PlayerOffsets::life_state) == 0;
    dest.origin = buf.read_vec3_float(PlayerOffsets::origin);
    dest.vel    = buf.read_vec3_float(PlayerOffsets::velocity);
}

bool memory_buffer_vector_reads() {
    if (buf is null) return false;
    return true;
}
```

## Pattern scan workflow

```angelscript
uint64 g_entity_system = 0;
uint64 g_view_matrix   = 0;
uint64 g_local_player  = 0;
bool   g_scanned       = false;
uint64 g_last_base     = 0;

void scan_once() {
    uint64 base = process::get_module_base("client.dll");
    if (base == 0) return;

    // Signatures below are PLACEHOLDERS — re-verify per patch.
    uint64 sig = process::find_signature(base, "48 8B 0D ? ? ? ? 48 89 5C 24");
    if (sig != 0) g_entity_system = process::get_relative_address(sig, 3, 7);

    sig = process::find_signature(base, "48 8D 05 ? ? ? ? 48 89 05 ? ? ? ?");
    if (sig != 0) g_view_matrix = process::get_relative_address(sig, 3, 7);

    sig = process::find_signature(base, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 8B 01");
    if (sig != 0) g_local_player = process::get_relative_address(sig, 3, 7);

    g_scanned   = true;
    g_last_base = base;
    alert::show("Scan complete");
}

void check_rebase() {
    uint64 cur_base = process::get_module_base("client.dll");
    if (cur_base != g_last_base) {
        g_scanned = false;
        scan_once();
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
void dump_struct(uint64 base_addr, string label) {
    for (int i = -64; i < 192; i += 4) {
        int64 addr = int64(base_addr) + int64(i);
        float fval = process::read_float(uint64(addr));
        int32 ival = process::read_int32(uint64(addr));
        console::log(util::format_string("{}: offset {}  float={}  int={}",
                                         label, i, fval, ival));
    }
}
// Step 4: cross-reference with known structs from leaked SDKs/schema dumps
```

## Memory region enumeration (virtual_query)

```angelscript
// Single region query at a specific address — returns the contiguous region with uniform flags
memory_region r = process::virtual_query(target_addr);
bool is_executable  = r.executable;
bool is_writable    = r.writable;
bool is_present     = r.present;

// Enumerate forward: when present is false, base/size still describe the unmapped hole,
// so advance by base + size to walk every region including gaps.

void memory_region_enumeration_virtual() {
    console::log(util::format_string("region base={} size={} present={} exec={} write={}",
                                     util::to_hex(r.base), r.size, r.present, r.executable, r.writable));
}
```

## Process dump (offline analysis)

```angelscript
// Dump the main process image into the "dmp" folder inside the scripts folder

// Dump a specific named module — useful for client.dll / engine.dll separately

// Enumerate and dump all modules for offline diffing:
array<module_entry>@ mods = process::get_module_list();

void process_dump_offline_analysis() {
    process::dump("main.bin");
    process::dump("client.dll", "client.bin");
    if (mods !is null) {
        for (uint i = 0; i < mods.length(); i++) {
            process::dump(mods[i].name, mods[i].name + ".bin");
            console::log(util::format_string("Dumped {} base={} size={}KB",
                                             mods[i].name, util::to_hex(mods[i].base),
                                             mods[i].size / 1024));
        }
    }
}
```

## WebSocket IPC (process.open_socket and the ws namespace)

Echo's WebSocket support has two distinct roles:

**`process::open_socket`** — opens a WebSocket *client* connection to a URL you give it and starts a background
receive loop. It requires an attached process, and only one connection may be open at a time. Echo's own memory
API speaks JSON over that socket.

**`ws::connect`** — the same idea from the other side: Echo as a WebSocket client to your own server
(config push, command channel).

```angelscript
// ── Memory API socket ───────────────────────────────────────────────────────
// Opens a WebSocket client to the given URL and starts a background receive loop.
// Requires an attached process; only one connection may be open at a time.
bool opened = process::open_socket("ws://127.0.0.1:9000");

// The socket speaks JSON over UTF-8 frames. Every request carries a "type" and an
// optional integer "id" that is echoed back in the response:
// { "type": "read",        "id": 2, "address": "0x7FF...", "size": 4 }
// { "type": "read_batch",  "id": 3, "reads": [{ "address": "...", "size": 8 }, ...] }
// { "type": "sig_scan",    "id": 5, "sig": "48 8B 05 ??", "module": "client.dll" }
// { "type": "sig_scan_ida","id": 6, "pattern": "48 8B 05 ? ? ? ?", "module": "client.dll" }
// { "type": "modules",     "id": 4 }
// { "type": "disassemble", "id": 12, "address": "0x...", "size": 32 }
// { "type": "resolve_relative", "id": 8, "address": "0x...", "offset": 3, "inst_size": 7 }

// ── Client mode: subscribe to an external command/config server ─────────────

void ws_open() {
    ws::send("{\"type\": \"hello\"}");
}

void ws_msg(string msg) {
    string err;
    json_obj@ obj = json::parse(msg, err);
    if (obj is null) return;
    string cmd = obj.get_string("cmd");
    if (cmd == "set_fov") ui::set(g_aim_fov, int(obj.get_float("value")));
}

void ws_dc() { alert::show_tag("Config server disconnected", "warn"); }
void ws_err(string err) { console::error("WS error: " + err); }

void websocket_ipc_process_open() {
    if (!opened) alert::show_tag("Memory socket failed to open", "error");
    ws::connect("ws://localhost:9001", @ws_open, @ws_msg, @ws_dc, @ws_err);
}
```

## Unicorn emulation for obfuscated reads

```angelscript
void emulate_decrypt(uint64 decrypt_fn, uint64 encrypted_value_addr) {
    // A handle backed by the attached process — pages are faulted in on demand
    uint64 h = uc::create_process();
    if (h == 0) { console::error("uc::create_process failed"); return; }

    uint64 encrypted = process::read_uint64(encrypted_value_addr);
    uc::reg_write64(h, x86_reg::rcx, encrypted);
    uc::setup_stack(h, 0x7FF000000000, 0x10000, 0x7FF000008000);

    uc::hook_code(h, @on_insn);

    int rc = uc::start(h, decrypt_fn, decrypt_fn + 0x200, 1000000, 5000); // 1s / 5k insns max
    if (rc != uc::error::ok) {
        console::error(util::format_string("Emulation failed: {}", uc::last_error(h)));
        uc::close(h);
        return;
    }
    uint64 rax = 0;
    uc::reg_read64(h, x86_reg::rax, rax);
    console::log("Decrypted: " + util::to_hex(rax));
    uc::close(h);
}

// Hook signature: bool code_hook_fn(uint64 h, uint64 address, uint32 size)
bool on_insn(uint64 h, uint64 address, uint32 size) {
    return true; // return false to stop emulation
}
```

## Zydis: finding xrefs and call sites

```angelscript
array<uint64> find_callers(uint64 module_base, uint64 target_fn) {
    array<uint64> results;
    uint64 addr = module_base;
    uint64 end  = module_base + process::get_module_size(module_base);

    while (addr < end) {
        array<uint8>@ bytes = process::read_bytes(addr, 16);
        if (bytes is null) { addr += 1; continue; }
        array<disasm_insn@> insns;
        if (!zydis::disasm(bytes, addr, insns) || insns.length() == 0) { addr += 1; continue; }

        disasm_insn@ ins = insns[0];
        if (ins.text.substr(0, 4) == "call") {
            uint64 resolved = process::get_relative_address(addr, 1, ins.length);
            if (resolved == target_fn) results.insertLast(addr);
        }
        addr += ins.length;
    }
    return results;
}

array<uint64> find_xrefs(uint64 module_base, uint64 target_addr) {
    array<uint64> results;
    uint64 addr = module_base;
    uint64 end  = module_base + process::get_module_size(module_base);

    while (addr < end) {
        array<uint8>@ bytes = process::read_bytes(addr, 16);
        if (bytes is null) { addr += 1; continue; }
        array<disasm_insn@> insns;
        if (!zydis::disasm(bytes, addr, insns) || insns.length() == 0) { addr += 1; continue; }

        disasm_insn@ ins = insns[0];
        // Pattern: MOV reg,[reg+0xOFFSET] → the offset IS the struct field offset
        if (ins.text.find("[r") >= 0) {
            uint64 resolved = process::get_relative_address(addr, 3, ins.length);
            if (resolved == target_addr) results.insertLast(addr);
        }
        addr += ins.length;
    }
    return results;
}
```

## String xref → offset discovery

```angelscript
// USER CODE — turn a string into a space-separated hex pattern ("41 42 00")
string bytes_to_pattern(string s) {
    string hex = util::hex_encode(s).to_upper();
    string hex_out = "";
    for (uint i = 0; i + 1 < hex.length(); i += 2) {
        if (hex_out.length() > 0) hex_out += " ";
        hex_out += hex.substr(i, 2);
    }
    return hex_out + " 00";
}

void find_string_xref(uint64 module_base, string target_str) {
    // Build a space-separated hex pattern for the scanner
    string pat = bytes_to_pattern(target_str);

    uint64 str_addr = process::find_signature(module_base, pat);
    if (str_addr == 0) { console::error("String not found"); return; }

    array<uint64> xrefs = find_xrefs(module_base, str_addr);
    for (uint i = 0; i < xrefs.length(); i++) {
        console::log("XREF at " + util::to_hex(xrefs[i]));
        array<uint8>@ ctx_bytes = process::read_bytes(xrefs[i] - 0x40, 64);
        if (ctx_bytes is null) continue;
        array<disasm_insn@> ctx;
        if (!zydis::disasm(ctx_bytes, xrefs[i] - 0x40, ctx)) continue;
        for (uint j = 0; j < ctx.length(); j++)
            console::log(util::format_string("  {}: {}", util::to_hex(ctx[j].runtime_address), ctx[j].text));
    }
}
```

## Heap scan for RTTI objects

```angelscript
void find_class_instances(uint64 module_base, string class_mangled_name) {
    // Build the MSVC type-descriptor pattern and look for it in the module
    string rtti_pat = "?AV" + class_mangled_name + "@@";
    string pat = bytes_to_pattern(rtti_pat);

    uint64 str_addr = process::find_signature(module_base, pat);
    if (str_addr == 0) return;
    uint64 type_desc = str_addr - 0x10; // MSVC TypeDescriptor layout
    console::log("TypeDescriptor at " + util::to_hex(type_desc));
    // Scan data segments for pointers to type_desc to find all live instances
}
```

## Dev tips

- Always validate scanned addresses: check they land within the module's address range.
- For encrypted offsets, emulate the decrypt stub with Unicorn — faster and more reliable than re-implementing the key.
- Prefer `memory_buffer` batch reads over individual reads when touching 4+ fields of the same entity.
- `process::open_socket` and `ws::connect` are different: `open_socket` opens a connection to a URL you supply
  (Echo's memory API speaks JSON over it); `ws::connect` subscribes to your own config/command service.
- `zydis::disasm_func` stops at the first `ret`/`iret` and fails past 4096 instructions — follow call targets manually.
- Dump the module before a patching round; compare dumps to confirm what changed.
