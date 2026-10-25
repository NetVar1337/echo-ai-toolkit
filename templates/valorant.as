// Valorant ESP — UE4 fork with Vanguard (VGK)
// Requires: Dumper-7-VGK SDK (https://github.com/sinistercodes/Dumper-7-VGK)
// VGK runs at kernel level — Echo is fully external, no injection required.
// Do NOT use kernel drivers or memory-mapping hardware with this script.
//
// IMPORTANT: THE OFFSETS AND SIGNATURES BELOW ARE PLACEHOLDERS. They are
// illustrative values from one Dumper-7-VGK run and are NOT verified. They
// change every patch. Re-run Dumper-7-VGK and update them before use.

const uint32 UOBJECT_CLASS        = 0x10;
const uint32 UOBJECT_NAME_INDEX   = 0x18;
const uint32 ACTOR_ROOT_COMP      = 0x130;
const uint32 ACTOR_HEALTH         = 0x520;   // verify via Dumper-7-VGK
const uint32 PLAYERSTATE_TEAM_ID  = 0x3E8;
const uint32 PC_CAMERA_MANAGER    = 0x350;
const uint32 CAMMAN_VIEW_MATRIX   = 0x440;
const uint32 CAMMAN_LOCATION      = 0x11C;
const uint32 CAMMAN_ROTATION      = 0x128;
const uint32 CAMMAN_FOV           = 0x140;
const uint32 SCENE_COMP_LOCATION  = 0x11C;

const string GAME_EXE = "VALORANT-Win64-Shipping.exe";

f_view_cache g_view;
mutex@ g_mx = create_mutex();

bool main() {
    attach_data ad = process::attach(GAME_EXE);
    if (ad.pid == 0) {
        alert::show("VALORANT process not found");
        return false;
    }

    if (process::get_module_base(GAME_EXE) == 0) {
        alert::show("failed to read module base");
        process::detach();
        return false;
    }

    create_thread(15, @tick);
    on_render(@render);
    return true;
}

// GObjects is encrypted by VGK. This pattern targets the decryption stub.
// Replace with the sig from your Dumper-7-VGK run — it changes each patch.
uint64 get_gobjects() {
    uint64 base = process::get_module_base(GAME_EXE);
    if (base == 0) return 0;

    uint64 enc = process::find_signature(
        base,
        "48 8B 05 ? ? ? ? 48 85 C0 74 ? 48 8B 40 ? C3"
    );
    if (enc == 0) {
        alert::show("GObjects sig failed — run Dumper-7-VGK to get a new sig");
        return 0;
    }
    return process::read_uint64(process::get_relative_address(enc, 3, 7));
}

void tick() {
    // ~15 Hz — VGK is sensitive to read frequency
    uint64 base = process::get_module_base(GAME_EXE);
    if (base == 0) return;

    // Local player controller → camera manager → view cache
    uint64 local_pc = process::find_signature(
        base,
        "48 8B 0D ? ? ? ? E8 ? ? ? ? 48 89 43 ? 48 8B D8"
    );
    if (local_pc == 0) return;
    local_pc = process::read_uint64(process::get_relative_address(local_pc, 3, 7));
    if (local_pc == 0) return;

    uint64 cam_mgr = process::read_uint64(local_pc + PC_CAMERA_MANAGER);
    if (cam_mgr == 0) return;

    f_view_info info;
    info.location = vec3(process::read_float(cam_mgr + CAMMAN_LOCATION),
                         process::read_float(cam_mgr + CAMMAN_LOCATION + 4),
                         process::read_float(cam_mgr + CAMMAN_LOCATION + 8));
    info.rotation = vec3(process::read_float(cam_mgr + CAMMAN_ROTATION),
                         process::read_float(cam_mgr + CAMMAN_ROTATION + 4),
                         process::read_float(cam_mgr + CAMMAN_ROTATION + 8));
    info.fov = process::read_float(cam_mgr + CAMMAN_FOV);

    f_view_cache new_view = build_view_cache(info);

    g_mx.lock();
    g_view = new_view;
    g_mx.unlock();
}

void render() {
    g_mx.lock_shared();
    f_view_cache view = g_view;
    g_mx.unlock_shared();

    uint64 gobjects = get_gobjects();
    if (gobjects == 0) return;

    // TUObjectArray: data ptr at +0x0, count at +0x14
    uint32 obj_count = process::read_uint32(gobjects + 0x14);
    uint64 obj_data  = process::read_uint64(gobjects + 0x00);
    if (obj_data == 0 || obj_count == 0) return;

    render::update_font(fonts::TAHOMA, 10);

    uint32 drawn = 0;
    for (uint32 i = 0; i < obj_count && drawn < 64; i++) {
        // Each TUObjectArray entry: 24 bytes (ptr | serial | pad)
        uint64 obj = process::read_uint64(obj_data + uint64(i) * 24);
        if (obj == 0) continue;

        uint64 root_comp = process::read_uint64(obj + ACTOR_ROOT_COMP);
        if (root_comp == 0) continue;

        vec3 world_pos = vec3(process::read_float(root_comp + SCENE_COMP_LOCATION),
                              process::read_float(root_comp + SCENE_COMP_LOCATION + 4),
                              process::read_float(root_comp + SCENE_COMP_LOCATION + 8));
        if (world_pos.x == 0.0f && world_pos.y == 0.0f) continue;

        // unreal::w2s writes the screen position and returns false when the
        // point is off-screen or behind the camera
        vec2 screen;
        if (!unreal::w2s(world_pos, view, screen)) continue;

        float health = process::read_float(obj + ACTOR_HEALTH);
        if (health <= 0.0f || health > 150.0f) continue;

        float hp_pct = health / 150.0f;
        color col = color(255, int(hp_pct * 200.0f), 0, 210);

        float h = 65.0f, w = h * 0.35f;
        render::draw_box(int(screen.x - w * 0.5f), int(screen.y - h),
                         int(w), int(h),
                         col.r, col.g, col.b, col.a, box_style::OUTLINED, 0.0f);
        render::draw_box(int(screen.x - w * 0.5f) - 5, int(screen.y - h),
                         3, int(h * hp_pct),
                         col.r, col.g, col.b, col.a, box_style::FILLED, 0.0f);

        string hp_str = util::format_string("{:.0}", health);
        render::draw_text_outlined(int(screen.x), int(screen.y) + 2, hp_str,
                                   255, 255, 255, 180);

        drawn++;
    }
}

void on_unload() {
    process::detach();
}
