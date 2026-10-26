#!/usr/bin/env node
// angel-menu-mcp — Model Context Protocol server for controlling an Angel overlay's
// in-game menu from an AI client, over the overlay's /agent-ext WebSocket lane.
//
// Architecture: this process IS the WebSocket endpoint. It listens on
// ws://127.0.0.1:9010/agent-ui and waits for the running Angel script to connect
// (the "AI Menu Control: Connect" button in the overlay's Others > Debug tab — the
// script's UI_LANE_URL points here). MCP tool calls are translated into
// ui_list / ui_get / ui_set frames, sent to the connected script, and the id-matched
// reply is returned to the AI. This is the overlay's dedicated menu-control lane,
// independent of the web-mv memory-write bridge. No relay (bun-server) is needed.
//
// Danger-flagged controls (aim, chams, no-sway/recoil/spread, force-bone, cvar tweaks)
// refuse ui_set unless the operator has clicked "AI Menu Control: ARM danger controls"
// in the overlay menu. Arming is intentionally a live human click, never exposed here.
//
// Config via env:
//   ANGEL_WS_HOST   (default 127.0.0.1)
//   ANGEL_WS_PORT   (default 9010)
//   ANGEL_WS_PATH   (default /agent-ui)
//   ANGEL_REQ_TIMEOUT_MS (default 6000)

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { WebSocketServer } from "ws";

const HOST = process.env.ANGEL_WS_HOST || "127.0.0.1";
const PORT = parseInt(process.env.ANGEL_WS_PORT || "9010", 10);
const WPATH = process.env.ANGEL_WS_PATH || "/agent-ui";
const REQ_TIMEOUT_MS = parseInt(process.env.ANGEL_REQ_TIMEOUT_MS || "6000", 10);

// ── WebSocket endpoint the game script connects to ──────────────────────────
/** @type {import("ws").WebSocket | null} */
let scriptSock = null;
let nextId = 1;
/** id -> { resolve, reject, timer } */
const pending = new Map();

const wss = new WebSocketServer({ host: HOST, port: PORT, path: WPATH });

wss.on("connection", (sock) => {
  // one peer at a time — the newest connection wins (a script reconnect replaces the old handle)
  if (scriptSock && scriptSock !== sock) {
    try { scriptSock.close(); } catch { /* ignore */ }
  }
  scriptSock = sock;
  logStderr(`Angel script connected on ws://${HOST}:${PORT}${WPATH}`);

  sock.on("message", (data) => {
    let frame;
    try { frame = JSON.parse(data.toString()); } catch { return; }
    const id = frame.id;
    if (id === undefined || id === null) return;
    const key = String(id);
    const waiter = pending.get(key);
    if (!waiter) return; // late/duplicate reply — ignore
    pending.delete(key);
    clearTimeout(waiter.timer);
    if (frame.type === "error") {
      waiter.reject(
        new Error(
          `overlay error ${frame.code ?? "?"}: ${frame.message ?? "unknown"}`,
        ),
      );
    } else {
      waiter.resolve(frame);
    }
  });

  sock.on("close", () => {
    if (scriptSock === sock) scriptSock = null;
    logStderr("Angel script disconnected");
    // fail everything still in flight so tool calls don't hang
    for (const [key, waiter] of pending) {
      clearTimeout(waiter.timer);
      waiter.reject(new Error("Angel script disconnected mid-request"));
      pending.delete(key);
    }
  });

  sock.on("error", () => { /* close handler does the cleanup */ });
});

wss.on("error", (err) => {
  logStderr(`WebSocket server error: ${err.message}`);
});

wss.on("listening", () => {
  logStderr(
    `Listening on ws://${HOST}:${PORT}${WPATH} — waiting for the Angel overlay to connect ` +
      `(overlay: Others > Debug > "AI Menu Control: Connect").`,
  );
});

// Send one request frame and await its id-matched reply.
function request(type, extra = {}) {
  return new Promise((resolve, reject) => {
    if (!scriptSock || scriptSock.readyState !== scriptSock.OPEN) {
      reject(
        new Error(
          "Angel overlay is not connected. In the overlay, open Others > Debug and click " +
            '"AI Menu Control: Connect".',
        ),
      );
      return;
    }
    const id = nextId++;
    const key = String(id);
    const timer = setTimeout(() => {
      pending.delete(key);
      reject(new Error(`timeout after ${REQ_TIMEOUT_MS}ms waiting for ${type} reply`));
    }, REQ_TIMEOUT_MS);
    pending.set(key, { resolve, reject, timer });
    try {
      scriptSock.send(JSON.stringify({ type, id, ...extra }));
    } catch (e) {
      clearTimeout(timer);
      pending.delete(key);
      reject(e);
    }
  });
}

function logStderr(msg) {
  // stdout is the MCP transport — diagnostics MUST go to stderr
  process.stderr.write(`[angel-menu-mcp] ${msg}\n`);
}

// ── control-value coercion ──────────────────────────────────────────────────
// A control's `kind` decides how a tool's `value` is encoded on the wire.
function coerceValueForKind(kind, value) {
  if (kind === "check") {
    if (typeof value === "boolean") return value;
    if (typeof value === "number") return value !== 0;
    if (typeof value === "string") {
      const v = value.trim().toLowerCase();
      if (v === "true" || v === "1" || v === "on" || v === "yes") return true;
      if (v === "false" || v === "0" || v === "off" || v === "no") return false;
    }
    throw new Error(`checkbox "${value}" is not a boolean`);
  }
  // slider / combo — integer
  const n =
    typeof value === "number" ? value : parseInt(String(value).trim(), 10);
  if (!Number.isFinite(n)) throw new Error(`${kind} value "${value}" is not an integer`);
  return Math.trunc(n);
}

// Fetch the kind of a control (needed to encode a ui_set value correctly).
async function controlKind(name) {
  const res = await request("ui_get", { name });
  return res.kind; // "check" | "slider" | "combo"
}

// ── MCP server ──────────────────────────────────────────────────────────────
const TOOLS = [
  {
    name: "list_features",
    description:
      "List every menu control the overlay exposes (feature checkboxes, sliders, comboboxes) with " +
      "its current value. `danger:true` controls (aim, chams, no-sway/recoil/spread, force-bone, " +
      "cvar tweaks) write game memory and require the operator to have armed writes in the overlay.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "get_feature",
    description: "Read one menu control's current value by its name (from list_features).",
    inputSchema: {
      type: "object",
      properties: { name: { type: "string", description: "control name, e.g. 'players'" } },
      required: ["name"],
      additionalProperties: false,
    },
  },
  {
    name: "set_feature",
    description:
      "Set one menu control. For a checkbox pass value true/false; for a slider or combobox pass an " +
      "integer (combobox = option index from list_features). Danger controls fail unless writes are " +
      "armed in the overlay. Returns the value read back after it was applied.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "control name" },
        value: {
          description: "boolean for a checkbox, integer for a slider/combobox",
          type: ["boolean", "number", "string"],
        },
      },
      required: ["name", "value"],
      additionalProperties: false,
    },
  },
  {
    name: "connection_status",
    description: "Whether the Angel overlay is currently connected to this server.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
];

const server = new Server(
  { name: "angel-menu-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args = {} } = req.params;
  try {
    if (name === "connection_status") {
      const connected = !!scriptSock && scriptSock.readyState === scriptSock.OPEN;
      return textResult(
        connected
          ? "Overlay connected."
          : 'Overlay NOT connected. In the overlay: Others > Debug > "AI Menu Control: Connect".',
      );
    }

    if (name === "list_features") {
      const res = await request("ui_list");
      const rows = (res.results || []).map((c) => {
        let extra = "";
        if (c.kind === "slider") extra = ` [${c.min}..${c.max} step ${c.step}]`;
        else if (c.kind === "combo") extra = ` [${(c.options || []).join(" | ")}]`;
        const danger = c.danger ? " (DANGER: writes memory)" : "";
        return `${c.name} = ${JSON.stringify(c.value)}  <${c.kind}${extra}>${danger}`;
      });
      return textResult(
        `${res.count} controls:\n${rows.join("\n")}`,
      );
    }

    if (name === "get_feature") {
      if (!args.name) throw new Error("name is required");
      const res = await request("ui_get", { name: args.name });
      return textResult(`${res.name} = ${JSON.stringify(res.value)}  <${res.kind}>`);
    }

    if (name === "set_feature") {
      if (!args.name) throw new Error("name is required");
      if (args.value === undefined) throw new Error("value is required");
      const kind = await controlKind(args.name);
      const value = coerceValueForKind(kind, args.value);
      const res = await request("ui_set", { name: args.name, value });
      return textResult(
        `${res.name} set. now = ${JSON.stringify(res.value)}  <${res.kind}>`,
      );
    }

    throw new Error(`unknown tool: ${name}`);
  } catch (e) {
    return { isError: true, content: [{ type: "text", text: String(e.message || e) }] };
  }
});

function textResult(text) {
  return { content: [{ type: "text", text }] };
}

const transport = new StdioServerTransport();
await server.connect(transport);
logStderr("MCP server ready (stdio).");
