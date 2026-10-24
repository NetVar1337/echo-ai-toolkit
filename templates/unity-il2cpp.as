// Unity IL2CPP ESP — Source 2 style, REA-discovered offsets
// Run REA inspect_unity_il2cpp on global-metadata.dat first to get class/method offsets

process@ proc = null;
uint64 camera_obj = 0;

bool main() {
    proc = process.attach("GameAssembly.dll");
    if (proc is null) { alert("GameAssembly.dll not found"); return false; }

    // --- Offsets (update via REA or cs.rin.ru dump) ---
    // These are placeholder patterns; replace with REA output or dumped offsets
    uint64 il2cpp_base = proc.get_module("GameAssembly.dll").base;

    // Il2CppObject layout: klass ptr at +0x0, fields follow
    // Camera.main → static field resolved via Il2CppClass
    uint64 camera_class = proc.scan_ida(
        "48 8B 05 ? ? ? ? 48 85 C0 74 ? 48 8B 40 ? 48 85 C0",
        "GameAssembly.dll"
    );
    if (camera_class == 0) { alert("Camera class pattern failed — update sig"); return false; }
    camera_obj = proc.resolve_rip(camera_class, 3, 7);

    create_thread(0, @tick);
    on_render(@render);
    return true;
}

void tick() {
    while (true) {
        sleep(50);
        // refresh entity list here if needed
    }
}

const uint32 OFFSET_TRANSFORM      = 0x10;   // Component._transform
const uint32 OFFSET_POSITION       = 0x90;   // Transform.m_LocalPosition (world)
const uint32 OFFSET_HEALTH_CUR     = 0x58;   // HealthComponent.current
const uint32 OFFSET_HEALTH_MAX     = 0x5C;   // HealthComponent.maximum
const uint32 OFFSET_NAME_PTR       = 0x60;   // Il2CppObject.name (pointer to string)
const uint32 IL2CPP_STRING_CHARS   = 0x14;   // Il2CppString.chars offset

void render() {
    if (proc is null || camera_obj == 0) return;

    // Read camera matrix — Unity stores it at Camera.projectionMatrix (0x1B0 typical)
    matrix4x4 vp = proc.read<matrix4x4>(camera_obj + 0x1B0);

    // Walk Il2CPP entity list — pattern depends on game
    uint64 obj_manager = proc.scan_ida(
        "48 8B 0D ? ? ? ? E8 ? ? ? ? 48 85 C0 74 ? 48 8B 10",
        "GameAssembly.dll"
    );
    if (obj_manager == 0) return;
    obj_manager = proc.resolve_rip(obj_manager, 3, 7);

    uint64 entity = proc.read<uint64>(obj_manager);
    uint32 drawn = 0;

    while (entity != 0 && drawn < 100) {
        uint64 transform = proc.read<uint64>(entity + OFFSET_TRANSFORM);
        if (transform == 0) { entity = proc.read<uint64>(entity + 0x8); continue; }

        vec3 world_pos = proc.read<vec3>(transform + OFFSET_POSITION);
        vec2 screen;
        if (!math.world_to_screen(vp, world_pos, screen)) {
            entity = proc.read<uint64>(entity + 0x8);
            continue;
        }

        float cur_hp = proc.read<float>(entity + OFFSET_HEALTH_CUR);
        float max_hp = proc.read<float>(entity + OFFSET_HEALTH_MAX);
        float hp_pct = max_hp > 0.0f ? cur_hp / max_hp : 0.0f;

        color box_col = color(255, uint8(hp_pct * 255.0f), 0, 220);
        float h = 60.0f, w = h * 0.4f;
        draw.rect(screen.x - w * 0.5f, screen.y - h, w, h, box_col, 1.5f);

        color bar_col = color(uint8((1.0f - hp_pct) * 255.0f), uint8(hp_pct * 255.0f), 0, 220);
        draw.rect_filled(screen.x + w * 0.5f + 2.0f, screen.y - h,
                         4.0f, h * hp_pct, bar_col);

        // Name label from Il2CppString
        uint64 name_ptr = proc.read<uint64>(entity + OFFSET_NAME_PTR);
        if (name_ptr != 0) {
            string name = proc.read_wstring(name_ptr + IL2CPP_STRING_CHARS, 24);
            draw.text(screen.x, screen.y + 2.0f, name, color(255, 255, 255, 200), 11.0f);
        }

        drawn++;
        entity = proc.read<uint64>(entity + 0x8);
    }
}

void on_unload() {
    proc = null;
}
