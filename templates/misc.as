// Misc features: bunny hop, radar, spectator list, flash reduction
// CS2/Source 2 offsets — verify against cs2-dumper

// ─── Offsets (CS2, verify per update) ─────────────────────────────
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

// ─── Process state ─────────────────────────────────────────────────
process@ proc;
uint64   entity_list  = 0;
uint64   local_player = 0;

// ─── Menu ─────────────────────────────────────────────────────────
tab@       t;
checkbox@  bhop_on;
checkbox@  flash_on;
slider@    flash_max;
checkbox@  radar_on;
slider@    radar_scale;
checkbox@  spec_on;
font_handle@ fnt;

// ─── Entry point ───────────────────────────────────────────────────
bool main() {
    t          = menu.add_tab("Misc");
    auto cat   = t.add_category("Features");
    bhop_on    = cat.add_checkbox("Bunny Hop",        false, "misc.bhop");
    flash_on   = cat.add_checkbox("Flash Reduce",     false, "misc.flash");
    flash_max  = cat.add_slider("Flash alpha cap", 0.0f, 255.0f, 20.0f, "misc.flash_max");
    radar_on   = cat.add_checkbox("Radar",            false, "misc.radar");
    radar_scale= cat.add_slider("Radar scale", 0.1f, 5.0f, 1.0f, "misc.radar_scale");
    spec_on    = cat.add_checkbox("Spectator list",   false, "misc.spec");

    fnt = renderer.load_font("Verdana", 11, false);

    proc = process.attach("cs2.exe");
    if (proc is null) { alert("cs2.exe not found"); return false; }

    create_thread(0,  @do_scan);
    create_thread(64, @tick);
    on_render(@draw);
    return true;
}

void do_scan() {
    uint64 sig = proc.scan("48 8B 0D ?? ?? ?? ?? 48 89 5C 24", "client.dll");
    if (sig == 0) { alert("sig failed"); return; }
    uint64 ent_sys = proc.resolve_rip(sig, 3, 7);
    entity_list    = proc.read<uint64>(proc.read<uint64>(ent_sys) + 0x10);

    sig = proc.scan("48 8B 0D ?? ?? ?? ?? 48 85 C9 74 ?? 8B 01", "client.dll");
    if (sig != 0) local_player = proc.resolve_rip(sig, 3, 7);
    alert("Misc ready");
}

uint64 get_entity(int idx) {
    uint64 chunk = proc.read<uint64>(entity_list + uint64(idx >> 9) * 8);
    if (chunk == 0) return 0;
    return proc.read<uint64>(chunk + uint64(idx & 0x1FF) * 120);
}

// ─── Bunny hop ─────────────────────────────────────────────────────
// Fires jump at the exact frame the player lands (FL_ONGROUND set)
bool was_on_ground = false;

void bhop_tick(uint64 lp) {
    if (!bhop_on.get() || lp == 0) return;
    bool space_held   = keyboard.get_key_state(VK_SPACE) != 0;
    if (!space_held) { was_on_ground = false; return; }

    int flags      = proc.read<int>(lp + OFF_FLAGS);
    bool on_ground = (flags & 1) != 0;

    if (on_ground && !was_on_ground) {
        // Player just landed while holding space — jump immediately
        keyboard.key_tap(VK_SPACE);
    }
    was_on_ground = on_ground;
}

// ─── Flash reduction ───────────────────────────────────────────────
void flash_tick(uint64 lp) {
    if (!flash_on.get() || lp == 0) return;
    float dur = proc.read<float>(lp + OFF_FLASH_DUR);
    if (dur <= 0.0f) return;
    float cap = flash_max.get();
    float cur = proc.read<float>(lp + OFF_FLASH_MAX);
    if (cur > cap) proc.write<float>(lp + OFF_FLASH_MAX, cap);
}

// ─── Spectator list (stored for render) ────────────────────────────
array<string> g_spectators;
mutex@ spec_mx = mutex();

void spec_tick(uint64 lp) {
    if (!spec_on.get() || lp == 0 || entity_list == 0) return;
    array<string> spectators;
    for (int i = 1; i < 64; i++) {
        uint64 ent = get_entity(i);
        if (ent == 0) continue;
        // Spectator: lifeState != 0 (dead/spec) and observing local player
        if (proc.read<uint8>(ent + OFF_LIFE) == 0) continue; // alive, skip
        uint64 obs_target = proc.read<uint64>(ent + OFF_OBSERVER);
        if (obs_target != lp) continue;
        // Read name
        string name;
        for (int c = 0; c < 32; c++) {
            uint8 ch = proc.read<uint8>(ent + OFF_NAME + c);
            if (ch == 0) break;
            name += string(ch);
        }
        if (name.length() > 0) spectators.insertLast(name);
    }
    spec_mx.lock();
    g_spectators = spectators;
    spec_mx.unlock();
}

// ─── Radar data ────────────────────────────────────────────────────
struct RadarDot { float rx, ry; bool team; }
array<RadarDot@> g_radar;
mutex@ radar_mx = mutex();

void radar_tick(uint64 lp) {
    if (!radar_on.get() || lp == 0 || entity_list == 0) return;
    float lx = proc.read<float>(lp + OFF_ORIGIN);
    float ly = proc.read<float>(lp + OFF_ORIGIN + 4);
    int   lt = proc.read<int>(lp  + OFF_TEAM);

    array<RadarDot@> dots;
    for (int i = 1; i < 64; i++) {
        uint64 ent = get_entity(i);
        if (ent == 0) continue;
        if (proc.read<uint8>(ent + OFF_LIFE) != 0) continue;
        if (proc.read<int>(ent + OFF_HP) <= 0) continue;

        float ex = proc.read<float>(ent + OFF_ORIGIN);
        float ey = proc.read<float>(ent + OFF_ORIGIN + 4);
        int   et = proc.read<int>(ent + OFF_TEAM);

        RadarDot@ dot = RadarDot();
        float scale = radar_scale.get();
        dot.rx   = (ex - lx) / (500.0f / scale); // 500 units = 1 radar unit
        dot.ry   = (ey - ly) / (500.0f / scale);
        dot.team = (et == lt);
        dots.insertLast(dot);
    }
    radar_mx.lock();
    g_radar = dots;
    radar_mx.unlock();
}

// ─── Tick ──────────────────────────────────────────────────────────
void tick() {
    uint64 lp_ptr = (local_player != 0) ? proc.read<uint64>(local_player) : 0;
    bhop_tick(lp_ptr);
    flash_tick(lp_ptr);
    spec_tick(lp_ptr);
    radar_tick(lp_ptr);
}

// ─── Render ────────────────────────────────────────────────────────
const float RADAR_CX = 200.0f; // radar center X on screen
const float RADAR_CY = 880.0f; // radar center Y on screen
const float RADAR_R  = 80.0f;  // radar radius in pixels

void draw() {
    // Spectator list
    if (spec_on.get()) {
        spec_mx.lock_shared();
        array<string> snap_spec = g_spectators;
        spec_mx.unlock_shared();
        if (snap_spec.length() > 0) {
            renderer.text_outlined(10.0f, 200.0f, "Spectators:", fnt,
                                   color(255,200,60,255), color(0,0,0,180));
            for (uint i = 0; i < snap_spec.length(); i++)
                renderer.text_outlined(10.0f, 214.0f + float(i)*14.0f, snap_spec[i], fnt,
                                       color(255,100,100,255), color(0,0,0,180));
        }
    }

    // Radar
    if (radar_on.get()) {
        renderer.circle(RADAR_CX, RADAR_CY, RADAR_R, 64, color(0,0,0,120));
        renderer.circle(RADAR_CX, RADAR_CY, RADAR_R, 64, color(255,255,255,60));
        renderer.line(RADAR_CX - RADAR_R, RADAR_CY, RADAR_CX + RADAR_R, RADAR_CY,
                      1.0f, color(255,255,255,30));
        renderer.line(RADAR_CX, RADAR_CY - RADAR_R, RADAR_CX, RADAR_CY + RADAR_R,
                      1.0f, color(255,255,255,30));

        radar_mx.lock_shared();
        array<RadarDot@> snap = g_radar;
        radar_mx.unlock_shared();

        for (uint i = 0; i < snap.length(); i++) {
            RadarDot@ d = snap[i];
            float rx = RADAR_CX + d.rx * RADAR_R;
            float ry = RADAR_CY - d.ry * RADAR_R; // y-axis flipped
            // Clamp to radar circle
            float dx = rx - RADAR_CX, dy = ry - RADAR_CY;
            float dist = sqrt(dx*dx + dy*dy);
            if (dist > RADAR_R - 3.0f) {
                float scale = (RADAR_R - 3.0f) / dist;
                rx = RADAR_CX + dx * scale;
                ry = RADAR_CY + dy * scale;
            }
            color c = d.team ? color(80,120,255,220) : color(220,60,60,220);
            renderer.rect(rx - 2.0f, ry - 2.0f, 4.0f, 4.0f, c);
        }
        // Local player dot (center)
        renderer.rect(RADAR_CX - 3.0f, RADAR_CY - 3.0f, 6.0f, 6.0f,
                      color(0,220,60,255));
    }
}

void on_unload() { proc = null; }
