# Game Hacking Cheatsheet — Echo Integration Map

**Source:** ridpath/gamehacking-cheatsheet — "Game Hacking & Reverse Engineering Mega Cheatsheet"  
Topics: memory editing, anti-cheat evasion, exploitation, engine RE, firmware, VR/AR, blockchain games.

---

## Cheatsheet topic → Echo API equivalents

| Cheatsheet technique | Echo equivalent | Notes |
|---|---|---|
| **Pointer path tracing** (multilevel pointer maps) | `follow_chain(base, offsets)` below | Core Echo pattern |
| **AOBScan for ASLR busting** | `proc.scan_ida("48 8B ? ...", "mod.exe")` | Built-in, IDA-style wildcards |
| **CE Auto Assembler code injection** | N/A | Echo is external — no code injection |
| **Stealth DLL injection** | N/A | Echo uses Discord overlay, never injects |
| **PEB unlinking / sig evasion** | N/A | Echo's only AC surface: OpenProcess handle |
| **Dynamic function discovery (Frida)** | `disasm.decode_function()` + Unicorn trace | See echo-reverse agent |
| **RTTI salvage** | `proc.scan` for vtable pattern, then decode | Use echo-memory agent |
| **Heap spray / allocation tracking** | `proc.query_regions()` + type-sig scan | |
| **Memory map diffing** | Compare `proc.query_regions()` snapshots | Store in `hash_map` between ticks |
| **UE GNames/GObjects pattern** | `proc.scan_ida` → chunked array traversal | See echo-sdk agent + dumper7-sdk.md |
| **Unity IL2CPP** | REA `global-metadata.dat` + Il2CppDumper | See echo-reverse agent |
| **WebAssembly game recon** | REA `inspect_wasm_artifact` | |
| **Aimbot (memory-based)** | `proc.read` + `mouse.move` | See echo-aimbot agent |
| **Aimbot (pixel-based)** | Not in Echo API — requires external screen cap | |
| **Aimbot (AI neural)** | `http.post("localhost:PORT", frame_data)` to local model | |
| **AC bypass techniques** | Echo's external arch reduces surface; see echo-anticheat | |
| **Replay format reversing** | REA binary analysis on `.dem`/`.replay` | |
| **DRM loader staging (VMProtect)** | Unicorn emulation to trace decryption stages | echo-reverse agent |
| **OLLVM deobfuscation** | Unicorn trace + reverse-skill `ollvm-deobfuscation.md` | |
| **Firmware / UEFI analysis** | REA firmware analysis + reverse-skill `firmware-pentest` | Out of Echo scope |
| **Console botting via remote play** | External — pixel bot + Arduino input | Not Echo |
| **Blockchain / NFT exploits** | Out of Echo scope | Separate web3 tooling |
| **zk-SNARK / ZK game proofs** | Out of Echo scope | |

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

## Tools from the cheatsheet and their Echo/RE context

| Tool | Role | Echo context |
|---|---|---|
| Cheat Engine | CE pointer scan, auto-assembler | Use for initial offset discovery; export to Echo |
| x64dbg | Dynamic debugger | Find function addresses → Echo pattern scan |
| Ghidra / IDA | Static analysis | Find struct layouts → Echo reads; or use REA |
| Frida | Dynamic instrumentation | Echo replaces Frida for overlay+memory; Frida still useful for Android |
| ReClass.NET | Struct layout visualizer | Explore memory layout → hard-code offsets in Echo |
| WinDivert / Wireshark | Packet capture | Network protocol RE → not Echo-relevant |
| Il2CppDumper | Unity IL2CPP metadata | Dump class/method offsets → use in Echo proc.read |
| UEDumper | UE SDK gen | Alternative to Dumper-7; same offset output format |
