// Fortnite ESP — UE5 GWorld traversal, cornered box, 7-bone skeleton, health bar
//
// Engine:    Unreal Engine 5
// AC:        EasyAntiCheat (external read — no injection needed)
// Offsets:   from Dumper-7 output; update proc.scan_ida() patterns after each patch
//
// Post-patch workflow:  skills/offset-update-workflow.md
// Dumper-7 SDK guide:   skills/dumper7-sdk.md
// UE5 traversal ref:    templates/ue5-sdk.as
// mcp-gamehacking:      get_agent_briefing("fortnite-specialist")

// ── struct offsets (update from Dumper-7 each patch) ──────────────────────────
const uint32 OFF_PERSISTENT_LEVEL  = 0x38;    // UWorld::PersistentLevel
const uint32 OFF_ACTOR_ARRAY       = 0xA0;    // ULevel::AActors.Data
const uint32 OFF_ACTOR_COUNT       = 0xA8;    // ULevel::AActors.Num
const uint32 OFF_ROOT_COMPONENT    = 0x1A8;   // AActor::RootComponent
const uint32 OFF_COMP_TRANS        = 0x264;   // USceneComponent::ComponentToWorld.Translation
const uint32 OFF_MESH              = 0x3B8;   // APawn::Mesh (USkeletalMeshComponent*)
const uint32 OFF_BONE_ARRAY        = 0x5C0;   // USkeletalMeshComponent::CachedBoneSpaceTransforms
const uint32 OFF_BONE_COUNT        = 0x5C8;
const uint32 OFF_HEALTH_SET        = 0x5E8;   // AFortPawn::HealthSet (UFortHealthSet*)
const uint32 OFF_HP_CUR            = 0x1D0;   // UFortHealthSet::CurrentValue
const uint32 OFF_HP_MAX            = 0x1D8;
const uint32 OFF_SHIELD_CUR        = 0x1F0;   // UFortHealthSet::ShieldCurrentValue
const uint32 OFF_SHIELD_MAX        = 0x1F8;
const uint32 OFF_PLAYER_STATE      = 0x2D0;   // APawn::PlayerState
const uint32 OFF_TEAM_INDEX        = 0x280;   // AFortPlayerState::TeamIndex

// bone indices — standard Fortnite humanoid rig (verify with Dumper-7 output)
const uint32 BONE_HEAD     = 66;
const uint32 BONE_NECK     = 65;
const uint32 BONE_CHEST    = 6;
const uint32 BONE_PELVIS   = 0;
const uint32 BONE_L_UPPER  = 9;
const uint32 BONE_R_UPPER  = 38;
const uint32 BONE_L_HAND   = 15;
const uint32 BONE_R_HAND   = 44;
const uint32 BONE_L_KNEE   = 70;
const uint32 BONE_R_KNEE   = 74;
const uint32 BONE_L_FOOT   = 72;
const uint32 BONE_R_FOOT   = 76;

color_t COL_BOX    = color_t(220, 50,  50,  200);
color_t COL_BONE   = color_t(220, 50,  50,  160);
color_t COL_FILL   = color_t(0,   0,   0,   60);
color_t COL_HP     = color_t(60,  220, 80,  255);
color_t COL_SHIELD = color_t(80,  140, 255, 255);

uint64 g_world = 0;

// view matrix cache (updated each tick)
float[16] g_vm;

// ── entry ─────────────────────────────────────────────────────────────────────

void main() {
    proc.attach("FortniteClient-Win64-Shipping.exe");

    g_world = find_gworld();
    if (g_world == 0) {
        alert("GWorld scan failed — update pattern in find_gworld()");
        return;
    }

    create_thread(function() {
        while (proc.is_running()) {
            read_view_matrix();
            tick();
            sleep(1);
        }
    });
}

void on_unload() {
    proc.detach();
}

// ── per-tick actor walk ───────────────────────────────────────────────────────

void tick() {
    uint64 level = proc.read<uint64>(g_world + OFF_PERSISTENT_LEVEL);
    if (level == 0) return;

    uint64 actor_base  = proc.read<uint64>(level + OFF_ACTOR_ARRAY);
    uint32 actor_count = proc.read<uint32>(level + OFF_ACTOR_COUNT);
    if (actor_base == 0 || actor_count == 0 || actor_count > 4096) return;

    for (uint32 i = 0; i < actor_count; i++) {
        uint64 actor = proc.read<uint64>(actor_base + uint64(i) * 8);
        if (actor == 0) continue;
        draw_actor(actor);
    }
}

void draw_actor(uint64 actor) {
    // Quick-filter: must have mesh (APawn) and health set (AFortPawn)
    uint64 mesh       = proc.read<uint64>(actor + OFF_MESH);
    uint64 health_set = proc.read<uint64>(actor + OFF_HEALTH_SET);
    if (mesh == 0 || health_set == 0) return;

    float hp         = proc.read<float>(health_set + OFF_HP_CUR);
    float hp_max     = proc.read<float>(health_set + OFF_HP_MAX);
    float shield     = proc.read<float>(health_set + OFF_SHIELD_CUR);
    float shield_max = proc.read<float>(health_set + OFF_SHIELD_MAX);
    if (hp <= 0.0f || hp_max <= 0.0f) return;

    // Root world position
    uint64 root = proc.read<uint64>(actor + OFF_ROOT_COMPONENT);
    if (root == 0) return;
    float rx = proc.read<float>(root + OFF_COMP_TRANS);
    float ry = proc.read<float>(root + OFF_COMP_TRANS + 4);
    float rz = proc.read<float>(root + OFF_COMP_TRANS + 8);

    float foot_sx, foot_sy;
    if (!w2s(rx, ry, rz, foot_sx, foot_sy)) return;

    // Head position for box height
    float head_sx = foot_sx;
    float head_sy = foot_sy - 60.0f;
    float hx, hy, hz;
    if (get_bone(mesh, BONE_HEAD, hx, hy, hz)) {
        float tx, ty;
        if (w2s(hx, hy, hz, tx, ty)) { head_sx = tx; head_sy = ty; }
    }

    float box_h = foot_sy - head_sy;
    if (box_h < 8.0f) return;
    float box_w = box_h * 0.55f;
    float box_x = head_sx - box_w * 0.5f;
    float box_y = head_sy;
    float corner = box_w * 0.22f;

    draw_cornered_box(box_x, box_y, box_w, box_h, COL_BOX, corner);
    draw_skeleton(mesh);

    // HP bar — left side
    {
        float bx = box_x - 5.0f;
        renderer.draw_rect_filled(bx - 1.0f, box_y - 1.0f, 4.0f, box_h + 2.0f, COL_FILL);
        float fill_h = box_h * (hp / hp_max);
        renderer.draw_rect_filled(bx, box_y + (box_h - fill_h), 2.0f, fill_h, COL_HP);
    }

    // Shield bar — right side
    if (shield_max > 0.0f) {
        float bx = box_x + box_w + 3.0f;
        renderer.draw_rect_filled(bx - 1.0f, box_y - 1.0f, 4.0f, box_h + 2.0f, COL_FILL);
        float fill_h = box_h * (shield / shield_max);
        renderer.draw_rect_filled(bx, box_y + (box_h - fill_h), 2.0f, fill_h, COL_SHIELD);
    }
}

// ── skeleton ──────────────────────────────────────────────────────────────────

void draw_skeleton(uint64 mesh) {
    // 12 segments — full humanoid rig
    const uint pairs_n = 12;
    uint32[12] pa = {BONE_HEAD,    BONE_NECK,   BONE_CHEST,   BONE_L_UPPER,
                     BONE_R_UPPER, BONE_L_UPPER, BONE_R_UPPER, BONE_PELVIS,
                     BONE_PELVIS,  BONE_L_KNEE,  BONE_R_KNEE,  BONE_CHEST};
    uint32[12] pb = {BONE_NECK,    BONE_CHEST,  BONE_PELVIS,  BONE_L_HAND,
                     BONE_R_HAND,  BONE_L_KNEE, BONE_R_KNEE,  BONE_L_KNEE,
                     BONE_R_KNEE,  BONE_L_FOOT, BONE_R_FOOT,  BONE_R_UPPER};

    for (uint i = 0; i < pairs_n; i++) {
        float ax, ay, az, bx, by, bz;
        if (!get_bone(mesh, pa[i], ax, ay, az)) continue;
        if (!get_bone(mesh, pb[i], bx, by, bz)) continue;
        float sx, sy, ex, ey;
        if (!w2s(ax, ay, az, sx, sy)) continue;
        if (!w2s(bx, by, bz, ex, ey)) continue;
        renderer.draw_line(sx, sy, ex, ey, COL_BONE, 1.0f);
    }
}

bool get_bone(uint64 mesh, uint32 idx, float &out wx, float &out wy, float &out wz) {
    uint64 bone_base  = proc.read<uint64>(mesh + OFF_BONE_ARRAY);
    uint32 bone_count = proc.read<uint32>(mesh + OFF_BONE_COUNT);
    if (bone_base == 0 || idx >= bone_count) return false;
    // FTransform: [rotation quat 16 bytes][translation vec3 12 bytes][scale 12 bytes] = 48 bytes
    uint64 entry = bone_base + uint64(idx) * 48;
    wx = proc.read<float>(entry + 16);
    wy = proc.read<float>(entry + 20);
    wz = proc.read<float>(entry + 24);
    return true;
}

// ── rendering helpers ─────────────────────────────────────────────────────────

void draw_cornered_box(float x, float y, float w, float h, color_t col, float c) {
    float t = 1.5f;
    renderer.draw_line(x,     y,     x + c, y,     col, t);
    renderer.draw_line(x,     y,     x,     y + c, col, t);
    renderer.draw_line(x + w, y,     x+w-c, y,     col, t);
    renderer.draw_line(x + w, y,     x + w, y + c, col, t);
    renderer.draw_line(x,     y + h, x + c, y + h, col, t);
    renderer.draw_line(x,     y + h, x,     y+h-c, col, t);
    renderer.draw_line(x + w, y + h, x+w-c, y + h, col, t);
    renderer.draw_line(x + w, y + h, x + w, y+h-c, col, t);
}

// ── W2S ──────────────────────────────────────────────────────────────────────

bool w2s(float wx, float wy, float wz, float &out sx, float &out sy) {
    float cx = wx*g_vm[0]  + wy*g_vm[4]  + wz*g_vm[8]  + g_vm[12];
    float cy = wx*g_vm[1]  + wy*g_vm[5]  + wz*g_vm[9]  + g_vm[13];
    float cw = wx*g_vm[3]  + wy*g_vm[7]  + wz*g_vm[11] + g_vm[15];
    if (cw < 0.001f) return false;
    sx = (1.0f + cx/cw) * float(renderer.width())  * 0.5f;
    sy = (1.0f - cy/cw) * float(renderer.height()) * 0.5f;
    return true;
}

void read_view_matrix() {
    // shortcut: reads view matrix from APlayerCameraManager via GWorld chain;
    // update the two offsets (0x1F0, 0x300) from Dumper-7 if W2S is wrong
    uint64 vm_ptr = proc.read<uint64>(g_world + 0x1F0);
    if (vm_ptr == 0) return;
    uint64 vm_addr = vm_ptr + 0x300;
    for (uint i = 0; i < 16; i++)
        g_vm[i] = proc.read<float>(vm_addr + uint64(i) * 4);
}

// ── GWorld ────────────────────────────────────────────────────────────────────

uint64 find_gworld() {
    // LEA rcx,[rip+GWorld] in UEngine::Tick — stable across most patches
    // If this breaks after a patch run: mcp-gamehacking get_agent_briefing("fortnite-specialist")
    uint64 addr = proc.scan_ida(
        "48 8B 05 ? ? ? ? 48 85 C0 74 ? 48 8B 40 ? 48 85 C0 74",
        "FortniteClient-Win64-Shipping.exe"
    );
    if (addr == 0) return 0;
    return proc.resolve_rip(addr, 3, 7);
}
