// 2D radar/minimap overlay — CS2 Source 2 variant
// Draws a circular radar panel on the overlay with entity dots + edge indicators.
//
// IMPORTANT: THE OFFSETS AND SIGNATURES BELOW ARE PLACEHOLDERS. They are
// illustrative values from one community dump and are NOT verified. Re-derive
// them with a current cs2-dumper run after every game update.

// ─── Offsets (placeholders — re-verify per patch) ────────────────────────────
const uint64 OFF_ORIGIN      = 0x1294;
const uint64 OFF_TEAM        = 0x3CB;
const uint64 OFF_HP          = 0x344;
const uint64 OFF_LIFE        = 0x338;
const uint64 OFF_VIEW_ANGLES = 0x1510;  // QAngle pitch/yaw/roll

// ─── Radar config ────────────────────────────────────────────────────────────
const float RADAR_X    = 20.0f;   // top-left corner on screen
const float RADAR_Y    = 20.0f;
const float RADAR_SIZE = 180.0f;  // diameter in pixels
const float RADAR_R    = RADAR_SIZE * 0.5f;
const float RADAR_CX   = RADAR_X + RADAR_R;
const float RADAR_CY   = RADAR_Y + RADAR_R;

// ─── Shared state (tick → render) ────────────────────────────────────────────
class RadarEntry {
    float rx, ry;   // pixel offset from panel center
    bool  is_team;
    bool  on_edge;  // clamped to rim
    int   hp;
}
array<RadarEntry@> g_ents;
mutex@ g_mx = create_mutex();

float g_local_yaw = 0.0f;

// ─── Menu ────────────────────────────────────────────────────────────────────
checkbox g_r_on;
checkbox g_r_rotate;  // rotating (yaw-locked) vs north-up
slider   g_r_range;   // source units
slider   g_r_alpha;   // percent

// ─── Process state ───────────────────────────────────────────────────────────
uint64 g_entity_list  = 0;
uint64 g_local_player = 0;

bool main() {
    ui::config_path("echo_radar");

    ui::add_tab("Radar");
    ui::add_category("Settings");
    g_r_on     = ui::add_checkbox("Enable", true, "radar.on");
    g_r_rotate = ui::add_checkbox("Rotating", true, "radar.rot");
    g_r_range  = ui::add_slider("Range (u)", 3000, 500, 8000, 100, "u", "radar.range");
    g_r_alpha  = ui::add_slider("Alpha", 70, 10, 100, 5, "%", "radar.alpha");

    attach_data ad = process::attach("cs2.exe");
    if (ad.pid == 0) {
        alert::show("cs2.exe not found");
        return false;
    }

    create_thread(0,  @do_scan);
    create_thread(32, @tick);
    on_render(@draw);
    return true;
}

void do_scan() {
    uint64 client = process::get_module_base("client.dll");
    if (client == 0) {
        alert::show("client.dll not found");
        return;
    }

    uint64 sig = process::find_signature(client, "48 8B 0D ? ? ? ? 48 89 5C 24");
    if (sig == 0) {
        alert::show("entity list sig failed");
        return;
    }
    uint64 ent_sys = process::get_relative_address(sig, 3, 7);
    g_entity_list  = process::read_uint64(process::read_uint64(ent_sys) + 0x10);

    sig = process::find_signature(client, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 8B 01");
    if (sig != 0) g_local_player = process::get_relative_address(sig, 3, 7);

    alert::show("Radar ready");
}

// Entity list chunk walk (user code — chunk layout is game specific)
uint64 get_entity(int idx) {
    uint64 chunk = process::read_uint64(g_entity_list + uint64(idx >> 9) * 8);
    if (chunk == 0) return 0;
    return process::read_uint64(chunk + uint64(idx & 0x1FF) * 120);
}

// ─── world_to_radar (user code) ──────────────────────────────────────────────
// on_edge=true when clamped to the rim; caller draws arrow instead of dot.
// Rotation uses math::forward_vector()/math::right_vector() for the local yaw
// instead of raw trigonometry.
void world_to_radar(float dx, float dz, float yaw_deg, float range,
                    float& px, float& py, bool& on_edge) {
    vec2 angles = vec2(0.0f, -yaw_deg);
    vec3 fwd = math::forward_vector(angles);
    vec3 right = math::right_vector(angles);

    float rx = dx * right.x + dz * right.z;
    float ry = dx * fwd.x   + dz * fwd.z;

    float scale = RADAR_R / range;
    px = rx * scale;
    py = ry * scale;

    float dist = vec2(px, py).length();
    if (dist > RADAR_R - 3.0f) {
        float norm = (RADAR_R - 3.0f) / dist;
        px *= norm;
        py *= norm;
        on_edge = true;
    } else {
        on_edge = false;
    }
}

// ─── Tick ────────────────────────────────────────────────────────────────────
void tick() {
    if (!ui::get(g_r_on) || g_entity_list == 0) return;

    uint64 lp_ptr = process::read_uint64(g_local_player);
    if (lp_ptr == 0) return;

    float lp_x    = process::read_float(lp_ptr + OFF_ORIGIN);
    float lp_z    = process::read_float(lp_ptr + OFF_ORIGIN + 8);
    float yaw     = process::read_float(lp_ptr + OFF_VIEW_ANGLES + 4);
    int   lp_team = process::read_int32(lp_ptr + OFF_TEAM);
    float range   = float(ui::get(g_r_range));

    g_local_yaw = ui::get(g_r_rotate) ? yaw : 0.0f;

    array<RadarEntry@> buf;

    for (int i = 1; i < 64; i++) {
        uint64 ent = get_entity(i);
        if (ent == 0) continue;
        if (process::read_uint8(ent + OFF_LIFE) != 0) continue;
        int hp = process::read_int32(ent + OFF_HP);
        if (hp <= 0) continue;

        float ex = process::read_float(ent + OFF_ORIGIN);
        float ez = process::read_float(ent + OFF_ORIGIN + 8);

        float dx = ex - lp_x;
        float dz = -(ez - lp_z);
        if (vec2(dx, dz).length() > range * 2.0f) continue;

        RadarEntry@ re = RadarEntry();
        world_to_radar(dx, dz, g_local_yaw, range, re.rx, re.ry, re.on_edge);
        re.is_team = (process::read_int32(ent + OFF_TEAM) == lp_team);
        re.hp      = hp;
        buf.insertLast(re);
    }

    g_mx.lock();
    g_ents = buf;
    g_mx.unlock();
}

// ─── Draw helpers (user code) ───────────────────────────────────────────────
void draw_background(int alpha) {
    render::draw_circle(RADAR_CX, RADAR_CY, RADAR_R, 15, 15, 15, alpha, true, 64);
    for (int i = 1; i <= 3; i++)
        render::draw_circle(RADAR_CX, RADAR_CY, RADAR_R * float(i) * 0.25f,
                            80, 80, 80, alpha / 2, false, 32);
    render::draw_line(RADAR_CX - RADAR_R, RADAR_CY,
                      RADAR_CX + RADAR_R, RADAR_CY, 80, 80, 80, alpha, 1.0f);
    render::draw_line(RADAR_CX, RADAR_CY - RADAR_R,
                      RADAR_CX, RADAR_CY + RADAR_R, 80, 80, 80, alpha, 1.0f);
    render::draw_circle(RADAR_CX, RADAR_CY, RADAR_R,
                        120, 120, 120, alpha, false, 64);
}

void draw_edge_indicator(float rx, float ry, int r, int g, int b, int a) {
    float len = vec2(rx, ry).length();
    if (len < 0.001f) return;
    float nx = rx / len, ny = ry / len;
    float tx = -ny,      ty = nx;
    float cx = RADAR_CX + rx, cy = RADAR_CY + ry;
    render::draw_triangle(cx + nx * 5.0f,         cy + ny * 5.0f,
                          cx - nx * 4.0f + tx * 4.0f, cy - ny * 4.0f + ty * 4.0f,
                          cx - nx * 4.0f - tx * 4.0f, cy - ny * 4.0f - ty * 4.0f,
                          r, g, b, a, true);
}

// ─── Render ──────────────────────────────────────────────────────────────────
void draw() {
    if (!ui::get(g_r_on)) return;

    int alpha = int(float(ui::get(g_r_alpha)) / 100.0f * 255.0f);
    draw_background(alpha);

    // Local player center dot + forward indicator
    render::draw_circle(RADAR_CX, RADAR_CY, 3.5f, 100, 200, 255, alpha, true, 16);
    render::draw_line(RADAR_CX, RADAR_CY, RADAR_CX, RADAR_CY - 10.0f,
                      100, 200, 255, alpha, 1.5f);

    g_mx.lock_shared();
    array<RadarEntry@> snap = g_ents;
    g_mx.unlock_shared();

    for (uint i = 0; i < snap.length(); i++) {
        RadarEntry@ e = snap[i];
        int r = 220, g = 60, b = 60;
        if (e.is_team) { r = 60; g = 120; b = 255; }
        if (e.on_edge) {
            draw_edge_indicator(e.rx, e.ry, r, g, b, alpha);
        } else {
            float cx = RADAR_CX + e.rx, cy = RADAR_CY + e.ry;
            float dot_r = 2.0f + float(e.hp) / 100.0f * 2.0f;
            render::draw_circle(cx, cy, dot_r + 1.0f, 0, 0, 0, alpha, true, 12);
            render::draw_circle(cx, cy, dot_r, r, g, b, alpha, true, 12);
        }
    }
}

void on_unload() {
    process::detach();
}
