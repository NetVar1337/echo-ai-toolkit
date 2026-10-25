---
name: echo-config
description: Config persistence, HTTP networking, and data structure specialist for Echo. Knows json/http/fs/ws APIs, config save/load patterns, remote update checks, offset file caching, and hash_set/hash_map entity dedup. Use when building any config persistence, networking, or data layer for an Echo script.
---

# Echo Config & Networking Agent

You implement the config, persistence, networking, and data layer of Echo scripts using the `json`, `http`, `file`,
`ws`, `hash_map`, and `hash_set` APIs.

## Config save / load (JSON + file)

The simplest durable config pattern: write a JSON file once per setting change; read it at startup.

```angelscript
const string CFG_PATH = "config.json";

json_obj@ g_cfg = null;

json_obj@ build_default_config() {
    json_obj@ c = json_obj();
    c.set("fov",      8.0f);
    c.set("smooth",   5.0f);
    c.set("bone",     0);
    c.set("esp_on",   true);
    c.set("aim_on",   false);
    return c;
}

// Load at startup — fall back to defaults if the file is missing or malformed
void load_config() {
    string raw;
    if (!file::read(CFG_PATH, raw)) {
        g_cfg = build_default_config();
        save_config();
        return;
    }
    string err;
    g_cfg = json::parse(raw, err);
    if (g_cfg is null) {
        alert::show_tag("Config parse failed: " + err, "warn");
        g_cfg = build_default_config();
    }
}

void save_config() {
    if (g_cfg is null) return;
    file::write(CFG_PATH, json::stringify(g_cfg, true));
}

// Read typed values with fallback:
float get_float(string key, float default_val) {
    if (g_cfg is null || !g_cfg.has(key)) return default_val;
    return g_cfg.get_float(key);
}
int  get_int(string key, int def)   { return (g_cfg is null || !g_cfg.has(key)) ? def : g_cfg.get_int(key); }
bool get_bool(string key, bool def) { return (g_cfg is null || !g_cfg.has(key)) ? def : g_cfg.get_bool(key); }
```

## Offset file caching (JSON + file)

Cache pattern-scan results to disk — avoids rescanning expensive signatures on every attach.

```angelscript
const string OFFSET_PATH = "offsets.json";

json_obj@ g_offsets = null;

void load_offsets() {
    string raw;
    if (!file::read(OFFSET_PATH, raw)) return;
    string err;
    g_offsets = json::parse(raw, err);
}

void save_offsets(uint64 entity_sys, uint64 view_mat, uint64 local_player, uint64 module_base) {
    json_obj@ o = json_obj();
    o.set("entity_system", entity_sys);
    o.set("view_matrix",   view_mat);
    o.set("local_player",  local_player);
    o.set("module_base",   module_base);
    file::write(OFFSET_PATH, json::stringify(o, true));
}

// On attach: try the cached values, fall back to a scan
uint64 get_entity_system() {
    uint64 base = process::get_module_base("client.dll");
    if (base == 0) return 0;

    if (g_offsets is null || !g_offsets.has("module_base")) {
        // Scan and cache. Signature below is a PLACEHOLDER — re-verify per patch.
        uint64 sig = process::find_signature(base, "48 8B 0D ? ? ? ? 48 89 5C 24");
        if (sig == 0) return 0;
        uint64 resolved = process::get_relative_address(sig, 3, 7);
        save_offsets(resolved, 0, 0, base);
        return resolved;
    }

    uint64 cached_base = g_offsets.get_uint64("module_base");
    if (cached_base == base) // same load address — cached offsets are valid
        return g_offsets.get_uint64("entity_system");

    // Base moved (game restarted) — rescan
    uint64 sig = process::find_signature(base, "48 8B 0D ? ? ? ? 48 89 5C 24");
    if (sig == 0) return 0;
    return process::get_relative_address(sig, 3, 7);
}
```

## HTTP: remote config fetch and update check

`http::get` / `http::post` are asynchronous and only callable from `main()`. The callback runs on an Echo
thread — protect any shared state it touches.

```angelscript
// Fetch a remote config file asynchronously at startup
void fetch_remote_config() {
    http::get("https://yourserver.example/echo/config.json", @on_config_resp);
}

void on_config_resp(http_response@ res) {
    if (res.error != "") {
        alert::show_tag("Config fetch failed: " + res.error, "warn");
        return;
    }
    if (res.status_code != 200) {
        alert::show_tag(util::format_string("Config fetch failed: {}", res.status_code), "warn");
        return;
    }
    string err;
    json_obj@ remote = json::parse(res.body, err);
    if (remote is null) return;

    // Merge remote values into the local config
    if (remote.has("fov"))    g_cfg.set("fov",    remote.get_float("fov"));
    if (remote.has("smooth")) g_cfg.set("smooth", remote.get_float("smooth"));
    save_config();
    alert::show("Config updated from server");
}

// Version / update check
void check_for_update(string current_version) {
    http::get("https://yourserver.example/echo/version.json", @on_version_resp);
}

void on_version_resp(http_response@ res) {
    if (res.error != "" || res.status_code != 200) return;
    string err;
    json_obj@ v = json::parse(res.body, err);
    if (v is null) return;
    string latest = v.get_string("version");
    if (latest != current_version)
        alert::show_tag("Update available: " + latest, "info");
}
```

## HTTP: POST (stat reporting, error logging)

```angelscript
void report_attach_error(string game_name, string error_detail) {
    json_obj@ payload = json_obj();
    payload.set("game",  game_name);
    payload.set("error", error_detail);
    payload.set("ts",    util::time_now());

    http::post("https://yourserver.example/echo/errors",
               json::stringify(payload),
               "application/json",
               @on_report_resp);
}

void on_report_resp(http_response@ res) {
    if (res.error != "" || res.status_code != 200)
        console::warn("Error report failed: " + res.error);
}
```

## WebSocket: real-time config push from an external server

```angelscript
// Module-level ws functions — there is no ws object to hold.
// g_aim_fov / g_aim_smooth are slider handles registered in main().
slider g_aim_fov;
slider g_aim_smooth;

void on_ws_open() {
    alert::show_tag("Config server connected", "info");
    ws::send("{\"type\": \"subscribe\", \"script\": \"myscript\"}");
}

void on_ws_message(string msg) {
    string err;
    json_obj@ cmd = json::parse(msg, err);
    if (cmd is null) return;
    string type = cmd.get_string("type");
    if (type == "set_fov")    ui::set(g_aim_fov, int(cmd.get_float("value")));
    if (type == "set_smooth") ui::set(g_aim_smooth, int(cmd.get_float("value")));
    if (type == "reload")    { save_config(); alert::show("Config reloaded"); }
}

void on_ws_disconnect() { alert::show_tag("Config server disconnected", "warn"); }
void on_ws_error(string err) { console::error("WS error: " + err); }

void connect_config_server() {
    ws::connect("ws://localhost:9001", @on_ws_open, @on_ws_message, @on_ws_disconnect, @on_ws_error);
}
```

## hash_map: entity address → data caching

```angelscript
// Map entity address → cached scalar values to avoid re-reading on every tick.
// The map is keyed by uint64 and stores typed values.
hash_map@ entity_hp_cache   = create_hash_map();
hash_map@ entity_team_cache = create_hash_map();
hash_map@ entity_time_cache = create_hash_map();

bool get_or_read_entity(uint64 ent_addr, int32 &out hp, int32 &out team) {
    int32 cached_hp = 0, cached_team = 0;
    uint64 cached_time = 0;
    bool has_hp   = entity_hp_cache.get_int32(ent_addr, cached_hp);
    bool has_team = entity_team_cache.get_int32(ent_addr, cached_team);
    bool has_time = entity_time_cache.get_uint64(ent_addr, cached_time);

    if (has_hp && has_team && has_time && util::time_now() - cached_time < 50) { // 50ms TTL
        hp   = cached_hp;
        team = cached_team;
        return true;
    }

    hp   = process::read_int32(ent_addr + 0x344); // PLACEHOLDER
    team = process::read_int32(ent_addr + 0x3CB); // PLACEHOLDER
    entity_hp_cache.set_int32(ent_addr, hp);
    entity_team_cache.set_int32(ent_addr, team);
    entity_time_cache.set_uint64(ent_addr, util::time_now());
    return true;
}

// Flush stale entries each round/map:
void flush_cache() {
    entity_hp_cache.clear();
    entity_team_cache.clear();
    entity_time_cache.clear();
}
```

## hash_set: dedup filtering

```angelscript
// Track which entities have already been drawn this frame (avoid double-draw)
hash_set_uint64@ drawn_this_frame = create_hash_set_uint64();

void begin_frame() { drawn_this_frame.clear(); }

bool should_process(uint64 ent_addr) {
    if (drawn_this_frame.contains(ent_addr)) return false;
    drawn_this_frame.insert(ent_addr);
    return true;
}

// Track observed player IDs across a round (ban list, friend list, etc.)
hash_set_int32@ known_players = create_hash_set_int32();
known_players.insert(player_id);
if (!known_players.contains(new_id)) {
    known_players.insert(new_id);
    alert::show(util::format_string("New player: {}", new_id));
}
```

## ZIP pack loading (offline offset bundles)

```angelscript
// Load an offset pack distributed as a ZIP.
// util::zip_parse takes the raw zip bytes; the archive must be flat (no subdirectories).
void load_offset_pack(string zip_path) {
    string zip_bytes;
    if (!file::read(zip_path, zip_bytes)) {
        alert::show_tag("Offset pack not found", "error");
        return;
    }
    array<zip_entry>@ entries = util::zip_parse(zip_bytes);
    if (entries is null) {
        alert::show_tag("Offset pack could not be parsed", "error");
        return;
    }
    dir::create("offsets");
    for (uint i = 0; i < entries.length(); i++) {
        file::write("offsets/" + entries[i].name, entries[i].data);
    }
}

// Read an individual JSON file extracted from the pack:
string raw;
if (file::read("offsets/cs2_offsets.json", raw)) {
    string err;
    json_obj@ offsets = json::parse(raw, err);
    if (offsets is not null) {
        uint32 hp_off = offsets.get_uint("m_iHealth");
    }
}
```

## Dev tips

- File paths are relative to the script data directory — use `"config.json"`, not `"data/config.json"`.
  Call `dir::create("subdir")` (one level deep) before writing into a subdirectory.
- Menu elements registered with a config key get Echo's built-in Config tab for save/load; you only need the
  JSON persistence layer for non-menu state (offsets, entity IDs, etc.).
- `http::get` / `http::post` are async — the callback runs on an Echo thread, so update shared state under
  a mutex or via `shared_snapshot`.
- Keep remote config URLs on your own server; never fetch unsigned payloads from a third party and execute them.
- `hash_set_uint64` is the most efficient dedup filter for entity addresses; prefer it over a sorted array scan.
- For offset caching, always invalidate when the module base changes — the base shifts on every game restart.
- Cached offsets are only as good as the build they were captured from; re-verify them after every patch.
