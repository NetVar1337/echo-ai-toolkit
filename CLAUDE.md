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
| `echo-sdk` | Dumper-7 SDK: UE4/5 entity traversal, FTransform, FName, Valorant GObjects decrypt |
| `echo-reverse` | RE pipeline: static analysis → Echo runtime; Zydis xref, Unicorn OLLVM, REA, reverse-skill |

Invoke: `Agent: echo-esp — write a CS2 bone ESP with mutex-safe entity buffer`

## Coding principles (Karpathy)

Apply to all Echo scripts — see `skills/karpathy-coding.md`:

1. **Think Before Coding** — understand memory layout, pointer chains, and AC surface before writing
2. **Simplicity First** — named offset constants over abstractions; no classes in single-game scripts
3. **Surgical Changes** — after a patch, update only the `proc.scan_ida()` pattern string
4. **Goal-Driven Execution** — every line serves the stated goal; skip gold-plating

## MCP integrations

If wired up (see `mcp/README.md`), the `.mcp.json` connects two MCP servers:

**gamehacking** — 4100+ skills, 75 agents, 16 tools:
```
research_technique("cs2 entity system")
get_agent_briefing("cs2-specialist")
read_subagent("bone-mapper")
```

**rea** — static binary analysis (Unity IL2CPP, Godot, APK, WASM, firmware):
```
inspect_wasm_artifact(path)
inspect_apk_signature(path)
```

## Claude Code plugin

Install for slash commands and automatic agent context injection:

```
/plugin install echo-ai-toolkit --marketplace NetVar1337/echo-ai-toolkit
```

Use `/echo-esp`, `/echo-reverse`, etc. to activate agent context. Or just describe your task — the plugin auto-detects keywords and routes to the right agent automatically.

## Ecosystem skill

`skills/echo-ecosystem.md` — reference for external tooling: web-mv, angel-menu-mcp, echo-esp-preview, as_bundler, echo-angelscript-lsp, SuperGhidra, radare2-mcp, ida-mcp, NoVmp, VTIL-Core, vtil2, Triton, VMProtect-devirtualization, vmp-lazy-unpack, LLVM.

## Docs

- Echo API: https://echo-23.gitbook.io/angel
- awesome-game-security: https://github.com/gmh5225/awesome-game-security
