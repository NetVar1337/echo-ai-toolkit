---
name: dumper7-sdk
description: Dumper-7 and Dumper-7-VGK SDK generation for UE4/UE5: GObjects traversal, FName resolution, FTransform layout, bone arrays, Valorant's encrypted GObjects pointer, and how to cache bone reads. Use when generating or consuming a UE SDK, or wiring one into Echo with unreal::read_bones.
---

# Dumper-7 SDK Reference

**Dumper-7** (Encryqed/Dumper-7): UE4 + UE5 SDK generator. Inject DLL → walks live GObjects/FNames → generates C++ headers with every class, struct, and offset found.

**Dumper-7-VGK** (sinistercodes/Dumper-7-VGK): fork that adds Valorant support, working around Vanguard's encrypted GObjects pointer.

> **Every offset below is a PLACEHOLDER taken from a specific build.** Copy them from your own
> freshly generated SDK headers and **re-verify after each game patch** — offsets shift between
> updates, and the values here are only here to show the shape of the access.

---

## SDK output structure

```
C:\Dumper-7\<GameName>-<BuildVersion>\
  CppSDK\
    SDK_HEADERS\
      Engine_classes.hpp       ← AActor, UObject, USceneComponent, APlayerController, etc.
      Engine_structs.hpp       ← FVector, FRotator, FQuat, FTransform, FName, TArray, etc.
      Engine_parameters.hpp    ← function parameter structs
      ShooterGame_classes.hpp  ← game-specific pawns, weapons, game modes
      ShooterGame_structs.hpp
      ...                      ← one file pair per UE package
    BasicObjects.hpp           ← minimal forward declarations
    SDK.hpp                    ← master include
```

### Reading offsets from generated headers

```cpp
// Engine_classes.hpp excerpt:
class AActor : public UObject {
public:
    static constexpr auto OFFSET_RootComponent        = 0x130;
    static constexpr auto OFFSET_CustomTimeDilation   = 0x168;
    static constexpr auto OFFSET_bHidden              = 0x1A4;

    USceneComponent*& RootComponent() {
        return *reinterpret_cast<USceneComponent**>(
            reinterpret_cast<uintptr_t>(this) + OFFSET_RootComponent);
    }
};

// Engine_structs.hpp excerpt:
struct FTransform {
    // offset 0x00  Rotation    (FQuat,    16 bytes) — quaternion
    // offset 0x10  Translation (FVector,  12 bytes) — WORLD POSITION
    // offset 0x20  Scale3D     (FVector,  12 bytes)
    // Total: 0x30 (48 bytes) — same in UE4 and UE5
};
```

---

## Using Dumper-7 offsets in Echo AngelScript

```angelscript
// ── Offset constants (PLACEHOLDERS — copy from your own SDK headers) ────────
const uint32 OFF_ROOTCOMPONENT      = 0x130;  // AActor
const uint32 OFF_COMPONENTTOWORLD   = 0x1C0;  // USceneComponent
const uint32 OFF_FTRANSFORM_TRANS   = 0x10;   // FTransform::Translation
const uint32 OFF_TEAMNUM            = 0x3B8;  // APawn / APlayerState
const uint32 OFF_HEALTH             = 0x330;  // game-specific

// ── Read actor world position ────────────────────────────────────────────────
uint64 get_actor_location(uint64 actor) {
    uint64 root = process::read_uint64(actor + OFF_ROOTCOMPONENT);
    if (root == 0) return 0;

    // FTransform is 48 bytes; translation is at +0x10 inside it
    uint64 transform = root + OFF_COMPONENTTOWORLD;
    return transform;   // caller reads the vec3 at transform + OFF_FTRANSFORM_TRANS
}

// Read the translation as a vec3
vec3 get_actor_pos(uint64 actor) {
    uint64 root = process::read_uint64(actor + OFF_ROOTCOMPONENT);
    if (root == 0) return vec3();

    vec3 loc;
    loc.read_float(root + OFF_COMPONENTTOWORLD + OFF_FTRANSFORM_TRANS);
    return loc;
}
```

---

## GObjects traversal (FChunkedFixedUObjectArray, UE4.21+)

```angelscript
// Layout:
//   GObjects +0x00  Objects     (uint64 → chunk ptr array)
//   GObjects +0x10  MaxElements (int32)
//   GObjects +0x14  NumElements (int32)
//   GObjects +0x18  MaxChunks   (int32)
//   GObjects +0x1C  NumChunks   (int32)
// Chunk: array of FUObjectItem (0x18 bytes each)
//   FUObjectItem +0x00 = Object* (UObject*)

uint64 game = process::get_module_base("game.exe");
if (game == 0) return false;

uint64 gobjects_sig = process::find_signature(game, "48 8B 05 ? ? ? ? 48 8B 0C C8 48 8D 04 D1");
if (gobjects_sig == 0) return false;

uint64 gobjects   = process::get_relative_address(gobjects_sig, 3, 7);
uint64 chunks_ptr = process::read_uint64(gobjects + 0x00);
uint32 num        = process::read_uint32(gobjects + 0x14);

for (uint32 i = 0; i < num; i++) {
    uint32 ci  = i / 0x10000;
    uint32 oi  = i % 0x10000;
    uint64 chk = process::read_uint64(chunks_ptr + uint64(ci) * 8);
    if (chk == 0) continue;
    uint64 obj = process::read_uint64(chk + uint64(oi) * 0x18);
    if (obj == 0) continue;
    // UObject* — UObject+0x00=vtable, +0x18=FName.Index (uint32)
}
```

---

## FName resolution (FNamePool, UE4.23+)

```angelscript
// FNamePool base via signature
uint64 game = process::get_module_base("game.exe");
uint64 pool_sig = process::find_signature(game, "48 8D 35 ? ? ? ? EB ? 48 8D 0D");
if (pool_sig == 0) return false;
uint64 pool = process::get_relative_address(pool_sig, 3, 7);

// Read FName from a UObject
uint32 fname_idx = process::read_uint32(uobject + 0x18);
uint32 chunk_i   = (fname_idx >> 16) & 0xFF;
uint32 idx_i     = fname_idx & 0xFFFF;
uint64 chunk     = process::read_uint64(pool + 0x10 + uint64(chunk_i) * 8);

// Each entry: 2-byte header (length<<6 | flags) + ANSI string bytes
// Read up to 64 bytes of string starting at chunk + idx_i * STRIDE + 2
// STRIDE is typically 4-byte aligned: (len + 2 + 3) & ~3
```

---

## UE W2S camera chain

```angelscript
// GWorld → GameInstance → LocalPlayers[0] → PlayerController → PlayerCameraManager
uint64 game = process::get_module_base("game.exe");
uint64 gw_sig = process::find_signature(game, "48 8B 1D ? ? ? ? 48 85 DB 74");
if (gw_sig == 0) return false;
uint64 gw       = process::get_relative_address(gw_sig, 3, 7);

uint64 world    = process::read_uint64(gw);
uint64 gi       = process::read_uint64(world + 0x180);   // UWorld::GameInstance  ← PLACEHOLDER
uint64 lp_data  = process::read_uint64(gi + 0x38);        // TArray<ULocalPlayer*> ← PLACEHOLDER
uint64 local_p  = process::read_uint64(lp_data);
uint64 pc       = process::read_uint64(local_p + 0x30);   // APlayerController     ← PLACEHOLDER
uint64 cam      = process::read_uint64(pc + 0x440);        // APlayerCameraManager  ← PLACEHOLDER

vec3 cam_loc; cam_loc.read_float(cam + 0x1490);   // CameraLocation            ← PLACEHOLDER
vec3 cam_rot; cam_rot.read_float(cam + 0x149C);   // CameraRotation (pitch/yaw/roll)
float fov      = process::read_float(cam + 0x14A8);
```

Then build the view cache and project:

```angelscript
f_view_info camera;
camera.location = cam_loc;
camera.rotation = cam_rot;
camera.fov = fov;

f_view_cache cache = build_view_cache(camera);

vec2 screen;
if (!unreal::w2s(world_pos, cache, screen)) continue;
```

`build_view_cache` avoids recomputing the rotation matrix and FOV for every entity — build it
once per frame, not once per entity.

---

## UE bone reading

Echo reads the bone array of a `USkeletalMeshComponent` in one call:

```angelscript
// Offsets are PLACEHOLDERS taken from your SDK headers
u_bone_array bones = unreal::read_bones(skeletal_mesh, 0x120, 0x128, 0x160);
if (!bones.valid()) return;      // the read failed (or the bones were not cached)
uint n = bones.count();
// bones[i] — indexable by raw bone index
```

The four-argument form reads the bone array with a cached fallback; the three-argument form
(`unreal::read_bones(skeletal_mesh, bone_array_offset, component_offset)`) skips the cache and
may flicker between frames.

Individual bone transforms use the `ftransform` type:

```angelscript
ftransform bone_transform;
bone_transform.read(bone_address);           // reads 48 bytes from the process

// Transform a local position into world space using the parent transform
vec3 world_pos = bone_transform.transform_to_world(parent_transform);
```

---

## Dumper-7-VGK — Valorant GObjects decrypt

Vanguard (vgk.sys) prevents direct GObjects access. Dumper-7-VGK implements a 7-case state machine decrypt.

**Algorithm:**
- `MAGIC = 0x2545F4914F6CDD1D`
- `case_idx = (MAGIC * mixedKey) % 7`
- Each case: different arithmetic on the stored pointer value
- Case logic is **patch-stable**; only `state_addr` and `key_addr` change per patch

**When it breaks:** log shows `Decrypted pointer is unreadable`

**Re-finding addresses after patch:**
1. Scan for magic constant bytes `\x1D\xDD\x6C\x4F\x91\xF4\x45\x25` in `VALORANT-Win64-Shipping.exe`
2. Or: xref to string `"CloseDisregardForGC"` → trace caller → that is the GObjects accessor
3. Update the two module-relative addresses in `Decryption.h` (or in your Echo Unicorn script)

**Emulating the decrypt in Echo** (Echo's Unicorn bindings are the `uc::` namespace, and the
handle is a plain `uint64`):

```angelscript
uint64 game = process::get_module_base("VALORANT-Win64-Shipping.exe");
if (game == 0) return false;

uint32 mod_size = process::get_module_size(game);
uint64 fn       = game + DECRYPT_FN_OFFSET;   // found via sig scan for the magic constant

uint64 h = uc::create();
if (h == 0) return false;

uc::mem_map(h, game, mod_size, uc::prot::all);

// stack setup
uc::mem_map(h, 0x7FF000000000, 0x10000, uc::prot::all);
uc::setup_stack(h, 0x7FF000000000, 0x10000, 0x7FF000000000 + 0x8000);

uc::reg_write64(h, x86_reg::rcx, encrypted_ptr);   // first arg = encrypted GObjects
uc::reg_write64(h, x86_reg::rsp, 0x7FF000008000);

uc::start(h, fn, fn + 0x300, 5000, 1000);

uint64 gobjects_ptr = 0;
uc::reg_read64(h, x86_reg::rax, gobjects_ptr);

uc::close(h);
```

---

## Dumper-7 config (Dumper-7.ini)

```ini
[Settings]
SleepTimeout=30
SDKGenerationPath=./sdk/
SDKNamespaceName=MyGame
DumpKey=0x77          ; VK_F7 — press to start dump
ShouldAutoUnload=1
```

**Non-standard GObjects override** (edit `Generator.cpp`):
```cpp
ObjectArray::Init(GObjectsOffset, ChunkSize, bIsChunked);
// Encrypted arrays:
InitObjectArrayDecryption([](void* ObjPtr) -> uint8* {
    return reinterpret_cast<uint8*>(uint64(ObjPtr) ^ 0x8375);
});
```

---

## Offset update workflow after patch

1. **Re-generate the SDK** (or re-run the schema/IL2CPP dumper) — the SDK headers are the ground truth.
2. `binary-differ` subagent (mcp-gamehacking) — diff old vs new binary.
3. Identify changed functions; extract new unique bytes.
4. Update the `process::find_signature` pattern string — single line edit.
5. Diff the SDK headers against your hard-coded constants and update the drifted ones.
6. Verify: at spawn, `health ≈ 100`, `entity_count` between 1–64.
