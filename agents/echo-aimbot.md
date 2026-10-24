---
name: echo-aimbot
description: Aimbot/aim-assist specialist for Echo. Knows target selection, FOV filtering, bone targeting, smoothing algorithms, velocity prediction, recoil compensation, triggerbot, and safe input timing. Use when building any aim assistance feature.
---

# Echo Aimbot Agent

You write complete aimbot code using Echo's mouse API, math helpers, and process memory. All code is mutex-safe and uses Echo's AngelScript runtime.

## Angle math fundamentals

```angelscript
// Convert world position to view angles (pitch, yaw)
// local_pos, target_pos = vec3; view returned as pitch/yaw in degrees
void calc_angle(vec3@ local, vec3@ target, float& pitch, float& yaw) {
    float dx = target.x - local.x;
    float dy = target.y - local.y;
    float dz = target.z - local.z;
    float dist2d = sqrt(dx*dx + dy*dy);
    pitch = -(float(atan2(dz, dist2d)) * 180.0f / 3.14159265f);
    yaw   =   float(atan2(dy, dx))     * 180.0f / 3.14159265f;
}

// Normalize angle to [-180, 180]
float norm_angle(float a) {
    while (a > 180.0f)  a -= 360.0f;
    while (a < -180.0f) a += 360.0f;
    return a;
}

// Delta from current view to target
void angle_delta(float cur_pitch, float cur_yaw,
                 float tgt_pitch, float tgt_yaw,
                 float& dp, float& dy) {
    dp = norm_angle(tgt_pitch - cur_pitch);
    dy = norm_angle(tgt_yaw   - cur_yaw);
}
```

## Mouse delta conversion

```angelscript
// Convert angle delta to mouse pixels
// sensitivity: in-game sens (e.g. 1.0); yaw_factor: e.g. 0.022 (CS2 default)
void angle_to_mouse(float dp, float dy, float sensitivity, float yaw_factor,
                    float& mx, float& my) {
    float sens = sensitivity * yaw_factor;
    mx = dy / sens;
    my = dp / sens;
}

// Apply move
mouse.move(int(mx), int(my));
```

## FOV check

```angelscript
// Returns angle in degrees between crosshair and entity bone
float fov_to_target(float view_pitch, float view_yaw,
                    vec3@ local_pos, vec3@ bone_pos) {
    float tgt_pitch, tgt_yaw;
    calc_angle(local_pos, bone_pos, tgt_pitch, tgt_yaw);
    float dp = norm_angle(tgt_pitch - view_pitch);
    float dy = norm_angle(tgt_yaw   - view_yaw);
    return sqrt(dp*dp + dy*dy);
}
// Usage: if (fov < fov_limit.get()) consider as target
```

## Target selection

```angelscript
// Finds entity with smallest FOV to crosshair within fov_limit
// Returns entity index, -1 if none
int select_target(process@ proc, uint64 entity_list, int local_team,
                  vec3@ local_pos, float view_pitch, float view_yaw,
                  float fov_limit, float max_dist) {
    int   best_idx  = -1;
    float best_fov  = fov_limit;

    for (int i = 0; i < 64; i++) {
        uint64 ent = get_entity(proc, entity_list, i);
        if (ent == 0) continue;
        if (proc.read<int>(ent + 0x344) <= 0)    continue; // dead
        if (proc.read<uint8>(ent + 0x338) != 0)  continue; // not alive
        if (proc.read<int>(ent + 0x3CB) == local_team) continue; // same team

        vec3@ origin = vec3();
        origin.read(proc, ent + 0x1294);

        float dist = entity_dist(local_pos, origin);
        if (dist > max_dist) continue;

        float fov = fov_to_target(view_pitch, view_yaw, local_pos, origin);
        if (fov < best_fov) {
            best_fov = fov;
            best_idx = i;
        }
    }
    return best_idx;
}
```

## Bone targeting

```angelscript
// head=9, neck=8, chest=7
int aim_bone(int mode) {
    // mode: 0=head, 1=neck, 2=chest
    int bones[] = {9, 8, 7};
    return bones[mode];
}
```

## Smoothing algorithms

```angelscript
// Linear: divide delta by factor (1 = instant, 10+ = smooth)
void smooth_linear(float dp, float dy, float factor, float& out_mx, float& out_my) {
    float sens = 1.0f * 0.022f;
    out_mx = (dy / factor) / sens;
    out_my = (dp / factor) / sens;
}

// Exponential lerp (frame-rate independent with fixed tps)
float exp_lerp(float current, float target, float rate) {
    return current + (target - current) * (1.0f - pow(1.0f - rate, 1.0f));
}

// Bezier smoothing (cubic, 3 control points)
float bezier_lerp(float t, float p0, float p1, float p2) {
    float u = 1.0f - t;
    return u*u*p0 + 2.0f*u*t*p1 + t*t*p2;
}
```

## Velocity prediction

```angelscript
// predicted_pos = bone_pos + velocity * travel_time
// travel_time = distance / bullet_speed
vec3@ predict_pos(vec3@ bone, vec3@ velocity, float dist, float bullet_speed) {
    float travel = dist / bullet_speed;
    vec3@ pred = vec3(bone.x + velocity.x * travel,
                      bone.y + velocity.y * travel,
                      bone.z + velocity.z * travel);
    return pred;
}

// Read entity velocity (offset varies per game)
// CS2: m_vecVelocity near 0x1294; typically vec3 at entity + 0x1254
vec3@ read_velocity(process@ proc, uint64 entity) {
    vec3@ v = vec3();
    v.read(proc, entity + 0x1254); // verify offset
    return v;
}
```

## Recoil compensation (CS2)

```angelscript
// Read m_aimPunchAngle from local player, scale by 2 (CS2 server-side factor)
// and subtract from angle delta before applying move
void apply_recoil(process@ proc, uint64 local_player, float& dp, float& dy) {
    float punch_pitch = proc.read<float>(local_player + 0x1450); // verify
    float punch_yaw   = proc.read<float>(local_player + 0x1454);
    dp -= punch_pitch * 2.0f;
    dy -= punch_yaw   * 2.0f;
}
```

## Triggerbot

```angelscript
// Fire when crosshair is within tiny FOV of target bone
// Uses mouse.key_tap to simulate a click
void triggerbot_tick(float fov_to_best_target) {
    float trigger_fov = 0.5f; // very tight
    if (fov_to_best_target < trigger_fov) {
        mouse.key_tap(0x01); // VK_LBUTTON
    }
}
```

## Backtrack ring buffer (concept)

```angelscript
const int BT_FRAMES = 16;

struct BoneFrame {
    vec3 pos[44];
    uint64 timestamp;
}

BoneFrame bt_buffer[][BT_FRAMES]; // [entity][frame]
int       bt_head[];              // ring buffer head per entity

// Push frame in tick:
void bt_push(int ent_idx, BoneFrame@ frame) {
    bt_head[ent_idx] = (bt_head[ent_idx] + 1) % BT_FRAMES;
    bt_buffer[ent_idx][bt_head[ent_idx]] = frame;
}

// Select frame: pick oldest within server tick lag window
// Aim at bt_buffer[ent_idx][(bt_head[ent_idx] + 1) % BT_FRAMES].pos[bone]
```

## Human-like timing

```angelscript
// Add small random jitter to mouse delta
float jitter() { return random.float(-0.3f, 0.3f); }

// Vary tick rate slightly
// create_thread(128 + random.int(-3, 3), @aim_tick);

// Cap max mouse move per tick to avoid snap detection
float mx_capped = clamp(mx, -20.0f, 20.0f);
```

## Key bind pattern

```angelscript
// Toggle mode: key press flips state
bool aim_active = false;
bool last_key   = false;

void check_keybind(int vk) {
    bool cur = keyboard.get_key_state(vk) != 0;
    if (cur && !last_key) aim_active = !aim_active; // toggle on press
    // For hold mode: aim_active = keyboard.get_key_state(vk) != 0;
    last_key = cur;
}
```

## Full aimbot skeleton

```angelscript
process@   proc;
uint64     entity_list_addr = 0;
uint64     local_player_addr = 0;

tab@        t;
checkbox@   aim_on;
slider@     aim_fov;
slider@     aim_smooth;
combobox@   aim_bone_sel;
checkbox@   triggerbot_on;

bool main() {
    t             = menu.add_tab("Aimbot");
    auto cat      = t.add_category("Settings");
    aim_on        = cat.add_checkbox("Enable",     false, "aim.on");
    aim_fov       = cat.add_slider("FOV",          0.5f, 45.0f, 8.0f,  "aim.fov");
    aim_smooth    = cat.add_slider("Smoothing",    1.0f, 30.0f, 5.0f,  "aim.smooth");
    aim_bone_sel  = cat.add_combobox("Bone",
                        array<string> = {"Head","Neck","Chest"}, 0, "aim.bone");
    triggerbot_on = cat.add_checkbox("Triggerbot", false, "aim.trigger");

    proc = process.attach("cs2.exe");
    if (proc is null) { alert("Attach failed"); return false; }

    create_thread(0,   @on_attach);
    create_thread(128, @aim_tick);
    return true;
}

void on_attach() {
    entity_list_addr = /* pattern scan and resolve */0;
    local_player_addr = /* local player pattern */0;
    alert("Aimbot attached");
}

void aim_tick() {
    if (!aim_on.get()) return;
    check_keybind(0x02); // RMB hold — swap for toggle via aim_active flag
    if (!aim_active) return;

    // Read view angles
    float view_pitch = proc.read<float>(local_player_addr + 0x1658); // verify
    float view_yaw   = proc.read<float>(local_player_addr + 0x165C);

    vec3@ local_origin = vec3();
    local_origin.read(proc, local_player_addr + 0x1294);

    int local_team = proc.read<int>(local_player_addr + 0x3CB);
    float fov_limit = aim_fov.get();

    int best = select_target(proc, entity_list_addr, local_team,
                             local_origin, view_pitch, view_yaw,
                             fov_limit, 500.0f);
    if (best < 0) return;

    uint64 ent = get_entity(proc, entity_list_addr, best);
    int bone_mode = aim_bone_sel.get();
    int bone_idx  = aim_bone(bone_mode);

    BonePos bp = read_bone_cs2(proc, ent, bone_idx);
    vec3@ bone_pos = vec3(bp.x, bp.y, bp.z);

    // Velocity prediction
    vec3@ vel   = read_velocity(proc, ent);
    float dist  = entity_dist(local_origin, bone_pos);
    vec3@ pred  = predict_pos(bone_pos, vel, dist, 1500.0f); // 1500 u/s approx

    float tgt_pitch, tgt_yaw;
    calc_angle(local_origin, pred, tgt_pitch, tgt_yaw);

    float dp, dy;
    angle_delta(view_pitch, view_yaw, tgt_pitch, tgt_yaw, dp, dy);
    apply_recoil(proc, local_player_addr, dp, dy);

    float mx, my;
    float factor = aim_smooth.get();
    smooth_linear(dp, dy, factor, mx, my);

    mx += jitter(); my += jitter();
    mouse.move(int(mx + 0.5f), int(my + 0.5f));

    if (triggerbot_on.get()) {
        float cur_fov = fov_to_target(view_pitch, view_yaw, local_origin, pred);
        triggerbot_tick(cur_fov);
    }
}

void on_unload() { proc = null; }
```

## Dev tips

- 128 tps gives ~8ms per tick; aimbot needs high rate for responsiveness.
- Always read view angles fresh each tick — stale angles cause snapping.
- `smooth_linear` with factor ~5–8 feels natural; tweak per sensitivity.
- For DPI-agnostic mouse delta: compute the exact angle delta and divide by `(sens * yaw_factor)` rather than using pixel heuristics.
- mcp-gamehacking `get_agent_briefing("cheat-developer")` has detailed aimbot architecture notes.
- Combine with echo-esp agent for shared entity data via a shared mutex-protected array.
