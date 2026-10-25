// Full CS2 aimbot: target selection, smoothing, velocity prediction, triggerbot
//
// OFFSETS AND SIGNATURES BELOW ARE PLACEHOLDERS. They are illustrative values
// from one community dump and are NOT verified. Re-derive them from a current
// cs2-dumper run after every game update before using this template.
//
// The mouse is driven through input::mouse_move(), which takes ABSOLUTE
// screen coordinates. To apply a relative delta we read the current cursor
// position with input::mouse_pos() and add the delta to it.

// ─── Offsets (placeholders — re-verify per patch) ────────────────────────────
const uint64 OFF_HP         = 0x344;
const uint64 OFF_LIFE       = 0x338;
const uint64 OFF_TEAM       = 0x3CB;
const uint64 OFF_ORIGIN     = 0x1294;
const uint64 OFF_VELOCITY   = 0x1254;
const uint64 OFF_PUNCH_P    = 0x1450; // m_aimPunchAngle pitch
const uint64 OFF_PUNCH_Y    = 0x1454; // m_aimPunchAngle yaw
const uint64 OFF_VIEW_P     = 0x1658; // view pitch
const uint64 OFF_VIEW_Y     = 0x165C; // view yaw
const uint64 OFF_SKELETON   = 0x168;
const uint64 OFF_BONE_ARR   = 0x80;

// Bone indices
const int BONE_HEAD  = 9;
const int BONE_NECK  = 8;
const int BONE_CHEST = 7;

// Source units per second travelled by a bullet (approximate, placeholder)
const float BULLET_SPEED = 1500.0f;

// ─── State ───────────────────────────────────────────────────────────────────
uint64 g_entity_list  = 0;
uint64 g_local_player = 0; // ptr to local pawn ptr

checkbox g_aim_on;
slider   g_aim_fov;      // degrees
slider   g_aim_smooth;   // 1..30
combobox g_aim_bone;
combobox g_aim_mode;     // 0 = hold RMB, 1 = toggle RMB
checkbox g_aim_recoil;
checkbox g_trig_on;
slider   g_trig_fov;     // hundredths of a degree

bool g_aim_active  = false;
bool g_last_rmb    = false;
bool g_aim_toggled = false;

// ─── Entry point ─────────────────────────────────────────────────────────────
bool main() {
    ui::config_path("echo_aimbot");

    ui::add_tab("Aimbot");
    ui::add_category("Settings");
    g_aim_on     = ui::add_checkbox("Enable", false, "aim.on");
    g_aim_fov    = ui::add_slider("FOV (deg)", 8, 1, 45, 1, "deg", "aim.fov");
    g_aim_smooth = ui::add_slider("Smoothing", 5, 1, 30, 1, "", "aim.smooth");
    g_aim_bone   = ui::add_combobox("Bone", {"Head", "Neck", "Chest"}, 0, "aim.bone");
    g_aim_mode   = ui::add_combobox("Mode", {"Hold RMB", "Toggle RMB"}, 0, "aim.mode");
    g_aim_recoil = ui::add_checkbox("Recoil comp", true, "aim.recoil");
    g_trig_on    = ui::add_checkbox("Triggerbot", false, "aim.trig");
    g_trig_fov   = ui::add_slider("Trigger FOV", 30, 5, 100, 5, "cdeg", "aim.trigfov");

    attach_data ad = process::attach("cs2.exe");
    if (ad.pid == 0) {
        alert::show("cs2.exe not found");
        return false;
    }

    create_thread(0,   @do_scan);
    create_thread(128, @aim_tick);
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

    alert::show("Aimbot ready");
}

// ─── User helpers (not Echo API) ─────────────────────────────────────────────
float clampf(float v, float lo, float hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

// ─── Entity helpers (user code — chunk layout is game specific) ──────────────
uint64 get_entity(int idx) {
    uint64 chunk = process::read_uint64(g_entity_list + uint64(idx >> 9) * 8);
    if (chunk == 0) return 0;
    return process::read_uint64(chunk + uint64(idx & 0x1FF) * 120);
}

vec3 get_bone(uint64 ent, int bone) {
    uint64 skel = process::read_uint64(ent + OFF_SKELETON);
    uint64 arr  = process::read_uint64(skel + OFF_BONE_ARR);
    uint64 a    = arr + uint64(bone) * 0x20 + 0x10;
    return vec3(process::read_float(a),
                process::read_float(a + 4),
                process::read_float(a + 8));
}

// ─── Aimbot tick ─────────────────────────────────────────────────────────────
void aim_tick() {
    if (!ui::get(g_aim_on) || g_entity_list == 0 || g_local_player == 0) return;

    // Keybind handling — input::key_active() is true while the key is held
    bool rmb = input::key_active(0x02); // VK_RBUTTON
    uint64 mode = ui::get(g_aim_mode);
    if (mode == 0) {
        g_aim_active = rmb;
    } else {
        if (rmb && !g_last_rmb) g_aim_toggled = !g_aim_toggled;
        g_aim_active = g_aim_toggled;
    }
    g_last_rmb = rmb;
    if (!g_aim_active) return;

    // Local player
    uint64 lp = process::read_uint64(g_local_player);
    if (lp == 0) return;
    int   lp_team = process::read_int32(lp + OFF_TEAM);
    vec3  lp_pos  = vec3(process::read_float(lp + OFF_ORIGIN),
                         process::read_float(lp + OFF_ORIGIN + 4),
                         process::read_float(lp + OFF_ORIGIN + 8));
    vec2  view    = vec2(process::read_float(lp + OFF_VIEW_P),
                         process::read_float(lp + OFF_VIEW_Y));

    // Select bone
    int bones[3] = {BONE_HEAD, BONE_NECK, BONE_CHEST};
    int target_bone = bones[int(ui::get(g_aim_bone))];

    // Find best target
    double fov_limit = double(ui::get(g_aim_fov));
    double best_fov  = fov_limit;
    int    best_idx  = -1;

    for (int i = 1; i < 64; i++) {
        uint64 ent = get_entity(i);
        if (ent == 0) continue;
        if (process::read_uint8(ent + OFF_LIFE) != 0) continue;
        if (process::read_int32(ent + OFF_HP) <= 0) continue;
        if (process::read_int32(ent + OFF_TEAM) == lp_team) continue;

        vec3  origin = vec3(process::read_float(ent + OFF_ORIGIN),
                            process::read_float(ent + OFF_ORIGIN + 4),
                            process::read_float(ent + OFF_ORIGIN + 8));
        float dist = origin.distance(lp_pos);
        if (dist > 15000.0f) continue; // ~380m hard cap

        vec2 target = math::calculate_angle(lp_pos, get_bone(ent, target_bone));
        double fov  = math::calculate_fov(view, target);
        if (fov < best_fov) {
            best_fov = fov;
            best_idx = i;
        }
    }

    if (best_idx < 0) return;

    // Get target bone with velocity prediction
    uint64 best_ent = get_entity(best_idx);
    vec3  bp        = get_bone(best_ent, target_bone);
    vec3  vel       = vec3(process::read_float(best_ent + OFF_VELOCITY),
                           process::read_float(best_ent + OFF_VELOCITY + 4),
                           process::read_float(best_ent + OFF_VELOCITY + 8));

    float dist   = bp.distance(lp_pos);
    float travel = dist / BULLET_SPEED; // approximate bullet speed in Source units/s
    vec3  pred   = bp.add(vel.multiply(travel));

    // Target angle
    vec2 tgt = math::calculate_angle(lp_pos, pred);

    // Recoil compensation
    vec2 delta = vec2(float(math::angle_diff(tgt.x, view.x)),
                       float(math::angle_diff(tgt.y, view.y)));
    if (ui::get(g_aim_recoil)) {
        delta.x -= process::read_float(lp + OFF_PUNCH_P) * 2.0f;
        delta.y -= process::read_float(lp + OFF_PUNCH_Y) * 2.0f;
    }

    // Smooth — math::smooth_angles() returns the smoothed angle pair
    double smoothing = double(ui::get(g_aim_smooth)) / 30.0;
    vec2 smoothed = math::smooth_angles(view, vec2(view.x + delta.x, view.y + delta.y),
                                        angle_range::R_180, smoothing, 1.0, 45.0);
    vec2 step = vec2(smoothed.x - view.x, smoothed.y - view.y);

    // Angle step → mouse pixels (CS2 default: sensitivity 1.0, yaw 0.022)
    float sens = 0.022f; // adjust if user sens differs
    float mx = step.y / sens + util::random_float(-0.25f, 0.25f);
    float my = step.x / sens + util::random_float(-0.25f, 0.25f);
    mx = clampf(mx, -20.0f, 20.0f);
    my = clampf(my, -20.0f, 20.0f);

    // input::mouse_move() is absolute: read the cursor, add the delta, move back
    int cx, cy;
    input::mouse_pos(cx, cy);
    input::mouse_move(cx + int(mx), cy + int(my));

    // Triggerbot
    if (ui::get(g_trig_on) && best_fov * 100.0 < double(ui::get(g_trig_fov))) {
        // shortcut: 80% fire chance per tick; add a delay for realism
        if (util::random_int(0, 4) != 0)
            input::mouse_click();
    }
}

void on_unload() {
    process::detach();
}
