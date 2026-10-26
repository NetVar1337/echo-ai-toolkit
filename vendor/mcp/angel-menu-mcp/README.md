# angel-menu-mcp

An MCP (Model Context Protocol) server that lets an AI client — Claude, or any MCP host — **enumerate and toggle the in-game menu of an Angel overlay** for automated testing. Flip ESP boxes, aim assist, radar modes, distance sliders, etc. from the AI, then observe the result in-game.

It talks to the overlay over the overlay's dedicated **AI Menu Control** lane (`/agent-ui`) — a channel separate from the web-mv memory-write bridge. **This server is the WebSocket endpoint** — the overlay connects _to it_ — so no separate relay is required.

> **Two ways to drive the menu:** this repo is the **AI / MCP** path. If you'd rather toggle the menu from a **browser or phone**, the same three verbs are built into the web-mv memory viewer as a "Menu Control" tab — see **[MEMORY_VIEWER.md](MEMORY_VIEWER.md)**. Different port and transport; pick one at a time.

## How it fits together

```
 Claude / MCP host
        │  (MCP stdio: list_features / get_feature / set_feature)
        ▼
 angel-menu-mcp  ──listens──▶  ws://127.0.0.1:9010/agent-ui
        ▲                              │
        └────── ui_* JSON frames ──────┘  (Angel overlay connects here)
```

## Works with any Angel script

The lane core is **control-agnostic** — nothing in it is specific to one script. To add it to **any** script (e.g. `bodycam.as`), see **[INTEGRATION.md](INTEGRATION.md)**: paste `angel-menu-control.as`, run the codegen (`generate-registry.mjs`) to auto-detect every menu control, and wire four one-line hooks. No per-control code by hand.

The codegen reads each control's **id** (`m_<var>`), its **label** (the real menu text), kind/range/options, **danger**, and the surrounding **tab / subtab / category** — so a client reproduces your overlay's own grouped, labeled menu instead of a flat list. Re-run it whenever the menu changes.

## Requirements

- Node.js ≥ 18
- An Angel overlay with the AI Menu Control lane (built into `huntshowdown.as`; added to any other script via INTEGRATION.md).

## Install

```sh
cd angel-menu-mcp
npm install
```

## Register with Claude Code

```sh
claude mcp add angel-menu -- node /absolute/path/to/angel-menu-mcp/index.js
```

Or wire it into any MCP host as a stdio server whose command is `node index.js`.

## Connect the overlay

1. Start your MCP host (it launches this server).
2. In the overlay, open **Others › Debug** and click **"AI Menu Control: Connect"**. The overlay connects to `ws://127.0.0.1:9010/agent-ui` (this server).
3. Ask the AI to `list_features`. If it reports "Overlay NOT connected", repeat step 2.

> The overlay allows one `ws::` socket at a time, shared between WebRadar, the web-mv WRITE lane, and this lane. Turn **WebRadar off** (and disconnect the web-mv WRITE lane) before connecting AI Menu Control.

## Tools

| Tool | Args | What it does |
|------|------|--------------|
| `list_features` | — | Every control: id, **label** (the real menu text), kind (`check`/`slider`/`combo`), current value, range/options, its **tab / subtab / category**, and a `danger` flag. |
| `get_feature` | `name` | Read one control's current value. |
| `set_feature` | `name`, `value` | Set one control. Checkbox → `true`/`false`; slider/combobox → integer (combobox = option index). Returns the value read back. |
| `connection_status` | — | Whether the overlay is connected. |

## Danger controls & arming

Controls that **write game memory** — aim assist, chams (all variants), no-sway / no-recoil / no-spread, force-bone, the cvar tweaks — are marked `danger: true`. `set_feature` on them **fails** with a "disarmed" error unless the operator has clicked **"AI Menu Control: ARM danger controls"** in the overlay first.

Arming is deliberately a **live human click in the overlay** and is _not_ exposed as a tool — the AI can flip visual features freely, but a person must consciously arm anything that touches the game process. Overlay-only visuals (ESP boxes, names, radar, external/drawn chams, debug panels) are always settable.

## Configuration (env vars)

| Var | Default | Meaning |
|-----|---------|---------|
| `ANGEL_WS_HOST` | `127.0.0.1` | bind host |
| `ANGEL_WS_PORT` | `9010` | bind port (must match the overlay's `UI_LANE_URL`) |
| `ANGEL_WS_PATH` | `/agent-ui` | ws path |
| `ANGEL_REQ_TIMEOUT_MS` | `6000` | per-request reply timeout |

## Notes

- `ui_set` is applied on the overlay's render thread and the result is reported after it lands, so a returned value reflects any dependent-visibility recompute the overlay does.
- One overlay peer at a time; a reconnect replaces the previous handle.
- Loopback-bound by default. There is no authentication on the lane — do not expose the port off-host.

## License

MIT
