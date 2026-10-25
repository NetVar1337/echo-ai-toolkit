---
name: awesome-game-security
description: Per-category resource map from gmh5225/awesome-game-security (4000+ curated resources) mapped onto Echo: the Echo agent to use, the mcp-gamehacking query to pull deep skills, and the key external tools for each domain — memory, RE, engine internals, SDK generation, mobile, kernel research.
---

# Awesome Game Security — Echo Integration Map

**Source:** gmh5225/awesome-game-security — 4000+ curated resources across memory hacking, RE, AC research, engine internals, kernel, mobile, and more.

For each category: the relevant Echo agent, the `mcp-gamehacking` query to pull deep skills, and the key tools/resources from the repo.

---

## Memory hacking / external cheats

**Echo agent:** `echo-memory`, `echo-esp`, `echo-aimbot`

**mcp-gamehacking queries:**
```
research_technique("external memory reading")
research_technique("pointer chain traversal")
get_agent_briefing("cheat-developer")
read_subagent("offset-finder")
read_subagent("pattern-scanner")
```

**Key resources:**
- [Cheat Engine](https://github.com/cheat-engine/cheat-engine) — gold standard memory scanner/debugger
- [ReClass.NET](https://github.com/ReClassNET/ReClass.NET) — live struct recovery from memory
- [mem](https://github.com/0x1F9F1/mem) — collection of C++11 reverse-engineering headers (pattern scanning, memory access)
- [hazedumper](https://github.com/frk1/hazedumper) — CS:GO offset dumper; **CS:GO only**, no CS2 support (last push 2024-03)

**Echo integration:**
```angelscript
// Offsets are UNVERIFIED PLACEHOLDERS from one community dump — re-derive with a
// current cs2-dumper run before use, they change with every game update.
const uint64 OFF_PAWN = 0x60C;   // local player -> pawn (placeholder)
const uint64 OFF_HP   = 0x344;   // m_iHealth           (placeholder)
const uint64 OFF_TEAM = 0x3CB;   // m_iTeamNum          (placeholder)

bool read_local_state(uint32 local_idx, float &out hp, int32 &out team) {
    // Pattern scan with IDA wildcards — the scanner needs a base address first
    uint64 base = process::get_module_base("client.dll");
    if (base == 0) return false;

    uint64 hit = process::find_signature(base, "48 8B 0D ?? ?? ?? ?? 48 85 C9");
    if (hit == 0) return false;

    // get_relative_address returns the address OF the operand, so read it to get
    // the pointer the instruction actually loads.
    uint64 entity_list = process::read_uint64(process::get_relative_address(hit, 3, 7));
    if (entity_list == 0) return false;

    // ReClass-style struct walk
    uint64 local = process::read_uint64(entity_list + uint64(local_idx) * 0x10);
    if (local == 0) return false;
    uint64 pawn = process::read_uint64(local + OFF_PAWN);
    if (pawn == 0) return false;

    hp       = process::read_float(pawn + OFF_HP);
    team     = process::read_int32(pawn + OFF_TEAM);
    return true;
}
```

---

## Anti-cheat systems

**Echo agent:** `echo-anticheat`

**mcp-gamehacking queries:**
```
get_agent_briefing("anti-cheat-analyst")
research_technique("battleye detection mechanisms")
research_technique("eac kernel driver analysis")
research_technique("vanguard cr3 protection")
read_subagent("ac-driver-analyzer")
read_subagent("detection-assessor")
search_skills("vac detection mechanisms")
```

**Key resources:**
- Community reversals of BattlEye, EAC, Vanguard, VAC, Ricochet, FACEIT — see gmh5225/awesome-game-security#anti-cheat section
- [EasyAntiCheat-Reversing](https://github.com/gmh5225/EAC-EasyAntiCheat-Reversing) — EAC driver internals

**Echo surface (what kernel-level AC can see about Echo):**
```angelscript
// Echo's only footprints visible to AC:
// 1. OpenProcess handle to game process
// 2. ReadProcessMemory syscalls (if not using driver)
// 3. Discord overlay (not Echo's code)
//
// Module presence is checked via the loaded-module list.
bool log_integrity_modules() {
    array<module_entry>@ mods = process::get_module_list();
    if (mods is null) return false;

    for (uint i = 0; i < mods.length(); i++) {
        string n = mods[i].name;
        if (n == "EasyAntiCheat.sys" || n == "vgk.sys" || n == "BEClient.dll") {
            console::log("integrity module loaded: " + n);
        }
    }
    return true;
}
```

---

## Kernel / driver level

**Echo agent:** `echo-anticheat`, `echo-reverse`

**mcp-gamehacking queries:**
```
get_agent_briefing("driver-developer")
get_agent_briefing("hypervisor-researcher")
research_technique("DKOM driver internals")
research_technique("EPT hook memory read")
research_technique("vulnerable driver surface")
read_subagent("ac-driver-analyzer")
read_subagent("syscall-stub-generator")
```

**Key resources:**
- [kdmapper](https://github.com/TheCruZ/kdmapper) — kernel driver manual mapper via vulnerable driver
- [KDU](https://github.com/hfiref0x/KDU) — Kernel Driver Utility, 100+ vulnerable driver table
- [EfiGuard](https://github.com/Mattiwatti/EfiGuard) — UEFI bootkit for kernel integrity bypass

**Note:** Echo is external and never injects or loads a kernel driver. This category is relevant for anti-cheat analysis and understanding detection surfaces.

---

## Engine internals — Unreal Engine 4/5

**Echo agent:** `echo-sdk`

**mcp-gamehacking queries:**
```
get_agent_briefing("unreal-engine-specialist")
research_technique("UE5 GObjects traversal")
research_technique("FName pool resolution")
research_technique("UE4 bone matrix")
read_subagent("struct-recovery")
read_subagent("vtable-mapper")
search_skills("UE5 GObjects 2024")
```

**Key resources:**
- [Dumper-7](https://github.com/Encryqed/Dumper-7) — UE4/5 SDK generator
- [Dumper-7-VGK](https://github.com/sinistercodes/Dumper-7-VGK) — Valorant VGK-aware fork
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) — UE4/5 scripting framework
- [FModel](https://github.com/4sval/FModel) — UE4/5 asset browser

See `skills/dumper7-sdk/SKILL.md` for full traversal patterns and `templates/ue5-sdk.as` / `templates/valorant.as`.

---

## Engine internals — Unity (Mono / IL2CPP)

**Echo agent:** `echo-reverse`, `echo-memory`

**mcp-gamehacking queries:**
```
get_agent_briefing("unity-specialist")
research_technique("Unity IL2CPP offset recovery")
research_technique("Mono method injection")
read_subagent("struct-recovery")
search_skills("global-metadata.dat")
```

**Key resources:**
- [Il2CppDumper](https://github.com/Perfare/Il2CppDumper) — extract class/method metadata from IL2CPP binary
- [Il2CppInspector](https://github.com/djkaty/Il2CppInspector) — deep IL2CPP analysis
- [BepInEx](https://github.com/BepInEx/BepInEx) — Unity mod framework (Mono injection)
- [MelonLoader](https://github.com/LavaGang/MelonLoader) — universal Unity/IL2CPP mod loader

**Echo integration:**
```angelscript
// After running REA inspect_unity_il2cpp on global-metadata.dat.
// A native scan yields a CODE address, never a managed class pointer — the class
// pointer is what the matched instruction loads, so resolve the operand and read it.
uint64 find_il2cpp_class() {
    uint64 il2cpp_base = process::get_module_base("GameAssembly.dll");
    if (il2cpp_base == 0) return 0;

    uint64 code_addr = process::find_signature(
        il2cpp_base, "48 8B 05 ?? ?? ?? ?? 48 85 C0 74 ??"
    );
    if (code_addr == 0) return 0;

    return process::read_uint64(process::get_relative_address(code_addr, 3, 7));
}
```

See `templates/unity-il2cpp.as` for the full pattern.

---

## Engine internals — Source / Source 2

**Echo agent:** `echo-esp`, `echo-memory`

**mcp-gamehacking queries:**
```
get_agent_briefing("cs2-specialist")
get_agent_briefing("source-engine-specialist")
research_technique("CS2 entity system traversal")
research_technique("Source 2 view matrix")
read_subagent("bone-mapper")
read_subagent("binary-differ")
search_skills("cs2 offsets")
```

**Key resources:**
- [a2x CS2 dumper](https://github.com/a2x/cs2-dumper) — live CS2 offset JSON
- [source2gen](https://github.com/neverlosecc/source2gen) — Source 2 schema SDK gen

See `templates/esp-bones.as` (full CS2 ESP) and `reference/offsets.md`.

---

## Reverse engineering tools

**Echo agent:** `echo-reverse`

**mcp-gamehacking queries:**
```
get_agent_briefing("reverse-engineer")
get_agent_briefing("ida-specialist")
get_agent_briefing("ghidra-specialist")
research_technique("IDA FLIRT signature creation")
research_technique("Ghidra P-code analysis")
read_subagent("pattern-scanner")
```

**Key resources:**
- [IDA Pro](https://hex-rays.com/ida-pro/) + [ida-mcp](https://github.com/HexRaysSA/ida-mcp) — industry standard; ida-mcp is **not** in this repo's `.mcp.json` — add it yourself if you have an IDA licence
- [Ghidra](https://github.com/NationalSecurityAgency/ghidra) + [SuperGhidra](https://github.com/yuatemycat/SuperGhidra) — NSA open-source
- [radare2](https://github.com/radareorg/radare2) + [radare2-mcp](https://github.com/radareorg/radare2-mcp) — radare2-mcp is **not** in this repo's `.mcp.json` — add it yourself
- [Binary Ninja](https://binary.ninja/) — modern decompiler
- [x64dbg](https://github.com/x64dbg/x64dbg) — Windows debugger
- [Cutter](https://github.com/rizinorg/cutter) — radare2 GUI

This repo's `.mcp.json` wires exactly three servers: `gamehacking`, `rea` and `angel-menu`.
ida-mcp, radare2-mcp and Hetty are optional — add them to your own client config.

---

## Packers / obfuscation (VMProtect, OLLVM, Themida)

**Echo agent:** `echo-reverse`

**mcp-gamehacking queries:**
```
get_agent_briefing("obfuscation-analyst")
research_technique("VMProtect devirtualization")
research_technique("OLLVM control flow flattening")
research_technique("Themida unpacking")
search_skills("vmprotect handler analysis")
```

**Key resources:**
- [NoVmp](https://github.com/can1357/NoVmp) — VMP devirt via VTIL
- [VTIL-Core](https://github.com/vtil-project/VTIL-Core) — IR for devirt
- [Triton](https://github.com/JonathanSalwan/Triton) — symbolic execution
- [de4dot](https://github.com/de4dot/de4dot) — .NET deobfuscator

Full devirt workflow: `skills/devirt-workflow/SKILL.md`.

---

## Signatures / pattern scanning

**Echo agent:** `echo-memory`

**mcp-gamehacking queries:**
```
research_technique("IDA pattern scanning ASLR")
read_subagent("pattern-scanner")
research_technique("signature generation from binary")
search_skills("AOB scan")
```

**Key resources:**
- [sig-maker](https://github.com/A200K/IDA-Pro-SigMaker) — IDA plugin: one click → IDA-style sig
- [mem](https://github.com/0x1F9F1/mem) — C++11 reverse-engineering headers with an AOB scanner (same repo as above; there is no project called "ps-mem")

**Multi-tier sig pattern for patch resilience:**
```angelscript
uint64 find_client_sig() {
    uint64 base = process::get_module_base("client.dll");
    if (base == 0) return 0;

    uint64 addr = 0;

    // Tier 1: exact bytes (breaks on minor patch)
    addr = process::find_signature(base, "48 89 5C 24 10 48 89 74");

    // Tier 2: skip volatile prefix, anchor on stable opcode sequence
    if (addr == 0)
        addr = process::find_signature(base, "?? ?? ?? ?? ?? ?? ?? ?? 57 48 83 EC 20 48 8B 0D ?? ?? ?? ??");

    // Tier 3: anchor on a stable string in the module, then decode around it
    if (addr == 0) {
        uint64 str = process::find_signature(base, "43 6C 69 65 6E 74"); // "Client"
        if (str != 0) {
            array<uint8>@ bytes = process::read_bytes(str - 0x40, 0x80);
            if (bytes is null) return 0;

            array<disasm_insn@> insns;
            if (zydis::disasm(bytes, str - 0x40, insns)) {
                for (uint i = 0; i < insns.length(); i++) {
                    if (insns[i].text.find("Client") >= 0) {
                        addr = insns[i].runtime_address;
                        break;
                    }
                }
            }
        }
    }
    return addr;
}
```

---

## SDK / offset generation

**Echo agent:** `echo-sdk`

**mcp-gamehacking queries:**
```
get_agent_briefing("unreal-engine-specialist")
research_technique("SDK generation UE4")
research_technique("Dumper-7 FName resolution")
read_subagent("vtable-mapper")
read_subagent("import-resolver")
```

**Key resources:**
- [Dumper-7](https://github.com/Encryqed/Dumper-7) — UE4/5
- [Dumper-7-VGK](https://github.com/sinistercodes/Dumper-7-VGK) — Valorant
- [Il2CppDumper](https://github.com/Perfare/Il2CppDumper) — Unity
- [source2gen](https://github.com/neverlosecc/source2gen) — Source 2

---

## Injection / hooking (AC awareness only)

**Echo agent:** `echo-anticheat` (detection surface awareness)

**mcp-gamehacking queries:**
```
get_agent_briefing("injection-specialist")
get_agent_briefing("hooking-specialist")
research_technique("manual map DLL injection")
research_technique("syscall direct indirect")
read_subagent("syscall-stub-generator")
read_subagent("detection-assessor")
```

**Key resources:**
- [kdmapper](https://github.com/TheCruZ/kdmapper) — kernel injection
- [Blackbone](https://github.com/DarthTon/Blackbone) — process manipulation
- [minhook](https://github.com/TsudaKageyu/minhook) — x86/x64 inline hook

Echo is external — this category informs understanding of how other cheats look to AC, not Echo operation.

---

## Networking / protocol analysis

**Echo agent:** `echo-reverse`, `echo-dev`

**mcp-gamehacking queries:**
```
get_agent_briefing("network-analyst")
research_technique("game protocol reverse engineering")
research_technique("packet capture game traffic")
research_technique("protobuf game protocol")
search_skills("wireshark game analysis")
```

**Key resources:**
- [Hetty](https://github.com/dstotijn/hetty) — HTTP proxy; optional, **not** in this repo's `.mcp.json` — add it yourself
- [mitmproxy](https://mitmproxy.org/) — MITM proxy
- [Frida](https://frida.re/) — SSL unpinning + runtime packet hooks

---

## Android / mobile

**Echo agent:** `echo-reverse`

**mcp-gamehacking queries:**
```
get_agent_briefing("android-researcher")
research_technique("Zygisk module injection")
research_technique("KernelSU root IL2CPP")
research_technique("Frida Android game")
search_skills("android game hacking")
```

**Key resources:**
- [Zygisk-Il2CppDumper](https://github.com/Perfare/Zygisk-Il2CppDumper) — IL2CPP dump from running process
- [KernelSU](https://github.com/tiann/KernelSU) — kernel-level root for Android
- [frida-gadget](https://frida.re/docs/gadget/) — Frida without root

---

## Full mcp-gamehacking × awesome-game-security cross-reference

For any resource in awesome-game-security, find the matching mcp-gamehacking skill:

```
# Find skills about a specific tool or technique:
search_skills("<tool name>")
search_skills("<technique>")

# Find the specialist agent for a game/platform:
get_agent_briefing("<game>-specialist")    # cs2, valorant, fortnite, apex
get_agent_briefing("<tech>-specialist")   # dma, android, hypervisor

# Deep-dive any technique:
research_technique("<exact technique>")

# Get subagent for a specific sub-task:
read_subagent("pattern-scanner")
read_subagent("struct-recovery")
read_subagent("binary-differ")
read_subagent("detection-assessor")
read_subagent("ac-driver-analyzer")
read_subagent("bone-mapper")
```

`skill_stats` gives totals; `list_skills` + filters finds a specific domain. The full catalog has 4100+ entries.
