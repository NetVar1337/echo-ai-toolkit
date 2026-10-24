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

---

## Cheatsheet topic → Echo API equivalents

| Cheatsheet technique | Echo equivalent | mcp-gamehacking query |
|---|---|---|
| **Pointer path tracing** (multilevel pointer maps) | `follow_chain(base, offsets)` below | `research_technique("pointer chain traversal")` |
| **AOBScan for ASLR busting** | `proc.scan_ida("48 8B ? ...", "mod.exe")` | `research_technique("IDA pattern scanning ASLR")` |
| **CE Auto Assembler code injection** | N/A — Echo is external | `get_agent_briefing("injection-specialist")` |
| **Stealth DLL injection** | N/A — Echo uses Discord overlay | `research_technique("manual map DLL injection")` |
| **PEB unlinking / sig evasion** | N/A — Echo's surface is OpenProcess only | `research_technique("DKOM process hiding")` |
| **Dynamic function discovery (Frida)** | `disasm.decode_function()` + Unicorn trace | `research_technique("dynamic function discovery")` |
| **RTTI salvage** | `proc.scan` for vtable pattern, then decode | `research_technique("RTTI vtable recovery")` |
| **Heap spray / allocation tracking** | `proc.query_regions()` + type-sig scan | `research_technique("heap object discovery")` |
| **Memory map diffing** | Compare `proc.query_regions()` snapshots | `research_technique("memory region diffing")` |
| **vtable hook detection** | Scan vtable entries, compare to .text range | `research_technique("vtable integrity check")` |
| **IAT hook detection** | Read IAT entries, verify they point into module .text | `research_technique("IAT hook detection")` |
| **Speedhack (time manipulation)** | N/A — Echo doesn't write game memory | `research_technique("game speed manipulation")` |
| **Wallhack via depth/stencil** | N/A — Echo is an overlay renderer only | `research_technique("wallhack rendering bypass")` |
| **Signal/interrupt-driven scan** | Use tick timer + `proc.scan_ida` | `research_technique("scan timing optimization")` |
| **Thread injection** | N/A | `research_technique("thread injection CreateRemoteThread")` |
| **UE GNames/GObjects pattern** | `proc.scan_ida` → chunked array traversal | `research_technique("UE5 GObjects traversal")` |
| **Unity IL2CPP** | REA `global-metadata.dat` + Il2CppDumper | `research_technique("Unity IL2CPP offset recovery")` |
| **WebAssembly game recon** | REA `inspect_wasm_artifact` | `research_technique("WebAssembly game analysis")` |
| **Aimbot (memory-based)** | `proc.read` + `mouse.move` | `research_technique("memory-based aimbot")` |
| **Aimbot (pixel-based)** | Not in Echo API — external screen cap needed | `research_technique("pixel-based aimbot YOLO")` |
| **Aimbot (AI neural)** | `http.post("localhost:PORT", frame_data)` | `research_technique("neural aimbot inference")` |
| **Triggerbot** | `proc.read` crosshair entity + `mouse.click` | `get_agent_briefing("triggerbot-developer")` |
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
// Echo equivalent:
uint64 follow_chain(uint64 base, array<uint64>@ offsets) {
    uint64 ptr = base;
    for (uint i = 0; i < offsets.length() - 1; i++) {
        ptr = proc.read<uint64>(ptr + offsets[i]);
        if (ptr == 0) return 0;
    }
    return ptr + offsets[offsets.length() - 1];
}

// Usage: health at [["game.exe"+0x1234] + 0x30] + 0x18
uint64 base = proc.get_module("game.exe").base;
array<uint64> chain = {0x1234, 0x30, 0x18};
uint64 hp_addr = follow_chain(base, chain);
float hp = proc.read<float>(hp_addr);
```

---

## Advanced pattern scanning techniques

```angelscript
// Multi-tier sig for patch resilience (from awesome-game-security pattern)
uint64 find_entity_system() {
    // Tier 1: full exact pattern
    uint64 addr = proc.scan_ida("48 8B 0D ? ? ? ? 48 85 C9 74 ? 48 8B 01", "client.dll");
    if (addr != 0) return proc.resolve_rip(addr, 3, 7);

    // Tier 2: relax first bytes, anchor on stable suffix
    addr = proc.scan_ida("? ? ? ? ? ? ? 48 85 C9 74 ? 48 8B 01", "client.dll");
    if (addr != 0) return proc.resolve_rip(addr, 0, 7);

    // Tier 3: string xref to known game class name
    uint64 str = proc.scan("43 53 32 47 61 6D 65", "client.dll"); // "CS2Game"
    if (str != 0) {
        array<instruction@>@ xrefs = disasm.find_xrefs(proc, str, 512);
        if (xrefs.length() > 0) return xrefs[0].address;
    }

    return 0; // shortcut: no json fallback here; add if all tiers break post-patch
}
```

---

## vtable recovery (RTTI salvage)

```angelscript
// Find all instances of a class by scanning heap for its vtable pointer
// 1. Locate vtable via IDA pattern (stable — vtable is in .rdata)
uint64 vtable = proc.scan_ida("? ? ? ? ? ? ? ? ? ? ? ? ? ? ? ? 48 8D 05", "game.exe");
vtable = proc.resolve_rip(vtable, 18, 22); // adjust for your binary

// 2. Walk every heap region looking for objects that start with this vtable
array<region_info@>@ regions = proc.query_regions();
for (uint i = 0; i < regions.length(); i++) {
    if (!regions[i].is_heap) continue;
    uint64 hit = proc.scan(/* vtable 8 bytes LE */, regions[i].base, regions[i].size);
    while (hit != 0) {
        // confirmed instance — read fields
        float health = proc.read<float>(hit + 0x334);
        // find next hit
        hit = proc.scan(/* vtable bytes */, hit + 8, regions[i].base + regions[i].size - hit - 8);
    }
}
```

---

## Memory map diffing

```angelscript
// Snapshot before/after a game event to find newly allocated objects
array<region_info@>@ snap1 = proc.query_regions();

// ... game event fires (entity spawns) ...

array<region_info@>@ snap2 = proc.query_regions();

// find regions in snap2 not in snap1 — these were freshly allocated
hash_map<uint64, bool> known;
for (uint i = 0; i < snap1.length(); i++)
    known[snap1[i].base] = true;

for (uint i = 0; i < snap2.length(); i++) {
    if (!known.contains(snap2[i].base))
        alert(fmt("New region: 0x{:X} size={}", snap2[i].base, snap2[i].size));
}
```

---

## Aimbot typologies in Echo

**Memory-based** (fully supported):
- Read entity positions and angles via `proc.read`
- Calculate aim delta, apply via `mouse.move(dx, dy)`
- See `templates/aimbot.as` and echo-aimbot agent

**Pixel-based** (not in Echo API):
- Echo has no screen capture API
- Workaround: external Python script with OpenCV → sends mouse commands to Echo via WebSocket

**AI neural** (partially supported):
- External inference server (e.g. YOLOv8 on local GPU)
- Echo sends `http.post("http://localhost:5000/infer", screen_data, @on_result)` after capture
- Then applies result via `mouse.move`

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
// Memory map diffing: snapshot regions, compare after game event
array<region_info>@ r1 = proc.query_regions();
// ... trigger game event ...
array<region_info>@ r2 = proc.query_regions();
// Compare: new regions → freshly allocated objects

// Heap type scan: scan for RTTI vtable pointer matching a known class
// vtable pointer is at object+0x00, points into .rdata
uint64 vtable_target = ...; // known vtable for PlayerPawn
array<region_info>@ regions = proc.query_regions();
for (uint i = 0; i < regions.length(); i++) {
    // scan each heap region for the vtable value
    uint64 hit = proc.scan(/* vtable bytes */, regions[i].base, regions[i].size);
    if (hit != 0) alert(fmt("Found instance at 0x{:X}", hit));
}
```

---

## AI neural aimbot — Echo + local inference

```angelscript
// 1. Send frame data to local inference server (YOLOv8 / custom CNN)
// 2. Receive bounding boxes → convert to mouse delta
string payload = fmt('{"frame": "..."}'); // screen region as base64
http.post("http://localhost:5000/infer", payload, function(response@ r) {
    if (!r.ok) return;
    json@ j = json.parse(r.body);
    float cx = float(j["cx"]); // center x of best target bbox
    float cy = float(j["cy"]); // center y
    float screen_cx = renderer.width() / 2.0f;
    float screen_cy = renderer.height() / 2.0f;
    mouse.move(int(cx - screen_cx), int(cy - screen_cy));
});
```

mcp-gamehacking: `research_technique("neural aimbot inference")`, `get_agent_briefing("ai-aimbot-developer")`

---

## Hook type detection (AC awareness)

```angelscript
// Check if a known function's first bytes are still the original prolog
// Detects inline hooks (jmp patch) placed by cheats or tools
uint64 fn = proc.get_export("client.dll", "CEntitySystem::GetLocalPlayer");
uint8 first = proc.read<uint8>(fn);
if (first == 0xE9 || first == 0xEB) {
    // jmp/short-jmp at prolog = inline hook present
    alert("Inline hook detected at CEntitySystem::GetLocalPlayer");
}

// vtable hook check: entry should point into module .text range
module@ m = proc.get_module("client.dll");
uint64 vt_entry = proc.read<uint64>(entity_vtable + 0x18);
if (vt_entry < m.base || vt_entry > m.base + m.size) {
    alert(fmt("vtable[3] outside client.dll: 0x{:X}", vt_entry));
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
| Il2CppDumper | Unity IL2CPP metadata | Dump offsets → use in Echo proc.read | `research_technique("Unity IL2CPP offset recovery")` |
| UEDumper | UE SDK gen | Alternative to Dumper-7; same offset format | `research_technique("SDK generation UE4")` |
| sig-maker | IDA sig generator | One click → IDA wildcard pattern for proc.scan_ida | `read_subagent("pattern-scanner")` |
| Binary Ninja | Modern decompiler | HLIL/MLIL for complex obfuscated code | `get_agent_briefing("binary-ninja-specialist")` |
| kdmapper | Kernel driver mapper | AC research — see echo-anticheat | `research_technique("vulnerable driver exploitation")` |
| KDU | Kernel Driver Utility | 100+ vulnerable driver table for kernel access | `research_technique("KDU driver list")` |

---

## Awesome game security cross-references

For each cheatsheet technique, the corresponding awesome-game-security resource category:

| Technique | awesome-game-security category | Echo skill |
|---|---|---|
| Memory hacking | gmh5225/awesome-game-security#memory | `skills/awesome-game-security.md#memory-hacking` |
| Anti-cheat analysis | gmh5225/awesome-game-security#anti-cheat | `skills/awesome-game-security.md#anti-cheat-systems` |
| RE tools | gmh5225/awesome-game-security#tools | `skills/awesome-game-security.md#reverse-engineering-tools` |
| VMP / OLLVM | gmh5225/awesome-game-security#protections | `skills/devirt-workflow.md` |
| UE4/UE5 SDK | gmh5225/awesome-game-security#unreal | `skills/dumper7-sdk.md` |
| Unity IL2CPP | gmh5225/awesome-game-security#unity | `skills/awesome-game-security.md#engine-internals--unity` |
| Pattern scanning | gmh5225/awesome-game-security#signature | `skills/awesome-game-security.md#signatures--pattern-scanning` |
| Kernel / driver | gmh5225/awesome-game-security#kernel | `skills/awesome-game-security.md#kernel--driver-level` |
