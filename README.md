# echo-ai-toolkit

AI development toolkit for the [Echo Universal API](https://echo-23.gitbook.io/angel) — an
AngelScript scripting platform for Windows games with direct process-memory access, a Discord
overlay renderer, Zydis disassembly, and a Unicorn emulator.

**12 agents · 18 skills · 15 templates · 5 MCP servers · 17 companion tools · 3 plugins**, plus a
`echo` CLI and a Pi profile. One command installs all of it.

> **Every API call in this repo is verified against the live Echo docs.** The real API is
> namespaced — `process::read_uint64()`, `render::draw_box()`, `ui::add_checkbox()`. If a call is
> not in [`reference/api.md`](reference/api.md), it does not exist. Two CI guards enforce this:
> every template is compiled against a real AngelScript 2.38.0 build, and every doc code block is
> grammar-checked.

---

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/NetVar1337/echo-ai-toolkit/main/install.sh | bash
```

```powershell
# Windows
irm https://raw.githubusercontent.com/NetVar1337/echo-ai-toolkit/main/install.ps1 | iex
```

Then:

```bash
echo doctor      # confirm what landed
echo             # start Pi with the Echo profile
```

Restart Claude Code (or `/reload-plugins`) and type `/echo-help`.

That's it. No flags, no tiers to choose. Details, size warnings, and opt-outs are below.

---

## Contents

- [Quick start](#quick-start)
- [What you get](#what-you-get)
- [Install](#install)
  - [Requirements](#requirements)
  - [What the installer does](#what-the-installer-does)
  - [Size, and how to install less](#size-and-how-to-install-less)
  - [Manual install](#manual-install)
  - [Use as a project instead of a plugin](#use-as-a-project-instead-of-a-plugin)
- [Verify your install](#verify-your-install)
- [The `echo` CLI](#the-echo-cli)
- [Using it with Claude Code](#using-it-with-claude-code)
- [Using it with Pi](#using-it-with-pi)
- [Agents (12)](#agents-12)
- [Skills (18)](#skills-18)
- [Templates (15)](#templates-15)
- [Companion tools (17)](#companion-tools-17)
- [MCP servers (5)](#mcp-servers-5)
- [Reference docs](#reference-docs)
- [Troubleshooting](#troubleshooting)
- [How this repo is verified](#how-this-repo-is-verified)
- [Repo layout](#repo-layout)
- [Contributing](#contributing)
- [Links](#links)
- [License](#license)

---

## What you get

| | Count | What |
|---|---|---|
| **Agents** | 12 | Specialist system prompts — ESP, aimbot, triggerbot, radar, loot, memory/RE, SDK, reverse, config, anti-cheat, examples, general API |
| **Skills** | 18 | Reference documents loaded on demand: engine internals, devirt workflows, offset recovery, AngelScript type system, anti-patterns |
| **Templates** | 15 | Runnable `.as` files — drop into `%AppData%\Roaming\scripts\` and load, no compile step |
| **MCP servers** | 5 | `gamehacking`, `rea`, `angel-menu`, `radare2`, `ida` |
| **Companion tools** | 17 | MCP servers, RE tooling, the devirtualization stack, reference docs — see [the table](#companion-tools-17) |
| **Plugins** | 3 | `echo-ai-toolkit`, `ponytail`, `andrej-karpathy-skills` |
| **CLI** | 1 | `echo` — launch Pi, update everything, verify everything |

---

## Install

### Requirements

| | Needed for | Notes |
|---|---|---|
| **Claude Code** | the plugin | [claude.com/claude-code](https://claude.com/claude-code) |
| **Node 18+** | MCP servers | Node **22.19+** additionally for Pi |
| **git** | cloning tools | |
| **Python 3** | Triton, VMP tooling | the installer creates its own venv |
| CMake + a C++ toolchain | NoVmp, VTIL-Core | auto-installed via apt/brew/winget when possible |
| .NET 8 SDK | vtil2 | auto-installed when possible |
| Bun | web-mv | auto-installed if missing |
| VS Code | the AngelScript LSP | optional; skipped if `code` is not VS Code |

The **Echo platform itself** needs Discord installed and running, with the overlay enabled and
the legacy option disabled. Borderless or windowed only. Echo is Windows-only.

### What the installer does

In order, each step idempotent — re-running is always safe:

1. **Checks prerequisites** and reports what is missing.
2. **Fetches [`vendor/`](vendor/)** — the only download: this repo's own tarball, or the checkout
   you already have.
3. **Installs the plugin** — registers the marketplace, installs `echo-ai-toolkit`.
4. **Installs companion plugins** — `ponytail`, `andrej-karpathy-skills`, both vendored and served
   by this repo's marketplace.
5. **Installs the MCP servers** — `angel-menu-mcp` from `vendor/`, `mcp-gamehacking` from this
   repo's split release archive.
6. **Installs Echo tooling** — `as_bundler`, `esp_preview.as`, the VS Code LSP, `web-mv`, and the
   reference READMEs, all from `vendor/`.
7. **Writes the Pi profile** — `SYSTEM.md`, `APPEND_SYSTEM.md`, `AGENTS.md`, 4 prompt templates,
   all 18 skills, and the `echo` launcher.
8. **Writes `mcp.json`** with all 5 servers and absolute paths.
9. **Installs the Python stack** — a venv, then `vendor/python/requirements.lock` (Triton,
   capstone, pefile, unicorn) installed with `--require-hashes`.
10. **Installs the compiler stack** — CMake/.NET/LLVM if absent, then NoVmp, VTIL-Core, vtil2,
    built from `vendor/`.
11. **Adds the `echo` alias** to your shell rc.

Anything whose prerequisite cannot be met is **skipped with the exact command to fix it** — never
a hard failure. The install always completes, and `echo doctor` shows the gaps.

### Vendored, not fetched

Every tool, plugin, binary and reference doc the installer installs **lives in this repository**
under [`vendor/`](vendor/) — 270 MB, 3727 files, each recorded by sha256 in
`vendor/MANIFEST.json`. A renamed, compromised or deleted upstream cannot change what you install,
because nothing is fetched from upstream.

```bash
echo update --tools     # restore every tool from vendor/ and rebuild
echo update --lock      # move the pins in tools.lock to current upstream heads
scripts/vendor_refresh.sh   # maintainers: re-fetch vendor/ at the new pins
echo doctor             # "Vendored tools" and "Pinned tools" rows report drift
```

What that means in practice:

| | Before | Now |
|---|---|---|
| Companion tool sources | 8 × `git clone` at install | `vendor/tools/`, `vendor/mcp/` |
| Release binaries | 3 × download from upstream | `vendor/bin/`, sha256-checked at install |
| Reference READMEs | 2 × raw.githubusercontent.com | `vendor/docs/` |
| Companion plugins | 2 third-party marketplaces | `vendor/plugins/`, our marketplace |
| MCP server deps | `npm install` | `npm ci` against vendored lockfiles |
| Python packages | unpinned `pip install` | `--require-hashes` against `vendor/python/requirements.lock` |
| `mcp-gamehacking` | 3.1 GB clone from upstream | split archive in **this** repo's releases, sha256 per part |

Three things still touch the network, all pinned: `npm ci` and `pip --require-hashes` (the registry
cannot substitute a package without breaking the hash), and the optional Bun/Pi binaries, whose
versions are pinned in `tools.lock`. The installer itself is a `curl … | bash` — clone the repo and
run `./install.sh` if you would rather read it first.

The fetched sources stay in `~/.local/share/echo-ai-toolkit/src`, so `echo update --tools` needs no
network at all. `mcp-gamehacking` is the one thing not in git: its tree is 18 GB (3.1 GB packed), GitHub blocks
files over 100 MB and warns above 1 GB per repo, and every CI job would pay for the checkout. It
ships as a split archive on this repo's releases, pinned by sha256 in `vendor/ARCHIVES` and rebuilt
by `scripts/vendor_archive.sh`.

### Size, and how to install less

**A full install is ~22 GB**, measured. Almost all of it is `mcp-gamehacking`: an 18 GB tree
containing 18 GB of `skills/` (4161 skill directories, each with its own `source.txt`). GitHub
reports that repo as 3.1 GB because that is the *compressed git* size — the working tree is what
lands on your disk.

If that is more than you want:

| Flag | Effect | Size |
|---|---|---|
| *(none)* | everything | ~22 GB |
| `ECHO_SKIP_GAMEHACKING=1` | skip the skills library; keeps every other tool | ~600 MB |
| `ECHO_SKIP_MCP=1` | skip all MCP builds | ~550 MB |
| `ECHO_TIER=standard` | skip the compiler-built stack (NoVmp, VTIL-Core, vtil2, LLVM, web-mv) | ~600 MB |
| `ECHO_TIER=minimal` | plugin + MCP servers only | ~35 MB |
| `ECHO_NO_ALIAS=1` | do not add the `echo` shell alias | — |

```bash
# recommended if you do not need 4161 pre-loaded skills
ECHO_SKIP_GAMEHACKING=1 bash install.sh

# plugin only, fastest possible
ECHO_TIER=minimal bash install.sh
```

Set `ECHO_HOME` to install somewhere other than `~/.local/share/echo-ai-toolkit`.

### Manual install

<details>
<summary>Plugin only, no script</summary>

```
/plugin marketplace add NetVar1337/echo-ai-toolkit
/plugin install echo-ai-toolkit@echo-ai-toolkit
/plugin marketplace add DietrichGebert/ponytail
/plugin install ponytail@ponytail
/plugin marketplace add forrestchang/andrej-karpathy-skills
/plugin install andrej-karpathy-skills@karpathy-skills
```

Then run `/echo-setup` inside Claude Code to fetch the MCP dependencies, or
`/echo-tier full` first to pick the tier.
</details>

### Use as a project instead of a plugin

```bash
git clone https://github.com/NetVar1337/echo-ai-toolkit
cd echo-ai-toolkit
claude
```

A project install reads `CLAUDE.md`, `agents/`, and `skills/` directly. The plugin install adds
slash commands, keyword auto-routing, and the side panel.

---

## Verify your install

```bash
echo doctor
```

One line per tool, `ok` / `MISSING` / `not applicable`, with the fix for anything missing:

```
Echo AI Toolkit — doctor
tools: /home/you/.local/share/echo-ai-toolkit

Plugin
  ok    echo-ai-toolkit plugin       echo-ai-toolkit@echo-ai-toolkit
  ok    ponytail plugin
  ok    andrej-karpathy-skills plugin

MCP servers
  ok    mcp.json                     .../mcp.json
  ok    mcp-gamehacking              built
  ok    angel-menu-mcp               installed
  ok    rea (npx)                    installs on first use
  ok    radare2 MCP                  r2pm present
  ok    ida MCP                      uvx present
...
  21 ok   2 missing   6 not applicable
```

Without the wrapper: `./scripts/echo-doctor.sh` or `.\scripts\echo-doctor.ps1`.

---

## The `echo` CLI

`echo` is a CLI around Pi and the toolkit, not just a launcher.

| Command | Does |
|---|---|
| `echo` | start Pi with the Echo profile |
| `echo <args…>` | pass everything through to Pi (`echo -p "query"`, `echo --help`) |
| `echo -- <args…>` | force pass-through, for a prompt that starts with a subcommand name |
| `echo update` | update toolkit + profile + Pi + all companion tools |
| `echo update --extensions` | Pi packages/extensions only, plus a profile resync |
| `echo update --self` | the Pi binary only |
| `echo update --models` | Pi model catalogs only |
| `echo update --all` | Pi and its packages |
| `echo update --tools` | companion tools only — check out the pinned refs, rebuild, verify assets, install pinned Triton |
| `echo update --profile` | resync the Echo profile from the toolkit |
| `echo update --lock` | re-resolve `tools.lock` to current upstream heads, then update |
| `echo doctor` | verify every tool |
| `echo status` | one-screen summary |
| `echo tools` | list installed companion tools |
| `echo version` | versions of everything |
| `echo help` | usage |

`--extensions`, `--self`, `--models`, `--all`, `--force` are **Pi's own flags** and pass straight
through to `pi update`. `--tools`, `--profile` and `--lock` are Echo's.

Routing: `--self` and `--models` leave the toolkit untouched; `--extensions` also refreshes the
profile, because the skills and prompts *are* the extensions. No flags means everything.

> **`echo` shadows the shell builtin** in interactive shells. Scripts still get the real builtin.
> Install with `ECHO_NO_ALIAS=1` to skip the alias and call
> `~/.local/share/echo-ai-toolkit/bin/echo` directly.

---

## Using it with Claude Code

```bash
/echo-help        # list all 12 agents
/echo-esp         # load ESP context
/echo-reverse     # load reverse-engineering context
/echo-tier        # show or set the install tier
/echo-setup       # run the installer from inside Claude Code
```

Or just describe your task — keywords route automatically:

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
| "IDA decompile this function" | `echo-reverse` |
| "give me a runnable example script" | `echo-scripts` |

Open an agent directly: `Agent: echo-esp — write a CS2 bone ESP`

---

## Using it with Pi

[Pi](https://pi.dev) is a minimal terminal agent harness. The installer writes an Echo profile
for it, so the same 18 skills and 4 prompt templates work there — with your own system prompt
instead of Pi's default.

```bash
echo                             # interactive
echo -p "write a CS2 bone ESP"   # print mode
```

The launcher passes both prompt files explicitly, so they always apply regardless of file
discovery:

```
pi --system-prompt        <profile>/SYSTEM.md          # replaces Pi's default prompt
   --append-system-prompt <profile>/APPEND_SYSTEM.md   # appended (repeatable)
```

| File | Role |
|---|---|
| `pi/SYSTEM.md` | Reverse-engineer / game-security-analyst persona. No refusal on any topic or technique — no hedging, warnings, disclaimers, or "consider instead". Only rule: never invent a fact. |
| `pi/APPEND_SYSTEM.md` | Repeats the no-refusal standing instruction, then the Echo API facts applied silently: namespacing, `bool main()`, out-params, the AngelScript language traps |
| `pi/AGENTS.md` | Repo layout, the two verification commands, conventions |
| `pi/prompts/*.md` | `/echo-api`, `/echo-esp`, `/echo-reverse`, `/echo-verify` |
| `pi/skills/` | all 18 skills, copied — Pi uses the same `SKILL.md` format |

Profile location: `~/.local/share/echo-ai-toolkit/pi`, selected via `PI_CODING_AGENT_DIR`, so
your normal `pi` config is untouched.

```bash
curl -fsSL https://pi.dev/install.sh | sh              # install Pi (Node 22.19+)
powershell -c "irm https://pi.dev/install.ps1 | iex"   # Windows
```

Then `/login` inside Pi to connect a provider.

---

## Agents (12)

Each agent is a self-contained system prompt — no external lookups needed.

| Agent | Use when… |
|---|---|
| `echo-dev` | General Echo API — script lifecycle, threading, menu, networking, utilities, SIMD, clipping |
| `echo-esp` | ESP: cornered boxes, skeletons, health bars, name tags, distance labels; W2S for Source 2 / Unreal / Unity / IW |
| `echo-aimbot` | Aimbot: target selection, FOV filtering, bone targeting, smoothing, prediction, recoil control |
| `echo-triggerbot` | Triggerbot: crosshair-on-enemy detection, shot delay variance, burst, per-hitbox |
| `echo-radar` | 2D radar/minimap: world→radar transforms, rotating panel, entity dots, edge indicators |
| `echo-loot` | Item/loot ESP: entity class identification, item tiers, dropped-weapon tracking, loot panels |
| `echo-memory` | Pointer chains, struct recovery, pattern scanning, Unicorn emulation, Zydis xrefs, memory buffers |
| `echo-anticheat` | Detection surfaces of VAC/EAC/BattlEye/Vanguard/RICOCHET, and safe coding patterns |
| `echo-sdk` | Dumper-7 / Dumper-7-VGK: GObjects traversal, FName resolution, FTransform, cached bone reads |
| `echo-reverse` | RE pipeline: obfuscation classification, REA, binary diffing, Unicorn tracing, VMP devirt |
| `echo-config` | Config persistence, HTTP, filesystem, WebSocket, JSON, `hash_map` / `hash_set` |
| `echo-scripts` | Complete runnable scripts — CS2 ESP, UE4 aimbot, Unity loot scanner |

---

## Skills (18)

Loaded on demand. Each is `skills/<name>/SKILL.md` with a `name` + `description` that the model
routes on — the same format Pi uses.

| Skill | Contents |
|---|---|
| `angelscript-patterns` | Mutex-guarded entity buffers, thread-safe tick/render loops, safe deref chains, rate limiters |
| `angelscript-types` | The AngelScript 2.x type system as Echo embeds it: `@` handles, `is null`, `array<T>` semantics, `cast<T>()`, no exceptions |
| `echo-anti-patterns` | 19 failure modes, each as wrong code plus the corrected real-API code |
| `echo-workflow` | Chaining agents into one script: the three-layer model, shared snapshot, thread rate table, startup order |
| `echo-ecosystem` | angel-menu-mcp, echo-esp-preview, the LSP, as_bundler, web-mv, SuperGhidra, the VMP stack |
| `anti-cheat-systems` | What integrity systems check: module/driver enumeration, handle scanning, memory integrity, input injection |
| `game-hacking-techniques` | Memory access models, entity list patterns, ESP/aimbot math, overlay rendering |
| `game-engine-resources` | Source 2, Unreal, Unity, IW internals — structs, offsets, W2S math, bone formats |
| `gamehacking-cheatsheet` | Technique → Echo API map, plus the `mcp-gamehacking` query per technique |
| `awesome-game-security` | Per-category resource map from the 4000+ curated list |
| `dumper7-sdk` | Dumper-7 structure, GObjects traversal, FName resolution, VGK decrypt, offset workflow |
| `omath-math` | W2S per engine, projectile prediction, rotation helpers, coordinate systems |
| `reverse-workflow` | Binary → working script: tool decision tree, signature generation, Zydis analysis, Unicorn tracing |
| `reverse-engineering-tools` | Debuggers, disassemblers, Frida, Cheat Engine plugins, dumpers, pattern tools |
| `devirt-workflow` | VMProtect devirt: lazy-unpack OEP, Triton semantics, NoVmp/VTIL, LLVM passes, r2 signatures |
| `offset-update-workflow` | Post-patch recovery: binary diff, reacquire the function, regenerate the pattern |
| `karpathy-coding` | Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution |
| `ponytail` | Minimum code, no unrequested abstractions, the shortcut-comment convention |

---

## Templates (15)

Copy any file into `%AppData%\Roaming\scripts\`, reopen the in-game menu. No compile step. All 15
are compiled in CI against a real AngelScript 2.38.0 build.

| Template | What it demonstrates |
|---|---|
| `basic.as` | Minimal `bool main()` + `on_unload()` |
| `render.as` | ESP box, colour picker, `on_render` hook |
| `menu.as` | Every menu element type with config persistence |
| `memory.as` | Process attach, IDA pattern scan, RIP-relative resolve, tick loop |
| `esp-bones.as` | Full CS2 ESP: cornered boxes, 16-pair skeleton, health bar, distance labels |
| `aimbot.as` | Full CS2 aimbot: target selection, smoothing, prediction, recoil, triggerbot |
| `misc.as` | Bunny hop, flash reduction, radar, spectator list |
| `ue5-sdk.as` | UE5 ESP from Dumper-7 offsets: GWorld traversal, `FTransform`, health bar |
| `unity-il2cpp.as` | Unity IL2CPP ESP: camera matrix, entity walk, health bar |
| `valorant.as` | Valorant ESP: VGK-aware, GObjects decrypt, UE4 `TUObjectArray` |
| `fortnite.as` | Fortnite ESP: GWorld traversal, 12-bone skeleton, HP + shield bars |
| `radar.as` | Circular radar panel: entity dots, edge arrows, rotating / north-up |
| `loot.as` | CS2 dropped-weapon ESP: item tiers, distance-gated labels, sorted panel |
| `esp-preview.as` | `g_preview` + `esp_layout` drag-to-arrange ESP |
| `web-mv.as` | web-mv memory-viewer endpoint |

> Game-specific offsets and patterns in these templates are **illustrative placeholders** from one
> build. They are not verified and break on every patch — re-derive them with a current dumper.
> See `skills/offset-update-workflow`.

---

## Companion tools (17)

| Tool | What it gives you | How it is fetched |
|---|---|---|
| [mcp-gamehacking](https://github.com/1llu50ry/mcp-gamehacking) | 4100+ skills, 75 agents, 19+ MCP tools | clone + `npm install` + build |
| [angel-menu-mcp](https://github.com/Jozkah/angel-menu-mcp) | toggle the Echo overlay menu from Claude | clone + `npm install` |
| [rea](https://github.com/morluto/rea) | static binary analysis: IL2CPP, Godot, APK, WASM, firmware | `npx -y rea-agents` on first connect |
| [ponytail](https://github.com/DietrichGebert/ponytail) | lazy-senior-dev discipline | Claude Code plugin |
| [andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) | coding-discipline guidelines | Claude Code plugin |
| [as_bundler](https://github.com/sinistercodes/as_bundler) | AngelScript bundler, validator, obfuscator, string scrambler | prebuilt release binary |
| [echo-esp-preview](https://github.com/speedsunderscore/echo-esp-preview) | `g_preview` + `esp_layout` — drag ESP elements into place | single `.as` drop-in |
| [echo-angelscript-lsp](https://github.com/speedsunderscore/echo-angelscript-lsp) | VS Code completion + hover docs for ~1900 Echo symbols | `.vsix` from the release |
| [Triton](https://github.com/JonathanSalwan/Triton) | symbolic execution + taint analysis | `pip install triton-library` into a venv |
| [VMProtect-devirtualization](https://github.com/JonathanSalwan/VMProtect-devirtualization) | Triton-based VMP devirt scripts | clone (bundles Intel Pin) |
| [vmp-lazy-unpack](https://github.com/x86rc/vmp-lazy-unpack) | VMP section unpacker + import resolver | clone + `pip install -e .` |
| [awesome-game-security](https://github.com/gmh5225/awesome-game-security) | 4000+ curated resources | README only (435 KB, *not* the 3.19 GB clone) |
| [gamehacking-cheatsheet](https://github.com/ridpath/gamehacking-cheatsheet) | the mega cheatsheet | README only (275 KB) |
| [web-mv](https://github.com/Jozkah/web-mv) | browser memory viewer at `ws://127.0.0.1:9000` | clone + `bun install` |
| [VTIL-Core](https://github.com/vtil-project/VTIL-Core) | VM-translation IR + optimizer passes | CMake build |
| [NoVmp](https://github.com/can1357/NoVmp) | full VMP devirt → optimized VTIL → native | CMake build (vendors VTIL-Core) |
| [vtil2](https://github.com/pop-rip/vtil2) | VTIL redesign in C# | `dotnet build` |
| [llvm-project](https://github.com/llvm/llvm-project) | OLLVM passes + Triton's LLVM interface | **system package** via `apt` / `brew` / `winget` — never built from source |

Everything lands in `~/.local/share/echo-ai-toolkit/`, and every one of them is installed from
`vendor/` in this repo — none is fetched from the upstream project at install time. Update with
`echo update --tools`.

---

## MCP servers (5)

Written to `~/.local/share/echo-ai-toolkit/mcp.json` and shipped as the plugin's `.mcp.json`.

| Server | Command | Needs |
|---|---|---|
| `gamehacking` | `node …/mcp-gamehacking/dist/index.js` | `ECHO_SKIP_GAMEHACKING=1` to omit |
| `rea` | `node …/rea/node_modules/rea-agents/scripts/rea.mjs` | Node (`npm ci` against `vendor/npm/rea/package-lock.json`) |
| `angel-menu` | `node …/angel-menu-mcp/index.js` | Node (installed from `vendor/`) |
| `radare2` | `r2pm -r r2mcp` | radare2 + `r2pm -Uci r2mcp` |
| `ida` | `uvx ida-mcp stdio` | IDA 9.4+ with idalib, Python 3.11+ |

A server whose prerequisite is missing logs an error and is skipped — it does not break the
session.

---

## Reference docs

| Doc | Contents |
|---|---|
| [`reference/api.md`](reference/api.md) | Complete API reference — all 22 namespaces plus the `memory_buffer` type, every signature, return semantics, caveats |
| [`reference/_API_CONTRACT.md`](reference/_API_CONTRACT.md) | The old→new API mapping, 12 rules, AngelScript language rules, canonical snippets |
| [`reference/offsets.md`](reference/offsets.md) | Offset and pattern reference (placeholders — verify per patch) |
| [`llms.txt`](llms.txt) | Single-file context bundle for GPT-4o, Gemini, local models — paste as context |
| [`prompts/system-prompt.md`](prompts/system-prompt.md) | Portable system prompt for non-Claude clients |
| [`pi/SYSTEM.md`](pi/SYSTEM.md) | The Pi persona and no-refusal policy |

---

## Troubleshooting

**`echo: pi is not installed`** — Pi needs Node 22.19+.
`curl -fsSL https://pi.dev/install.sh | sh`. Everything except `echo` still works without it.

**`echo: Echo profile missing`** — the profile did not get written.
`echo update --profile`, or re-run the installer.

**`echo` no longer prints text** — it shadows the shell builtin in interactive shells. Use
`command echo "text"`, or remove the alias block from your `.bashrc` / `.zshrc` / PowerShell
profile and set `ECHO_NO_ALIAS=1`.

**`claude plugin` shows nothing** — restart Claude Code, or `/reload-plugins`.

**MCP server fails to connect** — a missing prerequisite, not a broken install. `echo doctor`
names it. `mcp-gamehacking` needs `ECHO_SKIP_GAMEHACKING` **unset** and its build finished;
`radare2` needs `r2pm -Uci r2mcp`; `ida` needs IDA 9.4+ with idalib.

**`code --install-extension failed`** — on some distros `code` is `code-oss`, not VS Code. The
installer prints the `.vsix` path; install it manually, or skip it.

**`pip install` refused with "externally-managed-environment"** — PEP 668. The installer already
handles this by using a venv at `~/.local/share/echo-ai-toolkit/venv`. Activate it with
`source …/venv/bin/activate` to use Triton from a shell.

**`cmake not found` / `LLVM` skipped** — the installer tried `sudo -n apt-get`, which fails
without passwordless sudo. Run the command it printed, then `echo update --tools`.

**`mcp-gamehacking` clone died partway** — a 21 GB clone. The installer detects the broken tree
and re-clones on the next run. Or use `ECHO_SKIP_GAMEHACKING=1`.

**`echo update` says "git pull failed"** — local changes in a cloned tool. The installer never
discards your work; resolve it in that directory and re-run.

**Templates do not load in Echo** — scripts go in `%AppData%\Roaming\scripts\`, and the menu must
be closed and reopened to refresh the list. Discord must be running with the overlay enabled.

---

## How this repo is verified

Five guards, all in CI:

```bash
# 1. Every API call exists in the real Echo API
curl -fsSL https://echo-23.gitbook.io/angel/llms-full.txt -o /tmp/echo-llms-full.txt
python3 scripts/build_api_index.py /tmp/echo-llms-full.txt -o /tmp/echo-api-index.json
python3 scripts/check_api.py --root . --api-index /tmp/echo-api-index.json

# 2. The compile stub contains every documented symbol and invents none
python3 scripts/check_api.py --root . --api-index /tmp/echo-api-index.json \
  --stub scripts/angelscript/echo_stub.as

# 3. Every template compiles; every doc block is grammar-clean
python3 scripts/check_angelscript.py --root . \
  --checker "$PWD/scripts/angelscript/check" --workdir /tmp

# 4. The plugin loads and its hooks work
claude plugin validate . && claude plugin test .

# 5. vendor/ matches its manifest, and the installers reach no third-party host
python3 scripts/vendor_manifest.py --check
```

`scripts/angelscript/build.sh` fetches AngelScript 2.38.0 and builds the checker. Guard 3 is what
caught real defects no review did — a C++ `->` in a template, a bone table declaring 30 entries
while holding 32, an `attach()` on a DLL name instead of a process.

Guard 2 is the one that keeps the *docs* honest, not just the templates. Templates compile against
`scripts/angelscript/echo_stub.as`, so the stub is a second source of truth: anything invented in
both the stub and the docs would compile and look correct. The stub check compares it against the
live API index in both directions, so it caught `sleep()` — a function the toolkit taught in seven
files that appears nowhere in Echo's documentation.

CI runs 9 jobs: `json`, `api`, `drift`, `vendor`, `layout`, `angelscript`, `pi-profile`,
`plugin`, `installers`. `drift` runs weekly on a schedule, re-fetches the live docs, and opens an issue when
they no longer match what the repo teaches — Echo patches on its own schedule, so a guard that only
runs on push would let the toolkit go stale silently.

---

## Repo layout

```
agents/*.md                12 agent definitions (loaded as system prompts)
skills/<name>/SKILL.md     18 skills (name + description frontmatter)
templates/*.as             15 runnable AngelScript templates
reference/api.md           complete API reference
reference/_API_CONTRACT.md old→new mapping, rules, language traps
pi/                        Pi profile: SYSTEM.md, APPEND_SYSTEM.md, AGENTS.md, prompts, bin
scripts/check_api.py       API conformance guard (docs + compile stub)
scripts/build_api_index.py docs → machine-readable API index
scripts/check_angelscript.py + scripts/angelscript/   compile + grammar guard
scripts/echo.mjs           `echo update|doctor|status|tools|version` (one implementation)
scripts/echo-*.sh|ps1      thin shims that exec echo.mjs
tools.lock                 pin record: refs, versions, hashes
vendor/                    every tool, plugin, binary and doc the installer installs
vendor/MANIFEST.json       sha256 + upstream + license for every vendored file
vendor/ARCHIVES            split release archive for mcp-gamehacking
scripts/vendor_manifest.py --write / --check
scripts/vendor_refresh.sh  re-fetch vendor/ at the pins
scripts/vendor_archive.sh  rebuild the mcp-gamehacking archive
install.sh | install.ps1   the installers
hooks/register.tsx         slash commands, keyword routing, side panel
llms.txt                   single-file LLM context bundle
```

---

## Contributing

Add a skill at `skills/<name>/SKILL.md` or an agent at `agents/<name>.md`. Keep agents
self-contained — they load as system prompts and must include all context without external
lookups.

Requirements CI enforces:

- every skill and agent has `name` + `description` frontmatter
- every agent has a matching entry in `hooks/register.tsx`
- every API call exists in the live Echo docs
- the compile stub declares every documented symbol and nothing else
- every template compiles

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

## Links

- [Echo Universal API docs](https://echo-23.gitbook.io/angel)
- [Echo LLM-optimized reference](https://echo-23.gitbook.io/angel/llms-full.txt)
- [Pi coding agent](https://pi.dev)
- [awesome-game-security](https://github.com/gmh5225/awesome-game-security) — 4000+ curated resources
- [mcp-gamehacking](https://github.com/1llu50ry/mcp-gamehacking) — MCP server for the above
- [gamehacking-cheatsheet](https://github.com/ridpath/gamehacking-cheatsheet)

---

## License

MIT — see [LICENSE](LICENSE).
