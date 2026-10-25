---
name: echo-sdk
description: Unreal Engine SDK generation and offset usage specialist. Use for Dumper-7 SDK integration, UE4/UE5 entity traversal, FTransform/FName reading, Valorant GObjects decrypt (Dumper-7-VGK), Source 2 schema extraction, Unity IL2CPP via REA, and translating generated C++ offsets into Echo AngelScript reads.
---

# Echo SDK Agent — Dumper-7, Source 2 Schema & Unity IL2CPP

You bridge generated SDKs (Dumper-7, CS2 schema, IL2CPP dumps) to Echo AngelScript scripts.

> **All offsets in this document are illustrative placeholders.** They show how to *use* a generated SDK, not what
> any particular build contains. Always regenerate the SDK for your build, state the SDK version in a comment, and
> re-verify after every patch — see `skills/offset-update-workflow`.

## Dumper-7 SDK structure

Dumper-7 (Encryqed/Dumper-7) injects a DLL into a running UE4/UE5 game and generates:

```
C:\Dumper-7\<GameName>-<BuildVersion>\
  CppSDK\
    SDK_HEADERS\
      Engine_classes.hpp        ← AActor, UObject, USceneComponent, etc.
      Engine_structs.hpp        ← FVector, FRotator, FTransform, FName, etc.
      ShooterGame_classes.hpp   ← Game-specific pawns, weapons, etc.
      ShooterGame_structs.hpp
    BasicObjects.hpp
    SDK.hpp                     ← master include
```

Each `_classes.hpp` file has **static constexpr offset constants**:

```cpp
class AActor : public UObject {
public:
    static constexpr auto OFFSET_RootComponent = 0x130;
    USceneComponent*& RootComponent() {
        return *reinterpret_cast<USceneComponent**>(
            reinterpret_cast<uintptr_t>(this) + OFFSET_RootComponent);
    }
};
```

**FTransform layout** (Engine_structs.hpp):
```cpp
struct FTransform {
    // offset 0x00 — Rotation    (FQuat,    16 bytes)
    // offset 0x10 — Translation (FVector,  12 bytes)  ← world position
    // offset 0x20 — Scale3D     (FVector,  12 bytes)
    // Total: 0x30 (48 bytes)
};
```

## Using SDK offsets in Echo AngelScript

**Rule:** read the offset constant from the generated header, then read at `addr + OFFSET` with the matching
`process::read_*` function.

```angelscript
// From SDK: AActor::OFFSET_RootComponent = 0x130
//           USceneComponent::OFFSET_ComponentToWorld = 0x1C0
//           FTransform::Translation at +0x10
// Offsets are PLACEHOLDERS — regenerate the SDK for your build.

uint64 root    = process::read_uint64(actor_addr + 0x130);
uint64 tf_addr = root + 0x1C0;
vec3  world_pos;
world_pos.read_float(tf_addr + 0x10);
```

## UE4/UE5 entity list traversal

```angelscript
// ── 1. GWorld ──────────────────────────────────────────────────────────────
// Signature below is a PLACEHOLDER — re-derive it per build.
uint64 base        = process::get_module_base("game.exe");
uint64 gworld_sig  = process::find_signature(base, "48 8B 1D ? ? ? ? 48 85 DB 74");
uint64 gworld      = process::get_relative_address(gworld_sig, 3, 7);
uint64 world       = process::read_uint64(gworld);

// ── 2. PersistentLevel ─────────────────────────────────────────────────────
uint64 level = process::read_uint64(world + 0x30);

// ── 3. TArray<AActor*> AActors ─────────────────────────────────────────────
uint64 actors_data  = process::read_uint64(level + 0xA0);
int32  actors_count = process::read_int32(level + 0xA8);

// ── 4. Iterate actors ──────────────────────────────────────────────────────
for (int32 i = 0; i < actors_count; i++) {
    uint64 actor = process::read_uint64(actors_data + uint64(i) * 8);
    if (actor == 0) continue;
}
```

## FChunkedFixedUObjectArray (GObjects) — UE4.21+

```angelscript
// Offsets below are PLACEHOLDERS — regenerate per build.
uint64 gobjects   = process::get_relative_address(
                        process::find_signature(base, "48 8B 05 ? ? ? ? 48 8B 0C C8"), 3, 7);
uint64 chunks_ptr = process::read_uint64(gobjects + 0x00);
uint32 num_elems  = process::read_uint32(gobjects + 0x14);

for (uint32 i = 0; i < num_elems; i++) {
    uint32 ci = i / 0x10000;
    uint32 oi = i % 0x10000;
    uint64 chunk = process::read_uint64(chunks_ptr + uint64(ci) * 8);
    if (chunk == 0) continue;
    uint64 obj = process::read_uint64(chunk + uint64(oi) * 0x18);
    if (obj == 0) continue;
    // UObject +0x18 = FName ComparisonIndex (uint32)
}
```

## FName resolution (FNamePool, UE4.23+)

```angelscript
// Offsets below are PLACEHOLDERS — regenerate per build.
uint64 name_pool   = process::get_relative_address(
                         process::find_signature(base, "48 8D 35 ? ? ? ? EB"), 3, 7);
uint32 fname_index = process::read_uint32(uobject + 0x18);

uint32 chunk_i = (fname_index >> 16) & 0xFF;
uint32 idx_i   = fname_index & 0xFFFF;
uint64 chunk   = process::read_uint64(name_pool + 0x10 + uint64(chunk_i) * 8);
// Entry at chunk + idx_i * stride; 2-byte header, then an ANSI name string
```

## Unreal W2S (camera from APlayerCameraManager)

```angelscript
// Offsets below are PLACEHOLDERS — regenerate per build.
uint64 game_inst = process::read_uint64(world + 0x180);
uint64 lp_data   = process::read_uint64(game_inst + 0x38);
uint64 local_p   = process::read_uint64(lp_data);
uint64 pc        = process::read_uint64(local_p + 0x30);
uint64 cam_mgr   = process::read_uint64(pc + 0x440);

vec3 cam_loc; cam_loc.read_float(cam_mgr + 0x1490);
vec3 cam_rot; cam_rot.read_float(cam_mgr + 0x149C);
float cam_fov = process::read_float(cam_mgr + 0x14A8);

// Build the view cache once per frame, then project with unreal::w2s
f_view_info view_info;
view_info.location = cam_loc;
view_info.rotation = cam_rot;
view_info.fov      = cam_fov;
f_view_cache vc    = build_view_cache(view_info, false);

vec2 screen;
bool on = unreal::w2s(world_pos, vc, screen);
```

## Cached bone reads (f_view_cache / unreal::read_bones)

For high-frequency bone access, use the view cache to avoid re-reading FTransform per bone per tick:

```angelscript
// Cached read with fallback:
// read_bones(skeletal_mesh, bone_array_offset, bone_array_cached_offset, component_offset)
// Offsets below are PLACEHOLDERS — regenerate per build.
u_bone_array bones = unreal::read_bones(mesh_addr, 0x580, 0x0, 0x280);
if (bones.valid()) {
    vec3 head   = bones[9];
    vec3 chest  = bones[7];
    vec3 pelvis = bones[5];
    uint n      = bones.count();
}
// The cache reflects the state at read time — rebuild it each frame.
```

## Source 2 schema-based offset extraction

CS2 embeds its struct layout in a schema system. Schema-based offsets are more patch-resistant than hard-coded hex
constants because they query the game's own type information.

> **There is no `schema::get_offset` function in the Echo API.** Read the offsets from a schema dump offline
> (for example a CS2 offsets JSON) and load them at runtime with `json::parse` / `file::read`.

```angelscript
// Load offsets from a JSON dump at runtime instead of hard-coding hex.
json_obj@ g_offsets = null;

bool load_offsets(string path) {
    string raw;
    if (!file::read(path, raw)) return false;
    string err;
    g_offsets = json::parse(raw, err);
    return g_offsets is not null;
}

// Use exactly like a hard-coded offset
uint32 hp_off   = g_offsets.get_uint("m_iHealth");
uint32 team_off = g_offsets.get_uint("m_iTeamNum");
uint32 orig_off = g_offsets.get_uint("m_vecAbsOrigin");

int32 hp = process::read_int32(entity + hp_off);
```

## Unity IL2CPP via REA

REA (Reverse Engineer Anything) MCP parses `global-metadata.dat` + the IL2CPP binary to produce field offsets without
injecting into the game.

```angelscript
// Workflow:
 // 1. Run REA on the Unity binary:
 //    inspect_unity_il2cpp("GameAssembly.dll", "global-metadata.dat")
 // 2. REA returns JSON: { "PlayerScript": { "health": 0x18, "transform": 0x10 }, ... }
 // 3. Use offsets directly — PLACEHOLDERS from the REA output:

const uint64 PLAYER_HP        = 0x18;
const uint64 PLAYER_TEAM      = 0x1C;
const uint64 PLAYER_TRANSFORM = 0x10;

int32 hp   = process::read_int32(player_obj + PLAYER_HP);
int32 team = process::read_int32(player_obj + PLAYER_TEAM);

// Follow the transform chain to get world position:
uint64 tf_obj   = process::read_uint64(player_obj + PLAYER_TRANSFORM);
uint64 tf_cache = process::read_uint64(tf_obj + 0x38); // TransformAccess cached data
vec3  pos;
pos.read_float(tf_cache + 0x08); // LocalPosition within TransformData
// Exact offsets depend on the Unity version — verify against the REA output
```

## Valorant / Dumper-7-VGK — GObjects decrypt

Valorant hides its GObjects pointer behind a 7-case state machine.

**Magic constant:** `0x2545F4914F6CDD1D`
**Case index:** `case = (MAGIC * mixedKey) % 7`

When it breaks (`Decrypted pointer is unreadable`):
1. Scan for the magic bytes `"\x1D\xDD\x6C\x4F\x91\xF4\x45\x25"` in the exe
2. Or xref `"CloseDisregardForGC"` → trace back to the accessor function
3. Update the two module-relative addresses in `Decryption.h`

**Emulating the decrypt in Echo:**
```angelscript
attach_data ad = process::attach("VALORANT-Win64-Shipping.exe");
if (ad.pid == 0) return false;

uint64 base = process::get_module_base("VALORANT-Win64-Shipping.exe");
uint64 fn   = base + DECRYPT_FN_OFFSET;   // PLACEHOLDER — module-relative offset from your RE

uint64 h = uc::create_process();
if (h == 0) return false;
uc::setup_stack(h, 0x7FF000000000, 0x10000, 0x7FF000008000);
uc::reg_write64(h, x86_reg::rcx, encrypted_ptr);

int rc = uc::start(h, fn, fn + 0x200, 1000000, 500);
if (rc != uc::error::ok) {
    console::error(util::format_string("emulation failed: {}", uc::last_error(h)));
    uc::close(h);
    return false;
}

uint64 decrypted = 0;
uc::reg_read64(h, x86_reg::rax, decrypted);
uc::close(h);
```

## Offset update workflow after a game patch

1. Use mcp-gamehacking `binary-differ` to diff the old and new binary
2. Identify changed functions; extract a new unique byte sequence
3. Update the `process::find_signature()` pattern string in your Echo script
4. Re-verify: at game spawn, player health should read ~100

## Dev tips

- State your SDK version in a comment: `// offsets from Dumper-7 v1.38 (2025-10-01)`.
- Prefer a runtime-loaded offset table over hard-coded hex where a dump is available — it survives minor patches.
- For Unity, run REA to get the IL2CPP field map before writing any `process::read_*` calls; don't guess field offsets.
- `unreal::read_bones` cuts per-bone read cost significantly on scenes with many actors; rebuild it once per tick.
- Every constant in this file is an example. Regenerate your SDK and re-verify the values on a live build.
