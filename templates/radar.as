// 2D radar/minimap overlay — CS2 Source 2 variant
// Draws a circular radar panel on the overlay with entity dots + edge indicators.
// Offsets are examples — verify against current cs2-dumper output.

// ─── Offsets ───────────────────────────────────────────────────────
const uint64 OFF_ORIGIN     = 0x1294;
const uint64 OFF_TEAM       = 0x3CB;
const uint64 OFF_HP         = 0x344;
const uint64 OFF_LIFE       = 0x338;
const uint64 OFF_VIEW_ANGLES= 0x1510;  // QAngle pitch/yaw/roll

// ─── Radar config ──────────────────────────────────────────────────
const float RADAR_X    = 20.0f;   // top-left corner on screen
const float RADAR_Y    = 20.0f;
const float RADAR_SIZE = 180.0f;  // diameter in pixels
const float RADAR_R    = RADAR_SIZE * 0.5f;
const float RADAR_CX   = RADAR_X + RADAR_R;
const float RADAR_CY   = RADAR_Y + RADAR_R;

// ─── Shared state (tick → render) ─────────────────────────────────
struct RadarEntry {
    float rx, ry;   // pixel offset from panel center
    bool  is_team;
    bool  on_edge;  // clamped to rim
    int   hp;
}
array<RadarEntry@> g_ents;
mutex@ g_mx = mutex();

float g_local_yaw = 0.0f;

// ─── Menu ──────────────────────────────────────────────────────────
tab@      tab_radar;
checkbox@ r_on;
checkbox@ r_rotate;  // rotating (yaw-locked) vs north-up
slider@   r_range;
slider@   r_alpha;

font_handle@ fnt;

// ─── Process state ─────────────────────────────────────────────────
process@ proc;
uint64   entity_list  = 0;
uint64   local_player = 0;

bool main() {
    tab_radar = menu.add_tab("Radar");
    auto cat  = tab_radar.add_category("Settings");
    r_on      = cat.add_checkbox("Enable",    true,   "radar.on");
    r_rotate  = cat.add_checkbox("Rotating",  true,   "radar.rot");
    r_range   = cat.add_slider("Range (u)",   500.0f, 8000.0f, 3000.0f, "radar.range");
    r_alpha   = cat.add_slider("Alpha",       0.3f,   1.0f,    0.7f,    "radar.alpha");

    fnt = renderer.load_font("Verdana", 9, false);

    proc = process.attach("cs2.exe");
    if (proc is null) { alert("cs2.exe not found"); return false; }

    create_thread(0,  @do_scan);
    create_thread(32, @tick);
    on_render(@draw);
    return true;
}

void do_scan() {
    uint64 sig = proc.scan_ida("48 8B 0D ? ? ? ? 48 89 5C 24", "client.dll");
    if (sig == 0) { alert("entity list sig failed"); return; }
    uint64 ent_sys = proc.resolve_rip(sig, 3, 7);
    entity_list    = proc.read<uint64>(proc.read<uint64>(ent_sys) + 0x10);

    sig = proc.scan_ida("48 8B 0D ? ? ? ? 48 85 C9 74 ? 8B 01", "client.dll");
    if (sig != 0) local_player = proc.resolve_rip(sig, 3, 7);

    alert("Radar ready");
}

uint64 get_entity(int idx) {
    uint64 chunk = proc.read<uint64>(entity_list + uint64(idx >> 9) * 8);
    if (chunk == 0) return 0;
    return proc.read<uint64>(chunk + uint64(idx & 0x1FF) * 120);
}

// ─── world_to_radar ────────────────────────────────────────────────
// on_edge=true when clamped to the rim; caller draws arrow instead of dot.
void world_to_radar(float dx, float dz, float yaw_deg, float range,
                    float& px, float& py, bool& on_edge) {
    float yaw = -yaw_deg * 3.14159f / 180.0f;
    float rx =  dx * cos(yaw) - dz * sin(yaw);
    float ry =  dx * sin(yaw) + dz * cos(yaw);

    float scale = RADAR_R / range;
    px = rx * scale;
    py = ry * scale;

    float dist = sqrt(px*px + py*py);
    if (dist > RADAR_R - 3.0f) {
        float norm = (RADAR_R - 3.0f) / dist;
        px *= norm;
        py *= norm;
        on_edge = true;
    } else {
        on_edge = false;
    }
}

// ─── Tick ─────────────────────────────────────────────────────────
void tick() {
    if (!r_on.get() || entity_list == 0) return;

    uint64 lp_ptr = proc.read<uint64>(local_player);
    if (lp_ptr == 0) return;

    float lp_x  = proc.read<float>(lp_ptr + OFF_ORIGIN);
    float lp_z  = proc.read<float>(lp_ptr + OFF_ORIGIN + 8);
    float yaw   = proc.read<float>(lp_ptr + OFF_VIEW_ANGLES + 4);
    int   lp_team = proc.read<int>(lp_ptr + OFF_TEAM);
    float range = r_range.get();

    g_local_yaw = r_rotate.get() ? yaw : 0.0f;

    array<RadarEntry@> buf;

    for (int i = 1; i < 64; i++) {
        uint64 ent = get_entity(i);
        if (ent == 0) continue;
        if (proc.read<uint8>(ent + OFF_LIFE) != 0) continue;
        int hp = proc.read<int>(ent + OFF_HP);
        if (hp <= 0) continue;

        float ex = proc.read<float>(ent + OFF_ORIGIN);
        float ez = proc.read<float>(ent + OFF_ORIGIN + 8);

        float dx = ex - lp_x;
        float dz = -(ez - lp_z);
        if (sqrt(dx*dx + dz*dz) > range * 2.0f) continue;

        RadarEntry@ re = RadarEntry();
        world_to_radar(dx, dz, yaw, range, re.rx, re.ry, re.on_edge);
        re.is_team = (proc.read<int>(ent + OFF_TEAM) == lp_team);
        re.hp      = hp;
        buf.insertLast(re);
    }

    g_mx.lock();
    g_ents = buf;
    g_mx.unlock();
}

// ─── Draw helpers ──────────────────────────────────────────────────
void draw_background(uint8 alpha) {
    renderer.draw_circle_filled(RADAR_CX, RADAR_CY, RADAR_R, 64,
                                color_t(15, 15, 15, alpha));
    color_t ring_col(80, 80, 80, uint8(alpha / 2));
    for (int i = 1; i <= 3; i++)
        renderer.draw_circle(RADAR_CX, RADAR_CY, RADAR_R * float(i) * 0.25f,
                             32, ring_col, 1.0f);
    renderer.draw_line(RADAR_CX - RADAR_R, RADAR_CY,
                       RADAR_CX + RADAR_R, RADAR_CY, ring_col, 1.0f);
    renderer.draw_line(RADAR_CX, RADAR_CY - RADAR_R,
                       RADAR_CX, RADAR_CY + RADAR_R, ring_col, 1.0f);
    renderer.draw_circle(RADAR_CX, RADAR_CY, RADAR_R, 64,
                         color_t(120, 120, 120, alpha), 1.5f);
}

void draw_edge_indicator(float rx, float ry, color_t col) {
    float len = sqrt(rx*rx + ry*ry);
    if (len < 0.001f) return;
    float nx = rx / len, ny = ry / len;
    float tx = -ny,      ty = nx;
    float cx = RADAR_CX + rx, cy = RADAR_CY + ry;
    renderer.draw_triangle_filled(cx + nx*5.0f,         cy + ny*5.0f,
                                  cx - nx*4.0f + tx*4.0f, cy - ny*4.0f + ty*4.0f,
                                  cx - nx*4.0f - tx*4.0f, cy - ny*4.0f - ty*4.0f,
                                  col);
}

// ─── Render ────────────────────────────────────────────────────────
void draw() {
    if (!r_on.get()) return;

    uint8 alpha = uint8(r_alpha.get() * 255.0f);
    draw_background(alpha);

    // Local player center dot + forward indicator
    renderer.draw_circle_filled(RADAR_CX, RADAR_CY, 3.5f, 16,
                                color_t(100, 200, 255, alpha));
    renderer.draw_line(RADAR_CX, RADAR_CY, RADAR_CX, RADAR_CY - 10.0f,
                       color_t(100, 200, 255, alpha), 1.5f);

    g_mx.lock_shared();
    array<RadarEntry@> snap = g_ents;
    g_mx.unlock_shared();

    for (uint i = 0; i < snap.length(); i++) {
        RadarEntry@ e = snap[i];
        color_t col = e.is_team ? color_t(60, 120, 255, alpha)
                                : color_t(220, 60, 60,  alpha);
        if (e.on_edge) {
            draw_edge_indicator(e.rx, e.ry, col);
        } else {
            float cx = RADAR_CX + e.rx, cy = RADAR_CY + e.ry;
            float dot_r = 2.0f + float(e.hp) / 100.0f * 2.0f;
            renderer.draw_circle_filled(cx, cy, dot_r + 1.0f, 12,
                                        color_t(0, 0, 0, alpha));
            renderer.draw_circle_filled(cx, cy, dot_r, 12, col);
        }
    }
}

void on_unload() { proc = null; }
