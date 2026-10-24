# Reverse Engineering Tools Reference

Curated tooling for game RE work, sourced from awesome-game-security. Echo has Zydis and Unicorn built in; the tools below are for offline/external analysis.

---

## Debuggers

| Tool | Type | Notes |
|------|------|-------|
| x64dbg | User-mode debugger | Open-source, plugin ecosystem, great for game RE. `x64dbg/x64dbg` |
| WinDbg (Preview) | Microsoft debugger | Kernel + user-mode; good for driver analysis |
| HyperDbg | Hypervisor-based | Stealthy; runs below OS. `HyperDbg/HyperDbg` |
| PINCE | Linux (GDB frontend) | For Linux games. `korcankaraokcu/PINCE` |
| Cheat Engine | Memory scanner + debugger | Built-in assembler, Lua scripting, CE tables. Forks: `TheDaemoness/CheatEngineMonaco`, `atom0s/Steamless` |
| ReClass.NET | Struct visualizer | Visualizes memory as typed structs in real time. `ReClassNET/ReClass.NET` |

### Cheat Engine plugins
- `cheat-engine/aitools` — LLM agent integration via `registerAITool` callbacks
- `CE-MCP-Plugin` (`Eruditi/CE-MCP-Plugin`) — MCP server for Cheat Engine
- `cheat-engine/UnrealEngineTools` — Lua tools for UObject/UClass scanning

---

## Disassemblers / Decompilers

| Tool | Notes |
|------|-------|
| IDA Pro | Industry standard; FLIRT, type libraries, Hex-Rays decompiler |
| Ghidra | Free NSA tool; scripting via Java/Python; P-code IR |
| Binary Ninja | API-first; Python automation; MLIL/HLIL IRs |
| RetDec | Open-source decompiler; good for automated analysis |
| dogbolt.org | Multi-decompiler web frontend |

### IDA plugins (from awesome-game-security)
- `SigMaker` — generate IDA-style signatures from selected bytes
- FLIRT signature creation for identifying library functions
- `gmh5225/IDA-*` repos — various game-specific IDA scripts

### Ghidra extensions
- `astrelsky/Ghidra-Cpp-Class-Analyzer` — C++ class hierarchy recovery
- `Warxim/ghidra-xtensa` — ESP32/Xtensa support
- mcp-gamehacking `ghidra-specialist` agent for scripting guidance

---

## Dynamic Analysis / Instrumentation

| Tool | Notes |
|------|-------|
| Frida | Dynamic instrumentation, JS hooks, cross-platform. `frida/frida` |
| DynamoRIO | Dynamic binary instrumentation framework. `DynamoRIO/dynamorio` |
| TinyInst | Lightweight instrumentation. `googleprojectzero/TinyInst` |
| PIN | Intel's DBI framework |
| sogen | Unicorn-based full-system emulator for AV evasion research |
| r2emu | Radare2 emulation mode |

### Frida for game hacking
- `pcxxcq/frida-il2cpp-bridge` — IL2CPP method hooking via Frida
- `gmh5225/frida-il2cpp-datacollector` — ports CE monodatacollector to Android/iOS
- Stealth: `0xdea/frida-scripts`, various anti-detection patches for Frida

---

## Memory Tools

| Tool | Purpose |
|------|---------|
| ReClass.NET | Live struct visualization in game process |
| Process Hacker / System Informer | Process/handle/memory analysis |
| Winpmem | Physical memory acquisition |
| PCILeech / MemProcFS | DMA-based memory access (hardware required) |

---

## Game-Specific Tools

### Unreal Engine
| Tool | Purpose |
|------|---------|
| UEDumper | Dumps UE4/5 SDK from running process; generates C++ headers with offsets |
| UnrealDumper-4.25+ | UE4.25+ SDK dumper |
| RE-UE4SS | UE4/5 Lua scripting + live struct editing |
| UAssetAPI / UAssetGUI | `.uasset` file parsing and editing |

### Unity
| Tool | Purpose |
|------|---------|
| Il2CppDumper | Dumps IL2CPP metadata; generates `dump.cs` with field offsets |
| Il2CppInspector | Advanced IL2CPP analysis; generates C++ scaffolding |
| dnSpy | .NET assembly decompiler/debugger (for Mono games) |
| Cpp2IL | IL2CPP to IL decompilation |

### Source Engine
| Tool | Purpose |
|------|---------|
| Source 2 schema dump | Extract all netvar/field offsets via schema system |
| cs2-dumper | Automated offset dumper for CS2 (community maintained) |
| hazedumper | Cross-game automated offset dumper |

### Android / Mobile
| Tool | Purpose |
|------|---------|
| jadx | APK / Java bytecode decompiler |
| APKTool | APK unpacking and smali editing |
| KernelSU / Magisk | Root for dynamic analysis |
| Zygisk | Zygote-based injection framework |

---

## Pattern Scanning Tools

| Tool | Notes |
|------|-------|
| SigMaker (IDA plugin) | Select bytes in IDA, generate IDA-style signature |
| pat-tool | Command-line pattern finder from binary diff |
| Auto-sig generators | Various community tools that compare two builds and output updated patterns |

For Echo specifically: use `proc.scan("IDA_PATTERN", "module.dll")` — the built-in scanner handles both IDA-style and byte-mask patterns.

---

## Packet Analysis

| Tool | Notes |
|------|-------|
| Wireshark | Full network capture and dissection |
| WinDivert | User-mode packet interception (Windows). Used by various game sniffers. |
| Npcap | WinPcap replacement for Wireshark on modern Windows |
| Scapy | Python packet manipulation |

For game protocol RE: capture with Wireshark, then use mcp-gamehacking `network-analyst` agent for protocol analysis.

---

## mcp-gamehacking integration

Use these tools via the gamehacking MCP server:

```
analyze_project("ags-kdmapper")          → architecture of kdmapper
search_skills("IDA signature scanning")  → SigMaker and auto-sig approaches
read_skill("ags-unicorn-emulator")       → Unicorn usage patterns
get_agent_briefing("ida-specialist")     → IDA scripting guidance
get_agent_briefing("ghidra-specialist")  → Ghidra scripting guidance
read_subagent("struct-recovery")         → struct layout from memory dumps
read_subagent("pattern-scanner")         → generating and validating patterns
```
