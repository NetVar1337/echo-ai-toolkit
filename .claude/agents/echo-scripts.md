---
name: echo-scripts
description: Complete runnable Echo AngelScript examples. Contains full working scripts for CS2 ESP, UE4 aimbot, and Unity loot scanner. Use when you need a drop-in starting point or to see how all APIs connect into a real working script.
---

# Echo Scripts — Complete Working Examples

Drop any of these into `%AppData%\Roaming\scripts\<name>.as`, then reload the Echo in-game menu.

**Offsets are placeholders** — update from Dumper-7, schema, or binary-differ for your game/build.

---

## Script 1: CS2 Minimal ESP

```angelscript
// cs2_esp.as — cornered-box ESP with health bar and name/distance label

process@      proc;
tab@          t;
checkbox@     esp_on;
color_picker@ esp_col;
slider@       esp_dist;
font_handle@  fnt;
mutex@        ent_mx = mutex();

struct ED {
    float sx0, sy0, sw, sh;
    int   hp;
    bool  visible;
    string name;
    float dist;
}

array<ED@> g_ents;
uint64 g_entity_sys = 0;
uint64 g_view_mat   = 0;
uint64 g_local_ptr  = 0;

bool main() {
    t        = menu.add_tab("CS2 ESP");
    auto cat = t.add_category("Settings");
    esp_on   = cat.add_checkbox("Enable",    true,  "cs2esp.on");
    esp_col  = cat.add_color_picker("Color", color(0, 220, 60, 220));
    esp_dist = cat.add_slider("Max dist",    100.0f, 8000.0f, 3000.0f, "cs2esp.dist");
    fnt      = renderer.load_font("Arial", 13, font_hint::DEFAULT, false);

    proc = process.attach("cs2.exe");
    if (proc is null) { alert.show_tag("Attach failed", "error"); return false; }

    create_thread(0,  @scan_sigs);
    create_thread(64, @tick);
    on_render(@draw);
    return true;
}

void scan_sigs() {
    g_entity_sys = proc.resolve_rip(
        proc.scan("48 8B 0D ?? ?? ?? ?? 48 85 C9 74 ?? 4C 8B 01", "client.dll"), 3, 7);
    g_view_mat   = proc.resolve_rip(
        proc.scan("48 8D 05 ?? ?? ?? ?? 48 89 05 ?? ?? ?? ?? 48 8D 0D", "client.dll"), 3, 7);
    g_local_ptr  = proc.resolve_rip(
        proc.scan("48 8B 0D ?? ?? ?? ?? 48 85 C9 74 ?? 8B 01", "client.dll"), 3, 7);
    if (g_entity_sys == 0) alert.show_tag("Pattern scan failed", "error");
    else                   alert.show("CS2 ESP attached");
}

uint64 get_ent(int idx) {
    uint64 elist = proc.read<uint64>(g_entity_sys + 0x10);
    uint64 chunk = proc.read<uint64>(elist + (idx >> 9) * 8);
    if (chunk == 0) return 0;
    return proc.read<uint64>(chunk + (idx & 0x1FF) * 120);
}

bool w2s(float[16]& vp, vec3@ w, float& sx, float& sy) {
    float x = w.x*vp[0]+w.y*vp[4]+w.z*vp[8] +vp[12];
    float y = w.x*vp[1]+w.y*vp[5]+w.z*vp[9] +vp[13];
    float z = w.x*vp[3]+w.y*vp[7]+w.z*vp[11]+vp[15];
    if (z < 0.001f) return false;
    float inv = 1.0f / z;
    sx = 960.0f  + x * inv * 960.0f;
    sy = 540.0f  - y * inv * 540.0f;
    return sx >= 0 && sx <= 1920 && sy >= 0 && sy <= 1080;
}

void tick() {
    if (g_entity_sys == 0) return;
    uint64 local_pawn = proc.read<uint64>(g_local_ptr);
    int    local_team = local_pawn != 0 ? proc.read<int>(local_pawn + 0x3CB) : -1;
    vec3@  local_pos  = vec3();
    if (local_pawn != 0) local_pos.read(proc, local_pawn + 0x1294);

    float[16] vm;
    for (int i = 0; i < 16; i++) vm[i] = proc.read<float>(g_view_mat + uint64(i) * 4);

    array<ED@> local;
    for (int i = 1; i < 64; i++) {
        uint64 ent = get_ent(i);
        if (ent == 0 || ent == local_pawn) continue;
        if (proc.read<uint8>(ent + 0x338) != 0) continue;
        int hp = proc.read<int>(ent + 0x344);
        if (hp <= 0) continue;
        if (proc.read<int>(ent + 0x3CB) == local_team) continue;

        vec3@ origin = vec3(); origin.read(proc, ent + 0x1294);
        float dx = origin.x-local_pos.x, dy = origin.y-local_pos.y, dz = origin.z-local_pos.z;
        float dist = sqrt(dx*dx+dy*dy+dz*dz);
        if (dist > esp_dist.get()) continue;

        uint64 ctrl   = source2.get_controller(proc, ent);
        string pname  = ctrl != 0 ? proc.read_string(ctrl + 0x640, 32) : "?";

        vec3@ head = vec3(origin.x, origin.y, origin.z + 72.0f);
        float hx, hy, fx, fy;
        if (!w2s(vm, head, hx, hy)) continue;
        w2s(vm, origin, fx, fy);

        float bh = abs(hy - fy), bw = bh * 0.5f;
        ED@ ed  = ED();
        ed.sx0  = fx - bw; ed.sy0 = hy; ed.sw = bw*2; ed.sh = bh;
        ed.hp   = hp;
        ed.visible = proc.read<bool>(ent + 0xF9B);
        ed.name = pname; ed.dist = dist;
        local.insertLast(ed);
    }
    ent_mx.lock(); g_ents = local; ent_mx.unlock();
}

void draw() {
    if (!esp_on.get()) return;
    ent_mx.lock_shared(); array<ED@> snap = g_ents; ent_mx.unlock_shared();
    for (uint i = 0; i < snap.length(); i++) {
        ED@ ed = snap[i];
        color c = ed.visible ? esp_col.get() : color(180, 60, 60, 200);
        // Cornered box
        float cx_ = ed.sw * 0.25f, cy_ = ed.sh * 0.25f;
        renderer.line(ed.sx0,       ed.sy0,       ed.sx0+cx_, ed.sy0,       1.5f, c);
        renderer.line(ed.sx0,       ed.sy0,       ed.sx0,     ed.sy0+cy_,   1.5f, c);
        renderer.line(ed.sx0+ed.sw, ed.sy0,       ed.sx0+ed.sw-cx_, ed.sy0, 1.5f, c);
        renderer.line(ed.sx0+ed.sw, ed.sy0,       ed.sx0+ed.sw, ed.sy0+cy_,1.5f, c);
        renderer.line(ed.sx0,       ed.sy0+ed.sh, ed.sx0+cx_, ed.sy0+ed.sh,1.5f, c);
        renderer.line(ed.sx0,       ed.sy0+ed.sh, ed.sx0,  ed.sy0+ed.sh-cy_,1.5f,c);
        renderer.line(ed.sx0+ed.sw, ed.sy0+ed.sh, ed.sx0+ed.sw-cx_,ed.sy0+ed.sh,1.5f,c);
        renderer.line(ed.sx0+ed.sw, ed.sy0+ed.sh, ed.sx0+ed.sw,ed.sy0+ed.sh-cy_,1.5f,c);
        // Health bar
        renderer.draw_hue_bar(ed.sx0 - 6, ed.sy0, 3.0f, ed.sh, float(ed.hp)/100.0f);
        // Label
        renderer.text_outlined(ed.sx0, ed.sy0-14, ed.name+" ["+int(ed.dist/39.37f)+"m]",
                               fnt, c, color(0,0,0,180));
    }
}

void on_unload() { proc = null; }
```

---

## Script 2: UE4 Aimbot (generic)

```angelscript
// ue4_aimbot.as — hold RMB to softlock onto nearest actor within FOV

process@  proc;
checkbox@ aim_on;
slider@   aim_fov_sl, aim_smooth_sl;
uint64    g_gworld = 0;

const uint64 ACTOR_MESH  = 0x280; // USkeletalMeshComponent* — verify with Dumper-7
const uint64 BONES_ARRAY = 0x580; // SpaceBasesData
const uint64 CAM_LOC     = 0x1490;
const uint64 CAM_ROT     = 0x149C;
const float  SENS        = 1.0f;
const float  YAW_FACTOR  = 0.0066f;

bool main() {
    auto t       = menu.add_tab("UE4 Aim");
    auto cat     = t.add_category("Settings");
    aim_on       = cat.add_checkbox("Enable",    false, "ue4aim.on");
    aim_fov_sl   = cat.add_slider("FOV°",        1.0f, 45.0f, 8.0f,  "ue4aim.fov");
    aim_smooth_sl= cat.add_slider("Smoothing",   1.0f, 20.0f, 5.0f,  "ue4aim.smooth");

    proc = process.attach("game.exe");
    if (proc is null) { alert.show_tag("Attach failed", "error"); return false; }
    create_thread(0,   @scan_sigs);
    create_thread(128, @aim_tick);
    return true;
}

void scan_sigs() {
    uint64 sig = proc.scan_ida("48 8B 1D ? ? ? ? 48 85 DB 74 3B 41", "game.exe");
    g_gworld   = proc.resolve_rip(sig, 3, 7);
    alert.show("UE4 aimbot: GWorld found");
}

void aim_tick() {
    if (!aim_on.get() || !input.key_active(0x02)) return;
    uint64 world = proc.read<uint64>(g_gworld); if (world == 0) return;
    uint64 level = proc.read<uint64>(world + 0x30);
    uint64 adata = proc.read<uint64>(level + 0xA0);
    int    acount= proc.read<int>(level + 0xA8);

    uint64 gi   = proc.read<uint64>(world + 0x180);
    uint64 lp   = proc.read<uint64>(proc.read<uint64>(proc.read<uint64>(gi + 0x38)));
    uint64 cam  = proc.read<uint64>(lp + 0x440);
    vec3@  cloc = vec3(); cloc.read(proc, cam + CAM_LOC);
    float  cp   = proc.read<float>(cam + CAM_ROT);
    float  cy   = proc.read<float>(cam + CAM_ROT + 4);

    int   best = -1; float best_fov = aim_fov_sl.get();
    vec3@ best_pos = null;

    for (int i = 0; i < acount; i++) {
        uint64 actor = proc.read<uint64>(adata + uint64(i) * 8);
        if (actor == 0) continue;
        uint64 mesh  = proc.read<uint64>(actor + ACTOR_MESH); if (mesh == 0) continue;
        uint64 barr  = proc.read<uint64>(mesh  + BONES_ARRAY); if (barr == 0) continue;
        uint64 baddr = barr + 9 * 48 + 32;
        vec3@  bpos  = vec3(proc.read<float>(baddr), proc.read<float>(baddr+4), proc.read<float>(baddr+8));
        float tp, ty;
        math.unreal_calculate_angle(cloc, bpos, tp, ty);
        float fov = sqrt(pow(math.angle_diff(cp,tp),2)+pow(math.angle_diff(cy,ty),2));
        if (fov < best_fov) { best_fov=fov; best=i; best_pos=bpos; }
    }

    if (best_pos is null) return;
    float tp, ty;
    math.unreal_calculate_angle(cloc, best_pos, tp, ty);
    float dp = math.angle_diff(cp, tp) / aim_smooth_sl.get();
    float dy2= math.angle_diff(cy, ty) / aim_smooth_sl.get();
    mouse.move(int(dy2/(SENS*YAW_FACTOR)+0.5f), int(dp/(SENS*YAW_FACTOR)+0.5f));
}

void on_unload() { proc = null; }
```

---

## Script 3: Unity loot scanner

```angelscript
// unity_loot.as — scans for known prefab IDs and displays a sorted loot panel

process@      proc;
checkbox@     loot_on;
slider@       loot_dist;
font_handle@  fnt;
mutex@        loot_mx = mutex();

struct LootItem { string name; float dist; float sx, sy; bool vis; }
array<LootItem> g_loot;
uint64 g_cam = 0;
vec3@  g_local_pos = vec3();

hash_set_uint32@ LOOT_IDS = hash_set_uint32();

bool main() {
    auto t   = menu.add_tab("Loot");
    auto cat = t.add_category("Settings");
    loot_on  = cat.add_checkbox("Enable", true, "loot.on");
    loot_dist= cat.add_slider("Range (m)", 10.0f, 300.0f, 100.0f, "loot.dist");
    fnt      = renderer.load_font("Arial", 11, font_hint::DEFAULT, false);

    LOOT_IDS.insert(0x17F9); // rifle (example)
    LOOT_IDS.insert(0x2B4A); // medical (example)

    proc = process.attach("UnityGame.exe");
    if (proc is null) { alert.show_tag("Attach failed", "error"); return false; }
    create_thread(0,  @scan_sigs);
    create_thread(16, @tick_loot);
    on_render(@draw_loot);
    return true;
}

void scan_sigs() {
    uint64 sig = proc.scan("48 8B 0D ?? ?? ?? ?? 48 85 C9 74 ?? 8B 81", "UnityPlayer.dll");
    g_cam      = proc.resolve_rip(sig, 3, 7);
    alert.show("Loot scanner ready");
}

void tick_loot() {
    if (!loot_on.get() || g_cam == 0) return;
    float range = loot_dist.get() * 100.0f;
    g_local_pos.read(proc, g_cam + 0x08);

    uint64 ent_mgr   = proc.read<uint64>(proc.read<uint64>(g_cam + 0x20));
    int    ent_count = proc.read<int>(ent_mgr + 0x18);
    uint64 ent_list  = proc.read<uint64>(ent_mgr + 0x10);

    array<LootItem> items;
    for (int i = 0; i < ent_count; i++) {
        uint64 ent = proc.read<uint64>(ent_list + uint64(i) * 8);
        if (ent == 0) continue;
        if (!LOOT_IDS.contains(unity.rust_prefab_id(proc, ent))) continue;
        vec3@ wp = unity.rust_transform_position(proc, ent);
        float dx=wp.x-g_local_pos.x, dy=wp.y-g_local_pos.y, dz=wp.z-g_local_pos.z;
        float d = sqrt(dx*dx+dy*dy+dz*dz);
        if (d > range) continue;
        float sx, sy;
        bool vis = unity.w2s(proc, g_cam, wp, sx, sy);
        LootItem it;
        it.name = fmt("Item_{:04X}", unity.rust_prefab_id(proc, ent));
        it.dist = d; it.sx=sx; it.sy=sy; it.vis=vis;
        items.insertLast(it);
    }
    items.sort(@function(LootItem& a, LootItem& b){ return a.dist < b.dist; });
    loot_mx.lock(); g_loot=items; loot_mx.unlock();
}

void draw_loot() {
    if (!loot_on.get()) return;
    loot_mx.lock_shared(); array<LootItem> snap=g_loot; loot_mx.unlock_shared();
    color c = color(255, 200, 60, 220);
    for (uint i=0; i < snap.length(); i++) {
        LootItem@ it = snap[i];
        if (!it.vis || it.dist > 5000) continue;
        renderer.text_outlined(it.sx, it.sy-12, it.name+" "+fmt("{:.0f}m",it.dist/100),
                               fnt, c, color(0,0,0,180));
    }
    float px=20, py=200;
    int show = min(int(snap.length()), 10);
    if (show==0) return;
    renderer.rect(px-4,py-4,180,float(show)*15+8,color(0,0,0,140));
    for (int i=0;i<show;i++) {
        LootItem@ it=snap[i];
        renderer.text(px,py+i*15, it.name+" "+fmt("{:.0f}m",it.dist/100), fnt, c);
    }
}

void on_unload() { proc = null; }
```

## Notes

- Offsets (`0x344`, `0x3CB`, etc.) are CS2 examples — get correct values from Dumper-7 or `schema.get_offset`.
- `proc.scan_ida` patterns may break after patches — use `binary-differ` to regen.
- Replace `"UnityGame.exe"` / `"game.exe"` with your actual process name.
- To test: add `alert.show_tag(fmt("value: {}", some_read), "info")` — visible immediately without restarting the game.
