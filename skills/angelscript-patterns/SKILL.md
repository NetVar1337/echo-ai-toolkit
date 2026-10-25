---
name: angelscript-patterns
description: Reusable Echo AngelScript patterns: mutex-guarded entity buffers, thread-safe tick and render loops, safe deref chains, rate limiters, scan fallbacks, W2S null checks. Use when writing or structuring an Echo script that shares state across threads.
---

# Echo AngelScript patterns

Common patterns for Echo scripts. These complement the raw API in `reference/api.md`.

---

## main() error guard

Always gate the whole script on attach success so errors surface immediately rather than crashing silently in the render loop.

```angelscript
attach_data g_attach;
uint64      g_base = 0;

bool main() {
    g_attach = process::attach("game.exe");
    if (g_attach.pid == 0) {
        alert::show("game.exe not found");
        return false;
    }

    g_base = process::get_module_base("game.exe");
    if (g_base == 0) {
        alert::show("could not read module base");
        return false;
    }

    create_thread(20, @tick);       // 20 Hz — tps 0 would run the callback once and exit
    on_render(@render_tick);
    return true;
}

void on_unload() {
    process::detach();
}
```

---

## Thread-safe entity buffer (tick/render split)

Read entities on a background thread; the render thread only reads the snapshot. Avoids tearing when the render loop and the tick loop run concurrently.

```angelscript
mutex@ g_lock = create_mutex();

class Entity {
    vec3  pos;
    float health;
    bool  valid;
}

array<Entity@> g_entities;      // written by tick, read by render

void tick() {
    array<Entity@> snapshot;
    // ... fill snapshot from process::read_* calls, allocating a fresh Entity per entry ...

    g_lock.lock();
    g_entities = snapshot;      // shallow buffer copy, done under the lock
    g_lock.unlock();
}

void render_tick() {
    g_lock.lock();
    array<Entity@> local = g_entities;   // shallow buffer copy under the lock
    g_lock.unlock();

    for (uint i = 0; i < local.length(); i++) {
        if (!local[i].valid) continue;
        // draw local[i]
    }
}
```

`create_thread(20, @tick)` drives the tick callback at 20 Hz — do not add a `while`/`sleep`
loop inside the callback, and do not pass `tps 0` (that runs the callback once and exits).
Script classes are reference types, so each published entity must be a fresh instance; the
array copy only copies the handles.

---

## Safe pointer chase with validation

Raw reads can return garbage if the game is mid-update or the pointer is stale. Validate before using.

```angelscript
// Read a pointer and follow it; returns 0 on any bad step
// (user code, not Echo API)
uint64 safe_deref(uint64 base, const array<uint32> &in offsets) {
    uint64 ptr = base;
    for (uint i = 0; i < offsets.length(); i++) {
        if (ptr == 0 || ptr < 0x10000) return 0;   // null / kernel space
        ptr = process::read_uint64(ptr + offsets[i]);
    }
    return ptr;
}

// Usage: entity list pointer chain
// ILLUSTRATIVE offsets — placeholders, re-derive them for your target
array<uint32> chain = {0x18, 0x30, 0x8};
uint64 client = process::get_module_base("client.dll");
if (client == 0) return;                                  // module not loaded
uint64 entity_list = safe_deref(client + 0x1234, chain);
if (entity_list == 0) return;
```

Use the out-parameter read overload when a genuine `0` is meaningful:

```angelscript
uint64 ptr = 0;
if (!process::read_uint64(addr, ptr)) return;   // false = the read itself failed
if (ptr == 0) return;                             // 0 = the field is genuinely null
```

---

## Config persistence

Echo's `ui::config_path()` gives the script its own config directory and a config tab in the
overlay UI. For your own key/value state, use the sandboxed filesystem API with JSON.

```angelscript
string g_cfg_path = "my_script/config.json";

json_obj@ g_cfg = null;

void load_config() {
    string raw = "";
    if (file::read(g_cfg_path, raw)) {
        string err = "";
        g_cfg = json::parse(raw, err);
    }
    if (g_cfg is null) {
        g_cfg = json_obj();   // fresh empty object
    }
}

void save_config() {
    if (g_cfg is null) return;
    file::write(g_cfg_path, json::stringify(g_cfg));
}

bool main() {
    ui::config_path("my_script");
    load_config();
    // ...
    return true;
}

void on_unload() {
    save_config();
}
```

---

## Menu with handle-backed controls

UI elements are created once, in order: tab → sub-tab → category → elements. Values are read
and written through the element handle.

```angelscript
checkbox g_esp_enabled = false;
checkbox g_aim_enabled = false;
slider   g_aim_fov = 8;

bool main() {
    ui::config_path("my_script");

    ui::add_tab("Main");
    ui::add_category("Options");

    g_esp_enabled = ui::add_checkbox("ESP", true);
    g_aim_enabled = ui::add_checkbox("Aimbot", false);
    g_aim_fov     = ui::add_slider("FOV", 8, 1, 30, 1, "deg");

    on_render(@render_tick);
    return true;
}

void render_tick() {
    bool esp_on = ui::get(g_esp_enabled);
    int   fov   = ui::get(g_aim_fov);

    // writing back is allowed but rarely needed
    ui::set(g_aim_fov, fov);
}
```

---

## Pattern scan with fallback

If the primary signature breaks after a patch, fall back to a secondary one before alerting.

```angelscript
// ILLUSTRATIVE patterns — placeholders, re-verify per game patch
uint64 find_entity_system() {
    uint64 client = process::get_module_base("client.dll");
    if (client == 0) return 0;

    // primary — precise, may break after patching
    uint64 addr = process::find_signature(client, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 4C 8B 01");
    if (addr != 0) return process::get_relative_address(addr, 3, 7);

    // secondary — longer, more stable across minor patches
    addr = process::find_signature(client, "4C 8B 05 ? ? ? ? 4D 85 C0 74 ? 4C 8B 08");
    if (addr != 0) return process::get_relative_address(addr, 3, 7);

    alert::show("entity system pattern broken — needs update");
    return 0;
}
```

`process::find_signature(base, sig)` is the IDA-style form (wildcards are `?` or `??`).
`process::find_signature(base, sig, mask)` is the byte-mask form, where the mask uses
`x` for match and `?` for wildcard.

---

## Timer / rate limiter

Run expensive work (network call, heavy scan) at a fixed interval without blocking the render thread.

```angelscript
uint64 last_update_ms = 0;
const uint64 UPDATE_INTERVAL = 1000;   // 1 second

void render_tick() {
    uint64 now = util::tickcount();
    if (now - last_update_ms >= UPDATE_INTERVAL) {
        last_update_ms = now;
        do_expensive_update();   // user code
    }
    // fast draw path here
}
```

For sub-millisecond precision use `util::time_now()` and `util::time_ms(start, end)`.

---

## String formatting

```angelscript
// Formatted distance label
float dist = local_pos.distance(enemy_pos);
string label = util::format_string("{:.0f}m", dist);
render::draw_text(int(screen.x), int(screen.y), label, 255, 255, 255, 180);

// Health bar percentage text
string hp_text = util::format_string("{}/{}", int(cur_hp), int(max_hp));

// Hex address for debugging
console::log(util::format_string("entity at: {}", util::to_hex(entity_ptr)));
```

`util::format_string` supports `{}` (next argument), `{0}` (by index), `{:<8}` / `{08}` (alignment
and width) and `{:.2}` (precision). `util::to_hex(value)` prefixes `0x` by default.

---

## W2S null check

The engine-specific `w2s` helpers write into an out-parameter and return `false` when the
target is behind the camera or off-screen. Always check the return value.

```angelscript
vec2 screen;
if (!source2::w2s(world_pos, view_matrix, screen)) continue;

vec2 vp = render::get_viewport_size();
if (screen.x < 0 || screen.y < 0) continue;
if (screen.x > vp.x || screen.y > vp.y) continue;
// safe to draw
```

For Unreal, build the view cache once per frame and pass it in:

```angelscript
f_view_info camera;
camera.location = cam_loc;
camera.rotation = cam_rot;
camera.fov = 90.0f;
f_view_cache cache = build_view_cache(camera);

vec2 screen;
if (!unreal::w2s(world_pos, cache, screen)) continue;
```
