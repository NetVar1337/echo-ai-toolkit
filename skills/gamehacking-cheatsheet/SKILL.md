---
name: gamehacking-cheatsheet
description: Topic-to-API map for game hacking work: for each technique, the Echo API calls to use and the mcp-gamehacking query that surfaces deeper reference material. Use as a quick lookup when you know the technique but not the API shape.
---

# Game Hacking Cheatsheet — Echo Integration Map

**Sources:**
- ridpath/gamehacking-cheatsheet — "Game Hacking & Reverse Engineering Mega Cheatsheet"
- gmh5225/awesome-game-security — 4000+ curated resources

Topics: memory editing, anti-cheat evasion, exploitation, engine RE, firmware, VR/AR, blockchain games.

For deep skills on any technique, query mcp-gamehacking:
```
research_technique("<exact technique name>")
search_skills("<keyword>")
get_agent_briefing("<specialist>")
```

> **All offsets, patterns and vtable addresses in the snippets below are ILLUSTRATIVE
> PLACEHOLDERS.** They show the shape of each technique, not a current build — verify every one
> against your target and re-check after each game patch.

---

## Cheatsheet topic → Echo API equivalents

| Cheatsheet technique | Echo equivalent | mcp-gamehacking query |
|---|---|---|
| **Pointer path tracing** (multilevel pointer maps) | `follow_chain(base, offsets)` below | `research_technique("pointer chain traversal")` |
| **AOBScan for ASLR busting** | `process::find_signature(base, "48 8B ? ...")` | `research_technique("IDA pattern scanning ASLR")` |
| **CE Auto Assembler code injection** | N/A — Echo is external | `get_agent_briefing("injection-specialist")` |
| **Stealth DLL injection** | N/A — Echo uses Discord overlay | `research_technique("manual map DLL injection")` |
| **PEB unlinking / sig evasion** | N/A — Echo's surface is an OpenProcess read handle | `research_technique("DKOM process hiding")` |
| **Dynamic function discovery (Frida)** | `zydis::disasm_func(bytes, rip, insns)` + Unicorn trace | `research_technique("dynamic function discovery")` |
| **RTTI salvage** | `process::find_signature` for the vtable pattern, then decode | `research_technique("RTTI vtable recovery")` |
| **Heap spray / allocation tracking** | `process::virtual_query` + byte-pattern scan | `research_technique("heap object discovery")` |
| **Memory map diffing** | Compare `process::virtual_query` snapshots | `research_technique("memory region diffing")` |
| **vtable hook detection** | Scan vtable entries, compare to module `.text` range | `research_technique("vtable integrity check")` |
| **IAT hook detection** | Read IAT entries, verify they point into module `.text` | `research_technique("IAT hook detection")` |
| **Speedhack (time manipulation)** | N/A — Echo *can* write target memory, but writing to a protected game is against policy | `research_technique("game speed manipulation")` |
| **Wallhack via depth/stencil** | N/A — Echo is an overlay renderer only | `research_technique("wallhack rendering bypass")` |
| **Signal/interrupt-driven scan** | Use tick timer + `process::find_signature` | `research_technique("scan timing optimization")` |
| **Thread injection** | N/A | `research_technique("thread injection CreateRemoteThread")` |
| **UE GNames/GObjects pattern** | `process::find_signature` → chunked array traversal | `research_technique("UE5 GObjects traversal")` |
| **Unity IL2CPP** | REA `global-metadata.dat` + Il2CppDumper | `research_technique("Unity IL2CPP offset recovery")` |
| **WebAssembly game recon** | REA `inspect_wasm_artifact` | `research_technique("WebAssembly game analysis")` |
| **Aimbot (memory-based)** | `process::read_*` + `input::mouse_move` | `research_technique("memory-based aimbot")` |
| **Aimbot (pixel-based)** | Not in Echo API — external screen cap needed | `research_technique("pixel-based aimbot YOLO")` |
| **Aimbot (AI neural)** | `http::post("http://localhost:PORT", frame_data, "application/json", @cb)` | `research_technique("neural aimbot inference")` |
| **Triggerbot** | `process::read_*` crosshair entity + `input::mouse_click()` | `get_agent_briefing("triggerbot-developer")` |
| **Anti-debug detection bypass** | N/A — Echo never attaches a debugger | `research_technique("anti-debug bypass")` |
| **AC bypass techniques** | Echo's external arch reduces surface | `get_agent_briefing("anti-cheat-analyst")` |
| **Replay format reversing** | REA binary analysis on `.dem`/`.replay` | `research_technique("game replay format parsing")` |
| **DRM loader staging (VMProtect)** | Unicorn emulation to trace decryption stages | `research_technique("VMProtect devirtualization")` |
| **OLLVM deobfuscation** | Unicorn trace + reverse-skill `ollvm-deobfuscation.md` | `research_technique("OLLVM control flow flattening")` |
| **Network packet modification** | N/A — not in Echo API; use Frida/WinDivert | `research_technique("game protocol reverse engineering")` |
| **Firmware / UEFI analysis** | REA firmware analysis + reverse-skill | `get_agent_briefing("firmware-analyst")` |
| **Android game hacking** | REA APK inspection + Frida | `get_agent_briefing("android-researcher")` |
| **Blockchain / NFT exploits** | Out of Echo scope | `get_agent_briefing("web3-researcher")` |

---

## mcp-gamehacking — per-domain query guide

```
# Memory / external cheats
research_technique("external memory reading")
get_agent_briefing("cheat-developer")
read_subagent("offset-finder")
read_subagent("pattern-scanner")

# Anti-cheat
get_agent_briefing("anti-cheat-analyst")
research_technique("eac kernel driver analysis")
read_subagent("ac-driver-analyzer")
read_subagent("detection-assessor")

# Reverse engineering
get_agent_briefing("reverse-engineer")
get_agent_briefing("ida-specialist")
get_agent_briefing("ghidra-specialist")
read_subagent("binary-differ")
read_subagent("struct-recovery")

# Game-specific specialists
get_agent_briefing("cs2-specialist")
get_agent_briefing("valorant-specialist")
get_agent_briefing("fortnite-specialist")
get_agent_briefing("apex-specialist")
get_agent_briefing("unreal-engine-specialist")
get_agent_briefing("unity-specialist")

# SDK generation
research_technique("SDK generation UE4")
research_technique("Dumper-7 FName resolution")
read_subagent("vtable-mapper")
read_subagent("import-resolver")

# Obfuscation / packers
get_agent_briefing("obfuscation-analyst")
search_skills("vmprotect handler analysis")
research_technique("OLLVM control flow flattening")
```

---

## CE pointer-chain tracing → Echo

```angelscript
// Cheat Engine: base + [off1] → [off2] → [off3] → value
// Echo equivalent (user code):
uint64 follow_chain(uint64 base, array<uint64> &in offsets) {
    if (offsets.length() == 0) return 0;

    uint64 ptr = base;
    for (uint i = 0; i < offsets.length() - 1; i++) {
        ptr = process::read_uint64(ptr + offsets[i]);
        if (ptr == 0) return 0;
    }
    return ptr + offsets[offsets.length() - 1];
}

// Usage: health at [["game.exe"+0x1234] + 0x30] + 0x18
uint64 base = process::get_module_base("game.exe");
array<uint64> chain = {0x1234, 0x30, 0x18};
uint64 hp_addr = follow_chain(base, chain);
if (hp_addr == 0) return false;
float hp = process::read_float(hp_addr);
```

---

## Advanced pattern scanning techniques

```angelscript
// Multi-tier sig for patch resilience (from awesome-game-security pattern)
// PLACEHOLDER patterns — re-verify per patch
uint64 find_entity_system() {
    uint64 client = process::get_module_base("client.dll");
    if (client == 0) return 0;

    // Tier 1: full exact pattern
    uint64 addr = process::find_signature(client, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 48 8B 01");
    if (addr != 0) return process::read_uint64(process::get_relative_address(addr, 3, 7));

    // Tier 2: relax first bytes, anchor on stable suffix
    addr = process::find_signature(client, "? ? ? ? ? ? ? 48 85 C9 74 ? 48 8B 01");
    if (addr != 0) return process::read_uint64(process::get_relative_address(addr, 0, 7));

    // Tier 3: byte-mask form
    // 48 8B 0D ?? ?? ?? ?? 48 85 C9 74 ?? 48 8B 01  → 15 bytes, 15 mask chars
    addr = process::find_signature(client, "488B0D000000004885C97400488B01", "xxx????xxxx?xxx");
    if (addr != 0) return process::read_uint64(process::get_relative_address(addr, 3, 7));

    return 0; // shortcut: no json fallback here; add if all tiers break post-patch
}
```

For xrefs to a found address, disassemble around it and look for the reference:

```angelscript
array<uint8>@ bytes = process::read_bytes(str_addr - 0x40, 0x80);
if (bytes is null) return 0;

array<disasm_insn@> insns;
if (!zydis::disasm(bytes, str_addr - 0x40, insns)) return 0;

for (uint i = 0; i < insns.length(); i++) {
    disasm_operand op = insns[i].get_op(0);
    if (op.type == op_type::mem && op.mem_has_disp) {
        // mem_disp is a signed DISPLACEMENT, not an absolute address.
        // The absolute target is the displacement added to the end of the instruction.
        uint64 target = insns[i].runtime_address + insns[i].length + uint64(op.mem_disp);
        if (target == str_addr) return insns[i].runtime_address;
    }
}
return 0;
```

---

## vtable recovery (RTTI salvage)

```angelscript
// Find all instances of a class by scanning heap for its vtable pointer
// 1. Locate vtable via IDA pattern (stable — vtable is in .rdata)
// PLACEHOLDER pattern and offsets
uint64 game = process::get_module_base("game.exe");
if (game == 0) return;

uint64 vtable = process::find_signature(game, "? ? ? ? ? ? ? ? ? ? ? ? ? ? ? ? ? 48 8D 05");
if (vtable == 0) return;
// get_relative_address gives the ADDRESS OF the pointer — read it for the vtable value
vtable = process::read_uint64(process::get_relative_address(vtable, 18, 22));   // adjust for your binary
if (vtable == 0) return;

// 2. Walk the mapped regions looking for objects that start with this vtable
uint64 addr = 0;
while (addr < 0x7FFFFFFFFFFF) {
    memory_region r = process::virtual_query(addr);
    if (r.size == 0) break;

    if (r.present && r.writable) {
        // scan this region for the 8-byte vtable value (user code):
        // compare process::read_uint64(region_base + i) against vtable
        // on a hit, the object address is region_base + i
    }
    addr = r.base + r.size;
}
```

---

## Memory map diffing

```angelscript
// Snapshot before/after a game event to find newly allocated objects
hash_map@ known = create_hash_map();

uint64 addr = 0;
while (addr < 0x7FFFFFFFFFFF) {
    memory_region r = process::virtual_query(addr);
    if (r.size == 0) break;
    known.set_uint64(r.base, r.size);
    addr = r.base + r.size;
}

// ... game event fires (entity spawns) ...

uint64 addr2 = 0;
while (addr2 < 0x7FFFFFFFFFFF) {
    memory_region r = process::virtual_query(addr2);
    if (r.size == 0) break;

    uint64 prev = 0;
    if (!known.get_uint64(r.base, prev)) {
        alert::show(util::format_string("New region: {} size={}", util::to_hex(r.base), r.size));
    }
    addr2 = r.base + r.size;
}
```

---

## Aimbot typologies in Echo

**Memory-based** (fully supported):
- Read entity positions and angles via `process::read_*`
- Calculate aim delta, apply via `input::mouse_move(x, y)` (absolute coordinates)
- See `templates/aimbot.as` and echo-aimbot agent

**Pixel-based** (not in Echo API):
- Echo has no screen capture API
- Workaround: external Python script with OpenCV → sends mouse commands to Echo via WebSocket

**AI neural** (partially supported):
- External inference server (e.g. YOLOv8 on local GPU)
- Echo sends `http::post("http://localhost:5000/infer", screen_data, "application/json", @on_result)` after capture
- Then applies the result via `input::mouse_move`

---

## Anti-cheat: Echo's position

Echo uses the Discord overlay (external process, no injection). Detection surface:
1. `OpenProcess` handle to game process — visible to kernel AC drivers
2. `ReadProcessMemory` syscalls — monitored by some ACs
3. Mouse injection patterns — timing analysis by behavioral ACs

Most ACs whitelist Discord overlay rendering. AC bypass techniques from the cheatsheet (PEB unlinking, manual mapping, syscall stubs) are **not needed** for Echo's overlay — but may be needed if trying to hide the OpenProcess handle at kernel level.

---

## Dynamic memory analysis in Echo

```angelscript
// Memory map diffing: snapshot regions, compare after a game event
// (see the memory-map diffing snippet above for the full loop)

// Heap type scan: look for a known class vtable pointer at object+0x00
uint64 vtable_target = 0;   // known vtable for PlayerPawn

uint64 addr = 0;
while (addr < 0x7FFFFFFFFFFF) {
    memory_region r = process::virtual_query(addr);
    if (r.size == 0) break;

    if (r.present && r.writable) {
        // scan each heap region for the vtable value and report hits
        // user code: process::read_uint64(r.base + i) == vtable_target
    }
    addr = r.base + r.size;
}
```

---

## AI neural aimbot — Echo + local inference

```angelscript
// 1. Send frame data to local inference server (YOLOv8 / custom CNN)
// 2. Receive bounding boxes → convert to mouse delta
void on_result(http_response@ res) {
    if (res.error != "") {
        console::error("inference failed: " + res.error);
        return;
    }

    string err = "";
    json_obj@ j = json::parse(res.body, err);
    if (j is null) {
        console::error("bad json: " + err);
        return;
    }

    float cx = j.get_float("cx");   // center x of best target bbox (screen pixels)
    float cy = j.get_float("cy");   // center y (screen pixels)

    // mouse_move takes ABSOLUTE screen coordinates, not a delta
    input::mouse_move(int(cx), int(cy));
}

// http::post is only callable from main()
bool main() {
    string payload = "{\"frame\": \"...\"}";   // screen region as base64
    http::post("http://localhost:5000/infer", payload, "application/json", @on_result);
    return true;
}
```

mcp-gamehacking: `research_technique("neural aimbot inference")`, `get_agent_briefing("ai-aimbot-developer")`

---

## Hook type detection (AC awareness)

```angelscript
// Check if a known function's first bytes are still the original prolog
// Detects inline hooks (jmp patch) placed by cheats or tools
uint64 client = process::get_module_base("client.dll");
uint64 fn = process::get_module_export(client, "CEntitySystem::GetLocalPlayer");
if (fn == 0) {
    console::warn("export not found");
} else {
    uint8 first = process::read_uint8(fn);
    if (first == 0xE9 || first == 0xEB) {
        // jmp/short-jmp at prolog = inline hook present
        alert::show("Inline hook detected at CEntitySystem::GetLocalPlayer");
    }
}

// vtable hook check: entry should point into the module .text range
uint32 size = process::get_module_size(client);
uint64 vt_entry = process::read_uint64(entity_vtable + 0x18);
if (vt_entry < client || vt_entry > client + size) {
    alert::show(util::format_string("vtable[3] outside client.dll: {}", util::to_hex(vt_entry)));
}
```

mcp-gamehacking: `research_technique("vtable integrity check")`, `read_subagent("ac-driver-analyzer")`

---

## Tools from the cheatsheet and their Echo/RE context

| Tool | Role | Echo context | mcp-gamehacking |
|---|---|---|---|
| Cheat Engine | CE pointer scan, auto-assembler | Initial offset discovery → export to Echo | `search_skills("cheat engine")` |
| x64dbg | Dynamic debugger | Find function addresses → Echo pattern scan | `get_agent_briefing("ida-specialist")` |
| Ghidra / IDA | Static analysis | Struct layouts → hard-code in Echo or use REA | `get_agent_briefing("ghidra-specialist")` |
| Frida | Dynamic instrumentation | Echo replaces Frida on Windows; Frida still useful for Android | `get_agent_briefing("android-researcher")` |
| ReClass.NET | Struct layout visualizer | Explore memory layout → offsets in Echo | `research_technique("struct recovery ReClass")` |
| WinDivert / Wireshark | Packet capture | Network RE → not Echo-relevant | `research_technique("packet capture game traffic")` |
| Il2CppDumper | Unity IL2CPP metadata | Dump offsets → use in Echo `process::read_*` | `research_technique("Unity IL2CPP offset recovery")` |
| UEDumper | UE SDK gen | Alternative to Dumper-7; same offset format | `research_technique("SDK generation UE4")` |
| sig-maker | IDA sig generator | One click → IDA wildcard pattern for `process::find_signature` | `read_subagent("pattern-scanner")` |
| Binary Ninja | Modern decompiler | HLIL/MLIL for complex obfuscated code | `get_agent_briefing("binary-ninja-specialist")` |
| kdmapper | Kernel driver mapper | AC research — see echo-anticheat | `research_technique("vulnerable driver exploitation")` |
| KDU | Kernel Driver Utility | 100+ vulnerable driver table for kernel access | `research_technique("KDU driver list")` |

---

## Awesome game security cross-references

For each cheatsheet technique, the corresponding awesome-game-security resource category:

| Technique | awesome-game-security category | Echo skill |
|---|---|---|
| Memory hacking | gmh5225/awesome-game-security | `skills/awesome-game-security/SKILL.md` |
| Anti-cheat analysis | gmh5225/awesome-game-security | `skills/awesome-game-security/SKILL.md` |
| RE tools | gmh5225/awesome-game-security | `skills/reverse-engineering-tools/SKILL.md` |
| VMP / OLLVM | gmh5225/awesome-game-security | `skills/devirt-workflow/SKILL.md` |
| UE4/UE5 SDK | gmh5225/awesome-game-security | `skills/dumper7-sdk/SKILL.md` |
| Unity IL2CPP | gmh5225/awesome-game-security | `skills/awesome-game-security/SKILL.md` |
| Pattern scanning | gmh5225/awesome-game-security | `skills/awesome-game-security/SKILL.md` |
| Kernel / driver | gmh5225/awesome-game-security | `skills/awesome-game-security/SKILL.md` |
