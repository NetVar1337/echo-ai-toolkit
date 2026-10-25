---
name: echo-workflow
description: How to chain echo-esp, echo-aimbot, echo-radar, echo-config, echo-memory and echo-loot into one script without duplicating memory reads or losing type safety: the three-layer model, a mutex-guarded shared snapshot, thread rate tables, and the startup sequence. Use when architecting a multi-feature Echo script.
---

# Echo Multi-Agent Workflow

How to chain echo-esp, echo-aimbot, echo-radar, echo-config, echo-memory, and echo-loot into a single script without duplicating memory reads or losing type safety.

## The three-layer model

```
Layer 1: Memory Reader (tick thread, 64–128 tps)
  → reads process memory, builds structured data

Layer 2: Logic (tick thread, same or lower rate)
  → consumes structured data, produces output commands

Layer 3: Renderer + Config (render thread + startup)
  → draws overlay, loads/saves settings
```

**The key rule:** each layer communicates only via a `mutex`-protected snapshot. No layer reads process memory in the render thread.

## Shared entity data (the hub struct)

```angelscript
mutex@ g_snap_lock = create_mutex();

struct EntityData {
    vec3  world_pos, head_pos;
    float sx_head, sy_head, sx_feet, sy_feet;
    int   hp, team;
    bool  alive, visible;
    float dist;
    string name;
    uint64 addr;
}

array<EntityData> g_entities;   // published by the reader, consumed by everyone else

// Writer (memory reader tick thread):
void tick_memory() {
    array<EntityData> frame;
    // ... populate from process::read_* calls ...

    g_snap_lock.lock();
    g_entities = frame;
    g_snap_lock.unlock();
}

// Reader (any other thread): copy under the lock, then use the copy freely
array<EntityData> read_entities() {
    g_snap_lock.lock_shared();
    array<EntityData> snap = g_entities;
    g_snap_lock.unlock_shared();
    return snap;
}
```

Copying the array under the lock keeps the lock hold time short and lets readers work on
their own copy without holding the lock during rendering.

## Wiring ESP + Aimbot + Radar

```angelscript
float    g_local_yaw = 0.0f;
vec3     g_local_pos;

// Memory reader (64 tps)
void tick_read() {
    array<EntityData> frame;
    // populate using echo-esp entity list patterns
    g_snap_lock.lock();
    g_entities = frame;
    g_snap_lock.unlock();
}

// Aimbot (128 tps)
void tick_aim() {
    if (!ui::get(g_aim_on)) return;
    if (!input::key_active(0x02)) return;          // VK_RBUTTON held

    array<EntityData> ents = read_entities();
    // select target, then move the mouse with input::mouse_move(x, y) — echo-aimbot patterns
}

// Render: ESP + Radar (every frame)
void draw() {
    array<EntityData> ents = read_entities();

    for (uint i = 0; i < ents.length(); i++) {
        if (!ents[i].alive) continue;

        // ESP: cornered box, health bar, label
        //   render::draw_box(x, y, w, h, r, g, b, a, box_style::CORNERED, 0.15f)
        //   render::draw_text(x, y, label, r, g, b, a)
        // Radar: world_to_radar + draw_entity_dot (user code)
        // Both read from the same snapshot — zero extra memory reads in render
    }
}
```

## Menu layer (echo-dev)

UI elements are created once, in order: tab → sub-tab → category → elements. Values are read
and written through the element handle.

```angelscript
checkbox g_esp_on = false;
checkbox g_aim_on = false;
slider   g_aim_fov = 8;

void build_menu() {
    ui::add_tab("Main");
    ui::add_category("Targets");

    g_esp_on = ui::add_checkbox("ESP", true);
    g_aim_on = ui::add_checkbox("Aimbot", false);

    ui::add_category("Aim");
    g_aim_fov = ui::add_slider("FOV", 8, 1, 30, 1, "deg");
}
```

## Config layer (echo-config)

`ui::config_path()` gives the script its own config directory and a config tab in the overlay
UI, so the user can save and load configurations without you writing any file code. For your
own key/value state, use the sandboxed filesystem API with JSON.

```angelscript
json_obj@ g_cfg = null;

void load_config() {
    string raw = "";
    if (file::read("my_script/config.json", raw)) {
        string err = "";
        g_cfg = json::parse(raw, err);
    }
    if (g_cfg is null) g_cfg = json_obj();
}

void save_config() {
    if (g_cfg is null) return;
    file::write("my_script/config.json", json::stringify(g_cfg));
}
```

Wire it into `main()` — build the menu first, then load the persisted values back into the
element handles, then register the save-on-change callback (see the startup sequence below
for the full `main()`):

```angelscript
// inside main(), after build_menu()
load_config();
if (g_cfg.has("aim.fov")) {
    ui::set(g_aim_fov, int(g_cfg.get_float("aim.fov")));
}

// Auto-save on change via a UI callback (checkbox_callback takes a bool)
ui::add_checkbox("Aimbot (persisted)", false, function(bool val) {
    g_cfg.set("aim.on", val);
    save_config();
});
```

## Loot layer (echo-loot)

Run at a lower rate — items don't move. Keep a separate snapshot.

```angelscript
create_thread(8, @tick_loot);   // 8 tps is enough for loot

mutex@ g_loot_lock = create_mutex();
array<LootEntry> g_loot;

void tick_loot() {
    array<LootEntry> items;
    // echo-loot scan patterns
    g_loot_lock.lock();
    g_loot = items;
    g_loot_lock.unlock();
}

void draw() {
    g_loot_lock.lock_shared();
    array<LootEntry> lsnap = g_loot;
    g_loot_lock.unlock_shared();

    for (uint i = 0; i < lsnap.length(); i++) {
        // draw_loot_panel(lsnap[i])
    }
}
```

## Thread rate table

| Thread | Rate | Purpose |
|--------|------|---------|
| Memory reader | 64 tps | Entity positions, health, bones |
| Aimbot | 128 tps | High-frequency mouse output |
| Loot scanner | 8–16 tps | Items don't move fast |
| Signature scanner | `create_thread(0, @cb)` | One-shot at attach |
| Render hook | every frame | `on_render(@draw)` — never read memory here |

## Startup sequence

```angelscript
bool main() {
    ui::config_path("my_script");            // echo-config: own config dir + config tab
    build_menu();                            // echo-dev UI patterns
    load_config();                           // echo-config

    attach_data ad = process::attach("game.exe");
    if (ad.pid == 0) {
        alert::show_tag("Attach failed", "error");
        return false;
    }

    create_thread(0,   @scan_sigs);          // echo-memory: one-shot sig scan
    create_thread(64,  @tick_read);          // echo-esp: entity reads
    create_thread(128, @tick_aim);           // echo-aimbot
    create_thread(8,   @tick_loot);          // echo-loot
    on_render(@draw);                        // echo-esp + echo-radar
    return true;
}

void on_unload() {
    save_config();
    process::detach();
}
```

## Anti-patterns

| Anti-pattern | Problem | Fix |
|---|---|---|
| `process::read_*` inside `on_render` | Blocks render, causes stutter | Move reads to tick threads |
| Two threads each reading the entity list | Double IPC cost | One reader, snapshot for the rest |
| `save_config()` every tick | Filesystem thrash | Save only from the UI callback |
| One giant `EntityData` for both players and loot | Mismatched schemas | Separate structs per data shape |
| Aimbot at 8 tps because "scan uses that" | Sluggish, target overshoots | Aimbot gets its own 128 tps thread |
| Reading memory without attaching | Reads return default values silently | Attach in `main()` and check `ad.pid` |
| Using `ui::get`/`ui::set` from a tick thread | UI state is owned by the render thread | Read UI values at the start of the tick, store in a local |
