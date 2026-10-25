// Fortnite ESP — UE5 GWorld traversal, cornered box, 7-bone skeleton, health bar
//
// Engine:    Unreal Engine 5
// AC:        EasyAntiCheat (external read — no injection needed)
//
// IMPORTANT: THE OFFSETS AND SIGNATURES BELOW ARE PLACEHOLDERS. They are
// illustrative values copied from one Dumper-7 output and are NOT verified.
// They break with every patch. Re-run Dumper-7 and update them before use.
//
// Post-patch workflow:  skills/offset-update-workflow.md
// Dumper-7 SDK guide:   skills/dumper7-sdk.md
// UE5 traversal ref:    templates/ue5-sdk.as
// mcp-gamehacking:      get_agent_briefing("fortnite-specialist")

// ── struct offsets (placeholders — update from Dumper-7 each patch) ──────────
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

// Camera chain offsets (placeholders — update from Dumper-7 each patch)
const uint32 OFF_CAM_MANAGER       = 0x1F0;   // UWorld -> PlayerCameraManager
const uint32 OFF_CAM_LOC           = 0x300;   // CameraLocation
const uint32 OFF_CAM_ROT           = 0x30C;   // CameraRotation (pitch, yaw, roll)
const uint32 OFF_CAM_FOV           = 0x318;   // FOVAngle

// bone indices — standard Fortnite humanoid rig (placeholder, verify with Dumper-7)
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

// Colours are 4 separate ints: r, g, b, a
const int COL_BOX_R = 220, COL_BOX_G = 50,  COL_BOX_B = 50,  COL_BOX_A = 200;
const int COL_BONE_R = 220, COL_BONE_G = 50, COL_BONE_B = 50, COL_BONE_A = 160;
const int COL_FILL_R = 0,   COL_FILL_G = 0,   COL_FILL_B = 0,   COL_FILL_A = 60;
const int COL_HP_R   = 60,  COL_HP_G   = 220, COL_HP_B   = 80,  COL_HP_A   = 255;
const int COL_SHI_R  = 80,  COL_SHI_G  = 140, COL_SHI_B  = 255, COL_SHI_A  = 255;

uint64 g_world = 0;
f_view_cache g_view;

// ── shared state (written by tick, read by render) ──────────────────────────
class ActorInfo {
    uint64 mesh;
    vec3   root_pos;
    float  hp, hp_max;
    float  shield, shield_max;
}
array<ActorInfo@> g_actors;
mutex@ g_mx = create_mutex();

// ── entry ────────────────────────────────────────────────────────────────────

bool main() {
    attach_data ad = process::attach("FortniteClient-Win64-Shipping.exe");
    if (ad.pid == 0) {
        alert::show("FortniteClient-Win64-Shipping.exe not found");
        return false;
    }

    g_world = find_gworld();
    if (g_world == 0) {
        alert::show("GWorld scan failed — update the pattern in find_gworld()");
        process::detach();
        return false;
    }

    create_thread(64, @tick);
    on_render(@draw);
    return true;
}

void on_unload() {
    process::detach();
}

// ── per-tick actor walk ──────────────────────────────────────────────────────

void tick() {
    if (!process::is_alive()) return;

    read_view();

    array<ActorInfo@> next;

    uint64 level = process::read_uint64(g_world + OFF_PERSISTENT_LEVEL);
    if (level != 0) {
        uint64 actor_base  = process::read_uint64(level + OFF_ACTOR_ARRAY);
        uint32 actor_count = process::read_uint32(level + OFF_ACTOR_COUNT);
        if (actor_base != 0 && actor_count > 0 && actor_count <= 4096) {
            for (uint32 i = 0; i < actor_count && next.length() < 128; i++) {
                uint64 actor = process::read_uint64(actor_base + uint64(i) * 8);
                if (actor == 0) continue;
                ActorInfo@ info = read_actor(actor);
                if (info !is null) next.insertLast(info);
            }
        }
    }

    g_mx.lock();
    g_actors = next;
    g_mx.unlock();
}

// Read the fields we need for one actor (user code — offsets are game specific)
ActorInfo@ read_actor(uint64 actor) {
    // Quick-filter: must have mesh (APawn) and health set (AFortPawn)
    uint64 mesh       = process::read_uint64(actor + OFF_MESH);
    uint64 health_set = process::read_uint64(actor + OFF_HEALTH_SET);
    if (mesh == 0 || health_set == 0) return null;

    float hp         = process::read_float(health_set + OFF_HP_CUR);
    float hp_max     = process::read_float(health_set + OFF_HP_MAX);
    float shield     = process::read_float(health_set + OFF_SHIELD_CUR);
    float shield_max = process::read_float(health_set + OFF_SHIELD_MAX);
    if (hp <= 0.0f || hp_max <= 0.0f) return null;

    uint64 root = process::read_uint64(actor + OFF_ROOT_COMPONENT);
    if (root == 0) return null;

    ActorInfo@ info = ActorInfo();
    info.mesh   = mesh;
    info.root_pos = vec3(process::read_float(root + OFF_COMP_TRANS),
                         process::read_float(root + OFF_COMP_TRANS + 4),
                         process->read_float(root + OFF_COMP_TRANS + 8));
    info.hp         = hp;
    info.hp_max     = hp_max;
    info.shield     = shield;
    info.shield_max = shield_max;
    return info;
}

// ── render ───────────────────────────────────────────────────────────────────

void draw() {
    g_mx.lock_shared();
    array<ActorInfo@> snap = g_actors;
    f_view_cache view = g_view;
    g_mx.unlock_shared();

    for (uint i = 0; i < snap.length(); i++) {
        ActorInfo@ e = snap[i];

        vec2 foot;
        if (!unreal::w2s(e.root_pos, view, foot)) continue;

        // Head position for box height
        vec2 head = foot;
        vec3 bone_pos;
        if (get_bone(e.mesh, BONE_HEAD, bone_pos)) {
            vec2 bone_screen;
            if (unreal::w2s(bone_pos, view, bone_screen)) head = bone_screen;
        }

        float box_h = foot.y - head.y;
        if (box_h < 8.0f) continue;
        float box_w = box_h * 0.55f;
        float box_x = head.x - box_w * 0.5f;
        float box_y = head.y;
        float corner = box_w * 0.22f;

        draw_cornered_box(box_x, box_y, box_w, box_h,
                          COL_BOX_R, COL_BOX_G, COL_BOX_B, COL_BOX_A, corner);
        draw_skeleton(e.mesh, view);

        int bx = int(box_x) - 5;
        int by = int(box_y);
        int bh = int(box_h);

        // HP bar — left side
        render::draw_box(bx - 1, by - 1, 4, bh + 2,
                         COL_FILL_R, COL_FILL_G, COL_FILL_B, COL_FILL_A,
                         box_style::FILLED, 0.0f);
        int hp_fill = int(box_h * (e.hp / e.hp_max));
        render::draw_box(bx, by + (bh - hp_fill), 2, hp_fill,
                         COL_HP_R, COL_HP_G, COL_HP_B, COL_HP_A,
                         box_style::FILLED, 0.0f);

        // Shield bar — right side
        if (e.shield_max > 0.0f) {
            int sx = int(box_x + box_w) + 3;
            render::draw_box(sx - 1, by - 1, 4, bh + 2,
                             COL_FILL_R, COL_FILL_G, COL_FILL_B, COL_FILL_A,
                             box_style::FILLED, 0.0f);
            int sh_fill = int(box_h * (e.shield / e.shield_max));
            render::draw_box(sx, by + (bh - sh_fill), 2, sh_fill,
                             COL_SHI_R, COL_SHI_G, COL_SHI_B, COL_SHI_A,
                             box_style::FILLED, 0.0f);
        }
    }
}

// ── skeleton ─────────────────────────────────────────────────────────────────

void draw_skeleton(uint64 mesh, f_view_cache view) {
    // 12 segments — full humanoid rig
    const uint pairs_n = 12;
    uint32[12] pa = {BONE_HEAD,    BONE_NECK,   BONE_CHEST,   BONE_L_UPPER,
                     BONE_R_UPPER, BONE_L_UPPER, BONE_R_UPPER, BONE_PELVIS,
                     BONE_PELVIS,  BONE_L_KNEE,  BONE_R_KNEE,  BONE_CHEST};
    uint32[12] pb = {BONE_NECK,    BONE_CHEST,  BONE_PELVIS,  BONE_L_HAND,
                     BONE_R_HAND,  BONE_L_KNEE, BONE_R_KNEE,  BONE_L_KNEE,
                     BONE_R_KNEE,  BONE_L_FOOT, BONE_R_FOOT,  BONE_R_UPPER};

    for (uint i = 0; i < pairs_n; i++) {
        vec3 a, b;
        if (!get_bone(mesh, pa[i], a)) continue;
        if (!get_bone(mesh, pb[i], b)) continue;
        vec2 sa, sb;
        if (!unreal::w2s(a, view, sa)) continue;
        if (!unreal::w2s(b, view, sb)) continue;
        render::draw_line(sa.x, sa.y, sb.x, sb.y,
                          COL_BONE_R, COL_BONE_G, COL_BONE_B, COL_BONE_A, 1.0f);
    }
}

bool get_bone(uint64 mesh, uint32 idx, vec3 &out pos) {
    uint64 bone_base  = process::read_uint64(mesh + OFF_BONE_ARRAY);
    uint32 bone_count = process::read_uint32(mesh + OFF_BONE_COUNT);
    if (bone_base == 0 || idx >= bone_count) return false;
    // FTransform: [rotation quat 16 bytes][translation vec3 12 bytes][scale 12 bytes] = 48 bytes
    uint64 entry = bone_base + uint64(idx) * 48;
    pos = vec3(process::read_float(entry + 16),
               process::read_float(entry + 20),
               process::read_float(entry + 24));
    return true;
}

// ── rendering helpers (user code) ───────────────────────────────────────────

void draw_cornered_box(float x, float y, float w, float h,
                       int r, int g, int b, int a, float c) {
    float t = 1.5f;
    render::draw_line(x,     y,     x + c, y,     r, g, b, a, t);
    render::draw_line(x,     y,     x,     y + c, r, g, b, a, t);
    render::draw_line(x + w, y,     x+w-c, y,     r, g, b, a, t);
    render::draw_line(x + w, y,     x + w, y + c, r, g, b, a, t);
    render::draw_line(x,     y + h, x + c, y + h, r, g, b, a, t);
    render::draw_line(x,     y + h, x,     y+h-c, r, g, b, a, t);
    render::draw_line(x + w, y + h, x+w-c, y + h, r, g, b, a, t);
    render::draw_line(x + w, y + h, x + w, y+h-c, r, g, b, a, t);
}

// ── camera ───────────────────────────────────────────────────────────────────

void read_view() {
    // shortcut: reads the camera manager from the GWorld chain;
    // update the camera offsets from Dumper-7 if W2S is wrong
    uint64 cam_mgr = process::read_uint64(g_world + OFF_CAM_MANAGER);
    if (cam_mgr == 0) return;

    f_view_info info;
    info.location = vec3(process::read_float(cam_mgr + OFF_CAM_LOC),
                         process::read_float(cam_mgr + OFF_CAM_LOC + 4),
                         process::read_float(cam_mgr + OFF_CAM_LOC + 8));
    info.rotation = vec3(process::read_float(cam_mgr + OFF_CAM_ROT),
                         process::read_float(cam_mgr + OFF_CAM_ROT + 4),
                         process::read_float(cam_mgr + OFF_CAM_ROT + 8));
    info.fov = process::read_float(cam_mgr + OFF_CAM_FOV);

    f_view_cache new_view = build_view_cache(info);

    g_mx.lock();
    g_view = new_view;
    g_mx.unlock();
}

// ── GWorld ───────────────────────────────────────────────────────────────────

uint64 find_gworld() {
    // LEA rcx,[rip+GWorld] in UEngine::Tick — stable across most patches
    // If this breaks after a patch run: mcp-gamehacking get_agent_briefing("fortnite-specialist")
    uint64 base = process::get_module_base("FortniteClient-Win64-Shipping.exe");
    if (base == 0) return 0;

    uint64 addr = process::find_signature(
        base,
        "48 8B 05 ? ? ? ? 48 85 C0 74 ? 48 8B 40 ? 48 85 C0 74"
    );
    if (addr == 0) return 0;
    return process::get_relative_address(addr, 3, 7);
}
