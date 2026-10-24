# Dumper-7 SDK Reference

**Dumper-7** (Encryqed/Dumper-7): UE4 + UE5 SDK generator. Inject DLL → walks live GObjects/FNames → generates C++ headers with every class, struct, and offset found.

**Dumper-7-VGK** (sinistercodes/Dumper-7-VGK): fork that adds Valorant support, working around Vanguard's encrypted GObjects pointer.

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
// ── Offset constants (copy from SDK headers) ────────────────────────────────
const uint32 OFF_ROOTCOMPONENT      = 0x130;  // AActor  (Engine_classes.hpp)
const uint32 OFF_COMPONENTTOWORLD   = 0x1C0;  // USceneComponent
const uint32 OFF_FTRANSFORM_TRANS   = 0x10;   // FTransform::Translation
const uint32 OFF_TEAMNUM            = 0x3B8;  // APawn / APlayerState
const uint32 OFF_HEALTH             = 0x330;  // game-specific (ShooterGame_classes.hpp)

// ── Read actor world position ────────────────────────────────────────────────
uint64 get_actor_location(uint64 actor) {
    uint64 root = proc.read<uint64>(actor + OFF_ROOTCOMPONENT);
    if (root == 0) return 0;
    vec3@ loc;
    loc.read(proc, root + OFF_COMPONENTTOWORLD + OFF_FTRANSFORM_TRANS);
    return 1; // use loc in caller
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

uint64 gobjects   = proc.resolve_rip(
    proc.scan_ida("48 8B 05 ? ? ? ? 48 8B 0C C8 48 8D 04 D1", "game.exe"), 3, 7);
uint64 chunks_ptr = proc.read<uint64>(gobjects + 0x00);
uint32 num        = proc.read<uint32>(gobjects + 0x14);

for (uint32 i = 0; i < num; i++) {
    uint32 ci  = i / 0x10000;
    uint32 oi  = i % 0x10000;
    uint64 chk = proc.read<uint64>(chunks_ptr + ci * 8);
    if (chk == 0) continue;
    uint64 obj = proc.read<uint64>(chk + oi * 0x18);
    if (obj == 0) continue;
    // UObject* — UObject+0x00=vtable, +0x18=FName.Index (uint32)
}
```

---

## FName resolution (FNamePool, UE4.23+)

```angelscript
// FNamePool base via signature
uint64 pool = proc.resolve_rip(
    proc.scan_ida("48 8D 35 ? ? ? ? EB ? 48 8D 0D", "game.exe"), 3, 7);

// Read FName from a UObject
uint32 fname_idx = proc.read<uint32>(uobject + 0x18);
uint32 chunk_i   = (fname_idx >> 16) & 0xFF;
uint32 idx_i     = fname_idx & 0xFFFF;
uint64 chunk     = proc.read<uint64>(pool + 0x10 + chunk_i * 8);

// Each entry: 2-byte header (length<<6 | flags) + ANSI string bytes
// Read up to 64 bytes of string starting at chunk + idx_i * STRIDE + 2
// STRIDE is typically 4-byte aligned: (len + 2 + 3) & ~3
```

---

## UE W2S camera chain

```angelscript
// GWorld → GameInstance → LocalPlayers[0] → PlayerController → PlayerCameraManager
uint64 gw       = proc.resolve_rip(proc.scan_ida("48 8B 1D ? ? ? ? 48 85 DB 74", "game.exe"), 3, 7);
uint64 world    = proc.read<uint64>(gw);
uint64 gi       = proc.read<uint64>(world + 0x180);   // UWorld::GameInstance
uint64 lp_data  = proc.read<uint64>(gi + 0x38);        // TArray<ULocalPlayer*>
uint64 local_p  = proc.read<uint64>(lp_data);
uint64 pc       = proc.read<uint64>(local_p + 0x30);   // APlayerController
uint64 cam      = proc.read<uint64>(pc + 0x440);        // APlayerCameraManager

vec3@ cam_loc; cam_loc.read(proc, cam + 0x1490);   // CameraLocation
vec3@ cam_rot; cam_rot.read(proc, cam + 0x149C);   // CameraRotation (pitch/yaw/roll)
float fov      = proc.read<float>(cam + 0x14A8);
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

**Emulating the decrypt in Echo:**
```angelscript
uint64 base      = proc.get_module("VALORANT-Win64-Shipping.exe").base;
uint64 fn        = base + DECRYPT_FN_OFFSET;   // found via sig scan for magic constant

emulator@ emu = emulator(proc);
emu.mem_map(base, proc.get_module("VALORANT-Win64-Shipping.exe").size, UC_PROT_ALL);
// stack setup
emu.mem_map(0x7FF000000000, 0x10000, UC_PROT_ALL);
emu.reg_write(UC_X86_REG_RSP, 0x7FF000008000);
emu.reg_write(UC_X86_REG_RCX, encrypted_ptr);  // first arg = encrypted GObjects
emu.start(fn, fn + 0x300, 5000, 1000);
uint64 gobjects_ptr = emu.reg_read(UC_X86_REG_RAX);
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

1. `binary-differ` subagent (mcp-gamehacking) — diff old vs new binary
2. Identify changed functions; extract new unique bytes
3. Update `proc.scan_ida()` pattern string — single line edit
4. Verify: at spawn, `health ≈ 100`, `entity_count` between 1–64
