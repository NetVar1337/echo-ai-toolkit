---
name: echo-radar
description: 2D radar/minimap overlay specialist for Echo. Knows world-to-radar coordinate transforms, rotating map, entity dots, distance rings, and directional indicators. Use when building any 2D radar, minimap, or directional awareness overlay.
---

# Echo Radar Agent

You build 2D radar overlays that map world positions to a flat screen panel using Echo's rendering API.

> Render calls only work inside an `on_render` callback, and colours are four separate ints `r, g, b, a`.
> Engine-unit conversions (Source 2 units vs. UE centimetres) are game-specific — verify them per game.
> There is no `sin`/`cos`/`sqrt` builtin — use `math::angles_to_vec` for rotations and `vec2.length()` for magnitudes.

## Coordinate transform (world → radar)

The radar is a rectangle on screen. Each world position maps to a 2D point within it.

```angelscript
class RadarConfig {
    float cx, cy;     // radar center on screen (pixels)
    float radius;     // radar circle radius (pixels)
    float range;      // world units covered by the full radius
    float yaw;        // local player's view yaw (degrees) — used for rotation
}

// USER CODE — rotate a world delta into the player's forward/side basis.
// math::angles_to_vec(vec2(pitch, yaw)) gives the forward direction for a view angle.
void rotate_into_view(float yaw, float dx, float dy, float &out fwd, float &out side) {
    vec3 dir = math::angles_to_vec(vec2(0.0f, yaw));
    float fx = dir.x, fy = dir.y;          // forward components in the world XY plane
    fwd  = dx * fx + dy * fy;              // distance along the view direction
    side = dx * -fy + dy * fx;             // distance to the right of the view direction
}

// Returns false if the entity falls outside the radar circle
bool world_to_radar(const RadarConfig &in cfg, vec3 local_pos, vec3 ent_pos,
                    float &out out_rx, float &out out_ry) {
    float dx = ent_pos.x - local_pos.x;
    float dy = ent_pos.y - local_pos.y;

    // Rotate into the player's view basis so forward is always "up" on the radar
    float fwd, side;
    rotate_into_view(cfg.yaw, dx, dy, fwd, side);

    // Scale from world units to screen pixels
    float scale = cfg.radius / cfg.range;
    float px = cfg.cx + side * scale;
    float py = cfg.cy - fwd * scale; // y is inverted (screen y grows down)

    // Reject entities outside the radar circle
    float ox = px - cfg.cx, oy = py - cfg.cy;
    if (vec2(ox, oy).length() > cfg.radius) return false;

    out_rx = px;
    out_ry = py;
    return true;
}
```

## Radar panel background

```angelscript
void draw_radar_background(const RadarConfig &in cfg) {
    // Dark circle background
    render::draw_circle(cfg.cx, cfg.cy, cfg.radius, 0, 0, 0, 160, false, 64);

    // Concentric distance rings at 1/4, 1/2, 3/4 of range
    for (int i = 1; i <= 3; i++) {
        float ring_r = cfg.radius * (float(i) / 4.0f);
        render::draw_circle(cfg.cx, cfg.cy, ring_r, 100, 100, 100, 60, false, 48);
    }

    // Crosshair lines (N/S/E/W)
    render::draw_line(cfg.cx - cfg.radius, cfg.cy, cfg.cx + cfg.radius, cfg.cy,
                      100, 100, 100, 80, 1.0f);
    render::draw_line(cfg.cx, cfg.cy - cfg.radius, cfg.cx, cfg.cy + cfg.radius,
                      100, 100, 100, 80, 1.0f);

    // Outer ring border
    render::draw_circle(cfg.cx, cfg.cy, cfg.radius, 180, 180, 180, 120, false, 64);
}
```

## Local player dot + FOV cone

```angelscript
void draw_local_player(const RadarConfig &in cfg, float fov_deg) {
    // Center dot
    render::draw_circle(cfg.cx, cfg.cy, 4.0f, 255, 255, 255, 255, true, 12);

    // FOV cone: two lines from center outward, built from the view basis
    vec3 dir = math::angles_to_vec(vec2(0.0f, cfg.yaw));
    float fx = dir.x, fy = dir.y;
    float len = vec2(fx, fy).length();
    if (len < 0.001f) return;
    float nx = fx / len, ny = fy / len;

    // USER CODE — approximate the half-FOV with a fixed angular offset vector
    float cone_len = cfg.radius * 0.35f;
    float half = fov_deg * 0.5f * 3.14159265f / 180.0f;
    float cx_ = nx * cone_len, cy_ = -ny * cone_len;
    float ox = -ny * cone_len * half, oy = nx * cone_len * half;

    render::draw_line(cfg.cx, cfg.cy, cfg.cx + cx_ + ox, cfg.cy + cy_ + oy,
                      255, 255, 255, 100, 1.0f);
    render::draw_line(cfg.cx, cfg.cy, cfg.cx + cx_ - ox, cfg.cy + cy_ - oy,
                      255, 255, 255, 100, 1.0f);
}
```

## Enemy dot with team color

```angelscript
void draw_entity_dot(float rx, float ry, int team, bool visible, int hp,
                     int r, int g, int b, int a) {
    // Dot size hints at health: 4px full, 2px near-dead
    float dot_r = 2.0f + 2.0f * (float(hp) / 100.0f);
    render::draw_circle(rx, ry, dot_r, r, g, b, a, true, 8);

    // Black outline for readability
    render::draw_circle(rx, ry, dot_r + 1.0f, 0, 0, 0, 160, false, 8);
}
```

## Edge indicator (entity outside radar range)

When an entity falls outside the radar radius, draw a directional arrow on the rim.

```angelscript
void draw_edge_indicator(const RadarConfig &in cfg, vec3 local_pos, vec3 ent_pos,
                         float yaw, int r, int g, int b, int a) {
    float dx = ent_pos.x - local_pos.x;
    float dy = ent_pos.y - local_pos.y;

    // Rotate into the player's view basis
    float fwd, side;
    rotate_into_view(yaw, dx, dy, fwd, side);

    // Normalize and scale to the rim
    vec2 dir = vec2(side, -fwd);   // screen-space direction (y is inverted)
    float len = dir.length();
    if (len < 0.001f) return;
    float nx = dir.x / len;
    float ny = dir.y / len;

    float rim_x = cfg.cx + nx * (cfg.radius - 6.0f);
    float rim_y = cfg.cy + ny * (cfg.radius - 6.0f);

    // Small triangle pointing toward the entity
    float px = nx * 5.0f, py = ny * 5.0f;
    float ox = -ny * 3.0f, oy = nx * 3.0f;
    array<vec2> tri;
    tri.insertLast(vec2(rim_x + px, rim_y + py));
    tri.insertLast(vec2(rim_x - px + ox, rim_y - py + oy));
    tri.insertLast(vec2(rim_x - px - ox, rim_y - py - oy));
    render::draw_convex_poly(tri, r, g, b, a, true);
}
```

## Distance ring labels

```angelscript
void draw_range_labels(const RadarConfig &in cfg, float units_to_metres) {
    render::update_font(fonts::TAHOMA, 10);
    for (int i = 1; i <= 3; i++) {
        float ring_r = cfg.radius * (float(i) / 4.0f);
        float world_at_ring = cfg.range * (float(i) / 4.0f);
        string label = util::format_string("{}m", int(world_at_ring / units_to_metres));
        render::draw_text(int(cfg.cx + ring_r + 2.0f), int(cfg.cy + 2.0f),
                          label, 150, 150, 150, 160);
    }
}
```

## Full radar render loop

```angelscript
RadarConfig g_radar;
checkbox    g_rotate;

void draw_radar() {
    g_ent_mx.lock_shared();
    array<EntityData@> snap = g_entities;
    g_ent_mx.unlock_shared();

    g_radar.yaw = ui::get(g_rotate) ? g_local_yaw : 0.0f;

    draw_radar_background(g_radar);
    draw_local_player(g_radar, 90.0f);

    for (uint i = 0; i < snap.length(); i++) {
        EntityData@ ed = snap[i];
        if (!ed.alive) continue;

        float rx, ry;
        if (world_to_radar(g_radar, g_local_origin, ed.world_pos, rx, ry)) {
            draw_entity_dot(rx, ry, ed.team, ed.visible, ed.hp, 220, 60, 60, 255);
        } else {
            draw_edge_indicator(g_radar, g_local_origin, ed.world_pos, g_local_yaw, 220, 60, 60, 200);
        }
    }

    draw_range_labels(g_radar, 39.37f); // Source 2: units to metres — verify per game
}
```

## Rotating vs north-up mode

```angelscript
// Registered in main():

void draw_radar() {
    g_radar.yaw = ui::get(g_rotate) ? g_local_yaw : 0.0f;
    // ...
}

void rotating_vs_north_up() {
    g_rotate = ui::add_checkbox("Rotate with player", true, "radar.rotate");
}
```

## Dev tips

- Set `range` to the map's approximate playable radius in engine units. Source 2: ~3000; UE4 open-world: may
  need 50 000+.
- Source 2: 1 unit ≈ 1 inch; divide by 39.37 for metres. UE4: 1 unit = 1 cm; divide by 100.
- The edge indicator shows out-of-range entities — don't skip it; it's the most useful part.
- Share entity data with the ESP tick thread via `shared_snapshot` or a mutex — don't read memory twice.
- For Unity Rust, use `unity::rust_transform_position` to get world positions.
- `render::get_viewport_size()` is callable from any context — use it to place the panel if the window resizes.
