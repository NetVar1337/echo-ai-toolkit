# Using Menu Control with the web-mv memory viewer (browser / phone)

There are two ways to drive an overlay's menu with this project. Pick one — they use different ports and different transports:

| | Standalone MCP (this repo) | web-mv memory viewer |
|---|---|---|
| Driver | An AI / MCP host (Claude, etc.) | A browser (desktop or phone) |
| Transport | The MCP server **is** the WebSocket endpoint | A relay serves the UI and bridges WebSockets |
| Overlay connects to | `ws://127.0.0.1:9010/agent-ui` | `ws://127.0.0.1:9000/agent-ext` |
| Overlay-side code | Paste `angel-menu-control.as` into your script | Built into the web-mv **ext agent** |
| See | [README.md](README.md) / [INTEGRATION.md](INTEGRATION.md) | this file |

You *can* run both, but not on the same `ws::` socket at the same time — the host allows one `ws::` connection per script (see "One socket per script" in the README). Connect one lane at a time.

---

## What the web-mv path is

[web-mv](https://github.com/Jozkah/web-mv) is a browser-based memory viewer for reverse engineering. It has:

- a **relay** (Bun) that serves the web UI *and* bridges WebSocket frames, and
- two agent sockets: `/agent` (read/scan) and `/agent-ext` (the write-family extension agent).

The Menu Control verbs (`ui_list` / `ui_get` / `ui_set`) are built into the **ext agent** and ride the existing `/agent-ext` socket — there is no separate MCP server and no port 9010 here. The browser gets a **Menu Control** tab that lists the agent's controls and toggles them.

> This lives on the `feat/menu-control-lane` branch of the web-mv fork:
> https://github.com/Jozkah/web-mv/tree/feat/menu-control-lane

## Run it (desktop)

1. **Start the relay** from the web-mv repo (see its README for the exact start command). It listens on `127.0.0.1:9000` and serves the UI on the same port.
2. **Load the ext agent** (`web_mv_ext_agent.as`) in your Angel host and click **"Connect /agent-ext"**. It connects to `ws://127.0.0.1:9000/agent-ext`.
3. **Open the UI** at `http://127.0.0.1:9000` and open the **Menu Control** tab. It should list the agent's controls.
4. Toggle a checkbox / drag a slider / pick a combo option — it applies live in the overlay.

## Run it from a phone (same LAN)

The relay serves the whole UI on one port, and the page builds its WebSocket URL from whatever host it loaded from — so a phone needs **no rebuild**, only a wider bind.

1. Start the relay with `HOST=0.0.0.0` (default is loopback; `PORT` defaults to `9000`):
   ```sh
   # bash
   HOST=0.0.0.0 <relay start command>
   # PowerShell
   $env:HOST="0.0.0.0"; <relay start command>
   ```
2. On the phone, same Wi-Fi/LAN, open `http://<your-PC-LAN-IP>:9000` (find the IP with `ipconfig` / `ip addr`).
3. Open the **Menu Control** tab and toggle away.

The overlay agent still connects to `ws://127.0.0.1:9000/agent-ext` — it runs on the same PC as the relay, so that address never changes. Only the browser side crosses the LAN.

### Safety (read this)

- **No authentication on the relay.** It is a control channel into a process's memory. Bind beyond loopback on a **trusted LAN only**, and never expose the port to the internet. For remote access put it behind a TLS reverse proxy (Caddy/nginx) with auth, or a private network overlay (Tailscale/WireGuard), so the browser reaches it over `https`/`wss` with a login in front.
- **Danger controls still require a live PC-side ARM click.** Controls that write game memory (aim, chams, no-recoil, …) refuse `ui_set` until you click **"Menu Control: ARM danger controls"** in the overlay. That cannot be armed from the phone — the phone can flip overlay-only visuals, but a person at the PC must arm anything that touches the game process.

---

## Exposing your own overlay's controls (not the demo ones)

The web-mv ext agent ships with a handful of **demo controls** (a couple of ESP toggles, a distance slider, a combo, one danger toggle) so the tab works out of the box. To point it at a real overlay's menu instead, use the same codegen this repo provides:

```sh
node generate-registry.mjs your_overlay.as > registry.txt
```

Then replace the demo `mc_build_registry()` body in `web_mv_ext_agent.as` with the generated registration calls (the generator emits `amc_*` calls; the web-mv agent's helpers are named `mc_check` / `mc_slider` / `mc_combo` — same argument order, just rename the prefix, or adapt the generator's output prefix). Re-load the agent.

The codegen, the danger heuristic, and the `--danger` flag all work exactly as described in the [README](README.md) — the naming and safety story is identical across both paths.
