// Valorant ESP — UE4 fork with Vanguard (VGK)
// Requires: Dumper-7-VGK SDK (https://github.com/sinistercodes/Dumper-7-VGK)
// VGK runs at kernel level — Echo is fully external, no injection required.
// Do NOT use kernel drivers or memory-mapping hardware with this script.

process@ proc = null;

// --- Offsets from Dumper-7-VGK output ---
// Run Dumper-7-VGK, grab CppSDK output, update constants below after each patch.

const uint32 UOBJECT_CLASS        = 0x10;
const uint32 UOBJECT_NAME_INDEX   = 0x18;
const uint32 ACTOR_ROOT_COMP      = 0x130;
const uint32 ACTOR_HEALTH         = 0x520;   // verify via Dumper-7-VGK
const uint32 PLAYERSTATE_TEAM_ID  = 0x3E8;
const uint32 PC_CAMERA_MANAGER    = 0x350;
const uint32 CAMMAN_VIEW_MATRIX   = 0x440;
const uint32 SCENE_COMP_LOCATION  = 0x11C;

matrix4x4 vp_matrix;

bool main() {
    proc = process.attach("VALORANT-Win64-Shipping.exe");
    if (proc is null) { alert("VALORANT process not found"); return false; }

    if (proc.get_module("VALORANT-Win64-Shipping.exe").base == 0) {
        alert("failed to read module base");
        return false;
    }

    create_thread(0, @tick);
    on_render(@render);
    return true;
}

// GObjects is encrypted by VGK. This pattern targets the decryption stub.
// Replace with the sig from your Dumper-7-VGK run — it changes each patch.
uint64 get_gobjects() {
    uint64 enc = proc.scan_ida(
        "48 8B 05 ? ? ? ? 48 85 C0 74 ? 48 8B 40 ? C3",
        "VALORANT-Win64-Shipping.exe"
    );
    if (enc == 0) { alert("GObjects sig failed — run Dumper-7-VGK to get new sig"); return 0; }
    return proc.read<uint64>(proc.resolve_rip(enc, 3, 7));
}

void tick() {
    while (true) {
        sleep(66);   // ~15 Hz — VGK is sensitive to read frequency

        // Local player controller → camera manager → view-projection matrix
        uint64 local_pc = proc.scan_ida(
            "48 8B 0D ? ? ? ? E8 ? ? ? ? 48 89 43 ? 48 8B D8",
            "VALORANT-Win64-Shipping.exe"
        );
        if (local_pc == 0) continue;
        local_pc = proc.resolve_rip(local_pc, 3, 7);
        local_pc = proc.read<uint64>(local_pc);
        if (local_pc == 0) continue;

        uint64 cam_mgr = proc.read<uint64>(local_pc + PC_CAMERA_MANAGER);
        if (cam_mgr == 0) continue;

        vp_matrix = proc.read<matrix4x4>(cam_mgr + CAMMAN_VIEW_MATRIX);
    }
}

void render() {
    uint64 gobjects = get_gobjects();
    if (gobjects == 0) return;

    // TUObjectArray: data ptr at +0x0, count at +0x14
    uint32 obj_count = proc.read<uint32>(gobjects + 0x14);
    uint64 obj_data  = proc.read<uint64>(gobjects + 0x00);
    if (obj_data == 0 || obj_count == 0) return;

    uint32 drawn = 0;
    for (uint32 i = 0; i < obj_count && drawn < 64; i++) {
        // Each TUObjectArray entry: 24 bytes (ptr | serial | pad)
        uint64 obj = proc.read<uint64>(obj_data + uint64(i) * 24);
        if (obj == 0) continue;

        uint64 root_comp = proc.read<uint64>(obj + ACTOR_ROOT_COMP);
        if (root_comp == 0) continue;

        vec3 world_pos = proc.read<vec3>(root_comp + SCENE_COMP_LOCATION);
        if (world_pos.x == 0.0f && world_pos.y == 0.0f) continue;

        vec2 screen;
        if (!math.world_to_screen(vp_matrix, world_pos, screen)) continue;

        float health = proc.read<float>(obj + ACTOR_HEALTH);
        if (health <= 0.0f || health > 150.0f) continue;

        float hp_pct = health / 150.0f;
        color col = color(255, uint8(hp_pct * 200.0f), 0, 210);

        float h = 65.0f, w = h * 0.35f;
        draw.rect(screen.x - w * 0.5f, screen.y - h, w, h, col, 1.5f);
        draw.rect_filled(screen.x - w * 0.5f - 5.0f, screen.y - h,
                         3.0f, h * hp_pct, col);

        string hp_str = fmt("{:.0f}", health);
        draw.text(screen.x, screen.y + 2.0f, hp_str, color(255, 255, 255, 180), 10.0f);

        drawn++;
    }
}

void on_unload() {
    proc = null;
}
