---
name: game-engine-resources
description: Engine-specific internal structures, naming conventions and offset-finding strategies for Source 2, Unreal, Unity and IW engine — struct layouts, bone formats, W2S math, and how to locate each field. Use when mapping engine internals for ESP or memory reads.
---

# Game Engine Internals Reference

Engine-specific internal structures, naming conventions, and offset-finding strategies for game hacking and reverse engineering. Used by echo-esp and echo-memory agents.

> **All offsets, patterns and layouts below are ILLUSTRATIVE PLACEHOLDERS.** They come from
> community dumps and are only correct for the build they were taken from. Every one of them
> needs **per-patch verification** against your target before you ship it — re-scan, re-dump,
> and diff after each game update.

---

## Source 2 (CS2, Dota 2, Deadlock)

### Entity system
```
CGameEntitySystem (singleton, accessed via pattern scan in client.dll)
  → m_pEntityList: pointer to entity chunk array
  → chunk[i]      = read(entity_list + (i >> 9) * 8)
  → entity[j]     = read(chunk + (j & 0x1FF) * 120)
  → full index:   i = (chunk_idx << 9) | slot_idx
  512 entities per chunk (slot_idx is 9 bits), not 512 entities total;
  local player usually at slot 0 of chunk 0
```

In Echo:

```angelscript
uint64 client = process::get_module_base("client.dll");
if (client == 0) return false;

uint64 sig = process::find_signature(client, "48 8B 0D ? ? ? ?");
if (sig == 0) return false;

// get_relative_address returns the ADDRESS OF the rip-relative operand,
// so read the pointer it points at to get the entity list itself.
uint64 rel = process::get_relative_address(sig, 3, 7);
uint64 entity_list = process::read_uint64(rel);
if (entity_list == 0) return false;
```

### Schema / NetVar system
```
CSchemaSystem (accessed via interface registry "SchemaSystem_001")
  → GetTypeScope("client.dll")
  → FindDeclaredClass("C_CSPlayerPawn")
  → GetFields() → field.name, field.offset, field.type
This gives authoritative offsets without pattern scanning.
Community schema dumps: cs2-dumper (GitHub), hazedumper
```

### Key entity offsets (CS2 — PLACEHOLDER, verify per update)
```
C_CSPlayerPawn:
  m_iHealth          +0x344  int32
  m_lifeState        +0x338  uint8  (0=alive)
  m_iTeamNum         +0x3CB  int32  (2=T, 3=CT)
  m_vOldOrigin       +0x1294 vec3
  m_vecVelocity      +0x1254 vec3
  m_iszPlayerName    +0x640  char[128]
  m_nSkeletonInstance+0x168  ptr → CSkeletonInstance
  m_aimPunchAngle    +0x1450 vec3 (punch pitch/yaw/roll)
  m_bSpotted         +0xF9B  bool
  m_pClippingWeapon  +0x1370 ptr

CSkeletonInstance:
  +0x80: ptr → bone transform array
  each entry: 0x20 bytes; pos at +0x10 (vec3, 12 bytes)
```

Reading one of them in Echo:

```angelscript
float hp = process::read_float(pawn + 0x344);   // PLACEHOLDER offset
int32 team = process::read_int32(pawn + 0x3CB);  // PLACEHOLDER offset
```

### View matrix
```
Located at a global in client.dll, accessible via pattern scan.
Pattern: "48 8D 05 ?? ?? ?? ?? 48 89 05 ?? ?? ?? ??"   ← PLACEHOLDER
process::get_relative_address(addr, 3, 7)  → address of the matrix pointer
Format: 4x4 row-major float[16]
```

In Echo:

```angelscript
uint64 vm_addr = process::find_signature(client, "48 8D 05 ?? ?? ?? ?? 48 89 05 ?? ?? ?? ??");
if (vm_addr == 0) return false;

// 48 8D 05 is a LEA — get_relative_address gives the address OF the
// pointer, so read it to get the matrix address.
uint64 vm_ptr = process::get_relative_address(vm_addr, 3, 7);
uint64 vm = process::read_uint64(vm_ptr);
if (vm == 0) return false;

matrix4x4 view_matrix;
if (!view_matrix.read(vm)) return false;   // read() returns bool
```

### ConVar system
```
ICvar interface → FindVar("sv_cheats") → GetBool()
Pattern scan for "sv_cheats" string → XREF → ICvar interface access
```

---

## Unreal Engine 4 / 5

### Object system
```
GObjects (FUObjectArray or TUObjectArray):
  Accessed via pattern scan for "GUObjectArray" export or direct scan
  FUObjectArray.ObjObjects: FChunkedFixedUObjectArray
    → ObjectChunks[chunk_idx][object_in_chunk]
  Each entry: UObjectBase* (8 bytes) + optional flags

GNames (FNamePool in UE5, FNameEntry in UE4):
  Stores all FName strings
  FName = { Index: uint32, Number: uint32 }
  FNamePool.Blocks[index >> 16][index & 0xFFFF] → FNameEntry → string
```

### World chain
```
GWorld (UWorld*):
  → PersistentLevel (ULevel*)
    → AActors (TArray<AActor*>): all actors in level
  → GameState (AGameStateBase*)
  → GameInstance (UGameInstance*)
    → LocalPlayers (TArray<ULocalPlayer*>)
      → PlayerController (APlayerController*)
        → PlayerCameraManager (APlayerCameraManager*)
          → CameraLocation (FVector)
          → CameraRotation (FRotator: pitch, yaw, roll)
          → FOVX (float)
```

### W2S for Unreal

Echo's `unreal::w2s` takes a view cache, not a camera-manager address. Build it once per frame:

```angelscript
f_view_info camera;
camera.location = cam_loc;    // vec3 from the camera manager
camera.rotation = cam_rot;    // FRotator (pitch, yaw, roll)
camera.fov = 90.0f;

f_view_cache cache = build_view_cache(camera);

vec2 screen;
if (!unreal::w2s(world_pos, cache, screen)) continue;
```

### Bone reading (USkeletalMeshComponent)
```
Actor → USkeletalMeshComponent (via component array or direct offset)
USkeletalMeshComponent:
  +0x580: SpaceBasesData (TArray<FTransform>)  ← bone world transforms   ← PLACEHOLDER
  +0x588: count                                            ← PLACEHOLDER

FTransform (48 bytes = 0x30):
  +0x00: FQuat rotation    (16 bytes: x,y,z,w)
  +0x10: FVector translation (12 bytes: x,y,z) + 4 pad
  +0x20: FVector scale3d   (12 bytes: x,y,z) + 4 pad

To get bone position: SpaceBasesData.Data[i].translation  (at +0x10)
```

Echo reads the transform through the `ftransform` type, or through the bone helper:

```angelscript
// Per-bone transform
ftransform tf;
tf.read(bone_address);
vec3 world = tf.transform_to_world(parent_tf);

// Or the whole bone array in one call (offsets are PLACEHOLDERS)
u_bone_array bones = unreal::read_bones(skeletal_mesh, 0x120, 0x128, 0x160);
if (!bones.valid()) return;
uint n = bones.count();
```

### SDK generation
```
1. Run game
2. Use UEDumper (or RE-UE4SS) to dump live UObjects
3. Output: C++ header files with class names, field names, offsets
4. Use as ground truth instead of manual pattern scanning
```

---

## Unity (Mono / IL2CPP)

### Mono (older Unity games)
```
mono_domain_get() → AppDomain
mono_domain_assembly_open() → Assembly
mono_class_from_name(image, namespace, class_name) → MonoClass
mono_class_get_field_from_name(class, "fieldName") → MonoClassField
mono_field_get_offset(field) → byte offset into object
```

### IL2CPP (modern Unity)
```
Game ships il2cpp.so / GameAssembly.dll (native code)
+ global-metadata.dat (metadata file)

Il2CppDumper output:
  dump.cs       → C# pseudocode with [FieldOffset(0x...)] annotations
  il2cpp.h      → C++ headers with struct layouts

From dump: find class → read field offset → process::read_uint32(obj_ptr + offset)
```

### Finding game objects (IL2CPP)
```
il2cpp_domain_get_assemblies() → find "Assembly-CSharp"
il2cpp_image_get_class_count() + il2cpp_image_get_class() → iterate all classes
Or: Il2CppDumper + static analysis → find entry point → trace static fields
```

### Unity W2S

Echo's `unity::w2s` takes the camera matrix:

```angelscript
matrix4x4 cam_matrix;
if (!cam_matrix.read(camera_addr + OFF_CAM_MATRIX)) continue;   // PLACEHOLDER offset

vec2 screen;
if (!unity::w2s(world_pos, cam_matrix, screen)) continue;
```

Camera-derived state:
```
Camera.main → Transform.position = camera world pos
Camera.worldToCameraMatrix → view matrix
Camera.projectionMatrix → projection matrix
view_proj = projection * worldToCamera
```

---

## IW Engine (Call of Duty)

```
ClientState: static array in the game module
  cs_base = game_module + CLIENT_STATE_OFFSET     ← PLACEHOLDER
  localClientNum = 0 (usually)

CG_t (client game state): cg_base = game_module + CG_STATIC_OFFSET   ← PLACEHOLDER
  cg_base + ORIGIN_OFFSET  → local player origin (vec3)
  cg_base + ANGLES_OFFSET  → local player angles (vec3)
  cg_base + REFDEF_OFFSET  → refdef struct (view matrix, FOV)

Entity array:
  cg_entities + entity_index * sizeof(centity_t)
  centity_t + ORIGIN_OFFSET  → vec3
  centity_t + BONE_OFFSET    → bone matrix array
  each bone: 3x4 matrix (12 floats = 48 bytes)

W2S: use the refdef view/projection matrix
```

Echo's `iw_engine::w2s` matches this layout directly:

```angelscript
matrix3x3 view_matrix;
if (!view_matrix.read(refdef + REFDEF_VIEW_OFFSET)) continue;   // PLACEHOLDER offset

vec2 screen;
if (!iw_engine::w2s(world_pos, camera_location, view_matrix, fov_x, fov_y, screen)) continue;
```

---

## Bone matrix formats

| Engine | Format | Size | Position location |
|--------|--------|------|-------------------|
| Source 2 | position + orientation (stored separately) | 0x20/entry | entry + 0x10 (vec3) |
| Unreal | FTransform (quat + translate + scale) | 48 bytes | entry + 0x10 (FVector translation) |
| Unity IL2CPP | 4x4 float matrix | 64 bytes | column 3 (indices 12,13,14) |
| IW (CoD) | 3x4 row-major rotation+translation | 48 bytes | last column (indices 3,7,11) |

---

## W2S math (manual implementation)

Use this only when no engine helper fits. It mirrors what `source2::w2s` / `unity::w2s` do
internally.

```angelscript
// Full clip-space → screen projection (user code)
bool world_to_screen(matrix4x4 vp, vec3 world_pos, vec2 &out screen) {
    float cx = vp[0][0] * world_pos.x + vp[1][0] * world_pos.y + vp[2][0] * world_pos.z + vp[3][0];
    float cy = vp[0][1] * world_pos.x + vp[1][1] * world_pos.y + vp[2][1] * world_pos.z + vp[3][1];
    float cw = vp[0][3] * world_pos.x + vp[1][3] * world_pos.y + vp[2][3] * world_pos.z + vp[3][3];
    if (cw < 0.001f) return false;   // behind camera

    vec2 size = render::get_viewport_size();
    float inv = 1.0f / cw;
    screen.x = (size.x * 0.5f) * (1.0f + cx * inv);
    screen.y = (size.y * 0.5f) * (1.0f - cy * inv);
    return true;
}
```

For axis-aligned 3D boxes Echo has a built-in projection. `render::calculate_2d_bbox` is a
render-thread call — run it from an `on_render` callback (only `render::get_fps`,
`render::get_viewport_size` and `render::is_foreground` may be called from any context):

```angelscript
void render_tick() {
    bbox_2d box = render::calculate_2d_bbox(origin, mins, maxs, view_matrix);
    if (!box.valid) return;
    // box.x, box.y, box.width, box.height
    render::draw_box(int(box.x), int(box.y), int(box.width), int(box.height),
                     255, 0, 0, 255, box_style::OUTLINED, 0.0f);
}

bool main() {
    on_render(@render_tick);
    return true;
}
```

---

## Offset tracking across updates

1. **Manual**: re-scan signatures after each game update. Test known-stable patterns against new build first.
2. **Schema dump** (Source 2): schema system contains authoritative offsets; dump via pattern scan + schema API.
3. **SDK generator** (Unreal): re-run UEDumper after update.
4. **IL2CppDumper** (Unity): re-run after update, diff the `dump.cs` output.
5. **mcp-gamehacking**: `read_subagent("binary-differ")` — automated offset delta across builds.
6. **Community dumps**: hazedumper, cs2-dumper (GitHub) publish offsets after each CS2 update — treat them as a starting point only.

---

## mcp-gamehacking queries

```
get_agent_briefing("cs2-specialist")
get_agent_briefing("unreal-engine-specialist")
get_agent_briefing("unity-specialist")
get_agent_briefing("source-engine-specialist")
read_subagent("bone-mapper")           → bone index tables per game
read_subagent("offset-finder")         → cross-reference offsets
search_skills("unreal GNames")
search_skills("unity il2cpp dumper")
```
