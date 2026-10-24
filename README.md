# echo-ai-toolkit

AI-powered development toolkit for the [Echo Universal API](https://echo-23.gitbook.io/angel) — an AngelScript scripting platform with process memory access, Discord overlay rendering, Zydis disassembly, and Unicorn emulation.

Combines Echo's platform reference with the [awesome-game-security](https://github.com/gmh5225/awesome-game-security) knowledge base, [mcp-gamehacking](https://github.com/1llu50ry/mcp-gamehacking)'s 4100+ skills library, and integrations for Dumper-7 SDK generation, REA binary analysis, omath math, and more.

---

## Quick start

```bash
git clone https://github.com/NetVar1337/echo-ai-toolkit
cd echo-ai-toolkit
claude   # opens Claude Code with all agents available
```

Copy a template to `%AppData%\Roaming\scripts\`, reopen the in-game menu. No compile step.

---

## Agents (7)

Open with `Agent: <name> — <request>` in Claude Code, or just describe your task and Claude will route to the right agent.

| Agent | Use when... |
|-------|-------------|
| `echo-dev` | General Echo scripting — API reference, threading, menu, networking, utilities |
| `echo-esp` | Building ESP: boxes, skeletons, health bars, name tags, W2S for Source 2 / Unreal / Unity |
| `echo-aimbot` | Aimbot: target selection, FOV, smoothing, prediction, recoil, triggerbot |
| `echo-memory` | RE work: pointer chains, struct recovery, pattern scanning, Unicorn emulation, Zydis xrefs |
| `echo-anticheat` | Detection risk assessment: AC internals, Echo's exposure surface, safe coding patterns |
| `echo-sdk` | Dumper-7 SDK integration: UE4/5 entity traversal, FTransform/FName, Valorant GObjects decrypt |
| `echo-reverse` | RE pipeline: static analysis → Echo runtime; Zydis xref, Unicorn emulation, REA, reverse-skill |

---

## Skills (9 reference documents)

Loaded automatically when relevant agents need them. Also readable directly.

| Skill | Contents |
|-------|---------|
| `skills/anti-cheat-systems.md` | VAC, EAC, BattlEye, Vanguard, Ricochet, Byfron — drivers, mechanisms, research links |
| `skills/game-hacking-techniques.md` | Memory access models, injection ref, hook types, entity list patterns, ESP/aimbot math, anti-detection |
| `skills/reverse-engineering-tools.md` | Debuggers, disassemblers, Frida, Cheat Engine plugins, game-specific dumpers, pattern tools |
| `skills/game-engine-resources.md` | Source 2, Unreal, Unity, IW engine internals — structs, offsets, W2S math, bone formats |
| `skills/gamehacking-cheatsheet.md` | Cheatsheet topic → Echo API map, pointer chain helper, aimbot typologies, AC position |
| `skills/dumper7-sdk.md` | Dumper-7 SDK structure, GObjects traversal, FName resolution, VGK decrypt, offset update workflow |
| `skills/omath-math.md` | W2S per engine, projectile prediction, ExternalReverseEngineeredObject pattern, rotation helpers |
| `skills/karpathy-coding.md` | Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution |
| `skills/reverse-workflow.md` | Static → runtime RE pipeline; tool decision tree, sig generation, Unicorn OLLVM trace, patch workflow |

---

## Templates (8)

| Template | What it demonstrates |
|----------|---------------------|
| `basic.as` | Minimal `main()` + `on_unload()` |
| `render.as` | ESP box + color picker + `on_render` hook |
| `menu.as` | All menu element types with config persistence |
| `memory.as` | Process attach + IDA pattern scan + RIP resolve + tick loop |
| `esp-bones.as` | Full CS2 ESP: cornered boxes, skeleton, health bar, distance labels |
| `aimbot.as` | Full CS2 aimbot: target selection, smoothing, prediction, recoil, triggerbot |
| `misc.as` | Bunny hop, flash reduction, radar, spectator list |
| `ue5-sdk.as` | UE5 ESP from Dumper-7 SDK offsets: GWorld traversal, FTransform, cornered box, health bar |

---

## Reference docs

| Doc | Contents |
|-----|---------|
| `reference/api.md` | Complete API cheatsheet — every namespace and call |

---

## Integrations

### mcp-gamehacking
4100+ skills, 75 specialist agents, 16 MCP tools.

```bash
git clone https://github.com/1llu50ry/mcp-gamehacking
cd mcp-gamehacking && npm install && npm run build
# Edit .mcp.json: replace PATH_TO_MCP_GAMEHACKING with your clone path
```

### REA (Reverse Engineer Anything)
Static binary analysis: Unity IL2CPP, Godot, APK, WASM, pcap, firmware.

```bash
npm install --global rea-agents
npx rea-agents setup   # auto-wires Claude Code
```

### Dumper-7 / Dumper-7-VGK
UE4/UE5 SDK generator. Inject into running game → get CppSDK with all offsets.
- [Encryqed/Dumper-7](https://github.com/Encryqed/Dumper-7) (UE4/UE5)
- [sinistercodes/Dumper-7-VGK](https://github.com/sinistercodes/Dumper-7-VGK) (adds Valorant support)

### reverse-skill
44-rule RE skill router for IDA, radare2, OLLVM, patch-diff, malware analysis.

```bash
git clone https://github.com/zhaoxuya520/reverse-skill ../reverse-skill
# No install needed — clone alongside toolkit; echo-reverse agent references it
```

### omath
C++23 constexpr math reference for W2S, projectile prediction, coordinate transforms.
- [alt-orange/omath](https://github.com/alt-orange/omath) — formulas documented in `skills/omath-math.md`

See [`mcp/README.md`](mcp/README.md) for full setup and query examples.

---

## Links

- [Echo Universal API docs](https://echo-23.gitbook.io/angel)
- [Echo LLM-optimized reference](https://echo-23.gitbook.io/angel/llms-full.txt)
- [awesome-game-security](https://github.com/gmh5225/awesome-game-security) — 4000+ curated resources
- [mcp-gamehacking](https://github.com/1llu50ry/mcp-gamehacking) — MCP server for the above
- [gamehacking-cheatsheet](https://github.com/ridpath/gamehacking-cheatsheet) — mega-cheatsheet reference

---

## Contributing

Add a skill file in `skills/` or a new agent in `.claude/agents/`. Keep agent files self-contained — they're loaded as system prompts and should include all context needed without external lookups.
