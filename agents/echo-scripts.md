---
name: echo-scripts
description: Complete runnable Echo AngelScript examples. Contains full working scripts for CS2 ESP, UE4 aimbot, and Unity loot scanner. Use when you need a drop-in starting point or to see how all APIs connect into a real working script.
---

# Echo Scripts — Complete Working Examples

Drop any of these into `%AppData%\Roaming\scripts\<name>.as`, then reload the Echo in-game menu.

**Offsets and patterns are placeholders.** Every numeric offset, signature, weapon ID and prefab ID below is an
*example*, not a verified value for any build. Update from Dumper-7, a schema dump, or your own RE for your
game/build, and re-verify after every patch — see `skills/offset-update-workflow`.

---

## Script 1: CS2 Minimal ESP

```angelscript
// cs2_esp.as — cornered-box ESP with health bar and name/distance label

uint64      g_entity_list = 0;
uint64      g_view_mat    = 0;
uint64      g_local_ptr   = 0;

checkbox     esp_on;
color_picker esp_col;
slider       esp_dist;

mutex@       ent_mx = create_mutex();

class ED {
    float sx0, sy0, sw, sh;
    int   hp;
    bool  visible;
    string name;
    float dist;
}

array<ED@> g_ents;

// Offsets below are PLACEHOLDERS — re-verify per build.
const uint64 OFF_HEALTH = 0x344;
const uint64 OFF_LIFE   = 0x338;
const uint64 OFF_TEAM   = 0x3CB;
const uint64 OFF_ORIGIN = 0x1294;
const uint64 OFF_NAME   = 0x640;
const uint64 OFF_SPOT   = 0xF9B;
const float  UNITS_TO_M = 39.37f;

bool main() {
    ui::config_path("cs2esp");
    ui::add_tab("CS2 ESP");
    ui::add_category("Settings");
    esp_on   = ui::add_checkbox("Enable", true, "cs2esp.on");
    esp_col  = ui::add_color_picker("Color", 0, 220, 60, 220, true, "cs2esp.color");
    esp_dist = ui::add_slider("Max dist", 3000, 100, 8000, 100, "u", "cs2esp.dist");

    attach_data ad = process::attach("cs2.exe");
    if (ad.pid == 0) { alert::show_tag("Attach failed", "error"); return false; }

    create_thread(0,  @scan_sigs);
    create_thread(64, @tick);
    on_render(@draw);
    return true;
}

void scan_sigs() {
    uint64 client_base = process::get_module_base("client.dll");
    if (client_base == 0) { alert::show_tag("client.dll not found", "error"); return; }

    // Signatures below are PLACEHOLDERS — re-verify per patch.
    // The resolved address is the entity list address — the same one
    // source2::get_controller() expects.
    uint64 sig = process::find_signature(client_base, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 4C 8B 01");
    if (sig != 0) g_entity_list = process::get_relative_address(sig, 3, 7);

    sig = process::find_signature(client_base, "48 8D 05 ? ? ? ? 48 89 05 ? ? ? ? 48 8D 0D");
    if (sig != 0) g_view_mat = process::get_relative_address(sig, 3, 7);

    sig = process::find_signature(client_base, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 8B 01");
    if (sig != 0) g_local_ptr = process::get_relative_address(sig, 3, 7);

    if (g_entity_list == 0) alert::show_tag("Pattern scan failed", "error");
    else                   alert::show("CS2 ESP attached");
}

// USER CODE — chunked entity-list lookup for Source 2. The stride/offsets are PLACEHOLDERS.
uint64 get_ent(int idx) {
    uint64 chunk = process::read_uint64(g_entity_list + uint64(idx >> 9) * 8);
    if (chunk == 0) return 0;
    return process::read_uint64(chunk + uint64(idx & 0x1FF) * 120);
}

void tick() {
    if (g_entity_list == 0) return;

    uint64 local_pawn = process::read_uint64(g_local_ptr);
    int    local_team = local_pawn != 0 ? process::read_int32(local_pawn + OFF_TEAM) : -1;

    vec3 local_pos;
    if (local_pawn != 0) local_pos.read_float(local_pawn + OFF_ORIGIN);

    matrix4x4 vm;
    if (!vm.read(g_view_mat)) return;

    array<ED@> local;
    for (int i = 1; i < 64; i++) {
        uint64 ent = get_ent(i);
        if (ent == 0 || ent == local_pawn) continue;
        if (process::read_uint8(ent + OFF_LIFE) != 0) continue;
        int hp = process::read_int32(ent + OFF_HEALTH);
        if (hp <= 0) continue;
        if (process::read_int32(ent + OFF_TEAM) == local_team) continue;

        vec3 origin;
        origin.read_float(ent + OFF_ORIGIN);
        float dist = origin.distance(local_pos);
        if (dist > float(ui::get(esp_dist))) continue;

        uint64 ctrl  = source2::get_controller(g_entity_list, uint64(i));
        string pname = ctrl != 0 ? process::read_string(ctrl + OFF_NAME) : "?";

        vec2 head_screen;
        vec3 head = vec3(origin.x, origin.y, origin.z + 72.0f); // PLACEHOLDER head offset
        if (!source2::w2s(head, vm, head_screen)) continue;
        vec2 feet_screen;
        if (!source2::w2s(origin, vm, feet_screen)) continue;

        float bh = head_screen.y - feet_screen.y;
        if (bh < 0) bh = -bh;
        float bw = bh * 0.5f;

        ED@ ed = ED();
        ed.sx0 = feet_screen.x - bw;
        ed.sy0 = head_screen.y;
        ed.sw  = bw * 2.0f;
        ed.sh  = bh;
        ed.hp  = hp;
        ed.visible = process::read_uint8(ent + OFF_SPOT) != 0;
        ed.name = pname;
        ed.dist = dist;
        local.insertLast(ed);
    }
    ent_mx.lock(); g_ents = local; ent_mx.unlock();
}

void draw() {
    if (!ui::get(esp_on)) return;
    ent_mx.lock_shared();
    array<ED@> snap = g_ents;
    ent_mx.unlock_shared();

    render::update_font(fonts::TAHOMA, 13);

    color base = ui::get(esp_col);
    for (uint i = 0; i < snap.length(); i++) {
        ED@ ed = snap[i];
        int r = base.r, g = base.g, b = base.b, a = base.a;
        if (!ed.visible) { r = 180; g = 60; b = 60; a = 200; }

        // Cornered box
        float cx_ = ed.sw * 0.25f, cy_ = ed.sh * 0.25f;
        render::draw_line(ed.sx0,         ed.sy0,         ed.sx0 + cx_,     ed.sy0,         r, g, b, a, 1.5f);
        render::draw_line(ed.sx0,         ed.sy0,         ed.sx0,           ed.sy0 + cy_,   r, g, b, a, 1.5f);
        render::draw_line(ed.sx0 + ed.sw, ed.sy0,         ed.sx0 + ed.sw - cx_, ed.sy0,    r, g, b, a, 1.5f);
        render::draw_line(ed.sx0 + ed.sw, ed.sy0,         ed.sx0 + ed.sw,   ed.sy0 + cy_,   r, g, b, a, 1.5f);
        render::draw_line(ed.sx0,         ed.sy0 + ed.sh, ed.sx0 + cx_,     ed.sy0 + ed.sh, r, g, b, a, 1.5f);
        render::draw_line(ed.sx0,         ed.sy0 + ed.sh, ed.sx0,           ed.sy0 + ed.sh - cy_, r, g, b, a, 1.5f);
        render::draw_line(ed.sx0 + ed.sw, ed.sy0 + ed.sh, ed.sx0 + ed.sw - cx_, ed.sy0 + ed.sh, r, g, b, a, 1.5f);
        render::draw_line(ed.sx0 + ed.sw, ed.sy0 + ed.sh, ed.sx0 + ed.sw,   ed.sy0 + ed.sh - cy_, r, g, b, a, 1.5f);

        // Health bar — gradient from low health to high health
        float hp_pct = float(ed.hp) / 100.0f;
        render::draw_gradient_box(int(ed.sx0 - 6.0f), int(ed.sy0), 3, int(ed.sh),
                                  220, 40, 40, 220,
                                  int(60.0f * hp_pct), int(220.0f * hp_pct), 60, 220,
                                  true);

        // Label
        render::draw_text_outlined(int(ed.sx0), int(ed.sy0 - 14.0f),
                                   util::format_string("{} [{}m]", ed.name, int(ed.dist / UNITS_TO_M)),
                                   r, g, b, a);
    }
}

void on_unload() { process::detach(); }
```

---

## Script 2: UE4 Aim Assist (generic)

```angelscript
// ue4_aim.as — hold the right mouse button to softly track the nearest actor within FOV

uint64 g_gworld = 0;

checkbox aim_on;
slider   aim_fov_sl;
slider   aim_smooth_sl;

// Offsets below are PLACEHOLDERS — regenerate with Dumper-7.
const uint64 ACTOR_MESH  = 0x280; // USkeletalMeshComponent*
const uint64 BONES_ARRAY = 0x580; // SpaceBasesData
const uint64 CAM_LOC     = 0x1490;
const uint64 CAM_ROT     = 0x149C;
const float  SENS        = 1.0f;
const float  YAW_FACTOR  = 0.0066f; // verify per game

// USER CODE — Echo's mouse API is absolute; read the cursor, add a delta, write it back.
void move_mouse_relative(float dx, float dy) {
    int cx = 0, cy = 0;
    input::mouse_pos(cx, cy);
    vec2 vp = render::get_viewport_size();
    int nx = cx + int(dx);
    int ny = cy + int(dy);
    if (nx < 0) nx = 0;
    if (ny < 0) ny = 0;
    if (nx > int(vp.x)) nx = int(vp.x);
    if (ny > int(vp.y)) ny = int(vp.y);
    input::mouse_move(nx, ny);
}

bool main() {
    ui::config_path("ue4aim");
    ui::add_tab("UE4 Aim");
    ui::add_category("Settings");
    aim_on        = ui::add_checkbox("Enable", false, "ue4aim.on");
    aim_fov_sl    = ui::add_slider("FOV", 10, 1, 45, 1, "deg", "ue4aim.fov");
    aim_smooth_sl = ui::add_slider("Smoothing", 5, 1, 20, 1, "", "ue4aim.smooth");

    attach_data ad = process::attach("game.exe");
    if (ad.pid == 0) { alert::show_tag("Attach failed", "error"); return false; }

    create_thread(0,   @scan_sigs);
    create_thread(128, @aim_tick);
    return true;
}

void scan_sigs() {
    uint64 base = process::get_module_base("game.exe");
    if (base == 0) { alert::show_tag("game.exe not found", "error"); return; }
    uint64 sig = process::find_signature(base, "48 8B 1D ? ? ? ? 48 85 DB 74 3B 41");
    if (sig == 0) { alert::show_tag("GWorld pattern broken", "error"); return; }
    g_gworld = process::get_relative_address(sig, 3, 7);
    alert::show("UE4 aim assist: GWorld found");
}

void aim_tick() {
    if (!ui::get(aim_on)) return;
    if (!input::key_active(0x02)) return; // RMB hold
    if (g_gworld == 0) return;

    uint64 world  = process::read_uint64(g_gworld);
    if (world == 0) return;
    uint64 level  = process::read_uint64(world + 0x30);
    uint64 adata  = process::read_uint64(level + 0xA0);
    int32  acount = process::read_int32(level + 0xA8);

    uint64 gi  = process::read_uint64(world + 0x180);
    uint64 lp  = process::read_uint64(process::read_uint64(process::read_uint64(gi + 0x38)));
    uint64 cam = process::read_uint64(lp + 0x440);

    vec3 cloc; cloc.read_float(cam + CAM_LOC);
    vec3 crot; crot.read_float(cam + CAM_ROT);

    int    best = -1;
    double best_fov = double(ui::get(aim_fov_sl));
    vec3   best_pos = vec3(0, 0, 0);

    for (int i = 0; i < acount; i++) {
        uint64 actor = process::read_uint64(adata + uint64(i) * 8);
        if (actor == 0) continue;
        uint64 mesh = process::read_uint64(actor + ACTOR_MESH);
        if (mesh == 0) continue;
        uint64 barr = process::read_uint64(mesh + BONES_ARRAY);
        if (barr == 0) continue;

        // Head bone (index 9) → translation at +32 inside a 48-byte FTransform
        uint64 baddr = barr + 9 * 48 + 32;
        vec3 bpos;
        bpos.read_float(baddr);

        double fov = math::unreal_calculate_fov(crot, cloc, bpos);
        if (fov < best_fov) { best_fov = fov; best = i; best_pos = bpos; }
    }

    if (best < 0) return;

    vec2 delta = math::unreal_calculate_angle(crot, cloc, best_pos);
    float smooth = float(ui::get(aim_smooth_sl));
    float dp = float(delta.x) / smooth;
    float dy = float(delta.y) / smooth;

    move_mouse_relative(dy / (SENS * YAW_FACTOR), dp / (SENS * YAW_FACTOR));
}

void on_unload() { process::detach(); }
```

---

## Script 3: Unity loot scanner

```angelscript
// unity_loot.as — scans for known prefab IDs and displays a sorted loot panel

uint64 g_cam = 0;
vec3   g_local_pos;

checkbox loot_on;
slider   loot_dist;

mutex@   loot_mx = create_mutex();

class LootItem { string name; float dist; float sx, sy; bool vis; }
array<LootItem@> g_loot;

hash_set_uint32@ g_loot_ids = create_hash_set_uint32();

bool main() {
    ui::config_path("loot");
    ui::add_tab("Loot");
    ui::add_category("Settings");
    loot_on   = ui::add_checkbox("Enable", true, "loot.on");
    loot_dist = ui::add_slider("Range", 300, 10, 300, 10, "m", "loot.dist");

    // Prefab IDs below are EXAMPLES — build your set from an entity dump.
    g_loot_ids.insert(0x17F9); // rifle (example)
    g_loot_ids.insert(0x2B4A); // medical (example)

    attach_data ad = process::attach("UnityGame.exe");
    if (ad.pid == 0) { alert::show_tag("Attach failed", "error"); return false; }

    create_thread(0,  @scan_sigs);
    create_thread(16, @tick_loot);
    on_render(@draw_loot);
    return true;
}

void scan_sigs() {
    uint64 base = process::get_module_base("UnityPlayer.dll");
    if (base == 0) { alert::show_tag("UnityPlayer.dll not found", "error"); return; }
    uint64 sig = process::find_signature(base, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 8B 81");
    if (sig == 0) { alert::show_tag("Camera pattern broken", "error"); return; }
    g_cam = process::get_relative_address(sig, 3, 7);
    alert::show("Loot scanner ready");
}

void tick_loot() {
    if (!ui::get(loot_on)) return;
    if (g_cam == 0) return;

    float range = float(ui::get(loot_dist)) * 100.0f; // Unity units → metres — verify per game
    g_local_pos.read_float(g_cam + 0x08);

    uint64 ent_mgr   = process::read_uint64(process::read_uint64(g_cam + 0x20));
    int32  ent_count = process::read_int32(ent_mgr + 0x18);
    uint64 ent_list  = process::read_uint64(ent_mgr + 0x10);

    array<LootItem@> items;
    for (int i = 0; i < ent_count; i++) {
        uint64 ent = process::read_uint64(ent_list + uint64(i) * 8);
        if (ent == 0) continue;

        // unity::rust_prefab_id takes an asset path string — resolve the path for this entity first
        string asset_path = get_entity_asset_path(ent); // USER CODE — read the path from the entity
        if (asset_path == "") continue;
        if (!g_loot_ids.contains(unity::rust_prefab_id(asset_path))) continue;

        vec3 wp = unity::rust_transform_position(ent);
        float d = wp.distance(g_local_pos);
        if (d > range) continue;

        matrix4x4 vm;
        vec2 screen;
        bool vis = false;
        if (vm.read(g_cam + 0x30)) vis = unity::w2s(wp, vm, screen);

        LootItem@ it = LootItem();
        it.name = util::format_string("Item_{}", unity::rust_prefab_id(asset_path));
        it.dist = d;
        it.sx   = screen.x;
        it.sy   = screen.y;
        it.vis  = vis;
        items.insertLast(it);
    }

    // USER CODE — insertion sort by distance
    for (uint i = 1; i < items.length(); i++) {
        LootItem@ key = items[i];
        int j = int(i) - 1;
        while (j >= 0 && items[j].dist > key.dist) {
            items[j + 1] = items[j];
            j--;
        }
        items[j + 1] = key;
    }

    loot_mx.lock(); g_loot = items; loot_mx.unlock();
}

void draw_loot() {
    if (!ui::get(loot_on)) return;
    loot_mx.lock_shared();
    array<LootItem@> snap = g_loot;
    loot_mx.unlock_shared();

    render::update_font(fonts::TAHOMA, 11);

    for (uint i = 0; i < snap.length(); i++) {
        LootItem@ it = snap[i];
        if (!it.vis) continue;
        render::draw_text_outlined(int(it.sx), int(it.sy - 12.0f),
                                   it.name + " " + util::format_string("{:.0f}m", it.dist / 100.0f),
                                   255, 200, 60, 220);
    }

    int show = int(snap.length());
    if (show > 10) show = 10;
    if (show == 0) return;

    float px = 20.0f, py = 200.0f;
    render::draw_box(int(px - 4.0f), int(py - 4.0f), 180, int(float(show) * 15.0f + 8.0f),
                     0, 0, 0, 140, box_style::FILLED, 0.0f);
    for (int i = 0; i < show; i++) {
        LootItem@ it = snap[i];
        render::draw_text(int(px), int(py + float(i) * 15.0f),
                          it.name + " " + util::format_string("{:.0f}m", it.dist / 100.0f),
                          255, 200, 60, 220);
    }
}

void on_unload() { process::detach(); }
```

## Notes

- Offsets (`0x344`, `0x3CB`, etc.) are CS2 *examples* — get correct values from a schema dump or your own RE.
- `process::find_signature` patterns may break after patches — regenerate them with a binary diff.
- Replace `"UnityGame.exe"` / `"game.exe"` with your actual process name.
- W2S helpers write to an out-parameter and return `bool` — check the return value before drawing.
- `input::mouse_move` takes an absolute position; read `input::mouse_pos` first when you need a relative move.
- To test a value without restarting the game, log it: `alert::show_tag(util::format_string("value: {}", some_read), "info");`
