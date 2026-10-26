---
name: echo-aimbot
description: Aimbot/aim-assist specialist for Echo. Knows target selection, FOV filtering, bone targeting, smoothing algorithms, velocity prediction, recoil compensation, triggerbot, and safe input timing. Use when building any aim assistance feature.
---

# Echo Aimbot Agent

You write complete aim-assist code using Echo's input, math, and process-memory APIs. All code is mutex-safe and
uses Echo's AngelScript runtime.

> **Offsets in this document are illustrative placeholders.** Every game-specific offset, signature and struct
> layout below is an example, not a verified value. Re-verify each one against the build you are actually running
> (Dumper-7 / schema dump / your own RE) and re-verify after every patch — see the offset-update workflow in
> `skills/offset-update-workflow`. Never ship a script whose offsets you have not confirmed on a live build.

## Angle math fundamentals

```angelscript
// USER CODE — Echo's built-in equivalent is math::calculate_angle(from, to) -> vec2(pitch, yaw).
void calc_angle(vec3 from, vec3 to, vec2 &out angles) {
    angles = math::calculate_angle(from, to);
}

// Delta from current view to target, normalised to [-180, 180]
vec2 angle_delta(vec2 cur, vec2 tgt) {
    return vec2(
        float(math::normalize_angle(double(tgt.x - cur.x), angle_range::R_180)),
        float(math::normalize_angle(double(tgt.y - cur.y), angle_range::R_180))
    );
}
```

## Built-in math helpers

Prefer these over manual implementations — they handle edge cases and coordinate conventions.

```angelscript
// Angles from one world position to another — returns vec2(pitch, yaw)
vec2 aim = math::calculate_angle(local_pos, target_pos);

// Normalize angle to [-180, 180]
double a = math::normalize_angle(raw_angle, angle_range::R_180);

// Shortest signed delta between two angles
double dp = math::angle_diff(cur_pitch, tgt_pitch);
double dy = math::angle_diff(cur_yaw,   tgt_yaw);

// FOV in degrees between two sets of angles
double fov = math::calculate_fov(view_angles, entity_angles);

// Clamp pitch to [-89, 89] and normalize yaw
vec2 clamped = math::clamp_angles(vec2(pitch, yaw), angle_range::R_180);

// Smooth toward target — returns the new current angles.
// smoothing: 0.0 = fast, 1.0 = slow. min/max speed are degrees-per-tick bounds.
vec2 smoothed = math::smooth_angles(cur, tgt, angle_range::R_180, 0.3, 1.0, 45.0);

// Unreal Engine — FRotator coordinate system (pitch inverted vs. standard math)
vec2   ue_delta = math::unreal_calculate_angle(camera_rot, camera_pos, target_pos);
double ue_fov   = math::unreal_calculate_fov(camera_rot, camera_pos, target_pos);
vec2   ue_smooth = math::unreal_smooth_rotation(camera_rot, camera_pos, target_pos, 0.12, 1.0, 45.0);
```

## Mouse movement

`input::mouse_move` takes **absolute screen coordinates**, not a delta. To apply a relative movement,
read the current cursor position, add your delta, and write the new absolute position.

```angelscript
// USER CODE — Echo's mouse API is absolute-only, so relative movement is done by hand.
void move_mouse_relative(float dx, float dy) {
    int cx = 0, cy = 0;
    input::mouse_pos(cx, cy);
    vec2 vp = render::get_viewport_size();
    int nx = int(clampf(float(cx + dx), 0.0f, vp.x));
    int ny = int(clampf(float(cy + dy), 0.0f, vp.y));
    input::mouse_move(nx, ny);
}

// USER CODE — no clamp() builtin in the runtime; write your own.
float clampf(float v, float lo, float hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

// Convert angle delta to mouse pixels
// sensitivity: in-game sens (e.g. 1.0); yaw_factor: e.g. 0.022 (CS2 default, verify)
void angle_to_mouse(float dp, float dy, float sensitivity, float yaw_factor,
                    float &out mx, float &out my) {
    float sens = sensitivity * yaw_factor;
    mx = dy / sens;
    my = dp / sens;
}
```

## FOV check

```angelscript
// Angle in degrees between the crosshair and an entity bone
double fov_to_target(vec2 view_angles, vec3 bone_pos, vec3 local_pos) {
    vec2 tgt = math::calculate_angle(local_pos, bone_pos);
    double dp = math::angle_diff(view_angles.x, tgt.x);
    double dy = math::angle_diff(view_angles.y, tgt.y);
    double dp2 = dp * dp, dy2 = dy * dy;
    return float(vec2(float(dp2), float(dy2)).length());
}
// Usage: if (fov < fov_limit) consider as target
```

## Target selection

```angelscript
// Offsets below are PLACEHOLDERS — re-verify per game build.
const uint64 OFF_LIFE_STATE = 0x338;
const uint64 OFF_TEAM       = 0x3CB;
const uint64 OFF_ORIGIN     = 0x1294;

int select_target(uint64 entity_list, int local_team,
                  vec3 local_pos, vec2 view_angles,
                  double fov_limit, float max_dist) {
    int    best_idx = -1;
    double best_fov = fov_limit;

    for (int i = 0; i < 64; i++) {
        uint64 ent = source2::get_controller(entity_list, uint64(i));
        if (ent == 0) continue;
        if (process::read_uint8(ent + OFF_LIFE_STATE) != 0) continue;   // not alive
        if (process::read_int32(ent + OFF_TEAM) == local_team) continue;  // same team

        vec3 origin;
        origin.read_float(ent + OFF_ORIGIN);

        float dist = origin.distance(local_pos);
        if (dist > max_dist) continue;

        double fov = fov_to_target(view_angles, origin, local_pos);
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
// Bone indices are game-specific and change between games/versions — verify per game.
const int BONE_HEAD  = 9;
const int BONE_NECK  = 8;
const int BONE_CHEST = 7;

int aim_bone(int mode) {
    array<int> bones = {BONE_HEAD, BONE_NECK, BONE_CHEST};
    return bones[mode];
}
```

## Smoothing algorithms

```angelscript
// Linear: divide delta by factor (1 = instant, 10+ = smooth)
void smooth_linear(float dp, float dy, float factor, float &out mx, float &out my) {
    float sens = 1.0f * 0.022f;   // verify per game
    out_mx = (dy / factor) / sens;
    out_my = (dp / factor) / sens;
}

// Exponential lerp (frame-rate independent with fixed tps)
float exp_lerp(float current, float target, float rate) {
    return current + (target - current) * rate;
}

// Bezier smoothing (cubic, 3 control points)
float bezier_lerp(float t, float p0, float p1, float p2) {
    float u = 1.0f - t;
    return u * u * p0 + 2.0f * u * t * p1 + t * t * p2;
}

// Built-in alternative — returns the smoothed angles directly
vec2 smoothed = math::smooth_angles(cur, tgt, angle_range::R_180, 0.3, 1.0, 45.0);
```

## Velocity prediction

```angelscript
// USER CODE — bullet speed and velocity offsets are game-specific placeholders.
vec3 predict_pos(vec3 bone, vec3 velocity, float dist, float bullet_speed) {
    float travel = dist / bullet_speed;
    return vec3(bone.x + velocity.x * travel,
                bone.y + velocity.y * travel,
                bone.z + velocity.z * travel);
}

// Offset below is a PLACEHOLDER — re-verify per game build.
const uint64 OFF_VELOCITY = 0x1254;

vec3 read_velocity(uint64 entity) {
    vec3 v;
    v.read_float(entity + OFF_VELOCITY);
    return v;
}
```

## Recoil compensation (CS2)

```angelscript
// Read m_aimPunchAngle from local player, scale by 2 (CS2 server-side factor).
// Offsets are PLACEHOLDERS — re-verify per patch.
const uint64 OFF_PUNCH_PITCH = 0x1450;
const uint64 OFF_PUNCH_YAW   = 0x1454;

void apply_recoil(uint64 local_player, float dp, float dy,
                  float &out out_dp, float &out out_dy) {
    float punch_pitch = process::read_float(local_player + OFF_PUNCH_PITCH);
    float punch_yaw   = process::read_float(local_player + OFF_PUNCH_YAW);
    out_dp = dp - punch_pitch * 2.0f;
    out_dy = dy - punch_yaw   * 2.0f;
}
```

## Triggerbot

```angelscript
// Fire when crosshair is within tiny FOV of target bone
void triggerbot_tick(double fov_to_best_target) {
    double trigger_fov = 0.5;
    if (fov_to_best_target < trigger_fov) {
        input::mouse_click();   // real API: click / press / release, no VK code
    }
}
```

## Backtrack ring buffer (concept)

```angelscript
const int BT_FRAMES = 16;

class BoneFrame {
    array<vec3> pos;
    uint64 timestamp;
    int    entity_index;
}

// One ring buffer per entity index, stored flat: index = ent_idx * BT_FRAMES + slot
array<BoneFrame@> bt_buffer;
array<int>        bt_head;

void bt_push(int ent_idx, BoneFrame@ frame) {
    if (bt_head.length() <= ent_idx) {
        bt_head.resize(uint(ent_idx + 1));
        bt_buffer.resize(uint((ent_idx + 1) * BT_FRAMES));
        for (uint i = 0; i < bt_head.length(); i++) bt_head[i] = 0;
    }
    bt_head[ent_idx] = (bt_head[ent_idx] + 1) % BT_FRAMES;
    bt_buffer[ent_idx * BT_FRAMES + bt_head[ent_idx]] = frame;
}
// Select frame: pick oldest within server tick lag window
// Aim at bt_buffer[ent_idx * BT_FRAMES + (bt_head[ent_idx] + 1) % BT_FRAMES].pos[bone]
```

## Timing and jitter

```angelscript
// Add small random jitter to mouse movement
float jitter() { return util::random_float(-0.3f, 0.3f); }

// Cap max mouse move per tick
float mx_capped = clampf(mx, -20.0f, 20.0f);

// Seed randomizer at startup for reproducible jitter patterns per session

void timing_and_jitter() {
    util::seed_random(uint64(util::time_now() & 0xFFFF));
}
```

## Key bind pattern

```angelscript
// Hold mode — true while the key is physically held (most common)
bool aim_active = input::key_active(0x02); // VK_RBUTTON

// Toggle mode — key_toggled reflects the OS toggle state (e.g. caps lock),
// it does NOT flip on every press. For a press-to-toggle bind, keep your own state.
bool g_toggle  = false;
bool g_last_rmb = false;

void update_toggle() {
    bool now = input::key_active(0x02);
    if (now && !g_last_rmb) g_toggle = !g_toggle;
    g_last_rmb = now;
}

// Synthetic key events (send, not observe)

void key_bind_pattern() {
    input::key_press(0x41);   // key down
    input::key_release(0x41); // key up
    input::key_tap(0x41);     // down + up atomically
}
```

## Full aim-assist skeleton

```angelscript
uint64 entity_list_addr  = 0;
uint64 local_player_addr = 0;
uint64 view_matrix_addr  = 0;

checkbox aim_on;
slider   aim_fov;
slider   aim_smooth;
combobox aim_bone_sel;
checkbox triggerbot_on;

bool main() {
    ui::config_path("aimassist");
    ui::add_tab("Aim");
    ui::add_category("Settings");
    aim_on        = ui::add_checkbox("Enable", false, "aim.on");
    aim_fov       = ui::add_slider("FOV", 10, 1, 90, 1, "deg", "aim.fov");
    aim_smooth    = ui::add_slider("Smoothing", 5, 1, 30, 1, "", "aim.smooth");
    aim_bone_sel  = ui::add_combobox("Bone", {"Head", "Neck", "Chest"}, 0, "aim.bone");
    triggerbot_on = ui::add_checkbox("Triggerbot", false, "aim.trigger");

    attach_data ad = process::attach("cs2.exe");
    if (ad.pid == 0) { alert::show("Attach failed"); return false; }

    create_thread(0,   @on_attach);
    create_thread(128, @aim_tick);
    return true;
}

void on_attach() {
    // Signatures below are PLACEHOLDERS — re-verify per patch.
    uint64 client_base = process::get_module_base("client.dll");
    if (client_base == 0) { alert::show_tag("client.dll not found", "error"); return; }

    uint64 ent_sig = process::find_signature(client_base, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 48");
    if (ent_sig == 0) { alert::show_tag("Entity list pattern broken", "error"); return; }
    entity_list_addr = process::get_relative_address(ent_sig, 3, 7);

    uint64 vm_sig = process::find_signature(client_base, "48 8D 05 ? ? ? ? 48 89 05 ? ? ? ? 48");
    if (vm_sig != 0) view_matrix_addr = process::get_relative_address(vm_sig, 3, 7);

    alert::show("Aim assist attached");
}

void aim_tick() {
    if (!ui::get(aim_on)) return;
    if (!input::key_active(0x02)) return; // RMB hold
    if (entity_list_addr == 0 || local_player_addr == 0) return;

    // Offsets below are PLACEHOLDERS — re-verify per build.
    float view_pitch = process::read_float(local_player_addr + 0x1658);
    float view_yaw   = process::read_float(local_player_addr + 0x165C);

    vec3 local_origin;
    local_origin.read_float(local_player_addr + 0x1294);

    int local_team = process::read_int32(local_player_addr + 0x3CB);

    vec2 view_angles = vec2(view_pitch, view_yaw);
    int best = select_target(entity_list_addr, local_team,
                              local_origin, view_angles,
                              double(ui::get(aim_fov)), 500.0f);
    if (best < 0) return;

    uint64 ent      = source2::get_controller(entity_list_addr, uint64(best));
    int    bone_idx = aim_bone(int(ui::get(aim_bone_sel)));

    vec3 bone_pos = read_bone_cs2(ent, bone_idx); // USER CODE — see the echo-esp agent for the bone reader
    vec3 vel      = read_velocity(ent);
    float dist    = bone_pos.distance(local_origin);
    vec3 pred     = predict_pos(bone_pos, vel, dist, 1500.0f); // verify bullet speed

    vec2 tgt = math::calculate_angle(local_origin, pred);
    float dp = float(math::angle_diff(view_pitch, tgt.x));
    float dy = float(math::angle_diff(view_yaw,   tgt.y));
    apply_recoil(local_player_addr, dp, dy, dp, dy);

    // Cap per-tick movement (user code — math::clamp_angles only normalizes pitch/yaw range)
    float max_step = 15.0f;
    dp = clampf(dp, -max_step, max_step);
    dy = clampf(dy, -max_step, max_step);

    float mx, my;
    smooth_linear(dp, dy, float(ui::get(aim_smooth)), mx, my);
    mx += jitter(); my += jitter();
    move_mouse_relative(mx, my);

    if (ui::get(triggerbot_on)) {
        double cur_fov = fov_to_target(view_angles, pred, local_origin);
        triggerbot_tick(cur_fov);
    }
}

void on_unload() { process::detach(); }
```

## Recoil Control System (RCS standalone)

RCS compensates for weapon spray by reading the punch angles and counteracting them with mouse
movement — independent of the aim lock.

```angelscript
float g_last_punch_pitch = 0.0f;
float g_last_punch_yaw   = 0.0f;

void rcs_tick(uint64 local_player) {
    float punch_pitch = process::read_float(local_player + OFF_PUNCH_PITCH) * 2.0f;
    float punch_yaw   = process::read_float(local_player + OFF_PUNCH_YAW)   * 2.0f;

    // Delta from last tick — compensate only the *change*, not the whole angle
    float dp = punch_pitch - g_last_punch_pitch;
    float dy = punch_yaw   - g_last_punch_yaw;
    g_last_punch_pitch = punch_pitch;
    g_last_punch_yaw   = punch_yaw;

    if (dp > -0.01f && dp < 0.01f && dy > -0.01f && dy < 0.01f) return; // no new recoil

    float sens = 1.0f * 0.022f;   // verify per game
    float mx   = -(dy / sens);
    float my   = -(dp / sens);
    move_mouse_relative(clampf(mx, -25.0f, 25.0f), clampf(my, -25.0f, 25.0f));
}
```

## Assist vs. precision modes

```angelscript
combobox aim_mode;   // {"Assist", "Precision"}

bool is_precision_mode() { return int(ui::get(aim_mode)) == 1; }

// Assist: small FOV, heavy smoothing, hold key only
// Precision: wide FOV, fast tracking, always on
void aim_tick() {
    double fov_limit = is_precision_mode() ? 180.0 : double(ui::get(aim_fov));
    float  smooth    = is_precision_mode() ? 1.0f : float(ui::get(aim_smooth));
    bool   key_held  = is_precision_mode() ? true : input::key_active(0x02);
    if (!key_held) return;

    // ...select target, calc angle delta dp, dy...

    float max_step = is_precision_mode() ? 45.0f : 10.0f;
    dp = clampf(dp, -max_step, max_step);
    dy = clampf(dy, -max_step, max_step);

    float mx = (dy / smooth) / (1.0f * 0.022f);
    float my = (dp / smooth) / (1.0f * 0.022f);
    if (!is_precision_mode()) { mx += jitter(); my += jitter(); }
    move_mouse_relative(mx, my);
}
```

## Autofire with burst timing

Autofire holds LMB while on target. Burst mode fires N rounds, then pauses to reset spray.

```angelscript
const int  BURST_SIZE   = 3;     // rounds per burst
const uint BURST_GAP_MS = 200;   // pause between bursts (ms)
const uint RELEASE_MS   = 40;    // how long the trigger stays down (ms)

int    g_burst_count = 0;
uint64 g_burst_last  = 0;
uint64 g_release_at  = 0;        // 0 = trigger not held

void autofire_tick(double fov_to_best) {
    bool on_target = fov_to_best < 0.6;
    uint64 now = util::time_now();

    // The trigger release is a time gate on this same tick — the API has no sleep.
    if (g_release_at != 0 && now >= g_release_at) {
        input::mouse_release();
        g_release_at = 0;
    }

    if (!on_target) {
        if (g_release_at != 0) { input::mouse_release(); g_release_at = 0; }
        g_burst_count = 0; // reset burst on lost target
        return;
    }

    if (g_release_at != 0) return;   // one shot at a time

    // Burst mode: fire BURST_SIZE shots, then pause
    if (g_burst_count >= BURST_SIZE) {
        if (float(now - g_burst_last) < float(BURST_GAP_MS)) return;
        g_burst_count = 0;
    }

    input::mouse_press();
    g_release_at = now + RELEASE_MS;

    g_burst_count++;
    g_burst_last = now;
}

// Continuous mode (no burst limit):
void autofire_continuous(double fov_to_best) {
    if (fov_to_best < 0.5) input::mouse_click();
}
```

## Dev tips

- 128 tps gives ~8ms per tick; aim assist needs a high rate for responsiveness.
- Always read view angles fresh each tick — stale angles cause snapping.
- `smooth_linear` with factor ~5–8 feels natural; tweak per sensitivity.
- For DPI-agnostic movement: compute the exact angle delta and divide by `(sens * yaw_factor)` rather than using pixel heuristics.
- `input::mouse_move` is absolute — always read `input::mouse_pos` first when you need relative movement.
- For UE games use `math::unreal_calculate_angle` — it handles FRotator's inverted pitch convention correctly.
- Prefer `input::key_active(vk)` for hold-mode; `input::key_toggled(vk)` reflects OS toggle keys (caps lock), not press toggles.
- Combine with echo-esp agent for shared entity data via a shared mutex-protected array.
- Verify every offset and signature against a live build before shipping; re-check after each game patch.
