# Echo AI Toolkit

Scripts and templates for the Echo Universal API (AngelScript, Discord overlay, process memory).

## Available agents

| Agent | Use for |
|-------|---------|
| `echo-dev` | General Echo API — threading, menu, networking, utilities |
| `echo-esp` | ESP visuals — boxes, bones, health bars, W2S for Source 2/Unreal/Unity |
| `echo-aimbot` | Aim assist — FOV, smoothing, prediction, recoil, triggerbot |
| `echo-memory` | Memory/RE — pointer chains, structs, pattern scanning, Unicorn, Zydis |
| `echo-anticheat` | AC awareness — detection surface, safe coding patterns, risk matrix |

Invoke: `Agent: echo-esp — write a CS2 bone ESP with mutex-safe entity buffer`

## mcp-gamehacking

If wired up (see `mcp/README.md`), the `gamehacking` MCP server adds 4100+ skills and 75 specialist agents:

```
research_technique("cs2 entity system")
get_agent_briefing("cs2-specialist")
read_subagent("bone-mapper")
```

## Docs

- Echo API: https://echo-23.gitbook.io/angel
- awesome-game-security: https://github.com/gmh5225/awesome-game-security
