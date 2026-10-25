---
name: echo-radar
description: 2D radar/minimap overlay specialist for Echo. Knows world-to-radar coordinate transforms, rotating map, entity dots, distance rings, and directional indicators. Use when building any 2D radar, minimap, or directional awareness overlay.
---

# Echo Radar Agent

You build 2D radar overlays that map world positions to a flat screen panel using Echo's rendering API.

## Coordinate transform (world → radar)

The radar is a rectangle on screen. Each world position maps to a 2D point within it.

```angelscript
struct RadarConfig {
    float cx, cy;     // radar center on screen (pixels)
    float radius;     // radar circle radius (pixels)
    float range;      // world units covered by the full radius
    float yaw;        // local player's view yaw (degrees) — used for rotation
}

// Returns false if entity falls outside the radar circle
bool world_to_radar(RadarConfig& cfg, vec3@ local_pos, vec3@ ent_pos,
                    float& out_rx, float& out_ry) {
    float dx = ent_pos.x - local_pos.x;
    float dy = ent_pos.y - local_pos.y;

    // Rotate by negative view yaw so forward is always "up" on radar
    float rad = cfg.yaw * 3.14159265f / 180.0f;
    float cos_a =  cos(-rad);
    float sin_a =  sin(-rad);
    float rx = dx * cos_a - dy * sin_a;
    float ry = dx * sin_a + dy * cos_a;

    // Scale from world units to screen pixels
    float scale = cfg.radius / cfg.range;
    float px = cfg.cx + rx * scale;
    float py = cfg.cy - ry * scale; // y is inverted (screen y grows down)

    // Clamp to circle
    float dist_px = sqrt((px - cfg.cx)*(px - cfg.cx) + (py - cfg.cy)*(py - cfg.cy));
    if (dist_px > cfg.radius) return false;

    out_rx = px;
    out_ry = py;
    return true;
}
```

## Radar panel background

```angelscript
void draw_radar_background(RadarConfig& cfg) {
    // Dark circle background
    renderer.circle(cfg.cx, cfg.cy, cfg.radius, 64, color(0, 0, 0, 160));

    // Concentric distance rings at 1/4, 1/2, 3/4 of range
    for (int i = 1; i <= 3; i++) {
        float ring_r = cfg.radius * (i / 4.0f);
        renderer.circle(cfg.cx, cfg.cy, ring_r, 48, color(100, 100, 100, 60));
    }

    // Crosshair lines (N/S/E/W)
    renderer.line(cfg.cx - cfg.radius, cfg.cy, cfg.cx + cfg.radius, cfg.cy, 1.0f, color(100, 100, 100, 80));
    renderer.line(cfg.cx, cfg.cy - cfg.radius, cfg.cx, cfg.cy + cfg.radius, 1.0f, color(100, 100, 100, 80));

    // Outer ring border
    renderer.circle(cfg.cx, cfg.cy, cfg.radius, 64, color(180, 180, 180, 120));
}
```

## Local player dot + FOV cone

```angelscript
void draw_local_player(RadarConfig& cfg, float fov_deg) {
    // Center dot
    renderer.circle(cfg.cx, cfg.cy, 4.0f, 12, color(255, 255, 255, 255));

    // FOV cone: two lines from center outward
    float half_fov = fov_deg * 0.5f * 3.14159265f / 180.0f;
    float cone_len = cfg.radius * 0.35f;
    // Since we rotate the map by -yaw, player always faces "up" (negative y in screen space)
    float lx = cfg.cx + sin(-half_fov) * cone_len;
    float ly = cfg.cy - cos(-half_fov) * cone_len;
    float rx = cfg.cx + sin( half_fov) * cone_len;
    float ry = cfg.cy - cos( half_fov) * cone_len;
    renderer.line(cfg.cx, cfg.cy, lx, ly, 1.0f, color(255, 255, 255, 100));
    renderer.line(cfg.cx, cfg.cy, rx, ry, 1.0f, color(255, 255, 255, 100));
}
```

## Enemy dot with team color

```angelscript
void draw_entity_dot(float rx, float ry, int team, bool visible, int hp) {
    // Color by team and visibility
    color c;
    if (team == 2)          c = color(80,  140, 255, 220); // CT / friendly
    else if (visible)       c = color(220, 60,  60,  255); // T visible
    else                    c = color(200, 100, 100, 180); // T behind wall

    // Dot size hints at health: 4px full, 2px near-dead
    float dot_r = 2.0f + 2.0f * (float(hp) / 100.0f);
    renderer.circle(rx, ry, dot_r, 8, c);

    // Black outline for readability
    renderer.circle(rx, ry, dot_r + 1.0f, 8, color(0, 0, 0, 160));
}
```

## Edge indicator (entity outside radar range)

When an entity falls outside the radar radius, draw a directional arrow on the rim.

```angelscript
void draw_edge_indicator(RadarConfig& cfg, vec3@ local_pos, vec3@ ent_pos,
                         float yaw, color c) {
    float dx = ent_pos.x - local_pos.x;
    float dy = ent_pos.y - local_pos.y;

    // Rotate by -yaw
    float rad   = yaw * 3.14159265f / 180.0f;
    float cos_a = cos(-rad), sin_a = sin(-rad);
    float rx    = dx * cos_a - dy * sin_a;
    float ry    = dx * sin_a + dy * cos_a;

    // Normalize and scale to rim
    float len = sqrt(rx*rx + ry*ry);
    if (len < 0.001f) return;
    float nx = rx / len;
    float ny = ry / len;

    float rim_x = cfg.cx + nx * (cfg.radius - 6.0f);
    float rim_y = cfg.cy - ny * (cfg.radius - 6.0f);

    // Small triangle pointing toward entity
    float px = nx * 5.0f, py = -ny * 5.0f;
    float ox = -ny * 3.0f, oy = -nx * 3.0f;
    array<vec2> tri;
    tri.insertLast(vec2(rim_x + px, rim_y + py));
    tri.insertLast(vec2(rim_x - px + ox, rim_y - py + oy));
    tri.insertLast(vec2(rim_x - px - ox, rim_y - py - oy));
    renderer.draw_convex_poly(tri, c);
}
```

## Distance ring labels

```angelscript
void draw_range_labels(RadarConfig& cfg, font_handle@ fnt) {
    for (int i = 1; i <= 3; i++) {
        float ring_r = cfg.radius * (i / 4.0f);
        float world_at_ring = cfg.range * (i / 4.0f);
        string label = fmt("{}m", int(world_at_ring / 39.37f)); // Source 2: units to metres
        renderer.text(cfg.cx + ring_r + 2.0f, cfg.cy + 2.0f, label, fnt,
                      color(150, 150, 150, 160));
    }
}
```

## Full radar render loop

```angelscript
RadarConfig g_radar;
font_handle@ radar_fnt;

bool main() {
    g_radar.cx     = 160.0f;
    g_radar.cy     = 920.0f;
    g_radar.radius = 140.0f;
    g_radar.range  = 3000.0f; // 3000 units ~ 76m in CS2

    radar_fnt = renderer.load_font("Arial", 10, font_hint::DEFAULT, false);
    on_render(@draw_radar);
    return true;
}

void draw_radar() {
    ent_mx.lock_shared();
    array<EntityData@> snap = entities_buf;
    ent_mx.unlock_shared();

    g_radar.yaw = radar_rotate.get() ? g_local_yaw : 0.0f;

    draw_radar_background(g_radar);
    draw_local_player(g_radar, 90.0f);

    for (uint i = 0; i < snap.length(); i++) {
        EntityData@ ed = snap[i];
        if (!ed.alive) continue;

        float rx, ry;
        if (world_to_radar(g_radar, g_local_origin, ed.world_pos, rx, ry)) {
            draw_entity_dot(rx, ry, ed.team, ed.visible, ed.hp);
        } else {
            color ec = ed.team == 2 ? color(80, 140, 255, 200) : color(220, 60, 60, 200);
            draw_edge_indicator(g_radar, g_local_origin, ed.world_pos, g_local_yaw, ec);
        }
    }

    draw_range_labels(g_radar, radar_fnt);
}
```

## Rotating vs north-up mode

```angelscript
checkbox@ radar_rotate; // add to menu

void draw_radar() {
    g_radar.yaw = radar_rotate.get() ? g_local_yaw : 0.0f;
    // ...
}
```

## Dev tips

- Set `range` to the map's approximate playable radius in engine units. CS2: ~3000; UE4 open-world: may need 50 000+.
- Source 2: 1 unit ≈ 1 inch; divide by 39.37 for metres. UE4: 1 unit = 1 cm; divide by 100.
- The edge indicator shows out-of-range enemies — don't skip it; it's the most tactically useful part.
- Share entity data with the ESP tick thread via `shared_snapshot` or a mutex — don't read memory twice.
- For Unity Rust, use `unity.rust_transform_position` to get world positions.
