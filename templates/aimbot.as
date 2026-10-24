// Full CS2 aimbot: target selection, smoothing, velocity prediction, triggerbot
// Verify all offsets against current cs2-dumper output

// ─── Offsets ───────────────────────────────────────────────────────
const uint64 OFF_HP         = 0x344;
const uint64 OFF_LIFE       = 0x338;
const uint64 OFF_TEAM       = 0x3CB;
const uint64 OFF_ORIGIN     = 0x1294;
const uint64 OFF_VELOCITY   = 0x1254;
const uint64 OFF_PUNCH_P    = 0x1450; // m_aimPunchAngle pitch
const uint64 OFF_PUNCH_Y    = 0x1454; // m_aimPunchAngle yaw
const uint64 OFF_VIEW_P     = 0x1658; // view pitch (verify)
const uint64 OFF_VIEW_Y     = 0x165C; // view yaw  (verify)
const uint64 OFF_SKELETON   = 0x168;
const uint64 OFF_BONE_ARR   = 0x80;

// Bone indices
const int BONE_HEAD  = 9;
const int BONE_NECK  = 8;
const int BONE_CHEST = 7;
const float PI = 3.14159265f;

// ─── State ─────────────────────────────────────────────────────────
process@ proc;
uint64   entity_list  = 0;
uint64   local_player = 0; // ptr to local pawn ptr

tab@       t;
checkbox@  aim_on;
slider@    aim_fov;
slider@    aim_smooth;
combobox@  aim_bone;
combobox@  aim_mode;     // 0=hold RMB, 1=toggle RMB
checkbox@  aim_recoil;
checkbox@  trig_on;
slider@    trig_fov;

bool aim_active  = false;
bool last_rmb    = false;
bool aim_toggled = false;

// ─── Entry point ───────────────────────────────────────────────────
bool main() {
    t          = menu.add_tab("Aimbot");
    auto cat   = t.add_category("Settings");
    aim_on     = cat.add_checkbox("Enable",          false, "aim.on");
    aim_fov    = cat.add_slider("FOV (deg)",         0.5f, 45.0f, 8.0f,  "aim.fov");
    aim_smooth = cat.add_slider("Smoothing",         1.0f, 30.0f, 5.0f,  "aim.smooth");
    aim_bone   = cat.add_combobox("Bone",
                     array<string> = {"Head","Neck","Chest"}, 0, "aim.bone");
    aim_mode   = cat.add_combobox("Mode",
                     array<string> = {"Hold RMB","Toggle RMB"}, 0, "aim.mode");
    aim_recoil = cat.add_checkbox("Recoil comp", true,  "aim.recoil");
    trig_on    = cat.add_checkbox("Triggerbot",  false, "aim.trig");
    trig_fov   = cat.add_slider("Trigger FOV",  0.1f, 5.0f, 0.5f, "aim.trigfov");

    proc = process.attach("cs2.exe");
    if (proc is null) { alert("cs2.exe not found"); return false; }

    create_thread(0,   @do_scan);
    create_thread(128, @aim_tick);
    return true;
}

void do_scan() {
    uint64 sig = proc.scan("48 8B 0D ?? ?? ?? ?? 48 89 5C 24", "client.dll");
    if (sig == 0) { alert("entity list sig failed"); return; }
    uint64 ent_sys = proc.resolve_rip(sig, 3, 7);
    uint64 raw     = proc.read<uint64>(ent_sys);
    entity_list    = proc.read<uint64>(raw + 0x10);

    sig = proc.scan("48 8B 0D ?? ?? ?? ?? 48 85 C9 74 ?? 8B 01", "client.dll");
    if (sig != 0) local_player = proc.resolve_rip(sig, 3, 7);
    alert("Aimbot ready");
}

// ─── Math helpers ──────────────────────────────────────────────────
float norm_angle(float a) {
    while (a >  180.0f) a -= 360.0f;
    while (a < -180.0f) a += 360.0f;
    return a;
}

void calc_angle(float lx, float ly, float lz,
                float tx, float ty, float tz,
                float& pitch, float& yaw) {
    float dx = tx - lx, dy = ty - ly, dz = tz - lz;
    float d2 = sqrt(dx*dx + dy*dy);
    pitch = -(float(atan2(dz, d2)) * 180.0f / PI);
    yaw   =   float(atan2(dy, dx)) * 180.0f / PI;
}

float fov_between(float vp, float vy, float tp, float ty) {
    float dp = norm_angle(tp - vp);
    float dy = norm_angle(ty - vy);
    return sqrt(dp*dp + dy*dy);
}

// ─── Entity helpers ────────────────────────────────────────────────
uint64 get_entity(int idx) {
    uint64 chunk = proc.read<uint64>(entity_list + uint64(idx >> 9) * 8);
    if (chunk == 0) return 0;
    return proc.read<uint64>(chunk + uint64(idx & 0x1FF) * 120);
}

struct BonePos { float x, y, z; }

BonePos get_bone(uint64 ent, int bone) {
    uint64 skel = proc.read<uint64>(ent + OFF_SKELETON);
    uint64 arr  = proc.read<uint64>(skel + OFF_BONE_ARR);
    uint64 a    = arr + uint64(bone) * 0x20 + 0x10;
    BonePos b;
    b.x = proc.read<float>(a);
    b.y = proc.read<float>(a + 4);
    b.z = proc.read<float>(a + 8);
    return b;
}

// ─── Aimbot tick ───────────────────────────────────────────────────
void aim_tick() {
    if (!aim_on.get() || entity_list == 0 || local_player == 0) return;

    // Keybind handling
    bool rmb = keyboard.get_key_state(0x02) != 0; // VK_RBUTTON
    int  mode = aim_mode.get();
    if (mode == 0) {
        aim_active = rmb;
    } else {
        if (rmb && !last_rmb) aim_toggled = !aim_toggled;
        aim_active = aim_toggled;
    }
    last_rmb = rmb;
    if (!aim_active) return;

    // Local player
    uint64 lp = proc.read<uint64>(local_player);
    if (lp == 0) return;
    int lp_team  = proc.read<int>(lp + OFF_TEAM);
    float lp_ox  = proc.read<float>(lp + OFF_ORIGIN);
    float lp_oy  = proc.read<float>(lp + OFF_ORIGIN + 4);
    float lp_oz  = proc.read<float>(lp + OFF_ORIGIN + 8);
    float view_p = proc.read<float>(lp + OFF_VIEW_P);
    float view_y = proc.read<float>(lp + OFF_VIEW_Y);

    // Select bone
    int bones[3] = {BONE_HEAD, BONE_NECK, BONE_CHEST};
    int target_bone = bones[aim_bone.get()];

    // Find best target
    float fov_limit  = aim_fov.get();
    float best_fov   = fov_limit;
    int   best_idx   = -1;

    for (int i = 1; i < 64; i++) {
        uint64 ent = get_entity(i);
        if (ent == 0) continue;
        if (proc.read<uint8>(ent + OFF_LIFE) != 0) continue;
        if (proc.read<int>(ent + OFF_HP) <= 0)     continue;
        if (proc.read<int>(ent + OFF_TEAM) == lp_team) continue;

        float ox = proc.read<float>(ent + OFF_ORIGIN);
        float oy = proc.read<float>(ent + OFF_ORIGIN + 4);
        float oz = proc.read<float>(ent + OFF_ORIGIN + 8);
        float dx = lp_ox-ox, dy = lp_oy-oy, dz = lp_oz-oz;
        float dist = sqrt(dx*dx + dy*dy + dz*dz);
        if (dist > 15000.0f) continue; // ~380m hard cap

        BonePos bp = get_bone(ent, target_bone);
        float tp, ty;
        calc_angle(lp_ox, lp_oy, lp_oz, bp.x, bp.y, bp.z, tp, ty);

        float fov = fov_between(view_p, view_y, tp, ty);
        if (fov < best_fov) { best_fov = fov; best_idx = i; }
    }

    if (best_idx < 0) return;

    // Get target bone with velocity prediction
    uint64 best_ent = get_entity(best_idx);
    BonePos bp = get_bone(best_ent, target_bone);

    float vel_x = proc.read<float>(best_ent + OFF_VELOCITY);
    float vel_y = proc.read<float>(best_ent + OFF_VELOCITY + 4);
    float vel_z = proc.read<float>(best_ent + OFF_VELOCITY + 8);

    float dx = lp_ox - bp.x, dy = lp_oy - bp.y, dz = lp_oz - bp.z;
    float dist = sqrt(dx*dx + dy*dy + dz*dz);
    float travel = dist / 1500.0f; // approximate bullet speed in Source units/s

    float pred_x = bp.x + vel_x * travel;
    float pred_y = bp.y + vel_y * travel;
    float pred_z = bp.z + vel_z * travel;

    // Target angle
    float tgt_p, tgt_y;
    calc_angle(lp_ox, lp_oy, lp_oz, pred_x, pred_y, pred_z, tgt_p, tgt_y);

    // Recoil compensation
    float dp = norm_angle(tgt_p - view_p);
    float dy_a = norm_angle(tgt_y - view_y);
    if (aim_recoil.get()) {
        dp  -= proc.read<float>(lp + OFF_PUNCH_P) * 2.0f;
        dy_a -= proc.read<float>(lp + OFF_PUNCH_Y) * 2.0f;
    }

    // Angle → mouse pixels (CS2 default: sensitivity 1.0, yaw 0.022)
    float sens = 0.022f; // adjust if user sens differs
    float mx = dy_a  / sens;
    float my = dp    / sens;

    // Smooth
    float factor = aim_smooth.get();
    mx /= factor;
    my /= factor;

    // Jitter + cap
    mx += random.float(-0.25f, 0.25f);
    my += random.float(-0.25f, 0.25f);
    mx = clamp(mx, -20.0f, 20.0f);
    my = clamp(my, -20.0f, 20.0f);

    mouse.move(int(mx + 0.5f), int(my + 0.5f));

    // Triggerbot
    if (trig_on.get() && best_fov < trig_fov.get()) {
        if (random.int(0, 4) != 0) // shortcut: 80% fire chance per tick; add delay for realism
            mouse.key_tap(0x01); // VK_LBUTTON
    }
}

void on_unload() { proc = null; }
