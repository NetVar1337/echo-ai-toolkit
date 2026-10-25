# echo-ai-toolkit

AI development toolkit for the [Echo Universal API](https://echo-23.gitbook.io/angel) — an AngelScript scripting platform with process memory access, Discord overlay rendering, Zydis disassembly, and Unicorn emulation.

12 specialist agents, 18 skills, and 15 runnable templates — for building ESP, aimbot, radar, loot, config, and reverse-engineering scripts without reading the whole API surface first.

> **Every API call in this repo is verified against the live Echo docs.** The real API is namespaced (`process::read_uint64()`, `render::draw_box()`, `ui::add_checkbox()`). If a call isn't in [`reference/api.md`](reference/api.md), it doesn't exist. CI enforces this.

---

## Install

### Claude Code plugin (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/NetVar1337/echo-ai-toolkit/main/install.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/NetVar1337/echo-ai-toolkit/main/install.ps1 | iex
```

One command. Installs the plugin, vendors the optional MCP dependencies, and adds the
`ponytail` companion plugin. Safe to re-run — every step is idempotent.

<details>
<summary>Manual install (no script)</summary>

```
/plugin marketplace add NetVar1337/echo-ai-toolkit
/plugin install echo-ai-toolkit@echo-ai-toolkit
```

Then run `/echo-setup` inside Claude Code to fetch the optional MCP dependencies.
</details>

**Requirements:** Claude Code, Node.js 18+, git. The Echo platform itself requires
Discord with the overlay enabled (Echo is Windows-only).

### Use as a project (no plugin)

```bash
git clone https://github.com/NetVar1337/echo-ai-toolkit
cd echo-ai-toolkit
claude
```

Project installs read `CLAUDE.md` and `agents/*.md` directly. The plugin install adds
slash commands, keyword auto-routing, and a side panel.

---

## Use it

```bash
/echo-help        # list all 12 agents
/echo-esp         # load ESP context
/echo-reverse     # load reverse-engineering context
```

Or just describe your task — keywords auto-route to the right agent:

| You say | Routes to |
|---|---|
| "draw bones on screen" | `echo-esp` |
| "aimbot with FOV filter" | `echo-aimbot` |
| "triggerbot with shot delay" | `echo-triggerbot` |
| "minimap radar" | `echo-radar` |
| "loot ESP for dropped items" | `echo-loot` |
| "find_signature for entity list" | `echo-memory` |
| "Dumper-7 GObjects traversal" | `echo-sdk` |
| "persist config over http" | `echo-config` |

To open an agent directly: `Agent: echo-esp — write a CS2 bone ESP`

---

## Agents (12)

| Agent | Use when... |
|---|---|
| `echo-dev` | General Echo scripting — lifecycle, threading, menu, networking, utilities, SIMD |
| `echo-esp` | ESP: boxes, skeletons, health bars, name tags, W2S for Source 2 / Unreal / Unity / IW |
| `echo-aimbot` | Aimbot: target selection, FOV, smoothing, prediction, recoil control |
| `echo-triggerbot` | Triggerbot: crosshair detection, shot delay variance, burst, per-hitbox |
| `echo-radar` | 2D radar/minimap overlay — world→radar transform, entity dots, edge indicators |
| `echo-loot` | Item/loot ESP — entity class filtering, item tiers, dropped-weapon tracking |
| `echo-memory` | RE work: pointer chains, struct recovery, pattern scanning, Unicorn, Zydis xrefs |
| `echo-anticheat` | Detection awareness — what integrity systems check, and safe coding patterns |
| `echo-sdk` | Dumper-7 SDK, Source 2 schema extraction, Unity IL2CPP, cached bone reads |
| `echo-reverse` | RE pipeline: obfuscation classification, REA MCP, binary differ, VMP devirt |
| `echo-config` | Config persistence, HTTP, filesystem, WebSocket, JSON, hash_map / hash_set |
| `echo-scripts` | Complete runnable example scripts — CS2 ESP, UE4 aimbot, Unity loot scanner |

---

## Skills (18)

Reference documents loaded on demand by the agents.

| Skill | Contents |
|---|---|
| `angelscript-patterns` | Mutex entity buffer, thread-safe tick/render, safe deref chain, rate limiter, W2S null check |
| `angelscript-types` | AngelScript type system: `@` handles, `array<T>`, `cast<T>`, closures, no-exceptions, common LLM mistakes |
| `echo-anti-patterns` | Wrong code → correct code, side by side |
| `echo-workflow` | Multi-agent orchestration: shared_snapshot hub, thread rate table, startup sequence |
| `echo-ecosystem` | External tooling: web-mv, angel-menu-mcp, echo-esp-preview, as_bundler, SuperGhidra, NoVmp, Triton |
| `anti-cheat-systems` | What VAC / EAC / BattlEye / Vanguard / Ricochet check, at a high level |
| `game-hacking-techniques` | Memory access models, hook types, entity list patterns, ESP/aimbot math |
| `game-engine-resources` | Source 2, Unreal, Unity, IW engine internals — structs, offsets, W2S math, bone formats |
| `gamehacking-cheatsheet` | Topic → Echo API map + mcp-gamehacking query per technique |
| `awesome-game-security` | Per-category resource map from [gmh5225/awesome-game-security](https://github.com/gmh5225/awesome-game-security) |
| `dumper7-sdk` | Dumper-7 SDK structure, GObjects traversal, FName resolution, VGK decrypt, offset update workflow |
| `omath-math` | W2S per engine, projectile prediction, rotation helpers |
| `reverse-workflow` | Static → runtime RE pipeline; tool decision tree, sig generation, Unicorn OLLVM trace |
| `reverse-engineering-tools` | Debuggers, disassemblers, Frida, Cheat Engine plugins, dumpers, pattern tools |
| `devirt-workflow` | 6-step VMProtect devirt: vmp-lazy-unpack OEP, Triton semantics, NoVmp VTIL, LLVM passes |
| `offset-update-workflow` | Post-patch offset recovery: binary diff, function reacquisition, pattern update |
| `karpathy-coding` | Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution |
| `ponytail` | Lazy senior dev philosophy: minimum code rules, shortcut comment convention |

---

## Templates (15)

Copy any `.as` file into `%AppData%\Roaming\scripts\` and reopen the in-game menu. No compile step.

| Template | What it demonstrates |
|---|---|
| `basic.as` | Minimal `main()` + `on_unload()` |
| `render.as` | ESP box + `on_render` hook |
| `menu.as` | All menu element types with config persistence |
| `memory.as` | Process attach + IDA pattern scan + RIP-relative resolve + tick loop |
| `esp-bones.as` | Full CS2 ESP: cornered boxes, skeleton, health bar, distance labels |
| `aimbot.as` | Full CS2 aimbot: target selection, smoothing, prediction, recoil, triggerbot |
| `misc.as` | Bunny hop, flash reduction, radar, spectator list |
| `ue5-sdk.as` | UE5 ESP from Dumper-7 SDK offsets: GWorld traversal, FTransform, cornered box, health bar |
| `unity-il2cpp.as` | Unity IL2CPP ESP: camera matrix, entity list walk, health bar |
| `valorant.as` | Valorant ESP: VGK-aware external, GObjects decrypt, UE4 TUObjectArray |
| `fortnite.as` | Fortnite ESP: GWorld traversal, 12-bone skeleton, HP + shield bars |
| `radar.as` | 2D circular radar panel — entity dots, edge indicators, rotating/north-up mode |
| `loot.as` | CS2 dropped-weapon ESP — item tiers, distance-gated labels, sorted loot panel |
| `esp-preview.as` | `esp_layout` namespace drop-in preview helper |
| `web-mv.as` | web-mv HTTP memory viewer endpoint |

> Game-specific offsets and patterns in these templates are **illustrative placeholders**. Verify
> them per patch and per game version — see `skills/offset-update-workflow`.

---

## Reference

| Doc | Contents |
|---|---|
| [`reference/api.md`](reference/api.md) | Complete API reference — all 22 function namespaces, every signature, return semantics, caveats |
| [`llms.txt`](llms.txt) | Single-file context bundle for GPT-4o, Gemini, and local models — paste as context |
| [`prompts/system-prompt.md`](prompts/system-prompt.md) | Portable system prompt for non-Claude clients |
| [`reference/offsets.md`](reference/offsets.md) | Offset/pattern reference (placeholders — verify per patch) |

---

## Integrations

### mcp-gamehacking

4100+ skills, 75 specialist agents, 19+ MCP tools.

```bash
git clone https://github.com/1llu50ry/mcp-gamehacking
cd mcp-gamehacking && npm install && npm run build
```

`/echo-setup` (or the installer) does this for you into `~/.local/share/echo-ai-toolkit/`.

### REA (Reverse Engineer Anything)

Static binary analysis: Unity IL2CPP, Godot, APK, WASM, pcap, firmware. Installed via `npx` on
first MCP connect — no manual step.

### Dumper-7 / Dumper-7-VGK

UE4/UE5 SDK generator. Inject into the running game to get a CppSDK with all offsets.

- [Encryqed/Dumper-7](https://github.com/Encryqed/Dumper-7) (UE4/UE5)
- [sinistercodes/Dumper-7-VGK](https://github.com/sinistercodes/Dumper-7-VGK) (adds Valorant)

### Development tools

| Tool | Purpose |
|---|---|
| [echo-angelscript-lsp](https://github.com/speedsunderscore/echo-angelscript-lsp) | VS Code LSP: ~1900 Echo symbols, autocompletion, hover docs |
| [echo-esp-preview](https://github.com/speedsunderscore/echo-esp-preview) | `esp_layout` namespace — drop-in ESP layout helper |
| [as_bundler](https://github.com/sinistercodes/as_bundler) | AngelScript bundler, validator, obfuscator, string scrambler |
| [web-mv](https://github.com/cy-gnus/web-mv) | Browser-based memory viewer via Echo agent API |
| [angel-menu-mcp](https://github.com/Jozkah/angel-menu-mcp) | MCP server — toggle the overlay menu from Claude |
| [ponytail](https://github.com/DietrichGebert/ponytail) | Lazy senior dev mode plugin |
| [andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) | Coding-discipline skill set |

### Binary analysis MCPs

| MCP | Install |
|---|---|
| [radare2-mcp](https://github.com/radareorg/radare2-mcp) | `r2pm -Uci r2mcp` |
| [ida-mcp](https://github.com/HexRaysSA/ida-mcp) | `claude plugin install ida-mcp@HexRaysSA` |
| [SuperGhidra](https://github.com/yuatemycat/SuperGhidra) | Python tools + MCP daemon at `127.0.0.1:5073` |

### VMP / devirtualization

[NoVmp](https://github.com/can1357/NoVmp) · [VTIL-Core](https://github.com/vtil-project/VTIL-Core) ·
[vtil2](https://github.com/pop-rip/vtil2) · [Triton](https://github.com/JonathanSalwan/Triton) ·
[VMProtect-devirtualization](https://github.com/JonathanSalwan/VMProtect-devirtualization) ·
[vmp-lazy-unpack](https://github.com/x86rc/vmp-lazy-unpack)

### omath

C++23 constexpr math reference for W2S, projectile prediction, coordinate transforms —
[alt-orange/omath](https://github.com/alt-orange/omath).

---

## Contributing

Add a skill under `skills/<name>/SKILL.md` or an agent under `agents/<name>.md`. Keep agent files
self-contained — they load as system prompts and must include all context without external lookups.

Every skill and agent needs YAML frontmatter (`name`, `description`). Every agent needs a matching
slash command in `hooks/register.tsx`. CI checks both, plus API conformance.

```bash
python3 scripts/check_api.py --root . --api-index /tmp/echo-api-index.md
claude plugin validate .
```

---

## Links

- [Echo Universal API docs](https://echo-23.gitbook.io/angel)
- [Echo LLM-optimized reference](https://echo-23.gitbook.io/angel/llms-full.txt)
- [awesome-game-security](https://github.com/gmh5225/awesome-game-security) — 4000+ curated resources
- [mcp-gamehacking](https://github.com/1llu50ry/mcp-gamehacking) — MCP server for the above
- [gamehacking-cheatsheet](https://github.com/ridpath/gamehacking-cheatsheet)

## License

MIT — see [LICENSE](LICENSE).
