// Misc features: bunny hop, radar, spectator list, flash reduction
// CS2/Source 2 offsets.
//
// IMPORTANT: THE OFFSETS AND SIGNATURES BELOW ARE PLACEHOLDERS. They are
// illustrative values from one community dump and are NOT verified. Re-derive
// them with a current cs2-dumper run after every game update.

// ─── Offsets (placeholders — re-verify per update) ───────────────────────────
const uint64 OFF_FLAGS      = 0x3F4;  // m_fFlags; bit 0 = FL_ONGROUND
const uint64 OFF_ORIGIN     = 0x1294;
const uint64 OFF_VELOCITY   = 0x1254;
const uint64 OFF_TEAM       = 0x3CB;
const uint64 OFF_LIFE       = 0x338;
const uint64 OFF_HP         = 0x344;
const uint64 OFF_FLASH_DUR  = 0x1514; // m_flFlashDuration
const uint64 OFF_FLASH_MAX  = 0x1518; // m_flFlashMaxAlpha
const uint64 OFF_NAME       = 0x640;
const uint64 OFF_OBSERVER   = 0x12C8; // observed target ptr (for spectators)

const int VK_SPACE  = 0x20;
const int VK_LSHIFT = 0xA0;

// ─── Process state ───────────────────────────────────────────────────────────
uint64 g_entity_list  = 0;
uint64 g_local_player = 0;

// ─── Menu ────────────────────────────────────────────────────────────────────
checkbox g_bhop_on;
checkbox g_flash_on;
slider   g_flash_max;   // 0..255
checkbox g_radar_on;
slider   g_radar_scale; // tenths
checkbox g_spec_on;

bool main() {
    ui::config_path("echo_misc");

    ui::add_tab("Misc");
    ui::add_category("Features");
    g_bhop_on     = ui::add_checkbox("Bunny Hop", false, "misc.bhop");
    g_flash_on    = ui::add_checkbox("Flash Reduce", false, "misc.flash");
    g_flash_max   = ui::add_slider("Flash alpha cap", 20, 0, 255, 5, "", "misc.flash_max");
    g_radar_on    = ui::add_checkbox("Radar", false, "misc.radar");
    g_radar_scale = ui::add_slider("Radar scale", 10, 1, 50, 1, "x0.1", "misc.radar_scale");
    g_spec_on     = ui::add_checkbox("Spectator list", false, "misc.spec");

    attach_data ad = process::attach("cs2.exe");
    if (ad.pid == 0) {
        alert::show("cs2.exe not found");
        return false;
    }

    create_thread(0,  @do_scan);
    create_thread(64, @tick);
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
        alert::show("sig failed");
        return;
    }
    uint64 ent_sys = process::get_relative_address(sig, 3, 7);
    g_entity_list  = process::read_uint64(process::read_uint64(ent_sys) + 0x10);

    sig = process::find_signature(client, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 8B 01");
    if (sig != 0) g_local_player = process::get_relative_address(sig, 3, 7);

    alert::show("Misc ready");
}

// Entity list chunk walk (user code — chunk layout is game specific)
uint64 get_entity(int idx) {
    uint64 chunk = process::read_uint64(g_entity_list + uint64(idx >> 9) * 8);
    if (chunk == 0) return 0;
    return process::read_uint64(chunk + uint64(idx & 0x1FF) * 120);
}

// ─── Bunny hop ───────────────────────────────────────────────────────────────
// Fires jump at the exact frame the player lands (FL_ONGROUND set)
bool g_was_on_ground = false;

void bhop_tick(uint64 lp) {
    if (!ui::get(g_bhop_on) || lp == 0) return;

    // input::key_active() is true while the key is held
    if (!input::key_active(VK_SPACE)) {
        g_was_on_ground = false;
        return;
    }

    int  flags      = process::read_int32(lp + OFF_FLAGS);
    bool on_ground = (flags & 1) != 0;

    if (on_ground && !g_was_on_ground) {
        // Player just landed while holding space — jump immediately
        input::key_tap(VK_SPACE);
    }
    g_was_on_ground = on_ground;
}

// ─── Flash reduction ─────────────────────────────────────────────────────────
void flash_tick(uint64 lp) {
    if (!ui::get(g_flash_on) || lp == 0) return;
    float dur = process::read_float(lp + OFF_FLASH_DUR);
    if (dur <= 0.0f) return;
    float cap = float(ui::get(g_flash_max));
    float cur = process::read_float(lp + OFF_FLASH_MAX);
    if (cur > cap) process::write_float(lp + OFF_FLASH_MAX, cap);
}

// ─── Spectator list (stored for render) ──────────────────────────────────────
array<string> g_spectators;
mutex@ g_spec_mx = create_mutex();

void spec_tick(uint64 lp) {
    if (!ui::get(g_spec_on) || lp == 0 || g_entity_list == 0) return;
    array<string> spectators;
    for (int i = 1; i < 64; i++) {
        uint64 ent = get_entity(i);
        if (ent == 0) continue;
        // Spectator: lifeState != 0 (dead/spec) and observing local player
        if (process::read_uint8(ent + OFF_LIFE) == 0) continue; // alive, skip
        uint64 obs_target = process::read_uint64(ent + OFF_OBSERVER);
        if (obs_target != lp) continue;
        // Read name
        string name = process::read_string(ent + OFF_NAME);
        if (name.length() > 0) spectators.insertLast(name);
    }
    g_spec_mx.lock();
    g_spectators = spectators;
    g_spec_mx.unlock();
}

// ─── Radar data ──────────────────────────────────────────────────────────────
class RadarDot { float rx, ry; bool team; }
array<RadarDot@> g_radar;
mutex@ g_radar_mx = create_mutex();

void radar_tick(uint64 lp) {
    if (!ui::get(g_radar_on) || lp == 0 || g_entity_list == 0) return;
    vec3 lpos = vec3(process::read_float(lp + OFF_ORIGIN),
                     process::read_float(lp + OFF_ORIGIN + 4),
                     process::read_float(lp + OFF_ORIGIN + 8));
    int lt = process::read_int32(lp + OFF_TEAM);

    array<RadarDot@> dots;
    for (int i = 1; i < 64; i++) {
        uint64 ent = get_entity(i);
        if (ent == 0) continue;
        if (process::read_uint8(ent + OFF_LIFE) != 0) continue;
        if (process::read_int32(ent + OFF_HP) <= 0) continue;

        vec3 epos = vec3(process::read_float(ent + OFF_ORIGIN),
                         process::read_float(ent + OFF_ORIGIN + 4),
                         process::read_float(ent + OFF_ORIGIN + 8));
        int et = process::read_int32(ent + OFF_TEAM);

        RadarDot@ dot = RadarDot();
        float scale = float(ui::get(g_radar_scale)) / 10.0f;
        dot.rx   = (epos.x - lpos.x) / (500.0f / scale); // 500 units = 1 radar unit
        dot.ry   = (epos.y - lpos.y) / (500.0f / scale);
        dot.team = (et == lt);
        dots.insertLast(dot);
    }
    g_radar_mx.lock();
    g_radar = dots;
    g_radar_mx.unlock();
}

// ─── Tick ────────────────────────────────────────────────────────────────────
void tick() {
    uint64 lp_ptr = (g_local_player != 0) ? process::read_uint64(g_local_player) : 0;
    bhop_tick(lp_ptr);
    flash_tick(lp_ptr);
    spec_tick(lp_ptr);
    radar_tick(lp_ptr);
}

// ─── Render ──────────────────────────────────────────────────────────────────
const float RADAR_CX = 200.0f; // radar center X on screen
const float RADAR_CY = 880.0f; // radar center Y on screen
const float RADAR_R  = 80.0f;  // radar radius in pixels

void draw() {
    render::update_font(fonts::TAHOMA, 11);

    // Spectator list
    if (ui::get(g_spec_on)) {
        g_spec_mx.lock_shared();
        array<string> snap_spec = g_spectators;
        g_spec_mx.unlock_shared();
        if (snap_spec.length() > 0) {
            render::draw_text_outlined(10, 200, "Spectators:", 255, 200, 60, 255);
            for (uint i = 0; i < snap_spec.length(); i++)
                render::draw_text_outlined(10, 214 + int(i) * 14, snap_spec[i],
                                           255, 100, 100, 255);
        }
    }

    // Radar
    if (ui::get(g_radar_on)) {
        render::draw_circle(RADAR_CX, RADAR_CY, RADAR_R, 0, 0, 0, 120, true, 64);
        render::draw_circle(RADAR_CX, RADAR_CY, RADAR_R, 255, 255, 255, 60, false, 64);
        render::draw_line(RADAR_CX - RADAR_R, RADAR_CY, RADAR_CX + RADAR_R, RADAR_CY,
                          255, 255, 255, 30, 1.0f);
        render::draw_line(RADAR_CX, RADAR_CY - RADAR_R, RADAR_CX, RADAR_CY + RADAR_R,
                          255, 255, 255, 30, 1.0f);

        g_radar_mx.lock_shared();
        array<RadarDot@> snap = g_radar;
        g_radar_mx.unlock_shared();

        for (uint i = 0; i < snap.length(); i++) {
            RadarDot@ d = snap[i];
            float rx = RADAR_CX + d.rx * RADAR_R;
            float ry = RADAR_CY - d.ry * RADAR_R; // y-axis flipped
            // Clamp to radar circle
            float dx = rx - RADAR_CX, dy = ry - RADAR_CY;
            float dist = vec2(dx, dy).length();
            if (dist > RADAR_R - 3.0f) {
                float scale = (RADAR_R - 3.0f) / dist;
                rx = RADAR_CX + dx * scale;
                ry = RADAR_CY + dy * scale;
            }
            if (d.team)
                render::draw_box(int(rx) - 2, int(ry) - 2, 4, 4,
                                 80, 120, 255, 220, box_style::FILLED, 0.0f);
            else
                render::draw_box(int(rx) - 2, int(ry) - 2, 4, 4,
                                 220, 60, 60, 220, box_style::FILLED, 0.0f);
        }
        // Local player dot (center)
        render::draw_box(int(RADAR_CX) - 3, int(RADAR_CY) - 3, 6, 6,
                         0, 220, 60, 255, box_style::FILLED, 0.0f);
    }
}

void on_unload() {
    process::detach();
}
