// Full CS2/Source 2 ESP: boxes, skeleton, health bar, distance labels
// All offsets are examples — verify against current cs2-dumper output

// ─── Offsets ───────────────────────────────────────────────────────
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

// Pairs for skeleton draw: [from, to]
int BONE_PAIRS[][] = {
    {HEAD,NECK},{NECK,CHEST},{CHEST,SPINE},{SPINE,PELVIS},  // spine
    {CHEST,SHL},{SHL,ELB_L},{ELB_L,HAND_L},                // L arm
    {CHEST,SHR},{SHR,ELB_R},{ELB_R,HAND_R},                // R arm
    {PELVIS,HIP_L},{HIP_L,KNEE_L},{KNEE_L,FOOT_L},          // L leg
    {PELVIS,HIP_R},{HIP_R,KNEE_R},{KNEE_R,FOOT_R}           // R leg
};

// ─── Shared entity data (written by tick, read by render) ──────────
struct EspEntity {
    bool   alive;
    bool   visible;
    bool   is_team;
    int    hp;
    float  dist;
    string name;
    float  sx[44]; float sy[44]; bool sv[44]; // bone screen positions
    float  box_x, box_y, box_w, box_h;
}

array<EspEntity@> g_entities;
mutex@ g_mx = mutex();

// ─── Menu ─────────────────────────────────────────────────────────
tab@          t;
checkbox@     esp_on;
checkbox@     show_box;
checkbox@     show_skel;
checkbox@     show_hp;
checkbox@     show_name;
slider@       max_dist;
color_picker@ col_enemy;
color_picker@ col_team;
color_picker@ col_visible;
font_handle@  fnt;

// ─── Process state ─────────────────────────────────────────────────
process@ proc;
uint64   entity_list  = 0;
uint64   view_mat_addr= 0;
uint64   local_player = 0;

// ─── Entry point ───────────────────────────────────────────────────
bool main() {
    t          = menu.add_tab("ESP");
    auto cat   = t.add_category("Visuals");
    esp_on     = cat.add_checkbox("Enable",    true,  "esp.on");
    show_box   = cat.add_checkbox("Boxes",     true,  "esp.box");
    show_skel  = cat.add_checkbox("Skeleton",  true,  "esp.skel");
    show_hp    = cat.add_checkbox("Health bar",true,  "esp.hp");
    show_name  = cat.add_checkbox("Names",     true,  "esp.name");
    max_dist   = cat.add_slider("Max dist (m)",10.0f, 500.0f, 200.0f, "esp.dist");
    col_enemy  = cat.add_color_picker("Enemy", color(220,60,60,255),  "esp.col_e");
    col_team   = cat.add_color_picker("Team",  color(80,120,255,255), "esp.col_t");
    col_visible= cat.add_color_picker("Vis",   color(0,220,60,255),   "esp.col_v");

    fnt = renderer.load_font("Verdana", 11, false);

    proc = process.attach("cs2.exe");
    if (proc is null) { alert("cs2.exe not found"); return false; }

    create_thread(0,  @do_scan);   // one-shot: find addresses
    create_thread(32, @tick);      // 32 tps entity update
    on_render(@draw);
    return true;
}

// ─── Address scan (runs once after attach) ─────────────────────────
void do_scan() {
    // Entity system
    uint64 sig = proc.scan("48 8B 0D ?? ?? ?? ?? 48 89 5C 24", "client.dll");
    if (sig == 0) { alert("entity list sig failed"); return; }
    uint64 ent_sys  = proc.resolve_rip(sig, 3, 7);
    entity_list     = proc.read<uint64>(proc.read<uint64>(ent_sys) + 0x10);

    // View matrix
    sig = proc.scan("48 8D 05 ?? ?? ?? ?? 48 89 05 ?? ?? ?? ??", "client.dll");
    if (sig != 0) view_mat_addr = proc.resolve_rip(sig, 3, 7);

    // Local player
    sig = proc.scan("48 8B 0D ?? ?? ?? ?? 48 85 C9 74 ?? 8B 01", "client.dll");
    if (sig != 0) local_player = proc.resolve_rip(sig, 3, 7);

    alert("ESP ready");
}

// ─── Helpers ───────────────────────────────────────────────────────
uint64 get_entity(int idx) {
    uint64 chunk = proc.read<uint64>(entity_list + uint64(idx >> 9) * 8);
    if (chunk == 0) return 0;
    return proc.read<uint64>(chunk + uint64(idx & 0x1FF) * 120);
}

bool read_bone_screen(uint64 ent, int bone, float vp[], float& sx, float& sy) {
    uint64 skel     = proc.read<uint64>(ent + OFF_SKELETON);
    uint64 bone_arr = proc.read<uint64>(skel + OFF_BONE_ARR);
    uint64 addr     = bone_arr + uint64(bone) * 0x20 + 0x10;
    float wx = proc.read<float>(addr);
    float wy = proc.read<float>(addr + 4);
    float wz = proc.read<float>(addr + 8);

    float cx = vp[0]*wx + vp[4]*wy + vp[8]*wz  + vp[12];
    float cy = vp[1]*wx + vp[5]*wy + vp[9]*wz  + vp[13];
    float cw = vp[3]*wx + vp[7]*wy + vp[11]*wz + vp[15];
    if (cw < 0.001f) return false;
    float inv = 1.0f / cw;
    sx = 960.0f + cx * inv * 960.0f;
    sy = 540.0f - cy * inv * 540.0f;
    return sx >= 0 && sx <= 1920 && sy >= 0 && sy <= 1080;
}

// ─── Tick: read entity data ─────────────────────────────────────────
void tick() {
    if (!esp_on.get() || entity_list == 0 || view_mat_addr == 0) return;

    // Read view projection matrix (16 floats)
    float vp[16];
    for (int i = 0; i < 16; i++)
        vp[i] = proc.read<float>(view_mat_addr + uint64(i) * 4);

    uint64 lp_ptr  = proc.read<uint64>(local_player);
    int    lp_team = (lp_ptr != 0) ? proc.read<int>(lp_ptr + OFF_TEAM) : 0;
    float  lp_ox   = (lp_ptr != 0) ? proc.read<float>(lp_ptr + OFF_ORIGIN)     : 0;
    float  lp_oy   = (lp_ptr != 0) ? proc.read<float>(lp_ptr + OFF_ORIGIN + 4) : 0;
    float  lp_oz   = (lp_ptr != 0) ? proc.read<float>(lp_ptr + OFF_ORIGIN + 8) : 0;
    float  dist_max = max_dist.get() * 39.37f; // metres → Source units

    array<EspEntity@> local_buf;

    for (int i = 1; i < 64; i++) {
        uint64 ent = get_entity(i);
        if (ent == 0) continue;
        if (proc.read<uint8>(ent + OFF_LIFE) != 0) continue;  // dead
        int hp = proc.read<int>(ent + OFF_HP);
        if (hp <= 0) continue;

        float ox = proc.read<float>(ent + OFF_ORIGIN);
        float oy = proc.read<float>(ent + OFF_ORIGIN + 4);
        float oz = proc.read<float>(ent + OFF_ORIGIN + 8);
        float dx = lp_ox - ox, dy = lp_oy - oy, dz = lp_oz - oz;
        float dist_units = sqrt(dx*dx + dy*dy + dz*dz);
        if (dist_units > dist_max) continue;

        int team = proc.read<int>(ent + OFF_TEAM);
        bool spotted = proc.read<bool>(ent + OFF_SPOTTED);

        EspEntity@ ed = EspEntity();
        ed.alive   = true;
        ed.hp      = hp;
        ed.is_team = (team == lp_team);
        ed.visible = spotted;
        ed.dist    = dist_units / 39.37f;

        // Read player name
        char name_buf[64];
        for (int c = 0; c < 32; c++) {
            uint8 ch = proc.read<uint8>(ent + OFF_NAME + c);
            if (ch == 0) break;
            ed.name += string(ch);
        }

        // Project all skeleton bones
        float head_sx = 0, head_sy = 0, feet_sx = 0, feet_sy = 0;
        bool head_ok = false, feet_ok = false;
        for (int b = 0; b < 44; b++) {
            ed.sv[b] = read_bone_screen(ent, b, vp, ed.sx[b], ed.sy[b]);
        }
        head_ok  = ed.sv[HEAD];
        feet_ok  = ed.sv[FOOT_L] || ed.sv[FOOT_R];
        head_sx  = ed.sx[HEAD]; head_sy = ed.sy[HEAD];
        feet_sx  = ed.sv[FOOT_L] ? ed.sx[FOOT_L] : ed.sx[FOOT_R];
        feet_sy  = ed.sv[FOOT_L] ? ed.sy[FOOT_L] : ed.sy[FOOT_R];

        if (head_ok && feet_ok) {
            float bh = abs(feet_sy - head_sy);
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

// ─── Render ────────────────────────────────────────────────────────
void draw() {
    if (!esp_on.get()) return;

    g_mx.lock_shared();
    array<EspEntity@> snap = g_entities;
    g_mx.unlock_shared();

    for (uint i = 0; i < snap.length(); i++) {
        EspEntity@ e = snap[i];
        if (!e.alive) continue;

        color c = e.is_team   ? col_team.get()
                : e.visible   ? col_visible.get()
                :               col_enemy.get();
        // Fade alpha with distance
        float alpha_f = 1.0f - clamp(e.dist / max_dist.get(), 0.0f, 1.0f) * 0.5f;
        c.a = uint8(float(c.a) * alpha_f);

        // Box
        if (show_box.get() && e.box_w > 0) {
            float x = e.box_x, y = e.box_y, w = e.box_w, h = e.box_h;
            float cx = w * 0.25f, cy = h * 0.25f;
            // corners
            renderer.line(x,   y,   x+cx,y,   1.5f, c);
            renderer.line(x,   y,   x,   y+cy,1.5f, c);
            renderer.line(x+w, y,   x+w-cx,y, 1.5f, c);
            renderer.line(x+w, y,   x+w, y+cy,1.5f, c);
            renderer.line(x,   y+h, x+cx,y+h, 1.5f, c);
            renderer.line(x,   y+h, x,   y+h-cy,1.5f,c);
            renderer.line(x+w, y+h, x+w-cx,y+h,1.5f,c);
            renderer.line(x+w, y+h, x+w, y+h-cy,1.5f,c);
        }

        // Health bar (left of box, vertical)
        if (show_hp.get() && e.box_h > 0) {
            float filled = e.box_h * (float(e.hp) / 100.0f);
            float bx = e.box_x - 7.0f;
            renderer.rect_outlined(bx, e.box_y, 4.0f, e.box_h, 1.0f, color(0,0,0,180));
            int r = int(255.0f * (1.0f - float(e.hp)/100.0f));
            int g = int(255.0f * (float(e.hp)/100.0f));
            renderer.rect(bx+1.0f, e.box_y + (e.box_h - filled), 2.0f, filled, color(r,g,0,220));
        }

        // Skeleton
        if (show_skel.get()) {
            for (uint p = 0; p < BONE_PAIRS.length(); p++) {
                int a = BONE_PAIRS[p][0], b = BONE_PAIRS[p][1];
                if (!e.sv[a] || !e.sv[b]) continue;
                renderer.line(e.sx[a],e.sy[a],e.sx[b],e.sy[b],1.0f,c);
            }
        }

        // Name + distance
        if (show_name.get() && e.box_y > 14.0f) {
            string label = e.name + " [" + int(e.dist) + "m]";
            renderer.text_outlined(e.box_x + e.box_w*0.5f, e.box_y - 14.0f,
                                   label, fnt, c, color(0,0,0,160));
        }
    }
}

void on_unload() { proc = null; }
