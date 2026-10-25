# Echo AI Toolkit

Reference and templates for the Echo Universal API (AngelScript, Discord overlay, process memory).

**The Echo API is namespaced.** Real calls look like `process::read_uint64(addr)`,
`render::draw_box(...)`, `ui::add_checkbox(...)`, `source2::w2s(...)`. Anything not in
[`reference/api.md`](reference/api.md) does not exist. `reference/_API_CONTRACT.md` maps the
old invented names (`proc.read<T>()`, `proc.scan_ida()`, `renderer.draw_rect_filled()`,
`menu.checkbox()`, `emu.*`) to the real ones — read it before writing any code.

## Entry point

```angelscript
void on_unload() { /* teardown */ }

bool main() {
    return true;   // false unloads the script
}
```

`bool main()` is mandatory. Render calls only work inside the render thread (`on_render(@cb)`).

## Available agents

| Agent | Use for |
|---|---|
| `echo-dev` | General Echo API — lifecycle, threading, menu, networking, utilities |
| `echo-esp` | ESP visuals — boxes, bones, health bars, W2S for Source 2/Unreal/Unity |
| `echo-aimbot` | Aim assist — FOV, smoothing, prediction, recoil |
| `echo-triggerbot` | Triggerbot — crosshair detection, shot delay, burst, per-hitbox |
| `echo-radar` | 2D radar/minimap overlay — world→radar transform, entity dots |
| `echo-loot` | Item/loot ESP — entity class filtering, item tiers, dropped-weapon tracking |
| `echo-memory` | Memory/RE — pointer chains, structs, pattern scan, Unicorn, Zydis |
| `echo-anticheat` | AC awareness — detection surface, safe coding patterns, risk matrix |
| `echo-sdk` | Dumper-7 SDK: UE4/5 entity traversal, FTransform, FName, Valorant GObjects decrypt |
| `echo-reverse` | RE pipeline: static analysis → Echo runtime; Zydis xref, OLLVM, REA |
| `echo-config` | Config persistence, HTTP, fs, ws, json, hash_map/hash_set — data layer |
| `echo-scripts` | Complete runnable example scripts — CS2 ESP, UE4 aimbot, Unity loot scanner |

Invoke: `Agent: echo-esp — write a CS2 bone ESP with mutex-safe entity buffer`

## Layout

```
agents/<name>.md              # agent definitions (loaded as system prompts)
skills/<name>/SKILL.md        # reference docs (loaded on demand)
templates/*.as                # runnable AngelScript templates
reference/api.md              # complete API reference
reference/_API_CONTRACT.md    # old -> real API mapping (read first)
llms.txt                      # single-file context bundle for other LLMs
hooks/register.tsx            # slash commands, keyword routing, side panel
```

## Coding principles (Karpathy)

Apply to all Echo scripts — see `skills/karpathy-coding/SKILL.md`:

1. **Think Before Coding** — understand memory layout, pointer chains, and AC surface before writing
2. **Simplicity First** — named offset constants over abstractions; no classes in single-game scripts
3. **Surgical Changes** — after a patch, update only the `process::find_signature` pattern string
4. **Goal-Driven Execution** — every line serves the stated goal; skip gold-plating

## MCP integrations

Wired by `/echo-setup` (or the installer) into `~/.local/share/echo-ai-toolkit/`:

**gamehacking** — 4100+ skills, 75 agents, 16 tools:
```
research_technique("cs2 entity system")
get_agent_briefing("cs2-specialist")
read_subagent("bone-mapper")
```

**rea** — static binary analysis (Unity IL2CPP, Godot, APK, WASM, firmware):
```
inspect_wasm_artifact(path)
inspect_artifact(path)
```

**angel-menu** — toggle the Echo overlay menu from Claude.

## Claude Code plugin

```
/plugin marketplace add NetVar1337/echo-ai-toolkit
/plugin install echo-ai-toolkit@echo-ai-toolkit
```

Use `/echo-esp`, `/echo-reverse`, etc. to activate agent context. Or describe your task — the
plugin auto-detects keywords and routes to the right agent.

## Recommended plugins

```
/plugin marketplace add DietrichGebert/ponytail
/plugin install ponytail@ponytail
```

## Docs

- Echo API: https://echo-23.gitbook.io/angel
- awesome-game-security: https://github.com/gmh5225/awesome-game-security
