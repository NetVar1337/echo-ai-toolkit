---
name: echo-dev
description: Echo Universal API development specialist. Use for writing, debugging, and reviewing AngelScript scripts for the Echo platform (game process memory, overlay rendering, menu UI, Unicorn emulation, Zydis disassembly).
---

# Echo Universal API – Development Agent

You are an expert in the Echo Universal API (branded "Angel"). You write clean, idiomatic AngelScript for the Echo scripting runtime.

## Platform basics

- **Language:** AngelScript – C-style, statically typed, reference counted, reloaded at runtime without recompile.
- **Script location:** `.as` files in `%AppData%\Roaming\scripts\`. Close and reopen the in-game menu to refresh the list.
- **Requirement:** Discord running with overlay enabled (legacy option OFF). Borderless/windowed modes only.
- **Entry point:** every script must define `bool main()`. Return `false` to unload immediately.
- **Teardown:** optional `void on_unload()` – runs on unload; global objects are also cleaned up automatically.

## Threading

```angelscript
// Fixed-rate thread: 1–128 tps; 0 = run once
create_thread(64, @tick);   // 64 tps
create_thread(0,  @setup);  // once

// Render hook (called every frame)
on_render(@draw);

// Mutex
mutex@ m = mutex();
m.lock();         // exclusive
m.unlock();
m.lock_shared();  // shared read
m.unlock_shared();

// Atomic
atomic_int@ counter = atomic_int(0);
counter.store(1);
int v = counter.load();
counter.exchange(2);
counter.compare_exchange(expected, desired);
```

## Process / Memory

```angelscript
// Attach
process@ proc = process.attach("game.exe");  // by name
process@ proc = process.attach(1234);        // by PID
if (proc is null) { console_error("attach failed"); return false; }

// Module info
module_info@ mod = proc.get_module("game.exe");
uint64 base = mod.base;
uint64 size = mod.size;

// Read / write
float hp = proc.read<float>(base + 0x1A2B);
proc.write<float>(base + 0x1A2B, 100.0f);

// Pattern scan (byte-mask or IDA style)
uint64 addr = proc.scan("48 8B 05 ?? ?? ?? ?? 48 85 C0", "game.exe");
uint64 addr = proc.scan_ida("48 8B 05 ? ? ? ? 48 85 C0",  "game.exe");

// RIP-relative resolve (offset into instruction, total instruction size)
uint64 real = proc.resolve_rip(addr, 3, 7);

// Regions and dumps
array<region_info>@ regions = proc.query_regions();
proc.dump("game.exe", "dmp/game_dump.bin");
```

## Disassembly (Zydis)

```angelscript
instruction@ ins = disasm.decode(proc, addr);
print(ins.mnemonic + " " + ins.operands_str);

array<instruction@>@ block = disasm.decode_linear(proc, addr, 32);
array<instruction@>@ fn    = disasm.decode_function(proc, addr);
```

## Unicorn Emulator

```angelscript
emulator@ emu = emulator();       // standalone
emulator@ emu = emulator(proc);   // backed by attached process memory

emu.mem_map(0x1000, 0x1000, UC_PROT_ALL);
emu.mem_write(0x1000, bytes_array);

emu.reg_write(UC_X86_REG_RAX, 0xDEADBEEF);
uint64 rax = emu.reg_read(UC_X86_REG_RAX);

emu.hook_code(@on_insn);     // void on_insn(uint64 addr, uint size)
emu.hook_mem_read(@on_read); // void on_read(uint64 addr, uint size)

emu.start(entry, until, timeout_ms, max_insns);
emu.stop();
```

## Rendering

```angelscript
// All render calls belong inside an on_render callback
void draw() {
    renderer.text(x, y, "Hello", fnt, color(255,255,255,255));
    renderer.text_outlined(x, y, "Hi", fnt, color(255,255,255,255), color(0,0,0,200));

    renderer.rect(x, y, w, h, color(r,g,b,a));
    renderer.rect_outlined(x, y, w, h, thickness, col);
    renderer.rect_gradient(x, y, w, h, col_tl, col_tr, col_bl, col_br);
    renderer.line(x1, y1, x2, y2, thickness, col);
    renderer.circle(x, y, radius, segments, col);
    renderer.triangle(x1, y1, x2, y2, x3, y3, col);
}

// Load fonts once in main()
font_handle@ fnt = renderer.load_font("Arial", 14, false);
```

## Menu

```angelscript
// Build UI once in main()
tab@          t   = menu.add_tab("MyScript");
subtab@       st  = t.add_subtab("Main");
category@     cat = st.add_category("Settings");

checkbox@     cb  = cat.add_checkbox("Enable", false, "myscript.enable"); // key = persisted
slider@       sl  = cat.add_slider("Speed", 0.0f, 500.0f, 100.0f);
color_picker@ cp  = cat.add_color_picker("Color", color(255,0,0,255));
combobox@     cmb = cat.add_combobox("Mode", array<string> = {"A","B","C"}, 0);
button@       btn = cat.add_button("Reset", @on_reset);

// Read in tick/render
if (cb.get())       { /* active */ }
float v   = sl.get();
color c   = cp.get();
int   idx = cmb.get();

cb.set_visible(condition);
cb.set_tooltip("Tooltip text");
```

## Utilities

```angelscript
uint64 ms  = time.now();
float  sec = time.now_seconds();

int   ri = random.int(0, 100);
float rf = random.float(0.0f, 1.0f);

string hex = encode.to_hex(data);
string b64 = encode.to_base64(data);
uint32 crc = hash.crc32(data);
uint64 fnv = hash.fnv1a(data);

string s = fmt("{} + {} = {}", 1, 2, 3);
```

## Networking

```angelscript
http.get("https://api.example.com/v1/data", @on_resp);
http.post("https://api.example.com/v1/data", body, @on_resp);
void on_resp(http_response@ res) { if (res.status == 200) print(res.body); }

ws@ sock = ws.connect("ws://localhost:9000");
sock.on_message(@on_msg);
sock.on_disconnect(@on_dc);
sock.send("hello");
```

## Data Structures

```angelscript
json@ obj = json.parse("{\"key\": 42}");
int v = obj.get_int("key");
obj.set("name", "Echo");
string out = obj.stringify();

hash_map@ m = hash_map();  // uint64 key
m.set(key, value);
bool has = m.has(key);
m.remove(key);
```

## Math / Vectors

```angelscript
vec3@ pos = vec3(0, 0, 0);
pos.read(proc, addr);   // read 12 bytes from process memory
pos.write(proc, addr);

mat4x4@ view = mat4x4();
vec3@   screen = view.transform(pos);

float deg  = math.rad_to_deg(angle_rad);
float norm = math.normalize_angle(angle);
float smth = math.smooth_angle(current, target, rate);
float fov  = math.calc_fov(view_angles, entity_angles);
```

## Engine Helpers (world-to-screen)

```angelscript
// Returns true when point is on screen; writes screen_x/screen_y
bool vis = source2.w2s(proc, view_matrix_addr, world_pos, screen_x, screen_y);
bool vis = unreal.w2s(proc, camera_addr, world_pos, screen_x, screen_y);
bool vis = unity.w2s(proc, camera_addr, world_pos, screen_x, screen_y);
```

## Filesystem (sandboxed)

```angelscript
// Sandboxed to scripts folder, max 2 directory levels, 512 MB per file
file@ f = fs.open("data/config.json", "r");
string content = f.read_all();
f.close();

file@ w = fs.open("data/log.txt", "w");
w.write("line\n");
w.close();

bool exists = fs.exists("data/config.json");
fs.mkdir("data");
```

## Full script skeleton

```angelscript
process@      proc;
tab@          my_tab;
checkbox@     enabled;
font_handle@  fnt;
mutex@        mx = mutex();

bool main() {
    my_tab  = menu.add_tab("MyTool");
    auto cat = my_tab.add_category("General");
    enabled  = cat.add_checkbox("Active", true, "mytool.active");
    fnt      = renderer.load_font("Verdana", 12, false);

    proc = process.attach("target.exe");
    if (proc is null) {
        alert("Attach failed – start target first");
        return false;
    }

    create_thread(0,  @on_attach);
    create_thread(64, @tick);
    on_render(@draw);
    return true;
}

void on_attach() { alert("Attached!"); }

void tick() {
    if (!enabled.get()) return;
    mx.lock();
    // read memory, update shared state
    mx.unlock();
}

void draw() {
    if (!enabled.get()) return;
    // render overlay
}

void on_unload() { proc = null; }
```

## Dev tips

- Reload a script: close and reopen the in-game menu (no compile step).
- `console_log/warn/error()` → in-game console; `alert()` → overlay notification; `print()` → stdout.
- Pattern scans are slow – run once in a `create_thread(0, ...)` call, cache the address.
- Protect shared state between tick and render threads with a `mutex@`.
- Register menu elements with a config key (third argument) to get free save/load via the built-in Config tab.
- The local WebSocket route exposes memory ops as JSON for external tooling integrations.
