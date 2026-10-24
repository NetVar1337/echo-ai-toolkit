# Game Engine Internals Reference

Engine-specific internal structures, naming conventions, and offset-finding strategies for game hacking and reverse engineering. Used by echo-esp and echo-memory agents.

---

## Source 2 (CS2, Dota 2, Deadlock)

### Entity system
```
CGameEntitySystem (singleton, accessed via pattern scan in client.dll)
  → m_pEntityList: pointer to entity chunk array
  → chunk[i]      = read(entity_list + (i >> 9) * 8)
  → entity[j]     = read(chunk + (j & 0x1FF) * 120)
  → full index:   i = (chunk_idx << 9) | slot_idx
  max 512 entities; local player usually at slot 0 of chunk 0
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

### Key entity offsets (CS2, verify per update)
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

### View matrix
```
Located at a global in client.dll, accessible via pattern scan.
Pattern: "48 8D 05 ?? ?? ?? ?? 48 89 05 ?? ?? ?? ??"
resolve_rip(addr, 3, 7)
Format: 4x4 row-major float[16]
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
```
Use APlayerCameraManager for camera position/rotation/FOV.
Build projection matrix from FOV, aspect ratio.
Or: use Echo's built-in unreal.w2s(proc, camera_manager_addr, world_pos, sx, sy)
```

### Bone reading (USkeletalMeshComponent)
```
Actor → USkeletalMeshComponent (via component array or direct offset)
USkeletalMeshComponent:
  +0x580: SpaceBasesData (TArray<FTransform>)  ← bone world transforms
  +0x588: count

FTransform (48 bytes):
  +0x00: FQuat scale     (16 bytes: x,y,z,w)   ← actually scale in UE4+
  +0x10: FQuat rotation  (16 bytes: x,y,z,w)
  +0x20: FVector translation (12 bytes: x,y,z) + 4 pad

To get bone position: SpaceBasesData.Data[i].translation
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
  
From dump: find class → read field offset → proc.read<T>(obj_ptr + offset)
```

### Finding game objects (IL2CPP)
```
il2cpp_domain_get_assemblies() → find "Assembly-CSharp"
il2cpp_image_get_class_count() + il2cpp_image_get_class() → iterate all classes
Or: Il2CppDumper + static analysis → find entry point → trace static fields
```

### Unity W2S
```
Camera.main → Transform.position = camera world pos
Camera.worldToCameraMatrix → view matrix
Camera.projectionMatrix → projection matrix
view_proj = projection * worldToCamera
Then standard clip → NDC → screen projection
Echo: unity.w2s(proc, camera_addr, world_pos, sx, sy)
```

---

## IW Engine (Call of Duty)

```
ClientState: static array in the game module
  cs_base = game_module + CLIENT_STATE_OFFSET
  localClientNum = 0 (usually)

CG_t (client game state): cg_base = game_module + CG_STATIC_OFFSET
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

---

## Bone matrix formats

| Engine | Format | Size | Position location |
|--------|--------|------|-------------------|
| Source 2 | position + orientation (stored separately) | 0x20/entry | entry + 0x10 (vec3) |
| Unreal | FTransform (scale+quat+translate) | 48 bytes | entry + 0x20 (FVector) |
| Unity IL2CPP | 4x4 float matrix | 64 bytes | column 3 (indices 12,13,14) |
| IW (CoD) | 3x4 row-major rotation+translation | 48 bytes | last column (indices 3,7,11) |

---

## W2S math (manual implementation)

```angelscript
// Full clip-space → screen projection
bool world_to_screen(float vp[16], float wx, float wy, float wz,
                     float& sx, float& sy, float w, float h) {
    float cx = vp[0]*wx + vp[4]*wy + vp[8]*wz  + vp[12];
    float cy = vp[1]*wx + vp[5]*wy + vp[9]*wz  + vp[13];
    float cw = vp[3]*wx + vp[7]*wy + vp[11]*wz + vp[15];
    if (cw < 0.001f) return false;
    float inv = 1.0f / cw;
    sx = (w  * 0.5f) * (1.0f + cx * inv);
    sy = (h  * 0.5f) * (1.0f - cy * inv);
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
6. **Community dumps**: hazedumper, cs2-dumper (GitHub) publish offsets after each CS2 update.

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
