// Unity IL2CPP ESP — REA-discovered offsets
// Run REA inspect_unity_il2cpp on global-metadata.dat first to get class/method
// offsets.
//
// IMPORTANT: THE OFFSETS AND SIGNATURES BELOW ARE PLACEHOLDERS. They are
// illustrative values, NOT verified against any specific game build. Re-derive
// them per game and per patch before using this template.

const uint32 OFFSET_TRANSFORM      = 0x10;   // Component._transform
const uint32 OFFSET_POSITION       = 0x90;   // Transform.m_LocalPosition (world)
const uint32 OFFSET_HEALTH_CUR     = 0x58;   // HealthComponent.current
const uint32 OFFSET_HEALTH_MAX     = 0x5C;   // HealthComponent.maximum
const uint32 OFFSET_NAME_PTR       = 0x60;   // Il2CppObject.name (pointer to string)
const uint32 IL2CPP_STRING_CHARS   = 0x14;   // Il2CppString.chars offset

uint64 g_camera_obj = 0;
uint64 g_obj_manager = 0;

bool main() {
    attach_data ad = process::attach("GameAssembly.dll");
    if (ad.pid == 0) {
        alert::show("GameAssembly.dll not found");
        return false;
    }

    uint64 il2cpp_base = process::get_module_base("GameAssembly.dll");
    if (il2cpp_base == 0) {
        alert::show("GameAssembly.dll base not found");
        process::detach();
        return false;
    }

    // Camera class pointer — placeholder pattern; replace with REA output
    uint64 camera_class = process::find_signature(
        il2cpp_base,
        "48 8B 05 ? ? ? ? 48 85 C0 74 ? 48 8B 40 ? 48 85 C0"
    );
    if (camera_class == 0) {
        alert::show("Camera class pattern failed — update the signature");
        process::detach();
        return false;
    }
    g_camera_obj = process::get_relative_address(camera_class, 3, 7);

    // Object manager — placeholder pattern; replace with REA output
    uint64 mgr_sig = process::find_signature(
        il2cpp_base,
        "48 8B 0D ? ? ? ? E8 ? ? ? ? 48 85 C0 74 ? 48 8B 10"
    );
    if (mgr_sig != 0) {
        g_obj_manager = process::get_relative_address(mgr_sig, 3, 7);
    }

    create_thread(16, @tick);
    on_render(@render);
    return true;
}

// Read a 4x4 float matrix (16 floats) from the target process (user code)
matrix4x4 read_matrix16(uint64 addr) {
    matrix4x4 m;
    for (int c = 0; c < 4; c++)
        for (int r = 0; r < 4; r++)
            m[c][r] = process::read_float(addr + uint64(c * 4 + r) * 4);
    return m;
}

void tick() {
    // Refresh the object manager occasionally — the pointer can be rebuilt
    // by the game at any time
    if (g_obj_manager != 0) return;

    uint64 il2cpp_base = process::get_module_base("GameAssembly.dll");
    if (il2cpp_base == 0) return;

    uint64 mgr_sig = process::find_signature(
        il2cpp_base,
        "48 8B 0D ? ? ? ? E8 ? ? ? ? 48 85 C0 74 ? 48 8B 10"
    );
    if (mgr_sig != 0) g_obj_manager = process::get_relative_address(mgr_sig, 3, 7);
}

void render() {
    if (g_camera_obj == 0 || g_obj_manager == 0) return;

    // Read camera matrix — Camera.projectionMatrix (0x1B0 typical, placeholder)
    matrix4x4 vp = read_matrix16(g_camera_obj + 0x1B0);

    uint64 entity = process::read_uint64(g_obj_manager);
    uint32 drawn = 0;

    while (entity != 0 && drawn < 100) {
        uint64 transform = process::read_uint64(entity + OFFSET_TRANSFORM);
        if (transform == 0) {
            entity = process::read_uint64(entity + 0x8);
            continue;
        }

        // Read the transform position (three consecutive floats)
        vec3 world_pos = vec3(process::read_float(transform + OFFSET_POSITION),
                              process::read_float(transform + OFFSET_POSITION + 4),
                              process::read_float(transform + OFFSET_POSITION + 8));

        // unity::w2s writes the screen position and returns false when the
        // point is off-screen or behind the camera
        vec2 screen;
        if (!unity::w2s(world_pos, vp, screen)) {
            entity = process::read_uint64(entity + 0x8);
            continue;
        }

        float cur_hp = process::read_float(entity + OFFSET_HEALTH_CUR);
        float max_hp = process::read_float(entity + OFFSET_HEALTH_MAX);
        float hp_pct = max_hp > 0.0f ? cur_hp / max_hp : 0.0f;

        color box_col = color(255, int(hp_pct * 255.0f), 0, 220);
        float h = 60.0f, w = h * 0.4f;
        render::draw_box(int(screen.x - w * 0.5f), int(screen.y - h),
                         int(w), int(h),
                         box_col.r, box_col.g, box_col.b, box_col.a,
                         box_style::OUTLINED, 0.0f);

        color bar_col = color(int((1.0f - hp_pct) * 255.0f), int(hp_pct * 255.0f), 0, 220);
        render::draw_box(int(screen.x + w * 0.5f) + 2, int(screen.y - h),
                         4, int(h * hp_pct),
                         bar_col.r, bar_col.g, bar_col.b, bar_col.a,
                         box_style::FILLED, 0.0f);

        // Name label from Il2CppString — the chars are UTF-16LE
        uint64 name_ptr = process::read_uint64(entity + OFFSET_NAME_PTR);
        if (name_ptr != 0) {
            array<uint8>@ chars = process::read_bytes(name_ptr + IL2CPP_STRING_CHARS, 48);
            if (chars !is null) {
                array<uint8> buf(chars.length());
                for (uint i = 0; i < chars.length(); i++) buf[i] = chars[i];
                string name = util::wide_to_string(buf, true);
                if (name.length() > 0)
                    render::draw_text_outlined(int(screen.x), int(screen.y) + 2, name,
                                               255, 255, 255, 200);
            }
        }

        drawn++;
        entity = process::read_uint64(entity + 0x8);
    }
}

void on_unload() {
    process::detach();
}
