// UE5 SDK-based ESP — Echo AngelScript template
// Requires: Dumper-7 SDK generated from your target game
// See: skills/dumper7-sdk.md, .claude/agents/echo-sdk.md
//
// How to use:
//   1. Run Dumper-7 on your target UE5 game
//   2. Open CppSDK/SDK_HEADERS/Engine_classes.hpp and Engine_structs.hpp
//   3. Update the offset constants below from those files
//   4. Place in %AppData%\Roaming\scripts\, reload in-game

// ── Offset constants (update from Dumper-7 CppSDK after each patch) ─────────
// Source: Engine_classes.hpp / ShooterGame_classes.hpp
// Build: update patterns below using binary-differ after game patches
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

// ── GWorld scan pattern (update if broken after patch) ───────────────────────
const string GWORLD_SIG = "48 8B 1D ? ? ? ? 48 85 DB 74";

// ── Shared state ─────────────────────────────────────────────────────────────
process@  proc;
mutex@    ent_lock;
tab@      esp_tab;
subtab@   vis_tab;

bool      show_boxes    = true;
bool      show_health   = true;
bool      show_distance = true;
float     fov_limit     = 360.0;  // degrees; 360 = no limit
color     col_visible   = color(0, 255, 0, 200);
color     col_occluded  = color(255, 80, 80, 200);

struct Entity {
    vec3  pos;
    float health;
    float maxhealth;
    int   team;
}

array<Entity> entities;
int           local_team = -1;
vec3          local_pos;
vec3          cam_loc;
vec3          cam_rot;
float         cam_fov    = 90.0;

// ── Setup ────────────────────────────────────────────────────────────────────
bool main() {
    proc = process.attach("YourGame-Win64-Shipping.exe");  // ← change me
    if (!proc.valid()) {
        alert("Game not found");
        return false;
    }

    @ent_lock = mutex();

    menu@ m = get_menu();
    @esp_tab = m.add_tab("UE5 ESP");
    @vis_tab = esp_tab.add_subtab("Visuals");
    category@ cat = vis_tab.add_category("Settings");
    cat.add_checkbox("Boxes",    show_boxes);
    cat.add_checkbox("Health",   show_health);
    cat.add_checkbox("Distance", show_distance);
    cat.add_slider("FOV limit", fov_limit, 10.0, 360.0, 1.0);
    cat.add_color("Visible",    col_visible);
    cat.add_color("Occluded",   col_occluded);

    create_thread(64, @update_loop);    // 64 tps entity update
    on_render(@draw_loop);
    return true;
}

// ── Entity update ─────────────────────────────────────────────────────────────
void update_loop() {
    while (true) {
        do_update();
        sleep(15);
    }
}

void do_update() {
    // GWorld
    uint64 gw_sig = proc.scan_ida(GWORLD_SIG, "YourGame-Win64-Shipping.exe");
    if (gw_sig == 0) return;
    uint64 gworld_ptr = proc.resolve_rip(gw_sig, 3, 7);
    uint64 world      = proc.read<uint64>(gworld_ptr);
    if (world == 0) return;

    // Camera
    uint64 gi       = proc.read<uint64>(world + OFF_GAMEINSTANCE);
    uint64 lp_data  = proc.read<uint64>(gi + OFF_LOCALPLAYERS_DATA);
    uint64 local_p  = proc.read<uint64>(lp_data);
    uint64 pc       = proc.read<uint64>(local_p + OFF_PC);
    uint64 cam      = proc.read<uint64>(pc + OFF_CAMMANAGER);
    cam_loc.read(proc, cam + OFF_CAMLOC);
    cam_rot.read(proc, cam + OFF_CAMROT);
    cam_fov = proc.read<float>(cam + OFF_CAMFOV);
    if (cam_fov < 10.0 || cam_fov > 170.0) cam_fov = 90.0;

    // Actor list
    uint64 level      = proc.read<uint64>(world + OFF_PERSISTENTLEVEL);
    uint64 actors_ptr = proc.read<uint64>(level + OFF_ACTORS_DATA);
    int32  actors_num = proc.read<int32>(level + OFF_ACTORS_COUNT);
    if (actors_num <= 0 || actors_num > 512) return;

    array<Entity> tmp;
    local_team = -1;

    for (int32 i = 0; i < actors_num; i++) {
        uint64 actor = proc.read<uint64>(actors_ptr + i * 8);
        if (actor == 0) continue;

        int team = proc.read<int32>(actor + OFF_TEAM);
        float hp = proc.read<float>(actor + OFF_HEALTH);
        if (hp <= 0) continue;

        uint64 root  = proc.read<uint64>(actor + OFF_ROOTCOMPONENT);
        if (root == 0) continue;
        vec3@ pos;
        pos.read(proc, root + OFF_COMPONENTWORLD + OFF_FTRANSFORM_POS);

        // Assume local player has team set and is closest to (0,0,0) initially
        // Better: compare to PC actor address
        if (local_team == -1) local_team = team;

        Entity e;
        e.pos       = pos;
        e.health    = hp;
        e.maxhealth = proc.read<float>(actor + OFF_MAXHEALTH);
        if (e.maxhealth <= 0) e.maxhealth = 100.0;
        e.team      = team;
        tmp.push_back(e);
    }

    ent_lock.lock();
    entities = tmp;
    local_pos = cam_loc;  // approximate local pos as camera loc
    ent_lock.unlock();
}

// ── Draw ──────────────────────────────────────────────────────────────────────
void draw_loop() {
    ent_lock.lock();
    array<Entity> snap = entities;
    ent_lock.unlock();

    int sw = get_screen_width();
    int sh = get_screen_height();

    for (uint i = 0; i < snap.length(); i++) {
        Entity@ e = snap[i];
        if (e.team == local_team) continue;

        // FOV filter
        vec3 aim = calc_angle(local_pos, e.pos);
        float dfov = angle_dist(cam_rot, aim);
        if (fov_limit < 360.0 && dfov > fov_limit) continue;

        // W2S
        vec2@ head_scr = unreal.w2s(e.pos + vec3(0, 0, 90), cam_loc, cam_rot, cam_fov, sw, sh);
        if (head_scr.z < 0) continue;
        vec2@ feet_scr = unreal.w2s(e.pos,                  cam_loc, cam_rot, cam_fov, sw, sh);
        if (feet_scr.z < 0) continue;

        float h = math.abs(feet_scr.y - head_scr.y);
        float w = h * 0.5;
        float cx = feet_scr.x;
        float cy = head_scr.y;

        color col = (e.team != local_team) ? col_occluded : col_visible;

        // Cornered box
        if (show_boxes) {
            float clen = w * 0.25;
            renderer.line(cx - w/2,       cy,          cx - w/2 + clen, cy,          col, 1.5);
            renderer.line(cx + w/2 - clen, cy,          cx + w/2,        cy,          col, 1.5);
            renderer.line(cx - w/2,       cy + h,      cx - w/2 + clen, cy + h,      col, 1.5);
            renderer.line(cx + w/2 - clen, cy + h,      cx + w/2,        cy + h,      col, 1.5);
            renderer.line(cx - w/2,       cy,          cx - w/2,        cy + clen,   col, 1.5);
            renderer.line(cx - w/2,       cy + h - clen, cx - w/2,      cy + h,      col, 1.5);
            renderer.line(cx + w/2,       cy,          cx + w/2,        cy + clen,   col, 1.5);
            renderer.line(cx + w/2,       cy + h - clen, cx + w/2,      cy + h,      col, 1.5);
        }

        // Health bar
        if (show_health) {
            float pct  = math.clamp(e.health / e.maxhealth, 0.0, 1.0);
            float bh   = h * pct;
            float bx   = cx - w/2 - 6;
            color bg   = color(0, 0, 0, 150);
            color fg   = color(int((1-pct)*255), int(pct*255), 0, 220);
            renderer.rect(bx - 2, cy, 4, h, bg);
            renderer.rect(bx - 2, cy + h - bh, 4, bh, fg);
        }

        // Distance label
        if (show_distance) {
            float dist_m = (e.pos - local_pos).length() / 100.0;
            string lbl   = fmt("{:.0f}m", dist_m);
            renderer.text(cx, cy + h + 2, lbl, color(220, 220, 220, 200), get_font("default"));
        }
    }
}

// ── Math helpers ──────────────────────────────────────────────────────────────
float norm_ang(float a) {
    while (a >  180.0) a -= 360.0;
    while (a < -180.0) a += 360.0;
    return a;
}

vec3 calc_angle(vec3 src, vec3 dst) {
    vec3 d   = dst - src;
    float xy = math.sqrt(d.x*d.x + d.y*d.y);
    vec3 ang;
    ang.x = math.atan2(-d.z, xy) * (180.0 / math.PI);
    ang.y = math.atan2(d.y, d.x) * (180.0 / math.PI);
    ang.z = 0;
    return ang;
}

float angle_dist(vec3 a, vec3 b) {
    float dx = norm_ang(b.x - a.x);
    float dy = norm_ang(b.y - a.y);
    return math.sqrt(dx*dx + dy*dy);
}
