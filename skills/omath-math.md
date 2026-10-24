# omath — Math Framework for Echo

**Source:** alt-orange/omath — C++23 constexpr math for game hacking; coordinate systems for Source 2, Unreal, Unity, Frostbite, IW, CryEngine.

This skill maps omath's formulas to Echo AngelScript equivalents. Echo provides `vec2/3/4`, `mat4x4`, and the W2S helpers `source2.w2s`, `unreal.w2s`, `unity.w2s` natively; omath is the reference for the underlying math.

---

## W2S per engine

### Source 2 (`source2.w2s`)

omath implements Source 2 W2S as a view-projection matrix from camera angles + FOV:

```angelscript
// Echo native:
vec2@ screen = source2.w2s(world_pos, cam_pos, cam_ang, fov, screen_w, screen_h);
if (screen.z < 0) return; // behind camera

// Manual equivalent (matches omath::source2::w2s):
// 1. Build view matrix from cam_ang (pitch/yaw/roll) — right-hand Y-up
// 2. Transform world_pos to view space
// 3. Perspective divide: sx = (vx/vz) * (w/2) * (1/tan(fov/2)) + w/2
```

**omath coordinate convention (Source 2):** right-hand, Y-forward, Z-up.  
Echo's `source2.w2s` matches this; pass `cam_ang` as Echo `vec3(pitch, yaw, 0)`.

### Unreal Engine (`unreal.w2s`)

omath's `unreal::w2s` reads from APlayerCameraManager (see `skills/dumper7-sdk.md`):

```angelscript
// Echo native — requires cam_loc, cam_rot (FRotator: pitch/yaw/roll), fov
vec2@ screen = unreal.w2s(world_pos, cam_loc, cam_rot, fov, screen_w, screen_h);
if (screen.z < 0) return;

// omath formula reference:
// 1. Build rotation matrix from FRotator (pitch=-X, yaw=Z, roll=Y convention)
// 2. delta = world_pos - cam_loc
// 3. View-space coords via dot with each basis vector
// 4. sx = screen_w/2 * (1 + vy/vx * (1/tan(fov/2))) where vx = forward
```

### Unity (`unity.w2s`)

```angelscript
// omath::unity convention: left-hand, Y-up, Z-forward
vec2@ screen = unity.w2s(world_pos, cam_matrix, fov, screen_w, screen_h);
// cam_matrix: Camera.worldToCameraMatrix (4x4) read from game memory
```

### Frostbite / IW / CryEngine (manual)

omath provides separate functions; Echo has no built-in for these. Use `mat4x4`:

```angelscript
// Frostbite: read ViewProjMatrix (row-major, 4x4) from GameRenderer
mat4x4@ vp = proc.read<mat4x4>(renderer + OFF_VIEWPROJMATRIX);
vec4 clip = vp * vec4(world_pos, 1.0);
if (clip.w <= 0) return;
float sx = (clip.x / clip.w + 1.0) * screen_w * 0.5;
float sy = (1.0 - clip.y / clip.w) * screen_h * 0.5;
```

---

## Projectile prediction (`O(N)`)

omath uses iterative Euler integration for bullet travel time. Echo equivalent:

```angelscript
// Predict where to aim at to hit a moving target
vec3 predict_aim(vec3 target_pos, vec3 target_vel,
                 vec3 shooter_pos, float bullet_speed,
                 int max_iter = 8) {
    vec3 aim = target_pos;
    for (int i = 0; i < max_iter; i++) {
        float dist = (aim - shooter_pos).length();
        float t    = dist / bullet_speed;
        aim        = target_pos + target_vel * t;
    }
    return aim;
}
```

omath's `projectile_prediction` is identical — O(N) iterations with N typically 4–8.

---

## `ExternalReverseEngineeredObject<Trait>` — Echo equivalent

omath's template wraps a base address with typed field accessors. Echo replaces this with proc.read:

```angelscript
// omath: auto player = ExternalReverseEngineeredObject<PlayerTrait>(proc, addr);
//        float hp    = player.get<float>(PlayerTrait::health_offset);

// Echo equivalent:
class Player {
    uint64 addr;
    Player(uint64 a) { addr = a; }
    float health()   { return proc.read<float>(addr + 0x330); }
    vec3  position() { vec3@ p; p.read(proc, addr + 0x138); return p; }
    int   team()     { return proc.read<int32>(addr + 0x3B8); }
}
```

---

## Byte pattern scanning

omath's scanner: find a byte pattern in a memory region, returning offset.

```angelscript
// omath equivalent: scan module for IDA-style pattern
uint64 result = proc.scan_ida("48 8B 05 ? ? ? ? 48 8B 0C C8", "game.exe");

// For scanning heap regions (not a named module):
array<region_info>@ regions = proc.query_regions();
for (uint i = 0; i < regions.length(); i++) {
    uint64 hit = proc.scan(/* raw bytes */, regions[i].base, regions[i].size);
    if (hit != 0) { /* found */ break; }
}
```

---

## UE name resolution (FNamePool)

omath `unreal::resolve_name(pool, fname_index)` — see `skills/dumper7-sdk.md` for the full Echo implementation. Summary:

```angelscript
// fname_index = proc.read<uint32>(uobject + 0x18)
// chunk_i = (fname_index >> 16) & 0xFF
// idx_i   = fname_index & 0xFFFF
// chunk   = proc.read<uint64>(pool + 0x10 + chunk_i * 8)
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

```angelscript
// Clamp and normalize angles (omath::angle_normalize equivalent)
float normalize_angle(float a) {
    while (a >  180.0) a -= 360.0;
    while (a < -180.0) a += 360.0;
    return a;
}

// Angle delta for aimbot smoothing
vec3 angle_delta(vec3 from_ang, vec3 to_ang) {
    vec3 d;
    d.x = normalize_angle(to_ang.x - from_ang.x);
    d.y = normalize_angle(to_ang.y - from_ang.y);
    d.z = 0;
    return d;
}

// World position → aim angles (omath::calc_angle)
vec3 calc_angle(vec3 src, vec3 dst) {
    vec3 d = dst - src;
    float dist = math.sqrt(d.x*d.x + d.y*d.y);
    vec3 ang;
    ang.x = math.atan2(-d.z, dist) * (180.0 / math.PI);
    ang.y = math.atan2(d.y, d.x)   * (180.0 / math.PI);
    ang.z = 0;
    return ang;
}
```

---

## FOV check (omath aimbot filter)

omath filters targets by angular distance from crosshair — the same pattern Echo's aimbot uses:

```angelscript
// Return angular distance in degrees from local_ang to target
float fov_to_target(vec3 local_ang, vec3 local_pos, vec3 target_pos) {
    vec3 aim = calc_angle(local_pos, target_pos);
    float dx = normalize_angle(aim.x - local_ang.x);
    float dy = normalize_angle(aim.y - local_ang.y);
    return math.sqrt(dx*dx + dy*dy);
}

// In entity loop:
if (fov_to_target(view_ang, local_pos, enemy_pos) > fov_radius) continue;
```
