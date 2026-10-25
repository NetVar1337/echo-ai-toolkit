// CS2 loot/dropped-weapon ESP
// Scans entity list for dropped weapons; renders tiered labels + sorted panel.
//
// IMPORTANT: THE OFFSETS AND SIGNATURES BELOW ARE PLACEHOLDERS. They are
// illustrative values from one community dump and are NOT verified. Re-derive
// them with a current cs2-dumper run after every game update.

// ─── Offsets (placeholders — re-verify per patch) ───────────────────────────
const uint64 OFF_ORIGIN       = 0x1294;
const uint64 OFF_ITEM_DEF_IDX = 0x2FAA; // C_EconItemView::m_iItemDefinitionIndex (uint16)
const uint64 OFF_OWNER_HANDLE = 0x568;  // C_WeaponBase::m_hOwnerEntity

// ─── Loot config ─────────────────────────────────────────────────────────────
const float DIST_DOT   = 300.0f;  // metres — show dot only beyond this
const float DIST_LABEL = 150.0f;  // metres — show full label+tier prefix
const float DIST_HIDE  = 400.0f;  // metres — don't render at all

const int PANEL_MAX = 12;         // rows in sorted loot panel

// ─── Item tiers ──────────────────────────────────────────────────────────────
enum ItemTier { JUNK, COMMON, RARE, EPIC, LEGEND }

ItemTier cs2_weapon_tier(uint16 def_idx) {
    // shortcut: hard-coded per item definition index; update for new ops
    if (def_idx == 9 || def_idx == 19 || def_idx == 1 || def_idx == 2)
        return JUNK;    // glock, p2000, deagle, dualies
    if (def_idx == 7 || def_idx == 11)
        return RARE;    // AK, M4A4
    if (def_idx == 60 || def_idx == 8)
        return EPIC;    // M4A1-S, AWP
    if (def_idx == 9001)
        return LEGEND;  // placeholder — add new knives/special weapons here
    return COMMON;
}

color tier_color(ItemTier t) {
    if (t == LEGEND) return color(255, 215,  0, 255);  // gold
    if (t == EPIC)   return color(200,  80, 255, 255);  // purple
    if (t == RARE)   return color( 80, 150, 255, 255);  // blue
    if (t == COMMON) return color(180, 180, 180, 255);  // grey
    return                   color(100, 100, 100, 160);  // dim — JUNK
}

string tier_prefix(ItemTier t) {
    if (t == LEGEND) return "[*] ";
    if (t == EPIC)   return "[E] ";
    if (t == RARE)   return "[R] ";
    if (t == COMMON) return "[C] ";
    return                   "";
}

// ─── Shared state ────────────────────────────────────────────────────────────
class LootEntry {
    float  sx, sy;     // screen position of origin
    bool   on_screen;
    float  dist;       // metres from local player
    string name;
    ItemTier tier;
    uint64 ent_addr;
}
array<LootEntry@> g_loot;
mutex@ g_mx = create_mutex();

// ─── Menu ────────────────────────────────────────────────────────────────────
checkbox g_l_on;
checkbox g_l_panel;     // sorted panel in corner
slider   g_l_max_dist;  // metres
checkbox g_l_hide_junk;

// ─── Process state ───────────────────────────────────────────────────────────
uint64 g_entity_list   = 0;
uint64 g_local_player  = 0;
uint64 g_view_mat_addr = 0;

bool main() {
    ui::config_path("echo_loot");

    ui::add_tab("Loot");
    ui::add_category("Settings");
    g_l_on       = ui::add_checkbox("Enable", true, "loot.on");
    g_l_panel    = ui::add_checkbox("Sorted panel", true, "loot.panel");
    g_l_max_dist = ui::add_slider("Max dist (m)", 200, 50, 400, 10, "m", "loot.dist");
    g_l_hide_junk = ui::add_checkbox("Hide junk", true, "loot.nojunk");

    attach_data ad = process::attach("cs2.exe");
    if (ad.pid == 0) {
        alert::show("cs2.exe not found");
        return false;
    }

    create_thread(0, @do_scan);
    create_thread(8, @tick);    // 8 tps sufficient for static loot
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

    sig = process::find_signature(client, "48 8D 05 ? ? ? ? 48 89 05 ? ? ? ?");
    if (sig != 0) g_view_mat_addr = process::get_relative_address(sig, 3, 7);

    alert::show("Loot ESP ready");
}

// Entity list chunk walk (user code — chunk layout is game specific)
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

bool is_dropped_weapon(uint64 ent) {
    // Dropped weapon: valid entity with no owner handle (0 or invalid)
    uint32 owner = process::read_uint32(ent + OFF_OWNER_HANDLE);
    return (owner == 0 || (owner & 0xFFFF) == 0xFFFF);
}

string weapon_name_for(uint16 def_idx) {
    // shortcut: minimal lookup — extend this table as needed
    if (def_idx == 9)   return "Glock-18";
    if (def_idx == 11)  return "AK-47";
    if (def_idx == 7)   return "M4A4";
    if (def_idx == 60)  return "M4A1-S";
    if (def_idx == 8)   return "AWP";
    if (def_idx == 19)  return "P2000";
    if (def_idx == 2)   return "Dual Berrettas";
    return "wpn_" + util::format_string("{}", def_idx);
}

// ─── Tick ────────────────────────────────────────────────────────────────────
void tick() {
    if (!ui::get(g_l_on) || g_entity_list == 0) return;

    uint64 lp_ptr = process::read_uint64(g_local_player);
    if (lp_ptr == 0) return;

    vec3  lp_pos = vec3(process::read_float(lp_ptr + OFF_ORIGIN),
                        process::read_float(lp_ptr + OFF_ORIGIN + 4),
                        process::read_float(lp_ptr + OFF_ORIGIN + 8));
    float range     = float(ui::get(g_l_max_dist));
    bool  hide_junk = ui::get(g_l_hide_junk);

    // Read the view matrix for W2S
    bool have_vm = (g_view_mat_addr != 0);
    matrix4x4 vm;
    if (have_vm) vm = read_matrix16(g_view_mat_addr);

    array<LootEntry@> buf;

    // Scan all entity slots for dropped weapons
    for (int i = 1; i < 512; i++) {
        uint64 ent = get_entity(i);
        if (ent == 0) continue;
        if (!is_dropped_weapon(ent)) continue;

        uint16 def_idx = process::read_uint16(ent + OFF_ITEM_DEF_IDX);
        if (def_idx == 0) continue;

        vec3  epos = vec3(process::read_float(ent + OFF_ORIGIN),
                          process::read_float(ent + OFF_ORIGIN + 4),
                          process::read_float(ent + OFF_ORIGIN + 8));
        float dist_m = epos.distance(lp_pos) / 39.37f;
        if (dist_m > range || dist_m > DIST_HIDE) continue;

        ItemTier t = cs2_weapon_tier(def_idx);
        if (hide_junk && t == JUNK) continue;

        LootEntry@ le = LootEntry();
        le.ent_addr = ent;
        le.dist     = dist_m;
        le.tier     = t;
        le.name     = weapon_name_for(def_idx);
        le.on_screen = false;

        // W2S — source2::w2s writes the screen position and returns false
        // when the point is off-screen or behind the camera
        if (have_vm) {
            vec2 screen;
            le.on_screen = source2::w2s(epos, vm, screen);
            le.sx = screen.x;
            le.sy = screen.y;
        }

        buf.insertLast(le);
    }

    // Sort: tier desc, then dist asc
    // Bubble sort (small array, ponytail-approved)
    for (uint a = 0; a < buf.length(); a++) {
        for (uint b = a + 1; b < buf.length(); b++) {
            if (int(buf[a].tier) < int(buf[b].tier) ||
               (buf[a].tier == buf[b].tier && buf[a].dist > buf[b].dist)) {
                LootEntry@ tmp = buf[a];
                buf[a] = buf[b];
                buf[b] = tmp;
            }
        }
    }

    g_mx.lock();
    g_loot = buf;
    g_mx.unlock();
}

// ─── Render ──────────────────────────────────────────────────────────────────
void draw() {
    if (!ui::get(g_l_on)) return;

    g_mx.lock_shared();
    array<LootEntry@> snap = g_loot;
    g_mx.unlock_shared();

    render::update_font(fonts::TAHOMA, 10);

    // World-space labels
    for (uint i = 0; i < snap.length(); i++) {
        LootEntry@ e = snap[i];
        if (!e.on_screen) continue;

        color col = tier_color(e.tier);

        if (e.dist <= DIST_LABEL) {
            // Full label: prefix + name + distance
            string label = tier_prefix(e.tier) + e.name + " " +
                           util::format_string("{:.0}m", e.dist);
            render::draw_text_outlined(int(e.sx), int(e.sy), label,
                                       col.r, col.g, col.b, col.a);
        } else if (e.dist <= DIST_DOT) {
            // Dot only
            render::draw_circle(e.sx, e.sy, 3.5f, 0, 0, 0, 180, true, 12);
            render::draw_circle(e.sx, e.sy, 2.5f, col.r, col.g, col.b, col.a, true, 12);
        }
    }

    // Sorted panel (top-right corner)
    if (!ui::get(g_l_panel) || snap.length() == 0) return;

    vec2  vp    = render::get_viewport_size();
    int   pw    = 160;
    int   row_h = 16;
    uint  rows  = (snap.length() < uint(PANEL_MAX)) ? snap.length() : uint(PANEL_MAX);
    int   ph    = row_h * int(rows) + 8;
    int   px    = int(vp.x) - pw - 10;
    int   py    = 10;

    render::draw_box(px, py, pw, ph, 10, 10, 10, 200, box_style::FILLED, 0.0f);
    render::draw_box(px, py, pw, ph, 80, 80, 80, 180, box_style::OUTLINED, 0.0f);

    for (uint i = 0; i < rows; i++) {
        LootEntry@ e = snap[i];
        string label = tier_prefix(e.tier) + e.name + " " +
                       util::format_string("{:.0}m", e.dist);
        color c = tier_color(e.tier);
        render::draw_text_outlined(px + 6, py + 4 + int(i) * row_h, label,
                                   c.r, c.g, c.b, c.a);
    }
}

void on_unload() {
    process::detach();
}
