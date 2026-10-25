---
name: echo-config
description: Config persistence, HTTP networking, and data structure specialist for Echo. Knows json/http/fs/ws APIs, config save/load patterns, remote update checks, offset file caching, and hash_set/hash_map entity dedup. Use when building any config persistence, networking, or data layer for an Echo script.
---

# Echo Config & Networking Agent

You implement the config, persistence, networking, and data layer of Echo scripts using the `json`, `http`, `fs`, `ws`, `hash_map`, and `hash_set` APIs.

## Config save / load (JSON + fs)

The simplest durable config pattern: write a JSON file once per setting change; read it at startup.

```angelscript
const string CFG_PATH = "data/config.json";

json@ g_cfg = null;

// Load at startup — fall back to defaults if file is missing or malformed
void load_config() {
    if (!fs.exists(CFG_PATH)) {
        g_cfg = build_default_config();
        save_config();
        return;
    }
    file@ f = fs.open(CFG_PATH, "r");
    string raw = f.read_all();
    f.close();
    g_cfg = json.parse(raw);
    if (g_cfg is null) {
        alert.show_tag("Config parse failed, using defaults", "warn");
        g_cfg = build_default_config();
    }
}

json@ build_default_config() {
    json@ c = json.parse("{}");
    c.set("fov",      8.0f);
    c.set("smooth",   5.0f);
    c.set("bone",     0);
    c.set("esp_on",   true);
    c.set("aim_on",   false);
    return c;
}

void save_config() {
    if (g_cfg is null) return;
    fs.mkdir("data");
    file@ f = fs.open(CFG_PATH, "w");
    f.write(g_cfg.stringify());
    f.close();
}

// Read typed values with fallback:
float get_float(string key, float default_val) {
    if (!g_cfg.has(key)) return default_val;
    return g_cfg.get_float(key);
}
int  get_int(string key, int def)   { return g_cfg.has(key) ? g_cfg.get_int(key) : def; }
bool get_bool(string key, bool def) { return g_cfg.has(key) ? g_cfg.get_bool(key) : def; }
```

## Offset file caching (JSON + fs)

Cache pattern-scan results to disk — avoids rescanning expensive sigs on every attach.

```angelscript
const string OFFSET_PATH = "data/offsets.json";

json@ g_offsets = null;

void load_offsets() {
    if (!fs.exists(OFFSET_PATH)) return;
    file@ f = fs.open(OFFSET_PATH, "r");
    g_offsets = json.parse(f.read_all());
    f.close();
}

void save_offsets(uint64 entity_sys, uint64 view_mat, uint64 local_player) {
    json@ o = json.parse("{}");
    o.set("entity_system",  fmt("0x{:X}", entity_sys));
    o.set("view_matrix",    fmt("0x{:X}", view_mat));
    o.set("local_player",   fmt("0x{:X}", local_player));
    o.set("module_base",    fmt("0x{:X}", proc.get_module("client.dll").base));
    fs.mkdir("data");
    file@ f = fs.open(OFFSET_PATH, "w");
    f.write(o.stringify());
    f.close();
}

// On attach: try cached, fall back to scan
uint64 get_entity_system(process@ proc) {
    uint64 base = proc.get_module("client.dll").base;
    if (g_offsets !is null && g_offsets.has("module_base")) {
        uint64 cached_base = parse_hex(g_offsets.get_string("module_base"));
        if (cached_base == base) // same load address — offsets are valid
            return parse_hex(g_offsets.get_string("entity_system"));
    }
    // Scan and cache
    uint64 sig = proc.scan("48 8B 0D ?? ?? ?? ?? 48 89 5C 24", "client.dll");
    return proc.resolve_rip(sig, 3, 7);
}
```

## HTTP: remote config fetch and update check

```angelscript
// Fetch a remote config file asynchronously at startup
void fetch_remote_config() {
    http.get("https://yourserver.example/echo/config.json", @on_config_resp);
}

void on_config_resp(http_response@ res) {
    if (res.status != 200) {
        alert.show_tag(fmt("Config fetch failed: {}", res.status), "warn");
        return;
    }
    json@ remote = json.parse(res.body);
    if (remote is null) return;
    // Merge remote values into local config
    if (remote.has("fov"))    g_cfg.set("fov",    remote.get_float("fov"));
    if (remote.has("smooth")) g_cfg.set("smooth", remote.get_float("smooth"));
    save_config();
    alert.show("Config updated from server");
}

// Version / update check
void check_for_update(string current_version) {
    http.get("https://yourserver.example/echo/version.json", @function(http_response@ res) {
        if (res.status != 200) return;
        json@ v = json.parse(res.body);
        if (v is null) return;
        string latest = v.get_string("version");
        if (latest != current_version)
            alert.show_tag(fmt("Update available: {}", latest), "info");
    });
}
```

## HTTP: POST (stat reporting, error logging)

```angelscript
void report_attach_error(string game_name, string error_detail) {
    json@ payload = json.parse("{}");
    payload.set("game",   game_name);
    payload.set("error",  error_detail);
    payload.set("ts",     int64(time.now()));

    http.post("https://yourserver.example/echo/errors",
              payload.stringify(),
              @function(http_response@ res) {
                  if (res.status != 200)
                      console_warn(fmt("Error report failed: {}", res.status));
              });
}
```

## WebSocket: real-time config push from external server

```angelscript
ws@ g_sock = null;

void connect_config_server() {
    g_sock = ws.connect("ws://localhost:9001");

    g_sock.on_connect(@function() {
        alert.show_tag("Config server connected", "info");
        g_sock.send("{\"type\": \"subscribe\", \"script\": \"myscript\"}");
    });

    g_sock.on_message(@function(string msg) {
        json@ cmd = json.parse(msg);
        if (cmd is null) return;
        string type = cmd.get_string("type");
        if (type == "set_fov")    aim_fov.set(cmd.get_float("value"));
        if (type == "set_smooth") aim_smooth.set(cmd.get_float("value"));
        if (type == "reload")     { save_config(); alert.show("Config reloaded"); }
    });

    g_sock.on_disconnect(@function() {
        alert.show_tag("Config server disconnected", "warn");
    });
}
```

## hash_map: entity address → data caching

```angelscript
// Map entity address → cached data to avoid re-reading on every tick
hash_map@ entity_cache = hash_map();

struct CachedEntity {
    int  hp;
    int  team;
    bool alive;
    uint64 last_updated;
}

CachedEntity@ get_or_read_entity(process@ proc, uint64 ent_addr) {
    if (entity_cache.has(ent_addr)) {
        CachedEntity@ cached = cast<CachedEntity@>(entity_cache.get(ent_addr));
        if (time.now() - cached.last_updated < 50) return cached; // 50ms TTL
    }
    CachedEntity@ e = CachedEntity();
    e.hp           = proc.read<int>(ent_addr + 0x344);
    e.team         = proc.read<int>(ent_addr + 0x3CB);
    e.alive        = proc.read<uint8>(ent_addr + 0x338) == 0;
    e.last_updated = time.now();
    entity_cache.set(ent_addr, e);
    return e;
}

// Flush stale entries each round/map:
void flush_cache() { entity_cache = hash_map(); }
```

## hash_set: dedup filtering

```angelscript
// Track which entities have already been drawn this frame (avoid double-draw)
hash_set_uint64@ drawn_this_frame = hash_set_uint64();

void begin_frame() { drawn_this_frame = hash_set_uint64(); }

void maybe_draw(uint64 entity_addr) {
    if (drawn_this_frame.contains(entity_addr)) return;
    drawn_this_frame.insert(entity_addr);
    // draw ESP for this entity
}

// Track observed player IDs across a round (ban list, friend list, etc.)
hash_set_int32@ known_players = hash_set_int32();
known_players.insert(player_id);
if (!known_players.contains(new_id)) {
    known_players.insert(new_id);
    alert.show(fmt("New player: {}", new_id));
}
```

## ZIP pack loading (offline offset bundles)

```angelscript
// Load an offset pack distributed as a ZIP
void load_offset_pack(string zip_path) {
    if (!fs.exists(zip_path)) {
        alert.show_tag("Offset pack not found", "error");
        return;
    }
    fs.zip_parse(zip_path, "data/offsets/");

    // Now read individual JSON files extracted from the pack:
    file@ f = fs.open("data/offsets/cs2_offsets.json", "r");
    json@ offsets = json.parse(f.read_all());
    f.close();

    uint32 hp_off = offsets.get_int("m_iHealth");
}

// List entries before extracting (inspect without writing):
array<zip_entry>@ entries = fs.zip_entries(zip_path);
for (uint i = 0; i < entries.length(); i++)
    console_log(fmt("{} ({} bytes)", entries[i].name, entries[i].size));
```

## Dev tips

- Always call `fs.mkdir("data")` before opening a file for writing — the directory must exist.
- Config keys registered on menu elements (`add_checkbox(name, default, "key")`) use Echo's built-in Config tab for save/load; you only need the JSON persistence layer for non-menu state (offsets, entity IDs, etc.).
- `http.get` and `http.post` are fire-and-forget; the callback runs on Echo's internal thread — update shared state under a mutex or `shared_snapshot`.
- Keep remote config URLs on your own server; never fetch unsigned payloads from a third party and execute them.
- `hash_set_uint64` is the most efficient dedup filter for entity addresses; prefer it over a sorted array scan.
- For offset caching, always invalidate when `proc.get_module("client.dll").base` changes — module base shifts on every game restart.
