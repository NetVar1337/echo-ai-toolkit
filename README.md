# echo-ai-toolkit

AI development toolkit for the [Echo Universal API](https://echo-23.gitbook.io/angel) — an AngelScript scripting platform with process memory access, Discord overlay rendering, Zydis disassembly, and Unicorn emulation.

12 specialist agents, 18 skills, and 15 runnable templates — for building ESP, aimbot, radar, loot, config, and reverse-engineering scripts without reading the whole API surface first.

> **Every API call in this repo is verified against the live Echo docs.** The real API is namespaced (`process::read_uint64()`, `render::draw_box()`, `ui::add_checkbox()`). If a call isn't in [`reference/api.md`](reference/api.md), it doesn't exist. CI enforces this.

---

## Install

**One command installs everything.** No flags, no tiers to pick: the plugin, all 18
skills, all 12 agents, all 5 MCP servers, all 17 companion tools, both Claude Code
companion plugins, and the Pi profile with its `echo` CLI.

```bash
curl -fsSL https://raw.githubusercontent.com/NetVar1337/echo-ai-toolkit/main/install.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/NetVar1337/echo-ai-toolkit/main/install.ps1 | iex
```

Safe to re-run — every step is idempotent. Verify at any time:

```bash
echo doctor              # every tool: ok / MISSING / not applicable
```

### What lands

| | Count | What |
|---|---|---|
| Agents | 12 | `echo-dev`, `-esp`, `-aimbot`, `-triggerbot`, `-radar`, `-loot`, `-memory`, `-anticheat`, `-sdk`, `-reverse`, `-config`, `-scripts` |
| Skills | 18 | also copied into the Pi profile — same `SKILL.md` format |
| Templates | 15 | runnable `.as` files |
| MCP servers | 5 | gamehacking, rea, angel-menu, radare2, ida |
| Companion tools | 17 | the full list below |
| Plugins | 3 | echo-ai-toolkit, ponytail, andrej-karpathy-skills |

Expected size is **~3.6 GB**, almost all of it `mcp-gamehacking` (3.1 GB — 18 GB of
skills once on disk). That is the cost of a complete install. To go smaller:

| Flag | Effect |
|---|---|
| `ECHO_SKIP_GAMEHACKING=1` | skip mcp-gamehacking — drops the install to ~550 MB |
| `ECHO_SKIP_MCP=1` | skip every MCP build |
| `ECHO_TIER=standard` | skip the compiler-built stack (NoVmp, VTIL-Core, vtil2, LLVM, web-mv) |
| `ECHO_TIER=minimal` | plugin + MCP servers only |
| `ECHO_NO_ALIAS=1` | do not add the `echo` shell alias |

A tool whose prerequisite cannot be satisfied is **skipped with a reason**, never a
hard failure — so the install always completes, and `echo doctor` tells you what is
missing and why.

### Everything that gets installed

| Tool | What it gives you | How it is fetched |
|---|---|---|
| **echo-ai-toolkit** | 12 agents, 18 skills, 15 templates | Claude Code plugin |
| [mcp-gamehacking](https://github.com/1llu50ry/mcp-gamehacking) | 4100+ skills, 75 agents, 19+ MCP tools | clone + `npm install` + build |
| [angel-menu-mcp](https://github.com/Jozkah/angel-menu-mcp) | toggle the Echo overlay menu from Claude | clone + `npm install` |
| [rea](https://github.com/morluto/rea) | static binary analysis (IL2CPP, APK, WASM, firmware) | `npx -y rea-agents` on first connect |
| radare2 MCP | disasm, decompile, search, analysis | `r2pm -r r2mcp` (needs `r2pm -Uci r2mcp`) |
| IDA MCP | decompile, rename, xref, structs | `uvx ida-mcp` (needs IDA 9.4+ with idalib) |
| [ponytail](https://github.com/DietrichGebert/ponytail) | lazy-senior-dev discipline | Claude Code plugin |
| [andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) | coding-discipline guidelines | Claude Code plugin |
| [as_bundler](https://github.com/sinistercodes/as_bundler) | AngelScript bundler / validator / obfuscator | prebuilt release binary |
| [echo-esp-preview](https://github.com/speedsunderscore/echo-esp-preview) | `g_preview` + `esp_layout` drag-to-arrange ESP | single `.as` drop-in into your scripts dir |
| [echo-angelscript-lsp](https://github.com/speedsunderscore/echo-angelscript-lsp) | VS Code completion + hover docs for ~1900 Echo symbols | `.vsix` from the release, `code --install-extension` |
| [Triton](https://github.com/JonathanSalwan/Triton) | symbolic execution + taint analysis | `pip install triton-library` into a venv |
| [VMProtect-devirtualization](https://github.com/JonathanSalwan/VMProtect-devirtualization) | Triton-based VMP devirt scripts | clone (29 MB, bundles Intel Pin) |
| [vmp-lazy-unpack](https://github.com/x86rc/vmp-lazy-unpack) | VMP section unpacker + import resolver | clone + `pip install -e .` |
| [awesome-game-security](https://github.com/gmh5225/awesome-game-security) | 4000+ curated resources | README only (435 KB, *not* the 3.19 GB clone) |
| [gamehacking-cheatsheet](https://github.com/ridpath/gamehacking-cheatsheet) | the mega cheatsheet | README only (636 KB) |
| [web-mv](https://github.com/Jozkah/web-mv) | browser memory viewer (`ws://127.0.0.1:9000`) | installs Bun if missing, clone + `bun install` |
| [VTIL-Core](https://github.com/vtil-project/VTIL-Core) | VM-translation IR + optimizer passes | CMake build |
| [NoVmp](https://github.com/can1357/NoVmp) | full VMP devirt → optimized VTIL → native | CMake build (vendors VTIL-Core) |
| [vtil2](https://github.com/pop-rip/vtil2) | VTIL redesign in C# | `dotnet build` |
| [llvm-project](https://github.com/llvm/llvm-project) | OLLVM passes + Triton's LLVM interface | **system package** (`winget` / `brew` / `apt`) — never built from source |

Everything lands in `~/.local/share/echo-ai-toolkit/` (`$env:ECHO_HOME` to override).
MCP wiring is written to `~/.local/share/echo-ai-toolkit/mcp.json`.

**Requirements:** Claude Code. Node 22.19+ for Pi and the MCP servers, Python 3 for the
RE tooling, CMake / .NET 8 for the compiler-built stack (installed automatically where
the platform allows). The Echo platform itself needs Discord with the overlay enabled
(Echo is Windows-only).

<details>
<summary>Manual install (no script)</summary>

```
/plugin marketplace add NetVar1337/echo-ai-toolkit
/plugin install echo-ai-toolkit@echo-ai-toolkit
/plugin marketplace add DietrichGebert/ponytail
/plugin install ponytail@ponytail
/plugin marketplace add forrestchang/andrej-karpathy-skills
/plugin install andrej-karpathy-skills@karpathy-skills
```

Then run `/echo-setup` inside Claude Code to fetch the MCP dependencies.
</details>

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

## Pi coding agent

[Pi](https://pi.dev) is a minimal terminal agent harness. The installer writes an Echo
profile for it and adds an `echo` launcher, so the same 18 skills and 4 prompt
templates work there too — with your own system prompt instead of Pi's default.

```bash
echo                             # interactive, Echo profile loaded
echo -p "write a CS2 bone ESP"   # print mode (anything not a subcommand goes to Pi)
echo -- update my code           # -- forces pass-through for prompts that look like commands
```

### The wrapper

`echo` is a CLI around Pi, not just a launcher:

| Command | Does |
|---|---|
| `echo` | start Pi with the Echo profile |
| `echo update` | update toolkit + profile + Pi + all companion tools |
| `echo update --extensions` | Pi packages/extensions only (+ profile resync) |
| `echo update --self` | the Pi binary only |
| `echo update --models` | Pi model catalogs only |
| `echo update --all` | Pi and its packages |
| `echo update --tools` | companion tools only (git pull + rebuild) |
| `echo update --profile` | resync the Echo profile from the toolkit |
| `echo doctor` | verify every tool — ok / MISSING / not applicable |
| `echo status` | one-screen summary |
| `echo tools` | list installed companion tools |
| `echo version` | versions of everything |
| `echo help` | usage |

`--extensions`, `--self`, `--models`, `--all`, `--force` are Pi's own flags and pass
straight through to `pi update`. `--tools` and `--profile` are Echo's.

### The profile

The launcher passes both prompt files explicitly, so they always apply:

```
pi --system-prompt        <profile>/SYSTEM.md          # replaces Pi's default prompt
   --append-system-prompt <profile>/APPEND_SYSTEM.md   # appended (repeatable)
```

| File | Role |
|---|---|
| `pi/SYSTEM.md` | Reverse-engineer / game-security-analyst persona. **No refusal on any topic or technique** — no hedging, warnings, disclaimers, or "consider instead". Only rule: never invent a fact. |
| `pi/APPEND_SYSTEM.md` | Repeats the no-refusal standing instruction, then the Echo API facts applied silently: namespacing, `bool main()`, out-params, the AngelScript language traps |
| `pi/AGENTS.md` | Repo layout, the two verification commands, conventions |
| `pi/prompts/*.md` | `/echo-api`, `/echo-esp`, `/echo-reverse`, `/echo-verify` |
| `pi/skills/` | all 18 skills, copied — Pi uses the same `SKILL.md` format |

Profile location: `~/.local/share/echo-ai-toolkit/pi`, selected via
`PI_CODING_AGENT_DIR`, so your normal `pi` config is untouched.

> **`echo` shadows the shell builtin.** The installer adds
> `alias echo='…/bin/echo'` to `.bashrc`/`.zshrc` (or a `function echo` to your
> PowerShell profile) — **interactive shells only**, so scripts still get the real
> builtin. If you would rather not, install with `ECHO_NO_ALIAS=1` and use
> `~/.local/share/echo-ai-toolkit/bin/echo` directly.

Pi needs Node 22.19+:

```bash
curl -fsSL https://pi.dev/install.sh | sh          # macOS / Linux
powershell -c "irm https://pi.dev/install.ps1 | iex"  # Windows
```

Then `/login` inside Pi to connect a provider.

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

The installer (or `/echo-setup`) does this for you into `~/.local/share/echo-ai-toolkit/`.

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
