<p align="center">
  <img src="https://img.shields.io/github/actions/workflow/status/NetVar1337/echo-ai-toolkit/validate.yml?branch=main&label=CI&style=flat-square" alt="CI">
  <img src="https://img.shields.io/badge/version-0.5.0-blue?style=flat-square" alt="version">
  <img src="https://img.shields.io/badge/agents-12-blueviolet?style=flat-square" alt="agents">
  <img src="https://img.shields.io/badge/skills-18-blueviolet?style=flat-square" alt="skills">
  <img src="https://img.shields.io/badge/templates-15-blueviolet?style=flat-square" alt="templates">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT">
</p>

<h1 align="center">echo-ai-toolkit</h1>

<p align="center">
  AI development toolkit for the <a href="https://echo-23.gitbook.io/angel"><strong>Echo Universal API</strong></a><br>
  12 specialist agents · 18 skills · 15 runnable templates · 5 MCP servers · 17 companion tools
</p>

<p align="center">
  <a href="#-install">Install</a> ·
  <a href="#-use-it">Use it</a> ·
  <a href="#-agents-12">Agents</a> ·
  <a href="#-skills-18">Skills</a> ·
  <a href="#-templates-15">Templates</a> ·
  <a href="#-pi-coding-agent">Pi</a> ·
  <a href="#-integrations">Integrations</a>
</p>

---

> **Every API call in this repo is verified against the live Echo docs.** The real API is namespaced:
> `process::read_uint64()`, `render::draw_box()`, `ui::add_checkbox()`.
> If a call isn't in [`reference/api.md`](reference/api.md) it doesn't exist — CI enforces this.

---

## ⚡ Install

One command installs everything: plugin, all agents, all skills, all MCP servers, all 17 companion tools, the Pi profile, and the `echo` CLI.

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/NetVar1337/echo-ai-toolkit/main/install.sh | bash
```

**Windows (PowerShell)**
```powershell
# Windows
irm https://raw.githubusercontent.com/NetVar1337/echo-ai-toolkit/main/install.ps1 | iex
```

Safe to re-run — every step is idempotent. Verify your install at any time:
```bash
echo doctor   # prints ok / MISSING / not applicable for every tool
```

<details>
<summary><strong>Manual install (no script)</strong></summary>

```
/plugin marketplace add NetVar1337/echo-ai-toolkit
/plugin install echo-ai-toolkit@echo-ai-toolkit
/plugin install ponytail@echo-ai-toolkit
/plugin install andrej-karpathy-skills@echo-ai-toolkit
```

Then run `/echo-setup` inside Claude Code to fetch the MCP dependencies.

</details>

<details>
<summary><strong>Project install (no plugin, just git clone)</strong></summary>

```bash
git clone https://github.com/NetVar1337/echo-ai-toolkit
cd echo-ai-toolkit
claude
```

Project installs read `CLAUDE.md` and `agents/*.md` directly. The plugin install adds slash commands, keyword auto-routing, and a side panel on top.

</details>

### What lands

| | Count | Items |
|:---|:---:|:---|
| 🤖 Agents | 12 | `echo-dev` `-esp` `-aimbot` `-triggerbot` `-radar` `-loot` `-memory` `-anticheat` `-sdk` `-reverse` `-config` `-scripts` |
| 📚 Skills | 18 | Copied into the Pi profile — same `SKILL.md` format |
| 📄 Templates | 15 | Runnable `.as` files — copy to `%AppData%\Roaming\scripts\` |
| 🔌 MCP servers | 5 | `gamehacking` · `rea` · `angel-menu` · `radare2` · `ida` |
| 🧰 Companion tools | 18 | Full list below (now includes **Signature Doctor**) |
| 🧩 Plugins | 3 | `echo-ai-toolkit` · `ponytail` · `andrej-karpathy-skills` |

> **Expected disk size: ~22 GB** (almost all is `mcp-gamehacking` — 18 GB of skills in the working tree).
> GitHub shows 3.1 GB because that is the *compressed git* size.

### Reduce install size

| Env flag | Effect |
|:---|:---|
| `ECHO_SKIP_GAMEHACKING=1` | Skip mcp-gamehacking — drops to ~600 MB |
| `ECHO_SKIP_MCP=1` | Skip every MCP build |
| `ECHO_TIER=standard` | Skip compiler-built stack (NoVmp, VTIL-Core, vtil2, LLVM, web-mv) |
| `ECHO_TIER=minimal` | Plugin + MCP servers only |
| `ECHO_NO_ALIAS=1` | Do not add the `echo` shell alias |

```bash
# lean install — same agents / skills / templates, minus the 21 GB skills library
ECHO_SKIP_GAMEHACKING=1 bash install.sh
```

A tool whose prerequisite cannot be satisfied is **skipped with a reason**, never a hard failure.

### 📦 Vendored, not fetched

Every tool, plugin, binary and reference doc above **lives in this repository** under
[`vendor/`](vendor/) — 272 MB, 3 700 files, each recorded by sha256 in `vendor/MANIFEST.json` along
with its upstream repo, commit and license. A renamed, compromised or deleted upstream cannot
change what you install.

| | Before | Now |
|:---|:---|:---|
| Companion tool sources | 9 × `git clone` at install | `vendor/tools/`, `vendor/mcp/` |
| Release binaries | 3 × download from upstream | `vendor/bin/`, sha256-checked at install |
| Reference READMEs | 2 × raw.githubusercontent.com | `vendor/docs/` |
| Companion plugins | 2 third-party marketplaces | `vendor/plugins/`, this repo's marketplace |
| MCP server deps | `npm install` | `npm ci` against vendored lockfiles |
| Python packages | unpinned `pip install` | `--require-hashes` against `vendor/python/requirements.lock` |
| `mcp-gamehacking` | 3.1 GB clone from upstream | split archive in **this** repo's releases, sha256 per part |

The installer verifies each vendored file against `vendor/CHECKSUMS.sha256`; a modified binary is
refused, not installed. `mcp-gamehacking` is the one thing not in git — its tree is 18 GB (3.1 GB
packed), GitHub blocks files over 100 MB, and every CI job would pay for the checkout — so it ships
as a 3-part archive on this repo's releases, pinned by sha256 in `vendor/ARCHIVES` and rebuilt by
`scripts/vendor_archive.sh`.

```bash
echo update --tools   # restore every tool from vendor/ and rebuild
echo update --lock    # move the pins in tools.lock to current upstream heads
scripts/vendor_refresh.sh   # maintainers: re-fetch vendor/ at the new pins
```

Three things still touch the network, all pinned: `npm ci` and `pip --require-hashes` (the registry
cannot substitute a package without breaking the hash), and the optional Bun/Pi binaries, whose
versions are pinned in `tools.lock`.

<details>
<summary><strong>Everything that gets installed</strong></summary>

| Tool | What it gives you | How it arrives |
|:---|:---|:---|
| **echo-ai-toolkit** | 12 agents, 18 skills, 15 templates | Claude Code plugin |
| [mcp-gamehacking](https://github.com/1llu50ry/mcp-gamehacking) | 4 100+ skills, 75 agents, 19+ MCP tools | vendored archive in this repo's releases + build |
| [angel-menu-mcp](https://github.com/Jozkah/angel-menu-mcp) | Toggle the Echo overlay menu from Claude | `vendor/mcp/`, `npm ci` |
| [rea](https://github.com/morluto/rea) | Static binary analysis (IL2CPP, APK, WASM, firmware) | `vendor/npm/`, `npm ci` |
| radare2 MCP | Disasm, decompile, search, analysis | `r2pm -r r2mcp` |
| IDA MCP | Decompile, rename, xref, structs | `uvx ida-mcp` (IDA 9.4+ with idalib) |
| [Signature Doctor](https://github.com/b4rzY/Signature-Doctor) | Offset & signature health dashboard — `http://127.0.0.1:3210` | `vendor/tools/`, `npm ci` |
| [ponytail](https://github.com/DietrichGebert/ponytail) | Lazy-senior-dev discipline | vendored, this repo's marketplace |
| [andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) | Coding-discipline guidelines | vendored, this repo's marketplace |
| [as_bundler](https://github.com/sinistercodes/as_bundler) | AngelScript bundler / validator / obfuscator | `vendor/bin/`, sha256-checked |
| [echo-esp-preview](https://github.com/speedsunderscore/echo-esp-preview) | `g_preview` + `esp_layout` drag-to-arrange ESP | `vendor/scripts/` |
| [echo-angelscript-lsp](https://github.com/speedsunderscore/echo-angelscript-lsp) | VS Code completion + hover for ~1 900 Echo symbols | `vendor/bin/`, then `code --install-extension` |
| [Triton](https://github.com/JonathanSalwan/Triton) | Symbolic execution + taint analysis | `--require-hashes` against `vendor/python/requirements.lock` |
| [VMProtect-devirtualization](https://github.com/JonathanSalwan/VMProtect-devirtualization) | Triton-based VMP devirt scripts | `vendor/tools/` |
| [vmp-lazy-unpack](https://github.com/x86rc/vmp-lazy-unpack) | VMP section unpacker + import resolver | `vendor/tools/`, `pip -e --no-deps` |
| [awesome-game-security](https://github.com/gmh5225/awesome-game-security) | 4 000+ curated resources | `vendor/docs/` |
| [gamehacking-cheatsheet](https://github.com/ridpath/gamehacking-cheatsheet) | The mega cheatsheet | `vendor/docs/` (275 KB) |
| [web-mv](https://github.com/Jozkah/web-mv) | Browser memory viewer (`ws://127.0.0.1:9000`) | `vendor/tools/`, `bun install --frozen-lockfile` |
| [VTIL-Core](https://github.com/vtil-project/VTIL-Core) | VM-translation IR + optimizer passes | `vendor/tools/`, CMake build |
| [NoVmp](https://github.com/can1357/NoVmp) | Full VMP devirt → optimized VTIL → native | `vendor/tools/`, CMake build |
| [vtil2](https://github.com/pop-rip/vtil2) | VTIL redesign in C# | `vendor/tools/`, `dotnet build` |
| LLVM | OLLVM passes + Triton's LLVM interface | System package (`winget` / `brew` / `apt`) |

Everything lands in `~/.local/share/echo-ai-toolkit/` (override with `$ECHO_HOME`).
MCP servers are registered directly in Claude Code via `claude mcp add --scope user`.

**Requirements:** Claude Code · Node 22.19+ (Pi + MCP servers) · Python 3 (RE tooling) · CMake / .NET 8 (compiler stack, auto-installed where the platform allows). Echo itself requires Discord with overlay enabled — Windows only.

</details>

---

## 🚀 Use it

```
/echo-help        # list all 12 agents
/echo-esp         # load ESP context
/echo-reverse     # load reverse-engineering context
/echo-tier        # show or set the install tier
/echo-setup       # run the installer from inside Claude Code
```

Or just describe your task — keywords route automatically:

| You say... | Routes to |
|:---|:---|
| "draw bones on screen" | `echo-esp` |
| "aimbot with FOV filter" | `echo-aimbot` |
| "triggerbot with shot delay" | `echo-triggerbot` |
| "minimap radar overlay" | `echo-radar` |
| "loot ESP for dropped items" | `echo-loot` |
| "find_signature for entity list" | `echo-memory` |
| "Dumper-7 GObjects traversal" | `echo-sdk` |
| "decompile with IDA / radare2" | `echo-reverse` |
| "persist config over HTTP" | `echo-config` |
| "give me a runnable example" | `echo-scripts` |

To open an agent directly:
```
Agent: echo-esp — write a CS2 cornered-box bone ESP
```

---

## 🤖 Agents (12)

| Agent | Use when you need... |
|:---|:---|
| `echo-dev` | General scripting — lifecycle, threading, menu, networking, SIMD, utilities |
| `echo-esp` | Boxes, skeletons, health bars, name tags, W2S for Source 2 / Unreal / Unity / IW |
| `echo-aimbot` | Target selection, FOV filter, smoothing, velocity prediction, recoil control |
| `echo-triggerbot` | Crosshair detection, shot delay variance, burst control, per-hitbox targeting |
| `echo-radar` | 2D radar/minimap — world→radar transform, entity dots, edge indicators |
| `echo-loot` | Item/loot ESP — entity class filtering, item tiers, dropped-weapon tracking |
| `echo-memory` | Pointer chains, struct recovery, IDA pattern scan, Unicorn emulation, Zydis xref |
| `echo-anticheat` | What integrity systems check and safe coding patterns around them |
| `echo-sdk` | Dumper-7 SDK, Source 2 schema, Unity IL2CPP, cached bone reads, FName / VGK |
| `echo-reverse` | Obfuscation classification, REA MCP, binary diff, OLLVM lift, VMP devirt |
| `echo-config` | Config persistence, HTTP, filesystem, WebSocket, JSON, hash_map / hash_set |
| `echo-scripts` | Complete runnable scripts — CS2 ESP, UE4 aimbot, Unity loot scanner |

---

## 📚 Skills (18)

Reference documents loaded on demand. Also copied into the Pi profile.

| Skill | Contents |
|:---|:---|
| `angelscript-patterns` | Mutex entity buffer, thread-safe tick/render, safe deref chain, W2S null check |
| `angelscript-types` | `@` handles, `array<T>`, `cast<T>`, closures, no-exceptions, common LLM mistakes |
| `echo-anti-patterns` | Wrong code → correct code, side by side |
| `echo-workflow` | Multi-agent orchestration: shared_snapshot hub, thread rate table, startup sequence |
| `echo-ecosystem` | External tooling: web-mv, angel-menu-mcp, esp-preview, as_bundler, SuperGhidra, NoVmp |
| `anti-cheat-systems` | What VAC / EAC / BattlEye / Vanguard / Ricochet check at a high level |
| `game-hacking-techniques` | Memory access models, hook types, entity list patterns, ESP/aimbot math |
| `game-engine-resources` | Source 2, Unreal, Unity, IW engine internals — structs, offsets, W2S, bone formats |
| `gamehacking-cheatsheet` | Topic → Echo API map + mcp-gamehacking query per technique |
| `awesome-game-security` | Per-category resource map from [gmh5225/awesome-game-security](https://github.com/gmh5225/awesome-game-security) |
| `dumper7-sdk` | GObjects traversal, FName resolution, VGK decrypt, offset update workflow |
| `omath-math` | W2S per engine, projectile prediction, rotation helpers |
| `reverse-workflow` | Static → runtime RE pipeline; tool decision tree, sig generation, Unicorn OLLVM trace |
| `reverse-engineering-tools` | Debuggers, disassemblers, Frida, Cheat Engine plugins, dumpers, pattern tools |
| `devirt-workflow` | 6-step VMP devirt: vmp-lazy-unpack OEP → Triton → NoVmp VTIL → LLVM passes |
| `offset-update-workflow` | Post-patch offset recovery: binary diff, function reacquisition, pattern update |
| `karpathy-coding` | Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution |
| `ponytail` | Minimum code, no unrequested abstractions, the shortcut-comment convention |

---

## 📄 Templates (15)

Copy any `.as` file into `%AppData%\Roaming\scripts\` and reopen the in-game menu. No compile step needed.

| Template | Demonstrates |
|:---|:---|
| `basic.as` | Minimal `main()` + `on_unload()` |
| `render.as` | ESP box + `on_render` hook |
| `menu.as` | All menu element types with config persistence |
| `memory.as` | Process attach, IDA pattern scan, RIP-relative resolve, tick loop |
| `esp-bones.as` | Full CS2 ESP: cornered boxes, skeleton, health bar, distance labels |
| `aimbot.as` | Full CS2 aimbot: target selection, smoothing, prediction, recoil, triggerbot |
| `misc.as` | Bunny hop, flash reduction, radar, spectator list |
| `ue5-sdk.as` | UE5 ESP from Dumper-7 offsets: GWorld traversal, FTransform, cornered box |
| `unity-il2cpp.as` | Unity IL2CPP ESP: camera matrix, entity list walk, health bar |
| `valorant.as` | Valorant ESP: VGK-aware external, GObjects decrypt, UE4 TUObjectArray |
| `fortnite.as` | Fortnite ESP: GWorld traversal, 12-bone skeleton, HP + shield bars |
| `radar.as` | 2D circular radar panel — entity dots, edge indicators, rotating/north-up |
| `loot.as` | CS2 dropped-weapon ESP — item tiers, distance-gated labels, sorted loot panel |
| `esp-preview.as` | `esp_layout` namespace drop-in preview helper |
| `web-mv.as` | web-mv HTTP memory viewer endpoint |

> ⚠️ Game-specific offsets and patterns are **illustrative placeholders**. Verify per patch and per game version — see `skills/offset-update-workflow`.

---

## 🖥 Pi coding agent

[Pi](https://pi.dev) is a minimal terminal agent harness. The installer writes an Echo profile and adds an `echo` launcher — the same 18 skills and 4 prompt templates work there with your own system prompt.

```bash
echo                             # interactive — Echo profile loaded
echo -p "write a CS2 bone ESP"   # print mode
echo -- update my code           # -- forces pass-through for prompts that look like commands
```

### Commands

| Command | Does |
|:---|:---|
| `echo` | Start Pi with the Echo profile |
| `echo update` | Update toolkit + profile + Pi + all companion tools |
| `echo update --extensions` | Pi packages/extensions only |
| `echo update --self` | Pi binary only |
| `echo update --models` | Pi model catalogs only |
| `echo update --all` | Pi and all its packages |
| `echo update --tools` | Companion tools only (git pull + rebuild) |
| `echo update --profile` | Resync the Echo profile from the toolkit |
| `echo doctor` | Verify every tool — ok / MISSING / not applicable |
| `echo status` | One-screen summary |
| `echo tools` | List installed companion tools |
| `echo version` | Versions of everything |
| `echo help` | Usage |

### Profile files

| File | Role |
|:---|:---|
| `pi/SYSTEM.md` | Reverse-engineer / game-security-analyst persona. No hedging, no disclaimers. |
| `pi/APPEND_SYSTEM.md` | Echo API facts applied silently: namespacing, `bool main()`, out-params, AS traps |
| `pi/AGENTS.md` | Repo layout, verification commands, conventions |
| `pi/prompts/*.md` | `/echo-api`, `/echo-esp`, `/echo-reverse`, `/echo-verify` |
| `pi/skills/` | All 18 skills — same `SKILL.md` format |

Profile location: `~/.local/share/echo-ai-toolkit/pi`, selected via `PI_CODING_AGENT_DIR`.

> **`echo` shadows the shell builtin** in interactive sessions only — scripts still get the real builtin.
> Install with `ECHO_NO_ALIAS=1` to skip the alias entirely.

<details>
<summary><strong>Install Pi</strong></summary>

```bash
# macOS / Linux
curl -fsSL https://pi.dev/install.sh | sh

# Windows
powershell -c "irm https://pi.dev/install.ps1 | iex"
```

Requires Node 22.19+. Then run `/login` inside Pi to connect a provider.

</details>

---

## 📐 Signature Doctor

[Signature Doctor](https://github.com/b4rzY/Signature-Doctor) is a local offset and signature health dashboard — run it to check whether your sigs still resolve after a patch.

```bash
# after install, launch with:
node ~/.local/share/echo-ai-toolkit/signature-doctor/server/index.mjs
# → http://127.0.0.1:3210
```

It speaks the same WebSocket bridge protocol as `web-mv`. Pass `WEB_MV_URL=http://127.0.0.1:<port>/rpc` if you prefer to route through an existing relay.

---

## 🔗 Integrations

### MCP servers (auto-registered)

The installer runs `claude mcp add --scope user` for each server — no manual wiring needed.

| MCP | What it provides | Status |
|:---|:---|:---|
| `gamehacking` | 4 100+ skills, 75 agents, 19+ tools | clone + build |
| `rea` | Static binary analysis: IL2CPP, APK, WASM, firmware | `npx` on first connect |
| `angel-menu` | Toggle the Echo overlay menu from Claude | clone + build |
| `radare2` | Disasm, decompile, search, analysis | needs `r2pm -Uci r2mcp` |
| `ida` | Decompile, rename, xref, structs | needs IDA 9.4+ with idalib |

### Development tooling

| Tool | Purpose |
|:---|:---|
| [echo-angelscript-lsp](https://github.com/speedsunderscore/echo-angelscript-lsp) | VS Code LSP: ~1 900 Echo symbols, autocompletion, hover docs |
| [echo-esp-preview](https://github.com/speedsunderscore/echo-esp-preview) | `esp_layout` drop-in ESP layout helper |
| [as_bundler](https://github.com/sinistercodes/as_bundler) | AngelScript bundler, validator, obfuscator, string scrambler |
| [web-mv](https://github.com/Jozkah/web-mv) | Browser-based memory viewer via Echo agent API |
| [Signature Doctor](https://github.com/b4rzY/Signature-Doctor) | Offset / signature health dashboard at `http://127.0.0.1:3210` |
| [angel-menu-mcp](https://github.com/Jozkah/angel-menu-mcp) | MCP — toggle the overlay menu from Claude |

### SDK generation

| Tool | Purpose |
|:---|:---|
| [Dumper-7](https://github.com/Encryqed/Dumper-7) | UE4/UE5 SDK generator — inject to get CppSDK with all offsets |
| [Dumper-7-VGK](https://github.com/sinistercodes/Dumper-7-VGK) | Dumper-7 + Valorant VGK support |

### Binary analysis MCPs

| MCP | Install |
|:---|:---|
| [radare2-mcp](https://github.com/radareorg/radare2-mcp) | `r2pm -Uci r2mcp` |
| [ida-mcp](https://github.com/HexRaysSA/ida-mcp) | `claude plugin install ida-mcp@HexRaysSA` |
| [SuperGhidra](https://github.com/yuatemycat/SuperGhidra) | Python tools + MCP daemon at `127.0.0.1:5073` |

### VMP / devirtualization stack

[NoVmp](https://github.com/can1357/NoVmp) ·
[VTIL-Core](https://github.com/vtil-project/VTIL-Core) ·
[vtil2](https://github.com/pop-rip/vtil2) ·
[Triton](https://github.com/JonathanSalwan/Triton) ·
[VMProtect-devirtualization](https://github.com/JonathanSalwan/VMProtect-devirtualization) ·
[vmp-lazy-unpack](https://github.com/x86rc/vmp-lazy-unpack)

---

## 📖 Reference

| Doc | Contents |
|:---|:---|
| [`reference/api.md`](reference/api.md) | Complete API — 22 namespaces, every signature, return semantics, caveats |
| [`llms.txt`](llms.txt) | Single-file context bundle for GPT-4o, Gemini, local models — paste as context |
| [`prompts/system-prompt.md`](prompts/system-prompt.md) | Portable system prompt for non-Claude clients |
| [`reference/offsets.md`](reference/offsets.md) | Offset / pattern reference (placeholders — verify per patch) |
| [Echo docs](https://echo-23.gitbook.io/angel) | Live authoritative API reference |
| [Echo LLM reference](https://echo-23.gitbook.io/angel/llms-full.txt) | LLM-optimised single-page dump |
| [awesome-game-security](https://github.com/gmh5225/awesome-game-security) | 4 000+ curated game-security resources |
| [gamehacking-cheatsheet](https://github.com/ridpath/gamehacking-cheatsheet) | Technique → implementation cheatsheet |

---

## ✅ How this repo is verified

Five guards, all in CI:

1. **API conformance** — every `ns::fn(` in the docs and templates exists in the live Echo API.
2. **Compile stub** — `scripts/angelscript/echo_stub.as` declares every documented symbol and
   nothing else, in both directions. This is what caught `sleep()`.
3. **AngelScript compile** — all 15 templates compile against AngelScript 2.38.0; every doc code
   block is grammar-checked.
4. **Plugin + hooks** — `claude plugin validate` and the hook test suite.
5. **Vendor** — `vendor/` matches its manifest, every expected tree is present, and the installers
   reach nothing but this repo and pinned registries.

CI runs 9 jobs: `json`, `api`, `drift`, `vendor`, `layout`, `angelscript`, `pi-profile`, `plugin`,
`installers`. `drift` runs weekly, re-fetches the live docs, and opens an issue when they no longer
match what the repo teaches.

---

## 🗂 Repo layout

```
agents/*.md                12 agent definitions (loaded as system prompts)
skills/<name>/SKILL.md     18 skills (name + description frontmatter)
templates/*.as             15 runnable AngelScript templates
reference/                 complete API reference + correction contract
vendor/                    every tool, plugin, binary and doc the installer installs
  MANIFEST.json            sha256 + upstream + license for every vendored file
  CHECKSUMS.sha256         the same, in sha256sum -c form (installer checks)
  ARCHIVES                 split release archive for mcp-gamehacking
tools.lock                 pin record: refs, versions, hashes
scripts/echo.mjs           `echo update|doctor|status|tools|version` (one implementation)
scripts/echo-*.sh|ps1      thin shims that exec echo.mjs
scripts/check_api.py       API conformance guard (docs + compile stub)
scripts/build_api_index.py docs -> machine-readable API index
scripts/check_angelscript.py + scripts/angelscript/   compile + grammar guard
scripts/vendor_manifest.py --write / --check
scripts/vendor_refresh.sh  re-fetch vendor/ at the pins
scripts/vendor_archive.sh  rebuild the mcp-gamehacking archive
install.sh | install.ps1   the installers
hooks/register.tsx         slash commands, keyword routing, side panel
llms.txt                   single-file LLM context bundle
```

---

## 🤝 Contributing

Add a skill under `skills/<name>/SKILL.md` or an agent under `agents/<name>.md`.

- Every skill and agent needs YAML frontmatter: `name`, `description`
- Every agent needs a matching slash command in `hooks/register.tsx`
- Keep agent files self-contained — they load as system prompts, no external lookups

CI checks layout, frontmatter, API conformance, and hook registration automatically:

```bash
curl -fsSL https://echo-23.gitbook.io/angel/llms-full.txt -o /tmp/echo-llms-full.txt
python3 scripts/build_api_index.py /tmp/echo-llms-full.txt -o /tmp/echo-api-index.json
python3 scripts/check_api.py --root . --api-index /tmp/echo-api-index.json
python3 scripts/check_api.py --root . --api-index /tmp/echo-api-index.json \
  --stub scripts/angelscript/echo_stub.as
./scripts/angelscript/build.sh
python3 scripts/check_angelscript.py --root . --checker "$PWD/scripts/angelscript/check" --workdir /tmp
claude plugin validate . && claude plugin test .
```

When Echo ships a docs change, `python3 scripts/build_api_index.py` rebuilds the index and the
stub check names every symbol you need to add to `scripts/angelscript/echo_stub.as`.

---

## License

MIT — see [LICENSE](LICENSE).
