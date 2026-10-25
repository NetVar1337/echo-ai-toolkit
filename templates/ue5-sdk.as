// UE5 SDK-based ESP — Echo AngelScript template
// Requires: Dumper-7 SDK generated from your target game
// See: skills/dumper7-sdk.md, .claude/agents/echo-sdk.md
//
// How to use:
//   1. Run Dumper-7 on your target UE5 game
//   2. Open CppSDK/SDK_HEADERS/Engine_classes.hpp and Engine_structs.hpp
//   3. Update the offset constants below from those files
//   4. Place in %AppData%\Roaming\scripts\, reload in-game
//
// IMPORTANT: THE OFFSETS AND THE SIGNATURE BELOW ARE PLACEHOLDERS. They come
// from one Dumper-7 output and are NOT verified. They break on every patch.
// Re-derive them before using this template.

// ── Offset constants (placeholders — update from Dumper-7 after each patch) ──
// Source: Engine_classes.hpp / ShooterGame_classes.hpp
const uint32 OFF_PERSISTENTLEVEL  = 0x30;   // UWorld::PersistentLevel
const uint32 OFF_ACTORS_DATA      = 0xA0;   // ULevel::AActors.Data (TArray)
const uint32 OFF_ACTORS_COUNT     = 0xA8;   // ULevel::AActors.Num
const uint32 OFF_ROOTCOMPONENT    = 0x130;  // AActor::RootComponent
const uint32 OFF_COMPONENTWORLD   = 0x1C0;  // USceneComponent::ComponentToWorld
const uint32 OFF_FTRANSFORM_POS   = 0x10;   // FTransform::Translation (within ComponentToWorld)
const uint32 OFF_HEALTH           = 0x330;  // ACharacter / APawn health — game-specific
const uint32 OFF_MAXHEALTH        = 0x334;  // game-specific
const uint32 OFF_TEAM             = 0x3B8;  // APawn / APlayerState::TeamNum — game-specific
const uint32 OFF_GAMEINSTANCE     = 0x180;  // UWorld::GameInstance
const uint32 OFF_LOCALPLAYERS_DATA = 0x38;  // UGameInstance::LocalPlayers.Data
const uint32 OFF_PC               = 0x30;   // ULocalPlayer::PlayerController
const uint32 OFF_CAMMANAGER       = 0x440;  // APlayerController::PlayerCameraManager
const uint32 OFF_CAMLOC           = 0x1490; // APlayerCameraManager::CameraLocation
const uint32 OFF_CAMROT           = 0x149C; // APlayerCameraManager::CameraRotation
const uint32 OFF_CAMFOV           = 0x14A8; // APlayerCameraManager::FOVAngle

// ── GWorld scan pattern (placeholder — update if broken after patch) ─────────
const string GWORLD_SIG = "48 8B 1D ? ? ? ? 48 85 DB 74";

// ── Shared state ─────────────────────────────────────────────────────────────
mutex@ g_ent_lock = create_mutex();
checkbox g_show_boxes;
checkbox g_show_health;
checkbox g_show_distance;
slider   g_fov_limit;      // degrees; 360 = no limit
color_picker g_col_visible;
color_picker g_col_occluded;

class Entity {
    vec3  pos;
    float health;
    float maxhealth;
    int   team;
}

array<Entity@> g_entities;
int  g_local_team = -1;
vec3 g_local_pos;
vec3 g_cam_rot;
f_view_cache g_view;

const string GAME_EXE = "YourGame-Win64-Shipping.exe"; // ← change me

// ── Setup ────────────────────────────────────────────────────────────────────
bool main() {
    ui::config_path("echo_ue5_sdk");

    attach_data ad = process::attach(GAME_EXE);
    if (ad.pid == 0) {
        alert::show("Game not found");
        return false;
    }

    ui::add_tab("UE5 ESP");
    ui::add_category("Settings");
    g_show_boxes    = ui::add_checkbox("Boxes", true, "ue5.boxes");
    g_show_health   = ui::add_checkbox("Health", true, "ue5.health");
    g_show_distance = ui::add_checkbox("Distance", true, "ue5.distance");
    g_fov_limit     = ui::add_slider("FOV limit", 360, 10, 360, 5, "deg", "ue5.fov");
    g_col_visible   = ui::add_color_picker("Visible", 0, 255, 0, 200, true, "ue5.col_v");
    g_col_occluded  = ui::add_color_picker("Occluded", 255, 80, 80, 200, true, "ue5.col_o");

    create_thread(64, @update_loop);    // 64 tps entity update
    on_render(@draw_loop);
    return true;
}

// ── Entity update ────────────────────────────────────────────────────────────
void update_loop() {
    do_update();
}

void do_update() {
    // GWorld — find_signature needs a base address first
    uint64 base = process::get_module_base(GAME_EXE);
    if (base == 0) return;

    uint64 gw_sig = process::find_signature(base, GWORLD_SIG);
    if (gw_sig == 0) return;
    uint64 gworld_ptr = process::get_relative_address(gw_sig, 3, 7);
    uint64 world      = process::read_uint64(gworld_ptr);
    if (world == 0) return;

    // Camera
    uint64 gi      = process::read_uint64(world + OFF_GAMEINSTANCE);
    uint64 lp_data = process::read_uint64(gi + OFF_LOCALPLAYERS_DATA);
    uint64 local_p = process::read_uint64(lp_data);
    uint64 pc      = process::read_uint64(local_p + OFF_PC);
    uint64 cam     = process::read_uint64(pc + OFF_CAMMANAGER);
    if (cam == 0) return;

    vec3 cam_loc = vec3(process::read_float(cam + OFF_CAMLOC),
                        process::read_float(cam + OFF_CAMLOC + 4),
                        process::read_float(cam + OFF_CAMLOC + 8));
    vec3 cam_rot = vec3(process::read_float(cam + OFF_CAMROT),
                        process::read_float(cam + OFF_CAMROT + 4),
                        process::read_float(cam + OFF_CAMROT + 8));
    float cam_fov = process::read_float(cam + OFF_CAMFOV);
    if (cam_fov < 10.0f || cam_fov > 170.0f) cam_fov = 90.0f;

    f_view_info view_info;
    view_info.location = cam_loc;
    view_info.rotation = cam_rot;
    view_info.fov      = cam_fov;

    // Actor list
    uint64 level      = process::read_uint64(world + OFF_PERSISTENTLEVEL);
    uint64 actors_ptr = process::read_uint64(level + OFF_ACTORS_DATA);
    int32  actors_num = process::read_int32(level + OFF_ACTORS_COUNT);
    if (actors_num <= 0 || actors_num > 512) return;

    array<Entity@> tmp;
    int local_team = -1;

    for (int32 i = 0; i < actors_num; i++) {
        uint64 actor = process::read_uint64(actors_ptr + uint64(i) * 8);
        if (actor == 0) continue;

        int   team = process::read_int32(actor + OFF_TEAM);
        float hp   = process::read_float(actor + OFF_HEALTH);
        if (hp <= 0.0f) continue;

        uint64 root = process::read_uint64(actor + OFF_ROOTCOMPONENT);
        if (root == 0) continue;

        // ComponentToWorld.Translation — three consecutive floats
        vec3 pos = vec3(process::read_float(root + OFF_COMPONENTWORLD + OFF_FTRANSFORM_POS),
                        process::read_float(root + OFF_COMPONENTWORLD + OFF_FTRANSFORM_POS + 4),
                        process::read_float(root + OFF_COMPONENTWORLD + OFF_FTRANSFORM_POS + 8));

        // Assume local player has a team set and is closest to (0,0,0) initially
        // Better: compare to the PC actor address
        if (local_team == -1) local_team = team;

        Entity@ e = Entity();
        e.pos       = pos;
        e.health    = hp;
        e.maxhealth = process::read_float(actor + OFF_MAXHEALTH);
        if (e.maxhealth <= 0.0f) e.maxhealth = 100.0f;
        e.team      = team;
        tmp.insertLast(e);
    }

    g_ent_lock.lock();
    g_entities   = tmp;
    g_local_team = local_team;
    g_local_pos  = cam_loc;  // approximate local pos as camera loc
    g_cam_rot    = cam_rot;
    g_view       = build_view_cache(view_info);
    g_ent_lock.unlock();
}

// ── Draw ─────────────────────────────────────────────────────────────────────
void draw_loop() {
    g_ent_lock.lock_shared();
    array<Entity@> snap = g_entities;
    int local_team = g_local_team;
    vec3 local_pos = g_local_pos;
    vec3 cam_rot = g_cam_rot;
    f_view_cache view = g_view;
    g_ent_lock.unlock_shared();

    render::update_font(fonts::TAHOMA, 12);

    for (uint i = 0; i < snap.length(); i++) {
        Entity@ e = snap[i];
        if (e.team == local_team) continue;

        // FOV filter
        double dfov = math::unreal_calculate_fov(cam_rot, local_pos, e.pos);
        if (double(ui::get(g_fov_limit)) < 360.0 && dfov > double(ui::get(g_fov_limit))) continue;

        // W2S — unreal::w2s writes the screen position and returns false when
        // the point is off-screen or behind the camera
        vec2 head_scr;
        if (!unreal::w2s(e.pos + vec3(0, 0, 90), view, head_scr)) continue;
        vec2 feet_scr;
        if (!unreal::w2s(e.pos, view, feet_scr)) continue;

        float h = feet_scr.y - head_scr.y;
        if (h < 0.0f) h = -h;
        float w = h * 0.5f;
        float cx = feet_scr.x;
        float cy = head_scr.y;

        color col = (e.team != local_team) ? ui::get(g_col_occluded)
                                           : ui::get(g_col_visible);

        // Cornered box
        if (ui::get(g_show_boxes)) {
            float clen = w * 0.25f;
            render::draw_line(cx - w / 2,       cy,          cx - w / 2 + clen, cy,
                              col.r, col.g, col.b, col.a, 1.5f);
            render::draw_line(cx + w / 2 - clen, cy,          cx + w / 2,        cy,
                              col.r, col.g, col.b, col.a, 1.5f);
            render::draw_line(cx - w / 2,       cy + h,      cx - w / 2 + clen, cy + h,
                              col.r, col.g, col.b, col.a, 1.5f);
            render::draw_line(cx + w / 2 - clen, cy + h,      cx + w / 2,        cy + h,
                              col.r, col.g, col.b, col.a, 1.5f);
            render::draw_line(cx - w / 2,       cy,          cx - w / 2,        cy + clen,
                              col.r, col.g, col.b, col.a, 1.5f);
            render::draw_line(cx - w / 2,       cy + h - clen, cx - w / 2,      cy + h,
                              col.r, col.g, col.b, col.a, 1.5f);
            render::draw_line(cx + w / 2,       cy,          cx + w / 2,        cy + clen,
                              col.r, col.g, col.b, col.a, 1.5f);
            render::draw_line(cx + w / 2,       cy + h - clen, cx + w / 2,      cy + h,
                              col.r, col.g, col.b, col.a, 1.5f);
        }

        // Health bar
        if (ui::get(g_show_health)) {
            float pct = e.health / e.maxhealth;
            if (pct > 1.0f) pct = 1.0f;
            float bh = h * pct;
            float bx = cx - w / 2 - 6;
            render::draw_box(int(bx) - 2, int(cy), 4, int(h),
                             0, 0, 0, 150, box_style::FILLED, 0.0f);
            render::draw_box(int(bx) - 2, int(cy + h - bh), 4, int(bh),
                             int((1 - pct) * 255), int(pct * 255), 0, 220,
                             box_style::FILLED, 0.0f);
        }

        // Distance label
        if (ui::get(g_show_distance)) {
            float dist_m = e.pos.distance(local_pos) / 100.0f;
            string lbl = util::format_string("{:.0}m", dist_m);
            render::draw_text(int(cx), int(cy + h) + 2, lbl, 220, 220, 220, 200);
        }
    }
}
