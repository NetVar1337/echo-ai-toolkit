# echo-ai-toolkit

AI-powered development toolkit for the [Echo Universal API](https://echo-23.gitbook.io/angel) — an AngelScript scripting platform with process memory access, Discord overlay rendering, Zydis disassembly, and Unicorn emulation.

Combines Echo's platform reference with the [awesome-game-security](https://github.com/gmh5225/awesome-game-security) knowledge base and [mcp-gamehacking](https://github.com/1llu50ry/mcp-gamehacking)'s 4100+ skills library.

---

## Quick start

```bash
git clone https://github.com/NetVar1337/echo-ai-toolkit
cd echo-ai-toolkit
claude   # opens Claude Code with all agents available
```

Copy a template to `%AppData%\Roaming\scripts\`, reopen the in-game menu. No compile step.

---

## Agents (5)

Open with `Agent: <name> — <request>` in Claude Code, or just describe your task and Claude will route to the right agent.

| Agent | Use when... |
|-------|-------------|
| `echo-dev` | General Echo scripting — API reference, threading, menu, networking, utilities |
| `echo-esp` | Building ESP: boxes, skeletons, health bars, name tags, W2S for Source 2 / Unreal / Unity |
| `echo-aimbot` | Aimbot: target selection, FOV, smoothing, prediction, recoil, triggerbot |
| `echo-memory` | RE work: pointer chains, struct recovery, pattern scanning, Unicorn emulation, Zydis xrefs |
| `echo-anticheat` | Detection risk assessment: AC internals, Echo's exposure surface, safe coding patterns |

---

## Skills (4 reference documents)

Loaded automatically when relevant agents need them. Also readable directly.

| Skill | Contents |
|-------|---------|
| `skills/anti-cheat-systems.md` | VAC, EAC, BattlEye, Vanguard, Ricochet, Byfron — drivers, mechanisms, research links |
| `skills/game-hacking-techniques.md` | Memory access models, injection ref, hook types, entity list patterns, ESP/aimbot math, anti-detection |
| `skills/reverse-engineering-tools.md` | Debuggers, disassemblers, Frida, Cheat Engine plugins, game-specific dumpers, pattern tools |
| `skills/game-engine-resources.md` | Source 2, Unreal, Unity, IW engine internals — structs, offsets, W2S math, bone formats |

---

## Templates (7)

| Template | What it demonstrates |
|----------|---------------------|
| `basic.as` | Minimal `main()` + `on_unload()` |
| `render.as` | ESP box + color picker + `on_render` hook |
| `menu.as` | All menu element types with config persistence |
| `memory.as` | Process attach + IDA pattern scan + RIP resolve + tick loop |
| `esp-bones.as` | Full CS2 ESP: cornered boxes, skeleton, health bar, distance labels |
| `aimbot.as` | Full CS2 aimbot: target selection, smoothing, prediction, recoil, triggerbot |
| `misc.as` | Bunny hop, flash reduction, radar, spectator list |

---

## Reference docs

| Doc | Contents |
|-----|---------|
| `reference/api.md` | Complete API cheatsheet — every namespace and call |

---

## mcp-gamehacking integration

Wire up the mcp-gamehacking MCP server to get 4100+ skills, 75 specialist agents, and 16 MCP tools inside your Claude Code session.

See [`mcp/README.md`](mcp/README.md) for full setup. Quick version:

```bash
git clone https://github.com/1llu50ry/mcp-gamehacking
cd mcp-gamehacking && npm install && npm run build
# Edit .mcp.json in this repo: replace PATH_TO_MCP_GAMEHACKING with your clone path
```

Example queries once connected:

```
research_technique("cs2 entity system traversal")
get_agent_briefing("cs2-specialist")
read_subagent("bone-mapper")
read_subagent("binary-differ")
search_skills("vanguard bypass cr3")
```

---

## Links

- [Echo Universal API docs](https://echo-23.gitbook.io/angel)
- [Echo LLM-optimized reference](https://echo-23.gitbook.io/angel/llms-full.txt)
- [awesome-game-security](https://github.com/gmh5225/awesome-game-security) — 4000+ curated resources
- [mcp-gamehacking](https://github.com/1llu50ry/mcp-gamehacking) — MCP server for the above

---

## Contributing

Add a skill file in `skills/` or a new agent in `.claude/agents/`. Keep agent files self-contained — they're loaded as system prompts and should include all context needed without external lookups.
