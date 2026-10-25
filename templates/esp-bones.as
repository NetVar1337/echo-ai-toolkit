// Full CS2/Source 2 ESP: boxes, skeleton, health bar, distance labels
//
// OFFSETS BELOW ARE PLACEHOLDERS. They are illustrative values copied from a
// community dump of one specific build. They are NOT verified and will be
// wrong after any game update. Re-derive every offset with a current
// cs2-dumper run before using this template.

// ─── Offsets (placeholders — re-verify per patch) ────────────────────────────
const uint64 OFF_HP         = 0x344;
const uint64 OFF_LIFE       = 0x338;  // 0 = alive
const uint64 OFF_TEAM       = 0x3CB;
const uint64 OFF_ORIGIN     = 0x1294;
const uint64 OFF_NAME       = 0x640;
const uint64 OFF_SKELETON   = 0x168;
const uint64 OFF_BONE_ARR   = 0x80;   // from skeleton base
const uint64 OFF_SPOTTED    = 0xF9B;

const int HEAD  = 9;
const int NECK  = 8;
const int CHEST = 7;
const int SPINE = 6;
const int PELVIS= 5;
const int SHL   = 10; const int ELB_L = 12; const int HAND_L = 13;
const int SHR   = 14; const int ELB_R = 16; const int HAND_R = 17;
const int HIP_L = 18; const int KNEE_L= 23; const int FOOT_L = 28;
const int HIP_R = 33; const int KNEE_R= 38; const int FOOT_R = 43;

// Pairs for skeleton draw: flat [from, to, from, to, ...]
array<int> BONE_PAIRS = {
    HEAD,NECK,  NECK,CHEST,  CHEST,SPINE,  SPINE,PELVIS,   // spine
    CHEST,SHL,  SHL,ELB_L,   ELB_L,HAND_L,                 // L arm
    CHEST,SHR,  SHR,ELB_R,   ELB_R,HAND_R,                 // R arm
    PELVIS,HIP_L, HIP_L,KNEE_L, KNEE_L,FOOT_L,              // L leg
    PELVIS,HIP_R, HIP_R,KNEE_R, KNEE_R,FOOT_R              // R leg
};
const int BONE_PAIR_COUNT = 16;

// ─── Shared entity data (written by tick, read by render) ────────────────────
class EspEntity {
    bool   alive;
    bool   visible;
    bool   is_team;
    int    hp;
    float  dist;
    string name;
    array<float> sx; array<float> sy; array<bool> sv; // bone screen positions
    float  box_x, box_y, box_w, box_h;

    EspEntity() {
        sx.resize(44);
        sy.resize(44);
        sv.resize(44);
    }
}

array<EspEntity@> g_entities;
mutex@ g_mx = create_mutex();

// ─── Menu ────────────────────────────────────────────────────────────────────
checkbox     g_esp_on;
checkbox     g_show_box;
checkbox     g_show_skel;
checkbox     g_show_hp;
checkbox     g_show_name;
slider       g_max_dist;      // metres
color_picker g_col_enemy;
color_picker g_col_team;
color_picker g_col_visible;

// ─── Process state ───────────────────────────────────────────────────────────
uint64 g_entity_list   = 0;
uint64 g_view_mat_addr = 0;
uint64 g_local_player  = 0;

// ─── Entry point ─────────────────────────────────────────────────────────────
bool main() {
    ui::config_path("echo_esp_bones");

    ui::add_tab("ESP");
    ui::add_category("Visuals");
    g_esp_on      = ui::add_checkbox("Enable", true, "esp.on");
    g_show_box    = ui::add_checkbox("Boxes", true, "esp.box");
    g_show_skel   = ui::add_checkbox("Skeleton", true, "esp.skel");
    g_show_hp     = ui::add_checkbox("Health bar", true, "esp.hp");
    g_show_name   = ui::add_checkbox("Names", true, "esp.name");
    g_max_dist    = ui::add_slider("Max dist (m)", 200, 10, 500, 10, "m", "esp.dist");
    g_col_enemy   = ui::add_color_picker("Enemy", 220, 60, 60, 255, true, "esp.col_e");
    g_col_team    = ui::add_color_picker("Team", 80, 120, 255, 255, true, "esp.col_t");
    g_col_visible = ui::add_color_picker("Vis", 0, 220, 60, 255, true, "esp.col_v");

    attach_data ad = process::attach("cs2.exe");
    if (ad.pid == 0) {
        alert::show("cs2.exe not found");
        return false;
    }

    create_thread(0,  @do_scan);   // one-shot: find addresses
    create_thread(32, @tick);      // 32 tps entity update
    on_render(@draw);
    return true;
}

// ─── Address scan (runs once after attach) ───────────────────────────────────
void do_scan() {
    uint64 client = process::get_module_base("client.dll");
    if (client == 0) {
        alert::show("client.dll not found");
        return;
    }

    // Entity system
    uint64 sig = process::find_signature(client, "48 8B 0D ? ? ? ? 48 89 5C 24");
    if (sig == 0) {
        alert::show("entity list sig failed");
        return;
    }
    uint64 ent_sys = process::get_relative_address(sig, 3, 7);
    g_entity_list  = process::read_uint64(process::read_uint64(ent_sys) + 0x10);

    // View matrix
    sig = process::find_signature(client, "48 8D 05 ? ? ? ? 48 89 05 ? ? ? ?");
    if (sig != 0) g_view_mat_addr = process::get_relative_address(sig, 3, 7);

    // Local player
    sig = process::find_signature(client, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 8B 01");
    if (sig != 0) g_local_player = process::get_relative_address(sig, 3, 7);

    alert::show("ESP ready");
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
// Entity list chunk walk (user code — the chunk layout is game specific)
uint64 get_entity(int idx) {
    uint64 chunk = process::read_uint64(g_entity_list + uint64(idx >> 9) * 8);
    if (chunk == 0) return 0;
    return process::read_uint64(chunk + uint64(idx & 0x1FF) * 120);
}

// Read a 4x4 float matrix (16 floats) from the target process (user code)
matrix4x4 read_matrix16(uint64 addr) {
    matrix4x4 m;
    for (int c = 0; c < 4; c++)
        for (int r = 0; r < 4; r++)
            m[c][r] = process::read_float(addr + uint64(c * 4 + r) * 4);
    return m;
}

// Read one bone's world position (user code — bone stride is game specific)
vec3 get_bone_pos(uint64 ent, int bone) {
    uint64 skel = process::read_uint64(ent + OFF_SKELETON);
    uint64 arr  = process::read_uint64(skel + OFF_BONE_ARR);
    uint64 a    = arr + uint64(bone) * 0x20 + 0x10;
    return vec3(process::read_float(a),
                 process::read_float(a + 4),
                 process::read_float(a + 8));
}

// ─── Tick: read entity data ──────────────────────────────────────────────────
void tick() {
    if (!ui::get(g_esp_on) || g_entity_list == 0 || g_view_mat_addr == 0) return;

    // Read the 4x4 view-projection matrix (float[16])
    matrix4x4 vm = read_matrix16(g_view_mat_addr);

    uint64 lp_ptr  = process::read_uint64(g_local_player);
    int    lp_team = (lp_ptr != 0) ? process::read_int32(lp_ptr + OFF_TEAM) : 0;
    vec3   lp_pos  = (lp_ptr != 0)
                   ? vec3(process::read_float(lp_ptr + OFF_ORIGIN),
                          process::read_float(lp_ptr + OFF_ORIGIN + 4),
                          process::read_float(lp_ptr + OFF_ORIGIN + 8))
                   : vec3(0, 0, 0);
    float  dist_max = float(ui::get(g_max_dist)) * 39.37f; // metres → Source units

    array<EspEntity@> local_buf;

    for (int i = 1; i < 64; i++) {
        uint64 ent = get_entity(i);
        if (ent == 0) continue;
        if (process::read_uint8(ent + OFF_LIFE) != 0) continue;  // dead
        int hp = process::read_int32(ent + OFF_HP);
        if (hp <= 0) continue;

        vec3 origin = vec3(process::read_float(ent + OFF_ORIGIN),
                           process::read_float(ent + OFF_ORIGIN + 4),
                           process::read_float(ent + OFF_ORIGIN + 8));
        float dist_units = origin.distance(lp_pos);
        if (dist_units > dist_max) continue;

        int  team    = process::read_int32(ent + OFF_TEAM);
        bool spotted = process::read_uint8(ent + OFF_SPOTTED) != 0;

        EspEntity@ ed = EspEntity();
        ed.alive   = true;
        ed.hp      = hp;
        ed.is_team = (team == lp_team);
        ed.visible = spotted;
        ed.dist    = dist_units / 39.37f;
        ed.name    = process::read_string(ent + OFF_NAME);

        // Project all skeleton bones
        bool head_ok = false, feet_ok = false;
        for (int b = 0; b < 44; b++) {
            vec2 screen;
            bool ok = source2::w2s(get_bone_pos(ent, b), vm, screen);
            ed.sv[b] = ok;
            // w2s leaves the out-param untouched when it fails — only store
            // the position when the conversion actually succeeded.
            if (ok) {
                ed.sx[b] = screen.x;
                ed.sy[b] = screen.y;
            }
        }
        head_ok = ed.sv[HEAD];
        feet_ok = ed.sv[FOOT_L] || ed.sv[FOOT_R];

        float head_sx = ed.sx[HEAD];
        float head_sy = ed.sy[HEAD];
        float feet_sx = ed.sv[FOOT_L] ? ed.sx[FOOT_L] : ed.sx[FOOT_R];
        float feet_sy = ed.sv[FOOT_L] ? ed.sy[FOOT_L] : ed.sy[FOOT_R];

        if (head_ok && feet_ok) {
            float bh = feet_sy > head_sy ? feet_sy - head_sy : head_sy - feet_sy;
            float bw = bh * 0.45f;
            ed.box_x = head_sx - bw * 0.5f;
            ed.box_y = head_sy;
            ed.box_w = bw;
            ed.box_h = bh;
        }

        local_buf.insertLast(ed);
    }

    g_mx.lock();
    g_entities = local_buf;
    g_mx.unlock();
}

// ─── Render ──────────────────────────────────────────────────────────────────
void draw() {
    if (!ui::get(g_esp_on)) return;

    g_mx.lock_shared();
    array<EspEntity@> snap = g_entities;
    g_mx.unlock_shared();

    render::update_font(fonts::TAHOMA, 11);

    for (uint i = 0; i < snap.length(); i++) {
        EspEntity@ e = snap[i];
        if (!e.alive) continue;

        color c = e.is_team   ? ui::get(g_col_team)
                : e.visible   ? ui::get(g_col_visible)
                :               ui::get(g_col_enemy);

        // Fade alpha with distance
        float alpha_f = 1.0f - (e.dist / float(ui::get(g_max_dist))) * 0.5f;
        int a = int(c.a * alpha_f);
        if (a < 0) a = 0;

        // Box
        if (ui::get(g_show_box) && e.box_w > 0) {
            int x = int(e.box_x), y = int(e.box_y);
            int w = int(e.box_w), h = int(e.box_h);
            int cx = int(w * 0.25f), cy = int(h * 0.25f);
            // corners
            render::draw_line(x,     y,     x + cx, y,     c.r, c.g, c.b, a, 1.5f);
            render::draw_line(x,     y,     x,     y + cy, c.r, c.g, c.b, a, 1.5f);
            render::draw_line(x + w, y,     x + w - cx, y, c.r, c.g, c.b, a, 1.5f);
            render::draw_line(x + w, y,     x + w, y + cy, c.r, c.g, c.b, a, 1.5f);
            render::draw_line(x,     y + h, x + cx, y + h, c.r, c.g, c.b, a, 1.5f);
            render::draw_line(x,     y + h, x,     y + h - cy, c.r, c.g, c.b, a, 1.5f);
            render::draw_line(x + w, y + h, x + w - cx, y + h, c.r, c.g, c.b, a, 1.5f);
            render::draw_line(x + w, y + h, x + w, y + h - cy, c.r, c.g, c.b, a, 1.5f);
        }

        // Health bar (left of box, vertical)
        if (ui::get(g_show_hp) && e.box_h > 0) {
            int x = int(e.box_x) - 7;
            int y = int(e.box_y);
            int h = int(e.box_h);
            int filled = int(h * (float(e.hp) / 100.0f));
            render::draw_box(x, y, 4, h, 0, 0, 0, 180, box_style::OUTLINED, 0.0f);
            int r = int(255.0f * (1.0f - float(e.hp) / 100.0f));
            int g = int(255.0f * (float(e.hp) / 100.0f));
            render::draw_box(x + 1, y + (h - filled), 2, filled, r, g, 0, 220,
                             box_style::FILLED, 0.0f);
        }

        // Skeleton
        if (ui::get(g_show_skel)) {
            for (int p = 0; p < BONE_PAIR_COUNT; p++) {
                int b0 = BONE_PAIRS[p * 2], b1 = BONE_PAIRS[p * 2 + 1];
                if (!e.sv[b0] || !e.sv[b1]) continue;
                render::draw_line(e.sx[b0], e.sy[b0], e.sx[b1], e.sy[b1],
                                  c.r, c.g, c.b, a, 1.0f);
            }
        }

        // Name + distance
        if (ui::get(g_show_name) && e.box_y > 14.0f) {
            string label = e.name + " [" + util::format_string("{}m", int(e.dist)) + "]";
            render::draw_text_outlined(int(e.box_x + e.box_w * 0.5f),
                                       int(e.box_y) - 14, label,
                                       c.r, c.g, c.b, a);
        }
    }
}

void on_unload() {
    process::detach();
}
