# Adding AI Menu Control to another Angel script

The system has three parts:

| Part | File | Role |
|------|------|------|
| MCP server | `index.js` | The AI/MCP endpoint. Runs on your machine, the overlay connects to it. Script-agnostic — never changes. |
| Lane core | `angel-menu-control.as` | Paste-in AngelScript block: the ws lane + generic set/get. Control-agnostic — same for every script. |
| Codegen | `generate-registry.mjs` | Reads a target `.as`, auto-detects every menu control, emits its registry. Run once per script (re-run when the menu changes). |

Auto-detection reads everything it needs straight from the source, so it works on **any** Angel script that builds its menu with `ui::add_*`:

- **id** — the control's `m_<var>` global (stable, meaningful; used by `ui_get`/`ui_set`).
- **label** — the human menu text (the `ui::add_*` first argument, e.g. `"Show Name"`); shown by clients instead of the raw id.
- **kind / range / options** — checkbox, slider (min/max/step), combobox (option labels).
- **tab / subtab / category** — the surrounding `ui::add_tab` / `ui::add_subtab` / `ui::add_category`, so a client can mirror the overlay's own 3-level menu layout instead of one flat list.
- **danger** — a name heuristic (see below).

## Add it to a script (≈5 minutes)

1. **Paste the lane core.** Copy the entire contents of `angel-menu-control.as` into your script (anywhere at file scope).

2. **Generate the registry:**
   ```sh
   node generate-registry.mjs path/to/your_script.as > registry.txt
   ```
   Paste the `amc_build_registry()` function it prints into your script — it interleaves
   `amc_tab()` / `amc_subtab()` / `amc_category()` with the control registrations so the registry
   keeps your menu's structure.

   Flags:
   - `--list` — print what it detected (grouped by tab › subtab › category), don't emit code.
   - `--json` — emit a JSON array of controls (id, label, kind, value, range/options, tab/subtab/category, danger) for a web UI or the mock. Writable kinds only.
   - `--writable-only` — emit only checkbox/slider/combobox in the registry too (drop multi-select/color). Use for a host whose lane has no multi/color set path.
   - `--danger a,b,c` — flag extra controls as danger (see below).

3. **Add the buttons** — inside `build_menu()`, in any category (e.g. a Debug/Misc one):
   ```angelscript
   amc_add_buttons();
   ```

4. **Build the registry** — in `main()`, right after `build_menu()`:
   ```angelscript
   amc_build_registry();
   ```

5. **Drain sets on the render thread** — as the FIRST line of your render callback (the function passed to `on_render`):
   ```angelscript
   amc_render();
   ```

6. **Clean teardown** — in `on_unload()`:
   ```angelscript
   amc_on_unload();
   ```

That's it. Reload the script.

## Drive it

```sh
claude mcp add angel-menu -- node /abs/path/to/angel-menu-mcp/index.js
```
Then in the overlay: **Others → click "AI Menu Control: Connect"**. Ask the AI to `list_features` / `set_feature`.

## Danger controls

Controls whose registration got `danger=true` (memory writers — aim, chams, no-recoil, etc.) refuse `ui_set` until the operator clicks **"AI Menu Control: ARM"** in the overlay. Arming is a live human click, never a wire verb.

The danger flag is a **name heuristic** (`aim`, `cham`, `nosway`/`norecoil`/`nospread`, `force_bone`, `cv_*`, `team_chams`) — **review it**. Add any the heuristic missed:
```sh
node generate-registry.mjs your_script.as --danger exp_no_recoil,exp_no_spread,exp_instant_kill
```

## Notes & limits

- **One `ws::` socket per script.** If your script also uses `ws::` (WebRadar, a web-mv WRITE lane), only one may be connected at a time — disconnect the others before connecting AI Menu Control.
- **Writable kinds:** checkbox, slider, combobox. Multi-selects and color pickers are registered **read-only** (listed/read, not set) in v1 — `ui::set` overloads for them are unproven on the host. If your host has no `amc_multi`/`amc_color` (or you don't want them), regenerate with `--writable-only`.
- **Grouping / labels are auto-detected** from `ui::add_tab`/`add_subtab`/`add_category` and the `ui::add_*` label — nothing to annotate by hand. Controls outside any tab/category still register (a client buckets them under an untitled group).
- **Re-run codegen** whenever you add/remove/rename menu controls, and re-paste `amc_build_registry()`.
- **Config port:** the lane connects to `ws://127.0.0.1:9010/agent-ui`; the MCP server listens there by default (`ANGEL_WS_PORT` / `ANGEL_WS_PATH` to change — keep both ends matched, and `AMC_URL` in the lane core).

## Why codegen instead of runtime auto-registration

AngelScript has no menu-reflection API, and most controls have no config key (`ui::add_checkbox("Show Name", true)` × many), so a runtime wrapper could only name them by label — dozens of duplicates. Only a parser sees the `m_<var>` assignment, which is the stable, human-meaningful name. So the tool reads the source; the runtime stays a tiny generic lane.
