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

**The key rule:** each layer communicates only via `shared_snapshot` or a `mutex`-protected array. No layer reads process memory in the render thread.

## Shared entity data (the hub struct)

```angelscript
struct EntityData {
    vec3  world_pos, head_pos;
    float sx_head, sy_head, sx_feet, sy_feet;
    int   hp, team;
    bool  alive, visible;
    float dist;
    string name;
    uint64 addr;
}

shared_snapshot<array<EntityData>> g_entity_snapshot;

// Writer (memory reader tick thread):
void tick_memory() {
    array<EntityData> frame;
    // ... populate from proc.read calls ...
    g_entity_snapshot.publish(frame);
}

// Reader (any other thread):
snapshot_t<array<EntityData>> snap = g_entity_snapshot.read();
if (!snap.valid) return;
array<EntityData>@ ents = snap.value;
```

## Wiring ESP + Aimbot + Radar

```angelscript
shared_snapshot<array<EntityData>> g_ents;
float g_local_yaw = 0.0f;
vec3@ g_local_pos = vec3();

// Memory reader (64 tps)
void tick_read() {
    array<EntityData> frame;
    // populate using echo-esp entity list patterns
    g_entity_snapshot.publish(frame);
}

// Aimbot (128 tps)
void tick_aim() {
    if (!aim_on.get() || !input.key_active(0x02)) return;
    snapshot_t<array<EntityData>> snap = g_entity_snapshot.read();
    if (!snap.valid) return;
    // select target, call mouse.move() — echo-aimbot patterns
}

// Render: ESP + Radar (every frame)
void draw() {
    snapshot_t<array<EntityData>> snap = g_entity_snapshot.read();
    if (!snap.valid) return;
    array<EntityData>@ ents = snap.value;

    for (uint i = 0; i < ents.length(); i++) {
        // ESP: draw_cornered_box, draw_healthbar, draw_label
        // Radar: world_to_radar + draw_entity_dot
        // Both read from the same snapshot — zero extra memory reads in render
    }
}
```

## Config layer (echo-config)

```angelscript
bool main() {
    load_config(); // echo-config: fs.open + json.parse

    aim_fov.set(get_float("aim.fov", 8.0f));
    esp_dist.set(get_float("esp.dist", 3000.0f));

    // Auto-save on change via UI callbacks
    aim_fov.set_callback(@function(float v) { g_cfg.set("aim.fov", v); save_config(); });
    // ...
}
```

## Loot layer (echo-loot)

Run at a lower rate — items don't move. Keep a separate snapshot.

```angelscript
create_thread(8, @tick_loot); // 8 tps is enough for loot

shared_snapshot<array<LootEntry>> g_loot_snapshot;

void tick_loot() {
    array<LootEntry> items;
    // echo-loot scan patterns
    g_loot_snapshot.publish(items);
}

void draw() {
    // ... ESP / radar draws ...
    snapshot_t<array<LootEntry>> lsnap = g_loot_snapshot.read();
    if (lsnap.valid) draw_loot_panel(lsnap.value, fnt);
}
```

## Thread rate table

| Thread | Rate | Purpose |
|--------|------|---------|
| Memory reader | 64 tps | Entity positions, health, bones |
| Aimbot | 128 tps | High-frequency mouse output |
| Loot scanner | 8–16 tps | Items don't move fast |
| Signature scanner | `create_thread(0,...)` | One-shot at attach |
| Render hook | every frame | `on_render(@draw)` — never read memory here |

## Startup sequence

```angelscript
bool main() {
    build_menu();                            // echo-dev UI patterns
    load_config();                           // echo-config

    proc = process.attach("game.exe");
    if (proc is null) { alert.show_tag("Attach failed", "error"); return false; }

    create_thread(0,   @scan_sigs);          // echo-memory: one-shot sig scan
    create_thread(64,  @tick_read);          // echo-esp: entity reads
    create_thread(128, @tick_aim);           // echo-aimbot
    create_thread(8,   @tick_loot);          // echo-loot
    on_render(@draw);                        // echo-esp + echo-radar
    return true;
}
```

## Anti-patterns

| Anti-pattern | Problem | Fix |
|---|---|---|
| `proc.read` inside `on_render` | Blocks render, causes stutter | Move reads to tick threads |
| Two threads each reading the entity list | Double IPC cost | One reader, snapshot for the rest |
| `save_config()` every tick | Filesystem thrash | Save only in `set_callback` |
| One giant `EntityData` for both players and loot | Mismatched schemas | Separate structs per data shape |
| Aimbot at 8 tps because "scan uses that" | Sluggish, target overshoots | Aimbot gets its own 128 tps thread |
