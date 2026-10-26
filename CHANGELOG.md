# Changelog

All notable changes to this repo. The plugin version in
[`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) is what marketplaces key off.

## 0.4.0 — 2026-10-26

Correctness and reproducibility. No new agents, skills or templates; the surface is the same.

### The compile stub is now verified against the live API

- **Removed `sleep()`.** The toolkit taught `void sleep(uint ms)` in `reference/api.md`,
  `reference/_API_CONTRACT.md`, `agents/echo-aimbot.md`, five times in
  `skills/echo-anti-patterns/SKILL.md`, and declared it in the compile stub — while the live Echo
  docs contain zero occurrences of it. Every one of those now uses the documented mechanism: a tick
  thread (`create_thread(tps, cb)`) plus a `util::time_now()` gate.
- `scripts/check_api.py --stub` compares `scripts/angelscript/echo_stub.as` against the API index
  in both directions: every documented call must be declared, and nothing undeclared by the docs
  may appear. The stub is what templates compile against, so before this it was a second source of
  truth nothing checked.
- Filled 45 documented calls the stub was missing: all of `uc::*` (26), `zydis::*` (3), `trace::*`
  (4), `memory_buffer::read_vec{2,3,4}_double`, `render::calculate_2d_bbox{,_unity}`,
  `unreal::read_bones`, `unity::rust_{transform_position,prefab_id}`, `ui::set_label_style`,
  `util::{disable_capture_protection,zip_parse}`, `iw_engine::w2s`, `alert::show_tag`. Compile
  coverage went from 179 to 226 documented symbols.
- Removed two invented symbols from the stub: `json::object()` (the docs have `json_obj()`) and a
  duplicate `unreal::build_view_cache` (the docs expose it unqualified).

### Docs drift is detected on a schedule

- New `drift` CI job runs weekly, re-fetches `llms-full.txt`, and opens (or comments on, or closes)
  a GitHub issue when the live API no longer matches the repo. Echo patches on its own schedule;
  the previous guard only ran when someone pushed.
- `scripts/build_api_index.py` replaces the index-building heredoc that lived inside the workflow,
  so the same index is one command locally.

### Installs are pinned

- New [`tools.lock`](tools.lock): 8 git clones by commit SHA, 3 raw files and 3 release assets by
  sha256, `rea-agents` 6.8.0, `triton-library` 1.0.0rc4. The installers check out the pinned ref
  (`git init` + `fetch <sha>`), verify every downloaded file's sha256, and pass the pinned versions
  to `npx` and `pip`.
- `echo update --tools` moves existing installs to the pinned refs and rebuilds; `echo update
  --lock` re-resolves every pin to current upstream heads and rewrites the file (round-trips
  byte-identically). `echo doctor` reports any installed tool that is off-pin.

### One implementation of `echo update` / `echo doctor`

- `scripts/echo.mjs` implements `update`, `doctor`, `status`, `tools`, `version` and `help`.
  `scripts/echo-{update,doctor}.{sh,ps1}` and both launchers are now thin dispatchers, replacing
  four hand-maintained copies (672 lines of bash + PowerShell) with one implementation and four
  ~20-line shims. Not fewer lines — one behaviour: the PowerShell copies were parse-checked by CI
  and never executed, so they could diverge silently.
- `echo update --lock` and the pinned-refs doctor row are new CLI surface; the rest is
  behaviour-preserving, including the flag routing the `pi-profile` CI job asserts.

### Housekeeping

- `README.md`: dropped the hardcoded "302/302 · 28 hook tests" numbers, documented the fourth
  guard, the weekly drift job and `tools.lock`.
- `plugin.json`: removed the `"types"` field and `types/index.d.ts` — a 13-line union of agent names
  is not a type surface for an AngelScript API.
- Known limitation: the stub is checked by *name*, not by signature. Return and parameter types are
  approximate; the header of `echo_stub.as` says so.

## 0.3.0

- `echo` became a full CLI: `update`, `doctor`, `status`, `tools`, `version`.
- Pi coding agent profile with a custom system prompt and an `echo` launcher.
- Full install by default; measured and documented real install sizes; unknown tiers rejected.
- Recover from a partial multi-GB clone instead of failing on it.
- Install the build toolchains so a `full` install actually completes.

## 0.2.0

- AngelScript compile guard: every template compiles against AngelScript 2.38.0, every doc code
  block is grammar-checked.
- API conformance guard: docs may only teach calls that exist in the live Echo API.

## 0.1.0

- 12 agents, 18 skills, 15 templates, 5 MCP servers, 17 companion tools.
- One-command installer for Linux, macOS and Windows.
