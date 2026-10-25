---
name: echo-anti-patterns
description: The most common failure modes in LLM-generated Echo scripts, each shown as wrong code plus the corrected real-API code — unsafe memory access, wrong render-thread usage, broken UI handle handling, racy shared state. Use when reviewing or debugging an Echo script that crashes, misbehaves, or gets banned.
---

# Echo Anti-Patterns — What Crashes, Bans, and Breaks Scripts

These are the most common failure modes in LLM-generated Echo scripts. Each has a **what happens** and a **fix**.

All snippets use the real Echo API: `process::*` for memory, `render::*` for drawing,
`ui::*` for the menu, `input::*` for the mouse and keyboard.

---

## P0 — crashes the script immediately

### 1. Reading through a failed signature scan

```angelscript
// BAD — the scan returns 0 when nothing matches, so this reads from address 0x10
uint64 client = process::get_module_base("client.dll");
uint64 entity_list = process::find_signature(client, "48 8B 0D ? ? ? ?");
uint64 entity = process::read_uint64(entity_list + 0x10);

// GOOD — check the scan result first
uint64 entity_list = process::find_signature(client, "48 8B 0D ? ? ? ?");
if (entity_list == 0) {
    alert::show("scan failed — update pattern");
    return false;
}
uint64 entity = process::read_uint64(entity_list + 0x10);
```

### 2. Null pointer in a deref chain (any level)

```angelscript
// BAD — pawn may be 0, so the second read is garbage
uint64 pawn = process::read_uint64(controller + 0x60C);
float hp = process::read_float(pawn + 0x334);

// GOOD — null-check every pointer level
uint64 pawn = process::read_uint64(controller + 0x60C);
if (pawn == 0) continue;
float hp = process::read_float(pawn + 0x334);
```

Use the out-parameter overload when `0` is a legitimate value:

```angelscript
float hp = 0.0f;
if (!process::read_float(pawn + 0x334, hp)) continue;   // false = read failed
```

### 3. Array out-of-bounds from untrusted actor count

```angelscript
// BAD — actor_count from process memory can be any value including 500000
for (uint32 i = 0; i <= actor_count; i++) { ... }   // <= off-by-one, unbounded

// GOOD — sanity cap + < not <=
uint32 count = process::read_uint32(level + OFF_ACTOR_COUNT);
if (count == 0 || count > 4096) return;
for (uint32 i = 0; i < count; i++) { ... }
```

### 4. Reading memory before attaching

```angelscript
// BAD — reads before process::attach silently return default values (0 / 0.0f)
bool main() {
    create_thread(64, function() {
        uint64 val = process::read_uint64(0x1234);   // 0, no error
    });
    return true;
}

// GOOD — attach first and verify the pid
bool main() {
    attach_data ad = process::attach("game.exe");
    if (ad.pid == 0) return false;
    create_thread(64, @tick);
    return true;
}
```

### 5. Using uint32 for pointer reads (truncated address)

```angelscript
// BAD — pointers are 8 bytes on x64
uint32 ptr = process::read_uint32(entity + 0x60C);   // silently truncates high 4 bytes
uint64 data = process::read_uint64(ptr + 0x10);      // garbage

// GOOD
uint64 ptr = process::read_uint64(entity + 0x60C);
```

---

## P0 — detection by anti-cheat

### 6. Writing to game memory in a game with kernel AC

```angelscript
// BAD — EAC, BattlEye, Vanguard kernel drivers flag writes to game regions
process::write_float(hp_address, 9999.0f);   // instant detection

// Echo is external and read-only by design. Never write to game memory.
```

### 7. Instant mouse snap to the target (aimbot signature)

```angelscript
// BAD — jumps directly to target in one tick
input::mouse_move(int(target_screen_x), int(target_screen_y));

// GOOD — smooth over multiple ticks
float factor = 0.08f;                    // smoothing factor, 0.0–1.0
float dx = (target_x - current_x) * factor;
float dy = (target_y - current_y) * factor;
input::mouse_move(int(current_x + dx), int(current_y + dy));
```

Note `input::mouse_move(x, y)` takes **absolute** screen coordinates, not a delta.

### 8. Moving the mouse at a robotic exact frequency

```angelscript
// BAD — exactly 64 tps with no variance
create_thread(64, @aim_tick);

// GOOD — small random sleep per tick
create_thread(64, function() {
    aim_tick();
    sleep(uint(util::random_int(0, 4)));
});
```

---

## P1 — wrong values / broken behavior

### 9. Forgetting to resolve RIP for data references

```angelscript
// BAD — the scan returns the address of the LEA/MOV instruction, not the data
uint64 client = process::get_module_base("client.dll");
uint64 addr = process::find_signature(client, "48 8B 0D ? ? ? ?");
uint64 list = process::read_uint64(addr);   // reading opcode bytes as a pointer

// GOOD — resolve the RIP-relative operand first
uint64 instr = process::find_signature(client, "48 8B 0D ? ? ? ?");
if (instr == 0) return false;
uint64 ptr_addr = process::get_relative_address(instr, 3, 7);   // address of the pointer
uint64 list = process::read_uint64(ptr_addr);                   // dereference it
```

### 10. Race condition between tick and render threads

```angelscript
// BAD — concurrent read/write of a shared array = data race / crash
// (build_entities / draw_entity are user code)
array<entity_data> entities;
create_thread(64, function() { entities = build_entities(); });
on_render(function() { for (uint i = 0; i < entities.length(); i++) draw_entity(entities[i]); });

// GOOD — a mutex protects the swap
mutex@ mtx = create_mutex();
array<entity_data> entities;

create_thread(64, function() {
    array<entity_data> tmp;   // build into a local copy
    // fill tmp...
    mtx.lock();
    entities = tmp;
    mtx.unlock();
});

on_render(function() {
    mtx.lock_shared();
    for (uint i = 0; i < entities.length(); i++) draw_entity(entities[i]);
    mtx.unlock_shared();
});
```

### 11. Wrong FTransform stride for bone reads

```angelscript
// BAD — FTransform is 48 bytes, not 16
float bx = process::read_float(bone_base + idx * 16);   // wrong stride

// GOOD — FTransform layout: [quat 16b][translation 12b][scale 12b] = 48b
uint64 entry = bone_base + uint64(idx) * 48;
float bx = process::read_float(entry + 16);   // translation.x
float by = process::read_float(entry + 20);   // translation.y
float bz = process::read_float(entry + 24);   // translation.z
```

For Unreal, read the transform directly instead of hand-rolling the layout:

```angelscript
ftransform tf;
tf.read(bone_address);
vec3 pos = tf.transform_to_world(parent_tf);
```

### 12. Not handling game restart

```angelscript
// BAD — the loop keeps running after the game exits
while (true) { tick(); sleep(1); }

// GOOD
while (process::is_alive()) { tick(); sleep(1); }
```

Re-attach pattern:

```angelscript
bool main() {
    while (true) {
        if (!process::is_alive()) {
            attach_data ad = process::attach("game.exe");
            if (ad.pid == 0) {
                sleep(1000);
                continue;
            }
        }
        run_session();   // user code — the per-session work loop
    }
    return true;
}
```

---

## P1 — performance problems

### 13. Pattern scan inside the tick loop

```angelscript
// BAD — runs process::find_signature 64x per second
create_thread(64, function() {
    uint64 list = process::find_signature(base, "48 8B 0D ? ? ? ?");  // expensive every tick
});

// GOOD — scan once in main, store globally
uint64 g_entity_list = 0;

bool main() {
    uint64 base = process::get_module_base("client.dll");
    g_entity_list = process::find_signature(base, "48 8B 0D ? ? ? ?");
    if (g_entity_list == 0) return false;
    create_thread(64, @tick);
    return true;
}
```

### 14. Tight spin loop without sleep

```angelscript
// BAD — a one-shot thread that loops forever burns CPU and may trigger behavioral AC
create_thread(0, function() { while (true) { tick(); } });

// GOOD — a fixed tick rate
create_thread(64, @tick);
```

---

## P2 — wrong but silent

### 15. Using W2S screen bounds instead of the return value

```angelscript
// BAD — entities near the screen edge still produce in-range coordinates off-screen
vec2 screen;
source2::w2s(world_pos, view_matrix, screen);
if (screen.x > 0 && screen.y > 0) {
    render::draw_box(int(screen.x), int(screen.y), 40, 40, 255, 0, 0, 255, box_style::OUTLINED, 0.0f);
}

// GOOD — the helper returns false when the point is off-screen or behind the camera
vec2 screen;
if (!source2::w2s(world_pos, view_matrix, screen)) continue;
render::draw_box(int(screen.x), int(screen.y), 40, 40, 255, 0, 0, 255, box_style::OUTLINED, 0.0f);
```

### 16. Caching entity addresses across ticks

```angelscript
// BAD — entity slot i may point to a different actor after a respawn
uint64 cached = actor_base + stored_index * 8;
uint64 pawn = process::read_uint64(cached + 0x60C);   // stale

// GOOD — re-walk the entity list each tick; only cache values (hp, pos)
```

### 17. Trusting the module base without checking it

```angelscript
// BAD — get_module_base returns 0 when the module is not loaded, so every
// address computed from it lands in the null page
uint64 base = process::get_module_base("client.dll");
uint64 vtable = process::read_uint64(base + 0x1234);

// GOOD — base and size are plain integers; check them once at startup
uint64 base = process::get_module_base("client.dll");
if (base == 0) {
    alert::show("client.dll not loaded");
    return false;
}
uint32 size = process::get_module_size(base);

uint64 vt_entry = process::read_uint64(entity_vtable + 0x18);
if (vt_entry < base || vt_entry > base + size) {
    alert::show(util::format_string("vtable[3] outside client.dll: {}", util::to_hex(vt_entry)));
}
```

### 18. Building the menu from a tick thread (or every frame)

```angelscript
// BAD — UI elements must be created once, in order, from main()
create_thread(64, function() {
    ui::add_tab("Main");            // re-registers the tab every tick
    ui::add_checkbox("ESP", true);
});

// GOOD — build the menu once in main(), then read values in the tick
bool main() {
    ui::add_tab("Main");
    ui::add_category("Options");
    g_enabled = ui::add_checkbox("ESP", true);
    create_thread(64, @tick);
    return true;
}

void tick() {
    if (ui::get(g_enabled)) { ... }
}
```

### 19. Assuming a read succeeded because the value is non-zero

```angelscript
// BAD — a failed read returns 0, so a non-zero value looks like a successful read
uint64 health = process::read_uint64(entity + 0x330);
if (health != 0) { ... }

// GOOD — use the out-parameter overload to distinguish failure from a real value
uint64 health = 0;
if (!process::read_uint64(entity + 0x330, health)) return;
```
