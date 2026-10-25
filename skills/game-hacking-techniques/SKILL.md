---
name: game-hacking-techniques
description: Core techniques for process memory access, overlay rendering, and feature implementation in an external/overlay model: entity list traversal, pointer chains, struct recovery, ESP math, and aimbot geometry. Use when implementing a technique and need the canonical pattern for it.
---

# Game Hacking Techniques Reference

Core techniques for process memory exploitation, overlay rendering, and cheat feature implementation. Echo uses the external/overlay approach throughout.

> **Offsets, patterns and layout constants in this document are ILLUSTRATIVE PLACEHOLDERS.**
> They describe the shape of each access, not a current build. Re-verify every one of them
> against your target after each game patch.

---

## Memory access models

### External (Echo's model)
- Separate process uses `OpenProcess` + `ReadProcessMemory` / `WriteProcessMemory`
- No code injected into game
- Detectable via handle table scanning (kernel AC drivers)
- Echo wraps this: `process::read_uint64(addr)`, `process::read_float(addr)`, `process::write_float(addr, v)`

```angelscript
attach_data ad = process::attach("game.exe");
if (ad.pid == 0) return false;

uint64 hp = process::read_uint64(entity + 0x330);
float   fov = process::read_float(entity + 0x1A0);
```

### Internal
- DLL injected into game process
- Runs with game's privileges and address space
- Detectable via injected-region scanning, NMI callbacks, module list
- Echo doesn't use this; see injection section below for reference

### DMA / FPGA
- Hardware PCIe DMA card (PCILeech, FPGA boards)
- Reads physical memory directly, bypassing OS
- No software handle visible to AC kernel drivers
- `MemProcFS` provides a VFS abstraction over DMA hardware
- Closest software analogy: Echo's external read is logically similar but uses OS APIs

---

## Injection methods (reference, for when external is insufficient)

From awesome-game-security:

| Method | Description | Detection risk |
|--------|-------------|----------------|
| Manual mapping | Map DLL without OS loader; no module list entry | Medium |
| Reflective loading | DLL loads itself; no disk file needed | Medium |
| PTE manipulation | Mark pages as User-accessible from kernel | High capability, kernel required |
| APC injection | Queue APC to target thread's APC queue | Medium |
| KeUserModeCallBack | Trigger callback from kernel to user-mode | Kernel required |
| Early cascade | Inject before process fully initialized | Low |
| Page table injection (DXInject) | GPU payload transport | Research-only |

Key repos: `btbd/smap`, `can1357/ThePerfectInjector`, `dumbasPL/fumo_loader`, `Broihon/GH-Injector-Library`

---

## Hook types

| Hook | Where | How | Risk |
|------|-------|-----|------|
| VMT | Object's virtual function table | Replace vftable pointer | Medium |
| IAT | Import Address Table | Patch import entry | Low |
| Inline / trampoline | Overwrite function prologue with JMP | Medium |
| EPT | Extended Page Tables (hypervisor) | Very stealthy; HV required | Low (hard to detect) |
| Syscall | NtXxx stubs in ntdll | Intercept at syscall number | Medium-High |

For DX overlay hooks (for non-Echo overlays): `ThirteenAG/UniversalD3DHook11`, `rdbo/kiero`, `JustasMasiulis/overlay-unhook`

---

## Entity list patterns per engine

### Source 2 (CS2, Dota 2)
```
GameEntitySystem → m_pEntityList (ptr)
  chunk[i] = read(entity_list + (i >> 9) * 8)
  entity   = read(chunk + (i & 0x1FF) * 120)
Max 512 entities (index 0–511); local player typically at index 0.
```

### Unreal Engine 4/5
```
GWorld → UWorld.PersistentLevel → ULevel.AActors (TArray<AActor*>)
TArray { Data: ptr, Num: int32, Max: int32 }
Access: entity = read(actors_data + i * 8)
For UObjects: GObjects array (TUObjectArray / FChunkedFixedUObjectArray)
```

### Unity (IL2CPP / Mono)
```
IL2CPP: il2cpp_domain_get_assemblies → find Assembly-CSharp → find type/class
Mono: mono_domain_get → mono_thread_attach → navigate IL2Cpp metadata
Easier: use Il2CppDumper to get field offsets, then read directly.
Transform hierarchy: Object.FindObjectsOfType<T> equivalent via Il2Cpp APIs
```

### IW Engine (CoD)
```
ClientState array at static offset in game module
Entity array: clientstate + entity_array_offset, stride = sizeof(centity_t)
Bone matrix: entity + bone_matrix_offset; 12 floats per bone (3x4 row-major)
```

---

## Overlay approaches

| Approach | Risk | How |
|----------|------|-----|
| Discord overlay (Echo) | Very low | Discord compositor, whitelisted by most ACs |
| DX hook (kiero/UniversalHookX) | Medium | Hook Present/ExecuteCommandLists |
| ReShade addon | Low-Medium | ReShade addon API |
| External transparent window | Low | Create topmost transparent HWND |
| GDI+ / DWM | Low | Desktop Window Manager compositing |

Echo renders through the Discord overlay, so all drawing goes through the `render::` namespace
and only from inside the render thread:

```angelscript
void render_tick() {
    vec2 vp = render::get_viewport_size();
    render::draw_box(100, 100, 200, 50, 255, 0, 0, 255, box_style::FILLED, 0.0f);
}
```

---

## ESP fundamentals

### World-to-screen projection
```
clip  = view_proj_matrix × world_pos (homogeneous multiply)
ndc.x = clip.x / clip.w
ndc.y = clip.y / clip.w
screen.x = (ndc.x + 1) * width  * 0.5
screen.y = (1 - ndc.y) * height * 0.5
```
Point is behind camera when `clip.w < 0`.

In Echo, use the per-engine helpers — they return `false` instead of exposing `clip.w`:

```angelscript
vec2 screen;
if (!source2::w2s(world_pos, view_matrix, screen)) continue;   // Source 2
if (!unity::w2s(world_pos, cam_matrix, screen)) continue;      // Unity
if (!unreal::w2s(world_pos, view_cache, screen)) continue;      // Unreal
```

For Unreal, `f_view_cache cache = build_view_cache(camera);` is built once per frame.

### Bounding box from bones
```
Project head bone (top) and feet bone (bottom).
Width = height * 0.45 (approximate for standing player).
For tight box: project all bones, use min/max of screen coords.
```

Echo can project an axis-aligned 3D box directly:

```angelscript
bbox_2d box = render::calculate_2d_bbox(origin, mins, maxs, view_matrix);
if (!box.valid) continue;
render::draw_box(int(box.x), int(box.y), int(box.width), int(box.height),
                 255, 0, 0, 255, box_style::OUTLINED, 0.0f);
```

### Bone rendering
Connect adjacent bones with lines. Per engine:
- Source 2: quaternion storage, use bone position only (skip rotation for ESP)
- Unreal: FTransform = 48 bytes (16 scale/pad + 16 quat + 16 translation)
- Unity: Matrix4x4, position is column 3

---

## Aimbot fundamentals

### Angle calculation
```
delta = target_pos - local_origin
pitch = -atan2(delta.z, sqrt(delta.x² + delta.y²)) in degrees
yaw   =  atan2(delta.y, delta.x) in degrees
```

Echo provides it natively:

```angelscript
vec2 aim = math::calculate_angle(local_pos, target_pos);   // vec2(pitch, yaw)
double dy = math::angle_diff(view_angles.y, aim.y);
```

### FOV filter
```
fov_to_target = sqrt((target_pitch - view_pitch)² + (target_yaw - view_yaw)²)
if fov_to_target > fov_limit: skip
```

```angelscript
double fov = math::calculate_fov(view_angles, aim_angles);   // degrees
if (fov > fov_limit) continue;
```

### Smoothing
```
Linear:      move = delta / smooth_factor
Exponential: move = current + (target - current) * rate
```

```angelscript
// Echo native: smooth the angle pair toward the target
vec2 next = math::smooth_angles(current, target, angle_range::R_180, 0.3, 1.0, 45.0);
```

### Velocity prediction
```
travel_time = distance / bullet_speed
predicted   = bone_pos + velocity * travel_time
```

---

## Pattern scanning

### IDA-style (used by Echo)
```
Pattern: "48 8B 05 ? ? ? ? 48 85 C0"
? = wildcard byte
Scan: iterate bytes, match opcode bytes exactly, skip wildcards
```

```angelscript
uint64 base = process::get_module_base("game.exe");
uint64 addr = process::find_signature(base, "48 8B 05 ? ? ? ? 48 85 C0");
if (addr == 0) { /* not found */ }
```

### Byte-mask style
```
Pattern: "\x48\x8B\x05\x00\x00\x00\x00\x48\x85\xC0"
Mask:    "xxx????xxx"
x = match, ? = wildcard
```

```angelscript
// 48 8B 05 ?? ?? ?? ?? 48 85 C0
uint64 addr = process::find_signature(base, "488B05000000004885C0", "xxx???xxxxx");
```

### SIMD-accelerated
Use SSE2/AVX2 to compare 16/32 bytes at once; Echo exposes the SSE intrinsics for this —
`mm_cmpeq_epi8`, `mm_cmpeq_epi16`, `mm_cmpeq_epi32`, `mm_xor_si128`, `mm_and_si128`,
`mm_or_si128`, plus byte extraction via `mm_extract_epi8` / `mm_extract_epi16`.
All of them take `array<uint8>` operands of exactly 16 bytes.

### Signature strategy
- Aim for 8+ stable bytes surrounding the wildcard region
- Prefer bytes from instruction opcodes (stable) over operand values (change each patch)
- Test pattern against multiple builds before shipping

---

## Anti-detection patterns

### Timing
- Read at fixed low rate (16–64 tps), not every render frame
- Add ±2 tps random jitter to break periodicity
- Don't trigger input at fixed intervals

### Behavioral (aimbot)
- Smooth all movements; never instant snap
- Add micro-jitter to mouse output (±0.2 px)
- Randomize triggerbot reaction time: 20–80ms random delay
- Cap mouse delta per tick: 15–20px max
- Occasionally miss targets (miss_chance random)

### Memory access
- Read only fields you need; avoid full struct dumps
- Avoid continuous writes to game memory
- Don't write to memory regions AC specifically monitors (cheater flags)

---

## Useful repos (from awesome-game-security)

- Pattern/sig tools: `SigMaker` IDA plugin, `pat` tool
- Offset automation: `UEDumper` (Unreal), `Il2CppDumper` (Unity), schema dump (CS2)
- RE helpers: `ReClass.NET` for struct visualization, `x64dbg` for dynamic analysis
- DX hooks: `rdbo/kiero`, `ThirteenAG/UniversalD3DHook11`
- Injection ref: `gmh5225/awesome-game-security` Injection section
