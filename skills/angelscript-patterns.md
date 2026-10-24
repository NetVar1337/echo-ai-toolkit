# Echo AngelScript patterns

Common patterns for Echo scripts. These complement the raw API in `reference/api.md`.

---

## main() error guard

Always gate the whole script on attach success so errors surface immediately rather than crashing silently in the render loop.

```angelscript
process@ proc = null;

bool main() {
    proc = process.attach("game.exe");
    if (proc is null) { alert("game.exe not found"); return false; }

    uint64 base = proc.get_module("game.exe").base;
    if (base == 0) { alert("could not read module base"); return false; }

    create_thread(0, @tick);
    on_render(@render);
    return true;
}

void on_unload() {
    proc = null;
}
```

---

## Thread-safe entity buffer (tick/render split)

Read entities on a background thread; render thread only reads the snapshot. Avoids tearing when the render loop and the tick loop run concurrently.

```angelscript
mutex entity_lock;

struct Entity {
    vec3  pos;
    float health;
    bool  valid;
}

array<Entity> entities;      // written by tick, read by render

void tick() {
    while (true) {
        sleep(50);           // 20 Hz update rate

        array<Entity> snapshot;
        // ... fill snapshot from proc.read calls ...

        entity_lock.lock();
        entities = snapshot;
        entity_lock.unlock();
    }
}

void render() {
    entity_lock.lock();
    array<Entity> local = entities;   // copy under lock
    entity_lock.unlock();

    for (uint i = 0; i < local.length(); i++) {
        if (!local[i].valid) continue;
        // draw local[i]
    }
}
```

---

## Safe proc.read with validation

Raw reads can return garbage if the game is mid-update or the pointer is stale. Validate before using.

```angelscript
// Read a pointer and follow it; returns 0 on any bad step
uint64 safe_deref(uint64 base, array<uint32>@ offsets) {
    uint64 ptr = base;
    for (uint i = 0; i < offsets.length(); i++) {
        if (ptr == 0 || ptr < 0x10000) return 0;   // null / kernel space
        ptr = proc.read<uint64>(ptr + offsets[i]);
    }
    return ptr;
}

// Usage: entity list pointer chain
array<uint32> chain = {0x18, 0x30, 0x8};
uint64 entity_list = safe_deref(proc.get_module("client.dll").base + 0x1234, chain);
if (entity_list == 0) return;
```

---

## Config persistence

Save and restore checkboxes / sliders across script reloads via Echo's config API.

```angelscript
bool esp_enabled   = true;
bool aimbot_active = false;
float fov          = 5.0f;

void load_config() {
    esp_enabled   = config.read_bool("esp_enabled",   true);
    aimbot_active = config.read_bool("aimbot_active",  false);
    fov           = config.read_float("aimbot_fov",    5.0f);
}

void save_config() {
    config.write_bool("esp_enabled",   esp_enabled);
    config.write_bool("aimbot_active", aimbot_active);
    config.write_float("aimbot_fov",   fov);
}

bool main() {
    load_config();
    // ...
    return true;
}

void on_unload() {
    save_config();
}
```

---

## Menu with config-backed controls

```angelscript
void build_menu() {
    menu.begin("My Script");

    menu.checkbox("ESP",    @esp_enabled);
    menu.checkbox("Aimbot", @aimbot_active);

    if (aimbot_active) {
        menu.slider_float("FOV", @fov, 1.0f, 30.0f);
    }

    menu.end();
}

bool main() {
    load_config();
    on_render(@render);
    menu.register(@build_menu);
    return true;
}
```

---

## Pattern scan with fallback

If the primary sig breaks after a patch, fall back to a secondary before alerting.

```angelscript
uint64 find_entity_system() {
    // primary — precise, may break after patching
    uint64 addr = proc.scan_ida(
        "48 8B 0D ? ? ? ? 48 85 C9 74 ? 4C 8B 01",
        "client.dll"
    );
    if (addr != 0) return proc.resolve_rip(addr, 3, 7);

    // secondary — longer, more stable across minor patches
    addr = proc.scan_ida(
        "4C 8B 05 ? ? ? ? 4D 85 C0 74 ? 4C 8B 08",
        "client.dll"
    );
    if (addr != 0) return proc.resolve_rip(addr, 3, 7);

    alert("entity system pattern broken — needs update");
    return 0;
}
```

---

## Timer / rate limiter

Run expensive work (network call, heavy scan) at a fixed interval without blocking the render thread.

```angelscript
uint64 last_update_ms = 0;
const uint64 UPDATE_INTERVAL = 1000;   // 1 second

void render() {
    uint64 now = time.now_ms();
    if (now - last_update_ms >= UPDATE_INTERVAL) {
        last_update_ms = now;
        do_expensive_update();
    }
    // fast draw path here
}
```

---

## String formatting

```angelscript
// Formatted distance label
float dist = math.distance(local_pos, enemy_pos);
string label = fmt("{:.0f}m", dist);
draw.text(screen.x, screen.y, label, color(255, 255, 255, 180), 11.0f);

// Health bar percentage text
string hp_text = fmt("{}/{}", int(cur_hp), int(max_hp));

// Hex address for debugging
console_log(fmt("entity at: 0x{:X}", entity_ptr));
```

---

## W2S null check

`math.world_to_screen` returns false when the target is behind the camera. Always check.

```angelscript
vec2 screen;
if (!math.world_to_screen(view_matrix, world_pos, screen)) continue;
if (screen.x < 0 || screen.y < 0) continue;
if (screen.x > render_width || screen.y > render_height) continue;
// safe to draw
```
