// CS2 loot/dropped-weapon ESP
// Scans entity list for dropped weapons; renders tiered labels + sorted panel.
// Offsets are examples — verify against current cs2-dumper output.

// ─── Offsets ───────────────────────────────────────────────────────
const uint64 OFF_ORIGIN       = 0x1294;
const uint64 OFF_ITEM_DEF_IDX = 0x2FAA; // C_EconItemView::m_iItemDefinitionIndex (uint16)
const uint64 OFF_OWNER_HANDLE = 0x568;  // C_WeaponBase::m_hOwnerEntity

// ─── Loot config ───────────────────────────────────────────────────
const float DIST_DOT   = 300.0f;  // metres — show dot only beyond this
const float DIST_LABEL = 150.0f;  // metres — show full label+tier prefix
const float DIST_HIDE  = 400.0f;  // metres — don't render at all

const int PANEL_MAX = 12;         // rows in sorted loot panel

// ─── Item tiers ────────────────────────────────────────────────────
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

color_t tier_color(ItemTier t) {
    if (t == LEGEND) return color_t(255, 215,  0, 255);  // gold
    if (t == EPIC)   return color_t(200,  80, 255, 255);  // purple
    if (t == RARE)   return color_t( 80, 150, 255, 255);  // blue
    if (t == COMMON) return color_t(180, 180, 180, 255);  // grey
    return                   color_t(100, 100, 100, 160);  // dim — JUNK
}

string tier_prefix(ItemTier t) {
    if (t == LEGEND) return "[★] ";
    if (t == EPIC)   return "[E] ";
    if (t == RARE)   return "[R] ";
    if (t == COMMON) return "[C] ";
    return                   "";
}

// ─── Shared state ──────────────────────────────────────────────────
struct LootEntry {
    float  sx, sy;     // screen position of origin
    bool   on_screen;
    float  dist;       // metres from local player
    string name;
    ItemTier tier;
    uint64 ent_addr;
}
array<LootEntry@> g_loot;
mutex@ g_mx = mutex();

// ─── Menu ──────────────────────────────────────────────────────────
tab@      tab_loot;
checkbox@ l_on;
checkbox@ l_panel;     // sorted panel in corner
slider@   l_max_dist;
checkbox@ l_hide_junk;
font_handle@ fnt;

// ─── Process state ─────────────────────────────────────────────────
process@ proc;
uint64   entity_list  = 0;
uint64   local_player = 0;
uint64   view_mat_addr= 0;

bool main() {
    tab_loot  = menu.add_tab("Loot");
    auto cat  = tab_loot.add_category("Settings");
    l_on      = cat.add_checkbox("Enable",     true,   "loot.on");
    l_panel   = cat.add_checkbox("Sorted panel",true,  "loot.panel");
    l_max_dist= cat.add_slider("Max dist (m)", 50.0f, 400.0f, 200.0f, "loot.dist");
    l_hide_junk = cat.add_checkbox("Hide junk", true,  "loot.nojunk");

    fnt = renderer.load_font("Verdana", 10, false);

    proc = process.attach("cs2.exe");
    if (proc is null) { alert("cs2.exe not found"); return false; }

    create_thread(0,  @do_scan);
    create_thread(8,  @tick);    // 8 tps sufficient for static loot
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

    sig = proc.scan_ida("48 8D 05 ? ? ? ? 48 89 05 ? ? ? ?", "client.dll");
    if (sig != 0) view_mat_addr = proc.resolve_rip(sig, 3, 7);

    alert("Loot ESP ready");
}

uint64 get_entity(int idx) {
    uint64 chunk = proc.read<uint64>(entity_list + uint64(idx >> 9) * 8);
    if (chunk == 0) return 0;
    return proc.read<uint64>(chunk + uint64(idx & 0x1FF) * 120);
}

bool is_dropped_weapon(uint64 ent) {
    // Dropped weapon: valid entity with no owner handle (0 or invalid)
    uint32 owner = proc.read<uint32>(ent + OFF_OWNER_HANDLE);
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
    if (def_idx == 2)   return "Dual Berettas";
    return fmt("wpn_{}", uint32(def_idx));
}

// ─── Tick ─────────────────────────────────────────────────────────
void tick() {
    if (!l_on.get() || entity_list == 0) return;

    uint64 lp_ptr = proc.read<uint64>(local_player);
    if (lp_ptr == 0) return;

    float lp_x = proc.read<float>(lp_ptr + OFF_ORIGIN);
    float lp_y = proc.read<float>(lp_ptr + OFF_ORIGIN + 4);
    float lp_z = proc.read<float>(lp_ptr + OFF_ORIGIN + 8);
    float range = l_max_dist.get();
    bool hide_junk = l_hide_junk.get();

    // Read view matrix for W2S
    float vp[16];
    if (view_mat_addr != 0)
        for (int i = 0; i < 16; i++)
            vp[i] = proc.read<float>(view_mat_addr + uint64(i) * 4);

    array<LootEntry@> buf;

    // Scan all entity slots for dropped weapons
    for (int i = 0; i < 512; i++) {
        uint64 ent = get_entity(i);
        if (ent == 0) continue;
        if (!is_dropped_weapon(ent)) continue;

        uint16 def_idx = proc.read<uint16>(ent + OFF_ITEM_DEF_IDX);
        if (def_idx == 0) continue;

        float ex = proc.read<float>(ent + OFF_ORIGIN);
        float ey = proc.read<float>(ent + OFF_ORIGIN + 4);
        float ez = proc.read<float>(ent + OFF_ORIGIN + 8);

        float dx = ex - lp_x, dy = ey - lp_y, dz = ez - lp_z;
        float dist_units = sqrt(dx*dx + dy*dy + dz*dz);
        float dist_m     = dist_units / 39.37f;
        if (dist_m > range || dist_m > DIST_HIDE) continue;

        ItemTier t = cs2_weapon_tier(def_idx);
        if (hide_junk && t == JUNK) continue;

        LootEntry@ le = LootEntry();
        le.ent_addr = ent;
        le.dist     = dist_m;
        le.tier     = t;
        le.name     = weapon_name_for(def_idx);
        le.on_screen = false;

        // W2S
        if (view_mat_addr != 0) {
            vec3 wpos(ex, ey, ez);
            le.on_screen = source2.w2s(proc, view_mat_addr, wpos, le.sx, le.sy);
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

// ─── Render ────────────────────────────────────────────────────────
void draw() {
    if (!l_on.get()) return;

    g_mx.lock_shared();
    array<LootEntry@> snap = g_loot;
    g_mx.unlock_shared();

    // World-space labels
    for (uint i = 0; i < snap.length(); i++) {
        LootEntry@ e = snap[i];
        if (!e.on_screen) continue;

        color_t col = tier_color(e.tier);

        if (e.dist <= DIST_LABEL) {
            // Full label: prefix + name + distance
            string label = tier_prefix(e.tier) + e.name + fmt(" {:.0f}m", e.dist);
            renderer.text_outlined(e.sx, e.sy, label, col, color_t(0,0,0,200), fnt);
        } else if (e.dist <= DIST_DOT) {
            // Dot only
            renderer.draw_circle_filled(e.sx, e.sy, 3.5f, 12, color_t(0, 0, 0, 180));
            renderer.draw_circle_filled(e.sx, e.sy, 2.5f, 12, col);
        }
    }

    // Sorted panel (top-right corner)
    if (!l_panel.get() || snap.length() == 0) return;

    float pw     = 160.0f;
    float row_h  = 16.0f;
    uint  rows   = (snap.length() < uint(PANEL_MAX)) ? snap.length() : uint(PANEL_MAX);
    float ph     = row_h * float(rows) + 8.0f;
    float px     = float(renderer.width()) - pw - 10.0f;
    float py     = 10.0f;

    renderer.draw_rect_filled(px, py, pw, ph, color_t(10, 10, 10, 200));
    renderer.draw_rect_outlined(px, py, pw, ph, 1.0f, color_t(80, 80, 80, 180));

    for (uint i = 0; i < rows; i++) {
        LootEntry@ e = snap[i];
        string label = tier_prefix(e.tier) + e.name + fmt(" {:.0f}m", e.dist);
        renderer.text_outlined(px + 6.0f, py + 4.0f + float(i) * row_h,
                               label, tier_color(e.tier), color_t(0,0,0,160), fnt);
    }
}

void on_unload() { proc = null; }
