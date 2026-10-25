---
name: omath-math
description: The omath C++23 constexpr math framework mapped onto Echo AngelScript: world-to-screen per engine, projectile prediction, rotation and quaternion helpers, and coordinate-system differences for Source 2, Unreal, Unity and IW. Use when implementing or debugging projection and aim math.
---

# omath — Math Framework for Echo

**Source:** alt-orange/omath — C++23 constexpr math for game hacking; coordinate systems for Source 2, Unreal, Unity, Frostbite, IW, CryEngine.

This skill maps omath's formulas to Echo AngelScript equivalents. Echo provides `vec2`/`vec3`/`vec4`,
`matrix3x3`/`matrix3x4`/`matrix4x4`, the `math::*` helpers, and the W2S helpers
`source2::w2s`, `source::w2s`, `unreal::w2s`, `unity::w2s`, `iw_engine::w2s` natively; omath is the
reference for the underlying math.

---

## W2S per engine

Every Echo W2S helper has the same shape:

```angelscript
bool <engine>::w2s(vec3 world_pos, <view state>, vec2 &out screen_pos)
```

It writes the screen position into the out-parameter and returns `false` when the point is
off-screen or behind the camera. **Always check the return value** — the out-parameter is
meaningless on failure.

### Source 2 (`source2::w2s`)

```angelscript
// Echo native — needs a 4x4 view matrix
vec2 screen;
if (!source2::w2s(world_pos, view_matrix, screen)) continue;
// screen.x / screen.y are now in overlay pixels
```

The plain Source engine variant has the same signature:

```angelscript
vec2 screen;
if (!source::w2s(world_pos, view_matrix, screen)) continue;
```

omath implements Source 2 W2S as a view-projection matrix from camera angles + FOV:

```
// 1. Build view matrix from cam_ang (pitch/yaw/roll) — right-hand Y-up
// 2. Transform world_pos to view space
// 3. Perspective divide: sx = (vx/vz) * (w/2) * (1/tan(fov/2)) + w/2
```

**omath coordinate convention (Source 2):** right-hand, Y-forward, Z-up.
Echo's `source2::w2s` takes the already-built `matrix4x4`, so build it with
`math::rotation_matrix(rotation, origin)` and `math::multiply_matrix(a, b)`.

### Unreal Engine (`unreal::w2s`)

Unreal uses a **view cache**, not a raw matrix. Build it once per frame:

```angelscript
f_view_info camera;
camera.location = cam_loc;      // camera world position
camera.rotation = cam_rot;      // FRotator (pitch, yaw, roll)
camera.fov = 90.0f;

f_view_cache cache = build_view_cache(camera);          // vertical_fov = false
// f_view_cache cache = build_view_cache(camera, true);  // some games need vertical FOV

vec2 screen;
if (!unreal::w2s(world_pos, cache, screen)) continue;
```

omath's `unreal::w2s` reads from APlayerCameraManager (see `skills/dumper7-sdk.md`) for the
camera location, rotation and FOV; `f_view_info` is the Echo equivalent of that state.

omath formula reference:
```
// 1. Build rotation matrix from FRotator (pitch=-X, yaw=Z, roll=Y convention)
// 2. delta = world_pos - cam_loc
// 3. View-space coords via dot with each basis vector
// 4. sx = screen_w/2 * (1 + vy/vx * (1/tan(fov/2))) where vx = forward
```

### Unity (`unity::w2s`)

```angelscript
// omath::unity convention: left-hand, Y-up, Z-forward
// cam_matrix: Camera.worldToCameraMatrix (4x4) read from game memory
vec2 screen;
if (!unity::w2s(world_pos, cam_matrix, screen)) continue;
```

Unity-specific helpers exist too:

```angelscript
vec3 world_pos = unity::rust_transform_position(transform_address);
uint32 prefab_id = unity::rust_prefab_id("assets/bundled/prefabs/autospawn/resource/ores/stone-ore.prefab");
```

### IW engine (`iw_engine::w2s`)

```angelscript
// 3x3 rotation matrix: row0 = axis_forward, row1 = axis_right, row2 = axis_up
matrix3x3 view_matrix;
view_matrix.read(address);

vec2 screen;
if (!iw_engine::w2s(world_pos, camera_location, view_matrix, fov_x, fov_y, screen)) continue;
```

### Frostbite / CryEngine (manual)

Echo has no built-in for these. Use `matrix4x4`:

```angelscript
// Frostbite: read ViewProjMatrix (4x4) from GameRenderer
matrix4x4 vp;
vp.read(renderer + OFF_VIEWPROJMATRIX);

// matrix4x4 elements are plain floats: vp[row][col].
// The row/column order must match the engine's matrix layout
// (some engines store column-major, some row-major) — verify before relying on it.
float cx = vp[0][0] * world_pos.x + vp[1][0] * world_pos.y + vp[2][0] * world_pos.z + vp[3][0];
float cy = vp[0][1] * world_pos.x + vp[1][1] * world_pos.y + vp[2][1] * world_pos.z + vp[3][1];
float cw = vp[0][3] * world_pos.x + vp[1][3] * world_pos.y + vp[2][3] * world_pos.z + vp[3][3];
if (cw <= 0.0f) return;            // behind camera

vec2 vp_size = render::get_viewport_size();
float sx = (vp_size.x * 0.5f) * (1.0f + cx / cw);
float sy = (vp_size.y * 0.5f) * (1.0f - cy / cw);
```

---

## Angle and FOV helpers (Echo native)

Echo's `math::*` namespace covers most of what omath provides:

```angelscript
// Angle delta between two angles (shortest path)
double diff = math::angle_diff(a, b);

// Normalize an angle into a range
double n = math::normalize_angle(angle, angle_range::R_180);   // or angle_range::R_360

// FOV in degrees between two angle pairs
double fov = math::calculate_fov(angles_a, angles_b);

// Angles from one position to another (pitch, yaw)
vec2 aim = math::calculate_angle(my_pos, target_pos);

// Clamp pitch to valid range and normalize yaw
vec2 clamped = math::clamp_angles(raw_angles, angle_range::R_180);

// Direction vectors from angles
vec3 fwd = math::forward_vector(view_angles);
vec3 rgt = math::right_vector(view_angles);
vec3 up  = math::up_vector(view_angles);

// Vector <-> angles
vec2 ang = math::vec_to_angles(direction);
vec3 dir = math::angles_to_vec(ang);

// Matrix helpers
matrix4x4 rot = math::rotation_matrix(rotation, origin);
matrix4x4 mul = math::multiply_matrix(a, b);
vec3 rotated = math::rotated_vector(point, quaternion);

// Interpolation lives on the vector, not on math::
vec3 mid = a.lerp(b, 0.5);
```

### Smoothing

`math::smooth_angles` interpolates toward a target angle pair with configurable speed:

```angelscript
vec2 current = vec2(0.0f, 90.0f);
vec2 target  = vec2(10.0f, 120.0f);

double smoothing = 0.3;   // 0.0 = fast, 1.0 = slow
double min_speed = 1.0;   // 1.0 – 45.0
double max_speed = 45.0;  // 1.0 – 45.0

vec2 next = math::smooth_angles(current, target, angle_range::R_180, smoothing, min_speed, max_speed);
```

### Unreal-specific helpers

```angelscript
// FRotator (pitch, yaw, roll) -> pitch/yaw in radians
vec2 rad = math::unreal_rotation_to_radians(camera_rot);

// FOV in degrees between the current rotation and a world target
double fov = math::unreal_calculate_fov(camera_rot, camera_pos, target_pos);

// Direct angle delta in degrees to add to the current rotation
vec2 delta = math::unreal_calculate_angle(camera_rot, camera_pos, target_pos);

// Smoothed deltas in radians to add to the current rotation
vec2 smooth = math::unreal_smooth_rotation(camera_rot, camera_pos, target_pos, 0.3, 1.0, 45.0);
```

---

## Projectile prediction (`O(N)`)

omath uses iterative Euler integration for bullet travel time. Echo equivalent (user code):

```angelscript
// Predict where to aim at to hit a moving target
vec3 predict_aim(vec3 target_pos, vec3 target_vel,
                 vec3 shooter_pos, float bullet_speed,
                 int max_iter = 8) {
    vec3 aim = target_pos;
    for (int i = 0; i < max_iter; i++) {
        float dist = aim.distance(shooter_pos);
        float t    = dist / bullet_speed;
        aim        = target_pos.add(target_vel.multiply(t));
    }
    return aim;
}
```

omath's `projectile_prediction` is identical — O(N) iterations with N typically 4–8.

---

## `ExternalReverseEngineeredObject<Trait>` — Echo equivalent

omath's template wraps a base address with typed field accessors. Echo replaces this with
`process::read_*` (user code below):

```angelscript
// omath: auto player = ExternalReverseEngineeredObject<PlayerTrait>(handle, addr);
//        float hp    = player.get<float>(PlayerTrait::health_offset);

// Echo equivalent (user code):
class Player {
    uint64 addr;
    Player(uint64 a) { addr = a; }
    float health()   { return process::read_float(addr + 0x330); }
    vec3  position() { vec3 p; p.read_float(addr + 0x138); return p; }
    int   team()     { return process::read_int32(addr + 0x3B8); }
}
```

`vec3.read_float(address)` reads three floats from the attached process at that address.

---

## Byte pattern scanning

omath's scanner finds a byte pattern in a memory region and returns the offset. Echo's
`process::find_signature` does this per module:

```angelscript
// IDA-style pattern (wildcards are ? or ??)
uint64 base = process::get_module_base("game.exe");
uint64 result = process::find_signature(base, "48 8B 05 ? ? ? ? 48 8B 0C C8");

// Byte-mask style: sig holds the bytes, mask uses x for match and ? for wildcard
// 48 8B 05 ?? ?? ?? ?? 48 8B 0C C8
uint64 masked = process::find_signature(base, "488B0500000000488B0CC8", "xxx???xxxxxx");

// All matches in a module
array<uint64>@ all = process::find_signatures(base, "48 8B 0D ? ? ? ?");
if (all is null) { /* no match */ }
```

To enumerate regions, walk the address space with `process::virtual_query`:

```angelscript
// user code: enumerate the mapped regions of the target
uint64 addr = 0;
while (addr < 0x7FFFFFFFFFFF) {
    memory_region r = process::virtual_query(addr);
    if (r.size == 0) break;
    // r.base, r.size, r.present, r.writable, r.executable
    addr = r.base + r.size;
}
```

---

## UE name resolution (FNamePool)

omath ships its own FName resolver (an omath function, not part of the Echo API) — see
`skills/dumper7-sdk.md` for the full Echo implementation. Summary:

```angelscript
// fname_index = process::read_uint32(uobject + 0x18)
// chunk_i = (fname_index >> 16) & 0xFF
// idx_i   = fname_index & 0xFFFF
// chunk   = process::read_uint64(pool + 0x10 + chunk_i * 8)
// name starts at chunk + idx_i * stride + 2 (skip 2-byte header)
```

---

## DX/GL hooking (omath reference — not Echo)

omath provides a hook helper for DX11/DX12/GL Present/EndFrame. Echo does **not** inject, so DX hooking is out of scope. Reference for when building external overlay alternatives:

- DX11: hook `IDXGISwapChain::Present` vtable[8]
- DX12: hook `IDXGISwapChain3::Present` vtable[8]
- Echo uses Discord overlay — DX hooking is Discord's job, not Echo's

---

## Rotation math helpers

`math::*` covers most of this natively. If you need your own (user code):

```angelscript
// Clamp and normalize angles (omath::angle_normalize equivalent)
float normalize_angle(float a) {
    while (a >  180.0f) a -= 360.0f;
    while (a < -180.0f) a += 360.0f;
    return a;
}

// Angle delta for aimbot smoothing
vec3 angle_delta(vec3 from_ang, vec3 to_ang) {
    vec3 d;
    d.x = normalize_angle(to_ang.x - from_ang.x);
    d.y = normalize_angle(to_ang.y - from_ang.y);
    d.z = 0.0f;
    return d;
}

// World position -> aim angles (omath::calc_angle)
// Echo's native math::calculate_angle does exactly this and returns vec2(pitch, yaw)
vec2 calc_angle(vec3 src, vec3 dst) {
    return math::calculate_angle(src, dst);
}
```

Prefer the native `math::calculate_angle(from, to)` and `math::angle_diff(a, b)` when they fit.

---

## FOV check (omath aimbot filter)

omath filters targets by angular distance from the crosshair — the same pattern Echo's aimbot uses:

```angelscript
// Return angular distance in degrees from local_ang to target
float fov_to_target(vec2 local_ang, vec3 local_pos, vec3 target_pos) {
    vec2 aim = math::calculate_angle(local_pos, target_pos);
    return float(math::calculate_fov(local_ang, aim));
}

// In entity loop:
if (fov_to_target(view_ang, local_pos, enemy_pos) > fov_radius) continue;
```

`math::calculate_fov(a, b)` returns the FOV in degrees between two angle pairs directly, when
both angles are already known.
