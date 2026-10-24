# Echo Anti-Patterns — What Crashes, Bans, and Breaks Scripts

These are the most common failure modes in LLM-generated Echo scripts. Each has a **what happens** and a **fix**.

---

## P0 — crashes the script immediately

### 1. Reading from address 0 (null deref after failed scan)

```angelscript
// BAD
uint64 entity_list = proc.scan_ida("48 8B ...", "client.dll");
uint64 entity = proc.read<uint64>(entity_list + 0x10);  // crash if scan returned 0

// GOOD
uint64 entity_list = proc.scan_ida("48 8B ...", "client.dll");
if (entity_list == 0) { alert("scan failed — update pattern"); return; }
```

### 2. Null pointer in a deref chain (any level)

```angelscript
// BAD
uint64 pawn = proc.read<uint64>(controller + 0x60C);
float hp = proc.read<float>(pawn + 0x334);  // crash if pawn == 0

// GOOD — null-check every pointer level
uint64 pawn = proc.read<uint64>(controller + 0x60C);
if (pawn == 0) continue;
float hp = proc.read<float>(pawn + 0x334);
```

### 3. Array out-of-bounds from untrusted actor count

```angelscript
// BAD — actor_count from process memory can be any value including 500000
for (uint32 i = 0; i <= actor_count; i++) ...   // <= off-by-one, unbounded

// GOOD — sanity cap + < not <=
uint32 count = proc.read<uint32>(level + OFF_ACTOR_COUNT);
if (count == 0 || count > 4096) return;
for (uint32 i = 0; i < count; i++) ...
```

### 4. Calling proc.read before proc.attach

```angelscript
// BAD — proc is null until attach
void main() {
    create_thread(64, function() {
        uint64 val = proc.read<uint64>(0x1234);  // crash: not attached
    });
}

// GOOD
void main() {
    proc.attach("game.exe");
    if (!proc.is_running()) return;
    create_thread(64, function() { tick(); });
}
```

### 5. Using uint32 for pointer reads (truncated address)

```angelscript
// BAD — pointers are 8 bytes on x64
uint32 ptr = proc.read<uint32>(entity + 0x60C);  // silently truncates high 4 bytes
uint64 data = proc.read<uint64>(ptr + 0x10);     // crash: ptr is garbage

// GOOD
uint64 ptr = proc.read<uint64>(entity + 0x60C);
```

---

## P0 — detection by anti-cheat

### 6. Writing to game memory in a game with kernel AC

```angelscript
// BAD — EAC, BattlEye, Vanguard kernel drivers flag proc.write to game regions
proc.write<float>(hp_address, 9999.0f);   // instant detection

// Echo is external and read-only by design. Never write to game memory.
```

### 7. Linear one-shot mouse movement (aimbot signature)

```angelscript
// BAD — jumps directly to target in one tick
mouse.move_to(target_screen_x, target_screen_y);

// GOOD — smooth over multiple ticks
float factor = smooth_slider.get();  // e.g. 0.08
float dx = (target_x - current_x) * factor;
float dy = (target_y - current_y) * factor;
mouse.move(int(dx), int(dy));
```

### 8. Moving mouse at robotic exact frequency

```angelscript
// BAD — exactly 64 tps with no variance
create_thread(64, function() { aim_tick(); });

// GOOD — small random sleep per tick
create_thread(64, function() {
    aim_tick();
    sleep(uint(random.int(0, 4)));
});
```

---

## P1 — wrong values / broken behavior

### 9. Forgetting to resolve RIP for data references

```angelscript
// BAD — scan returns address of the LEA instruction, not the data
uint64 addr = proc.scan_ida("48 8B 0D ? ? ? ?", "client.dll");
uint64 list = proc.read<uint64>(addr);   // reading opcode bytes as a pointer

// GOOD — resolve the RIP-relative operand first
uint64 instr = proc.scan_ida("48 8B 0D ? ? ? ?", "client.dll");
if (instr == 0) return;
uint64 ptr_addr = proc.resolve_rip(instr, 3, 7);  // gets address of the pointer
uint64 list = proc.read<uint64>(ptr_addr);          // dereference it
```

### 10. Race condition between tick and render threads

```angelscript
// BAD — concurrent read/write of shared array = data race / crash
array<entity_data> entities;
create_thread(64, function() { entities.resize(0); /* fill */ });
on_render(function() { for (auto e : entities) draw(e); });

// GOOD — mutex protects the swap
mutex@ mtx = mutex();
array<entity_data> entities;
create_thread(64, function() {
    array<entity_data> tmp;   // build into local copy
    // fill tmp...
    mtx.lock();
    entities = tmp;
    mtx.unlock();
});
on_render(function() {
    mtx.lock_shared();
    for (uint i = 0; i < entities.length(); i++) draw(entities[i]);
    mtx.unlock_shared();
});
```

### 11. Wrong FTransform stride for bone reads

```angelscript
// BAD — FTransform is 48 bytes, not 16
float bx = proc.read<float>(bone_base + idx * 16);   // wrong stride

// GOOD — FTransform layout: [quat 16b][translation 12b][scale 12b] = 48b
uint64 entry = bone_base + uint64(idx) * 48;
float bx = proc.read<float>(entry + 16);   // translation.x
float by = proc.read<float>(entry + 20);   // translation.y
float bz = proc.read<float>(entry + 24);   // translation.z
```

### 12. Not handling game restart

```angelscript
// BAD — loop keeps running after game exits; may crash on next attach
while (true) { tick(); sleep(1); }

// GOOD
while (proc.is_running()) { tick(); sleep(1); }
// Re-attach pattern:
void main() {
    while (true) {
        while (!proc.is_running()) {
            proc.attach("game.exe");
            sleep(1000);
        }
        run_session();
    }
}
```

---

## P1 — performance problems

### 13. Pattern scan inside the tick loop

```angelscript
// BAD — runs proc.scan_ida 64x per second
create_thread(64, function() {
    uint64 list = proc.scan_ida("...", "client.dll");  // expensive every tick
});

// GOOD — scan once in main, store globally
uint64 g_entity_list = 0;
void main() {
    proc.attach("game.exe");
    g_entity_list = proc.scan_ida("...", "client.dll");
    if (g_entity_list == 0) return;
    create_thread(64, function() { tick(); });
}
```

### 14. Tight spin loop without sleep

```angelscript
// BAD — burns CPU, may trigger behavioral AC
create_thread(0, function() { while(true) { tick(); } });  // tps=0 = unlimited

// GOOD
create_thread(64, function() { tick(); });
```

---

## P2 — wrong but silent

### 15. Using W2S screen bounds check instead of return value

```angelscript
// BAD — entities near the screen edge get sx/sy in valid range even off-screen
source2.w2s(proc, vm_addr, pos, sx, sy);
if (sx > 0 && sy > 0) draw();

// GOOD
bool on = source2.w2s(proc, vm_addr, pos, sx, sy);
if (!on) continue;
```

### 16. Caching entity addresses across ticks

```angelscript
// BAD — entity slot i may point to a different actor after a respawn
uint64 cached = actor_base + stored_index * 8;
uint64 pawn = proc.read<uint64>(cached + 0x60C);   // stale

// GOOD — re-walk the entity list each tick; only cache values (hp, pos)
```
