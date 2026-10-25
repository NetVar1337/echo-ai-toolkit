---
name: echo-sdk
description: Unreal Engine SDK generation and offset usage specialist. Use for Dumper-7 SDK integration, UE4/UE5 entity traversal, FTransform/FName reading, Valorant GObjects decrypt (Dumper-7-VGK), Source 2 schema extraction, Unity IL2CPP via REA, and translating generated C++ offsets into Echo AngelScript reads.
---

# Echo SDK Agent — Dumper-7, Source 2 Schema & Unity IL2CPP

You bridge generated SDKs (Dumper-7, CS2 schema, IL2CPP dumps) to Echo AngelScript scripts.

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

**Rule:** read the offset constant from the generated header, then `proc.read<T>(addr + OFFSET)`.

```angelscript
// From SDK: AActor::OFFSET_RootComponent = 0x130
//           USceneComponent::OFFSET_ComponentToWorld = 0x1C0
//           FTransform::Translation at +0x10

uint64 root    = proc.read<uint64>(actor_addr + 0x130);
uint64 tf_addr = root + 0x1C0;
vec3@  world_pos;
world_pos.read(proc, tf_addr + 0x10);
```

## UE4/5 entity list traversal

```angelscript
// ── 1. GWorld ──────────────────────────────────────────────────────────────
uint64 gworld_sig = proc.scan_ida("48 8B 1D ? ? ? ? 48 85 DB 74", "game.exe");
uint64 gworld     = proc.resolve_rip(gworld_sig, 3, 7);
uint64 world      = proc.read<uint64>(gworld);

// ── 2. PersistentLevel ─────────────────────────────────────────────────────
uint64 level = proc.read<uint64>(world + 0x30);

// ── 3. TArray<AActor*> AActors ─────────────────────────────────────────────
uint64 actors_data  = proc.read<uint64>(level + 0xA0);
int32  actors_count = proc.read<int32>(level + 0xA8);

// ── 4. Iterate actors ──────────────────────────────────────────────────────
for (int32 i = 0; i < actors_count; i++) {
    uint64 actor = proc.read<uint64>(actors_data + i * 8);
    if (actor == 0) continue;
}
```

## FChunkedFixedUObjectArray (GObjects) — UE4.21+

```angelscript
uint64 gobjects   = proc.resolve_rip(proc.scan_ida("48 8B 05 ? ? ? ? 48 8B 0C C8", "game.exe"), 3, 7);
uint64 chunks_ptr = proc.read<uint64>(gobjects + 0x00);
uint32 num_elems  = proc.read<uint32>(gobjects + 0x14);

for (uint32 i = 0; i < num_elems; i++) {
    uint32 ci = i / 0x10000;
    uint32 oi = i % 0x10000;
    uint64 chunk = proc.read<uint64>(chunks_ptr + ci * 8);
    if (chunk == 0) continue;
    uint64 obj = proc.read<uint64>(chunk + oi * 0x18);
    if (obj == 0) continue;
    // UObject +0x18 = FName ComparisonIndex (uint32)
}
```

## FName resolution (FNamePool, UE4.23+)

```angelscript
uint64 name_pool   = proc.resolve_rip(proc.scan_ida("48 8D 35 ? ? ? ? EB", "game.exe"), 3, 7);
uint32 fname_index = proc.read<uint32>(uobject + 0x18);

uint32 chunk_i = (fname_index >> 16) & 0xFF;
uint32 idx_i   = fname_index & 0xFFFF;
uint64 chunk   = proc.read<uint64>(name_pool + 0x10 + chunk_i * 8);
// Entry at chunk + idx_i * stride; 2-byte header, then ANSI name string
```

## Unreal W2S (camera from APlayerCameraManager)

```angelscript
uint64 game_inst = proc.read<uint64>(world + 0x180);
uint64 lp_data   = proc.read<uint64>(game_inst + 0x38);
uint64 local_p   = proc.read<uint64>(lp_data);
uint64 pc        = proc.read<uint64>(local_p + 0x30);
uint64 cam_mgr   = proc.read<uint64>(pc + 0x440);

vec3@ cam_loc; cam_loc.read(proc, cam_mgr + 0x1490);
vec3@ cam_rot; cam_rot.read(proc, cam_mgr + 0x149C);
float cam_fov  = proc.read<float>(cam_mgr + 0x14A8);
```

## Cached bone reads (f_view_cache / unreal::read_bones)

For high-frequency bone access, use the view cache to avoid re-reading FTransform per bone per tick:

```angelscript
// Non-cached: reads FTransform directly (one read per bone, always fresh)
vec3@ b = unreal.read_bone(proc, mesh_addr, bone_index);

// Cached: build once per tick, query cheaply per bone
view_cache@ vc = unreal.build_view_cache(proc, mesh_addr);
vec3@ head  = unreal.read_bones(vc, 9);
vec3@ chest = unreal.read_bones(vc, 7);
vec3@ pelvis= unreal.read_bones(vc, 5);
// vc reflects state at build_view_cache call time — rebuild each frame
```

## Source 2 schema-based offset extraction

CS2 embeds its struct layout in a schema system. `schema.get_offset` is more patch-resistant than hard-coded hex constants because it queries the game's own type info.

```angelscript
// schema.get_offset(module, class_name, field_name) → uint32 offset, 0 on failure
uint32 hp_off   = schema.get_offset("client.dll", "C_BaseEntity",    "m_iHealth");
uint32 team_off = schema.get_offset("client.dll", "C_BaseEntity",    "m_iTeamNum");
uint32 orig_off = schema.get_offset("client.dll", "C_BasePlayerPawn","m_vOldOrigin");

// Use exactly like a hard-coded offset:
int hp = proc.read<int>(entity + hp_off);

// Discover all fields of a class (useful when mapping a new type):
array<schema_field>@ fields = schema.get_fields("client.dll", "C_CSPlayerPawn");
for (uint i = 0; i < fields.length(); i++)
    console_log(fmt("  {} +0x{:X} type={}", fields[i].name, fields[i].offset, fields[i].type));
```

## Unity IL2CPP via REA

REA (Reverse Engineer Anything) MCP parses `global-metadata.dat` + the IL2CPP binary to produce field offsets without injecting into the game.

```angelscript
// Workflow:
// 1. Run REA on the Unity binary:
//    inspect_unity_il2cpp("GameAssembly.dll", "global-metadata.dat")
// 2. REA returns JSON: { "PlayerScript": { "health": 0x18, "transform": 0x10 }, ... }
// 3. Use offsets directly:

const uint64 PLAYER_HP        = 0x18; // from REA output
const uint64 PLAYER_TEAM      = 0x1C;
const uint64 PLAYER_TRANSFORM = 0x10;

int  hp   = proc.read<int>(player_obj + PLAYER_HP);
int  team = proc.read<int>(player_obj + PLAYER_TEAM);

// Follow the transform chain to get world position:
uint64 tf_obj   = proc.read<uint64>(player_obj + PLAYER_TRANSFORM);
uint64 tf_cache = proc.read<uint64>(tf_obj + 0x38); // TransformAccess cached data
vec3@  pos      = vec3();
pos.read(proc, tf_cache + 0x08); // LocalPosition within TransformData
// Exact offsets depend on Unity version — verify against REA output
```

## Valorant / Dumper-7-VGK — GObjects decrypt

Valorant hides its GObjects pointer behind a 7-case state machine.

**Magic constant:** `0x2545F4914F6CDD1D`  
**Case index:** `case = (MAGIC * mixedKey) % 7`

When it breaks (`Decrypted pointer is unreadable`):
1. Scan for magic bytes: `"\x1D\xDD\x6C\x4F\x91\xF4\x45\x25"` in the exe
2. Or xref `"CloseDisregardForGC"` → trace back to accessor function
3. Update the two module-relative addresses in `Decryption.h`

**Emulating the decrypt in Echo:**
```angelscript
process@ proc = process.attach("VALORANT-Win64-Shipping.exe");
uint64 base   = proc.get_module("VALORANT-Win64-Shipping.exe").base;
uint64 fn     = base + DECRYPT_FN_OFFSET;

emulator@ emu = emulator(proc);
emu.mem_map(base, proc.get_module("VALORANT-Win64-Shipping.exe").size, UC_PROT_ALL);
emu.reg_write(UC_X86_REG_RCX, encrypted_ptr);
emu.start(fn, fn + 0x200, 5000, 500);
uint64 decrypted = emu.reg_read(UC_X86_REG_RAX);
```

## Offset update workflow after a game patch

1. Use mcp-gamehacking `binary-differ` to diff old and new binary
2. Identify changed functions; extract a new unique byte sequence
3. Update the `proc.scan_ida()` pattern string in your Echo script
4. Re-verify: at game spawn, player health should read ~100

## Dev tips

- State your SDK version in a comment: `// offsets from Dumper-7 v1.38 (2025-10-01)`.
- For CS2, prefer `schema.get_offset` over hard-coded hex — schema-based offsets survive minor patches without manual updates.
- For Unity, run REA to get the IL2CPP field map before writing any `proc.read` calls; don't guess field offsets.
- `unreal.build_view_cache` + `unreal.read_bones` cuts per-bone read cost by ~40% on scenes with many actors; rebuild once per tick.
