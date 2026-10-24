# Echo Universal API — Complete Reference

Full docs: https://echo-23.gitbook.io/angel  
LLM-optimized: https://echo-23.gitbook.io/angel/llms-full.txt  
Single-file bundle for LLMs: `llms.txt` in this repo root

---

## Script lifecycle

| Symbol | Signature | Notes |
|--------|-----------|-------|
| `main` | `void main()` | Required entry point. Called once on load. |
| `on_unload` | `void on_unload()` | Optional teardown before script unloads. |
| Script location | — | `%AppData%\Roaming\scripts\<name>.as` |
| Reload | — | Close + reopen the in-game overlay menu |

---

## Threading

```angelscript
create_thread(float tps, function@ cb)  // tps 1–128; 0 = run once; cb: void()
on_render(function@ cb)                 // cb called every frame on render thread
sleep(uint ms)                          // yield current thread for ms milliseconds
```

### mutex@

```angelscript
mutex@ m = mutex();
m.lock();           // exclusive write lock (blocks)
m.unlock();
m.lock_shared();    // shared read lock (multiple readers allowed)
m.unlock_shared();
```

### atomic_int

```angelscript
atomic_int n(0);
int  n.load()
n.store(int val)
int  n.exchange(int new_val)                         // returns old value
bool n.compare_exchange(int& expected, int desired)  // CAS; returns true on success
```

---

## process@ — process handle

```angelscript
process@ p = process.attach("GameName.exe")  // by image name
process@ p = process.attach(uint32 pid)      // by PID; returns null on failure
bool  proc.is_running()
proc.detach()
```

`proc` is a shorthand for the currently attached process in top-level scripts.

### Read / write

```angelscript
T     proc.read<T>(uint64 addr)          // T: uint8 uint16 uint32 uint64
                                         //    int8  int16  int32  int64
                                         //    float double
bool  proc.write<T>(uint64 addr, T val)
```

### Pattern scan

```angelscript
uint64 proc.scan(string pattern, string module)             // "48 8B ?? ?? 4D" space-sep, ?? = wild
uint64 proc.scan_ida(string pattern, string module)         // IDA style: "48 8B ? ? 4D"
uint64 proc.scan(string pattern, uint64 base, uint64 size)  // scan arbitrary region
uint64 proc.resolve_rip(uint64 instr_addr, uint32 disp_off, uint32 instr_len)
// resolve_rip: reads int32 at instr_addr+disp_off, adds to instr_addr+instr_len
// e.g. for LEA RAX,[RIP+disp] at addr: resolve_rip(addr, 3, 7)
```

### Module info

```angelscript
module_info@ m = proc.get_module(string name)
// m.base   uint64 — load address
// m.size   uint64 — size in bytes
// m.name   string — file name (e.g. "client.dll")
// returns null if module not loaded
```

### Memory regions

```angelscript
array<region_info@>@ proc.query_regions()
// region_info@ fields:
//   .base     uint64
//   .size     uint64
//   .protect  uint32  — PAGE_NOACCESS=1, PAGE_READONLY=2, PAGE_READWRITE=4, PAGE_EXECUTE_READ=0x20
//   .type     uint32  — MEM_PRIVATE=0x20000, MEM_MAPPED=0x40000, MEM_IMAGE=0x1000000
//   .is_heap  bool    — heuristic: private RW region not backed by a PE module
//   .module   string  — owning module name if MEM_IMAGE, else ""
```

### Module dump

```angelscript
bool proc.dump(string module_name, string output_path)  // output in scripts folder
```

---

## disasm — Zydis disassembler

```angelscript
instruction@ disasm.decode(process@ p, uint64 addr)
array<instruction@>@ disasm.decode_linear(process@ p, uint64 addr, uint32 count)
array<instruction@>@ disasm.decode_function(process@ p, uint64 addr)
array<instruction@>@ disasm.find_xrefs(process@ p, uint64 target, uint32 search_bytes)
```

### instruction@ fields

```angelscript
// .address        uint64   — address of this instruction
// .length         uint8    — byte length
// .mnemonic       string   — "MOV", "CALL", "LEA", etc.
// .operands_str   string   — full operand text, e.g. "RAX, [RCX+0x10]"
// .is_branch      bool
// .is_call        bool
// .is_ret         bool
// .branch_target  uint64   — resolved target for call/jmp (0 if indirect)
// .mem_disp       int64    — memory displacement (0 if no memory operand)
// .mem_base       int      — UC_X86_REG_* for base register (-1 if none)
// .mem_index      int      — UC_X86_REG_* for index register (-1 if none)
// .mem_scale      uint8    — SIB scale (1/2/4/8)
```

---

## emulator@ — Unicorn engine

```angelscript
emulator@ emu = emulator()             // standalone, no process backing
emulator@ emu = emulator(process@ p)  // unmapped reads fall through to proc.read
```

### Memory

```angelscript
emu.mem_map(uint64 addr, uint64 size, uint32 prot)   // prot: UC_PROT_* flags
emu.mem_write(uint64 addr, array<uint8>@ data)
array<uint8>@ emu.mem_read(uint64 addr, uint64 size)
emu.mem_unmap(uint64 addr, uint64 size)
```

### Registers

```angelscript
uint64 emu.reg_read(int reg)       // reg: UC_X86_REG_* constant
emu.reg_write(int reg, uint64 val)
```

**UC_X86_REG_* constants:**

| Constant | Register | Constant | Register |
|----------|----------|----------|----------|
| `UC_X86_REG_RAX` | rax | `UC_X86_REG_RBX` | rbx |
| `UC_X86_REG_RCX` | rcx | `UC_X86_REG_RDX` | rdx |
| `UC_X86_REG_RSI` | rsi | `UC_X86_REG_RDI` | rdi |
| `UC_X86_REG_RSP` | rsp | `UC_X86_REG_RBP` | rbp |
| `UC_X86_REG_R8`–`R15` | r8–r15 | `UC_X86_REG_RIP` | rip |
| `UC_X86_REG_RFLAGS` | rflags | `UC_X86_REG_XMM0`–`XMM15` | xmm0–15 |

**UC_PROT_* constants:**

| Constant | Value | Meaning |
|----------|-------|---------|
| `UC_PROT_NONE` | 0 | No access |
| `UC_PROT_READ` | 1 | Readable |
| `UC_PROT_WRITE` | 2 | Writable |
| `UC_PROT_EXEC` | 4 | Executable |
| `UC_PROT_ALL` | 7 | RWX |

### Hooks

```angelscript
emu.hook_code(function@ cb)          // cb: void(uint64 addr, uint32 size)
emu.hook_mem_read(function@ cb)      // cb: void(uint64 addr, uint32 size)
emu.hook_mem_write(function@ cb)     // cb: void(uint64 addr, uint32 size)
emu.hook_insn_invalid(function@ cb)  // cb: bool() — return true to skip bad insn
```

### Execution

```angelscript
emu.start(uint64 entry, uint64 until, uint32 timeout_ms, uint64 max_insns)
emu.stop()
emu.reset()
```

---

## renderer

All geometry calls use the `draw_` prefix. Text has shorter aliases.

```angelscript
int renderer.width()   // framebuffer width
int renderer.height()  // framebuffer height

// Rectangles
renderer.draw_rect_filled(float x, float y, float w, float h, color_t col)
renderer.draw_rect_outlined(float x, float y, float w, float h, float thick, color_t col)
renderer.draw_rect_gradient(float x, float y, float w, float h,
                             color_t tl, color_t tr, color_t bl, color_t br)

// Lines
renderer.draw_line(float x1, float y1, float x2, float y2, color_t col, float thick)

// Circles
renderer.draw_circle(float cx, float cy, float r, int segments, color_t col, float thick)
renderer.draw_circle_filled(float cx, float cy, float r, int segments, color_t col)

// Triangles
renderer.draw_triangle(float x1, float y1, float x2, float y2,
                        float x3, float y3, color_t col, float thick)
renderer.draw_triangle_filled(float x1, float y1, float x2, float y2,
                               float x3, float y3, color_t col)

// Text
font_handle@ renderer.load_font(string family, int size, bool bold)
renderer.text(float x, float y, string text, color_t col, font_handle@ font)
renderer.text_outlined(float x, float y, string text, color_t col,
                        color_t outline, font_handle@ font)
vec2 renderer.measure_text(string text, font_handle@ font)  // returns {width, height}
```

### color_t

```angelscript
color_t c = color_t(uint8 r, uint8 g, uint8 b, uint8 a)  // 0–255 each
color_t c = color_t(uint32 rgba)                          // packed 0xRRGGBBAA
uint8 c.r; c.g; c.b; c.a
```

---

## Menu

```angelscript
tab@          menu.add_tab(string name)
subtab@       tab.add_subtab(string name)
category@     subtab.add_category(string name)

// key = config persist key; omit or "" for no auto-save
checkbox@     cat.add_checkbox(string label, bool default, string key = "")
slider@       cat.add_slider(string label, float min, float max, float default, string key = "")
color_picker@ cat.add_color_picker(string label, color_t default, string key = "")
combobox@     cat.add_combobox(string label, array<string>@ items, int default, string key = "")
button@       cat.add_button(string label, function@ cb)   // cb: void()
keybind@      cat.add_keybind(string label, int default_vk, string key = "")
text_input@   cat.add_text_input(string label, string default, string key = "")

// Get current values
bool      checkbox.get()
float     slider.get()
color_t   color_picker.get()
int       combobox.get()    // selected index
int       keybind.get()     // current VK code
string    text_input.get()

el.set_visible(bool)
el.set_tooltip(string)
```

---

## Utilities

```angelscript
// Time
uint64 time.now()          // milliseconds
float  time.now_seconds()  // seconds as float

// Random
int   random.int(int min, int max)          // inclusive [min, max]
float random.float(float min, float max)    // [min, max)

// Encoding
string        encode.to_hex(array<uint8>@ data)
string        encode.to_base64(array<uint8>@ data)
array<uint8>@ encode.from_hex(string hex)
array<uint8>@ encode.from_base64(string b64)

// Hash
uint32 hash.crc32(array<uint8>@ data)
uint64 hash.fnv1a(string s)
uint64 hash.fnv1a(array<uint8>@ data)

// Format
string fmt(string format, ...)
// Specifiers: {} auto, {:d} int, {:.2f} float, {:X} upper hex,
//             {:x} lower hex, {:08X} zero-padded, {:s} string
```

---

## Networking

```angelscript
// HTTP (async; cb fires on completion)
http.get(string url, function@ cb)                   // cb: void(response@ r)
http.post(string url, string body, function@ cb)     // cb: void(response@ r)
http.post_json(string url, string json, function@ cb)
http.get_async(string url)                           // fire-and-forget

// response@ fields
// .ok      bool    — status < 400
// .status  int     — HTTP status code (200, 404, etc.)
// .body    string  — response body text

// WebSocket
ws@ sock = ws.connect(string url)      // ws:// or wss://
sock.on_message(function@ cb)          // cb: void(string msg)
sock.on_connect(function@ cb)          // cb: void()
sock.on_disconnect(function@ cb)       // cb: void()
sock.send(string msg)
sock.close()
bool sock.is_connected()
```

---

## Data structures

```angelscript
// JSON
json@ j = json.parse(string s)
json@ j = json.parse_file(string path)   // relative to scripts folder
int           j.get_int(string key)
float         j.get_float(string key)
string        j.get_string(string key)
bool          j.get_bool(string key)
json@         j.get_object(string key)
array<json@>@ j.get_array(string key)
bool          j.has(string key)
j.set(string key, T val)                 // T: int float string bool
string j.stringify()

// hash_map — uint64 → uint64
hash_map@ m = hash_map()
m.set(uint64 key, uint64 val)
uint64 m.get(uint64 key)      // returns 0 if missing
bool   m.has(uint64 key)
m.remove(uint64 key)
uint64 m.size()

// hash_set — uint64 keys
hash_set@ s = hash_set()
s.insert(uint64 key)
bool s.contains(uint64 key)
s.remove(uint64 key)
uint64 s.size()
```

---

## Math types

```angelscript
vec2(float x, float y)
vec3(float x, float y, float z)
vec4(float x, float y, float z, float w)

v.x; v.y; v.z; v.w          // field access
v + v; v - v; v * scalar; v / scalar
float v.length()
vec3  v.normalized()
float v.dot(vec3 b)
vec3  v.cross(vec3 b)        // vec3 only
float v.distance(vec3 b)

// Echo process I/O
v.read(process@ p, uint64 addr)    // reads 3 floats (vec3) from process
v.write(process@ p, uint64 addr)

// Matrices
mat3x4 / mat4x4
m[row][col]                         // row-major float access
vec3 m.transform_point(vec3 p)
vec3 m.transform_direction(vec3 d)
mat4x4.identity()
mat4x4 m.inverse()

// Math helpers
float math.rad_to_deg(float r)
float math.deg_to_rad(float d)
float math.normalize_angle(float deg)    // → [-180, 180]
float math.smooth_angle(float cur, float tgt, float factor)
float math.calc_fov(float dx, float dy)  // FOV angle in degrees
float math.lerp(float a, float b, float t)
float math.clamp(float v, float lo, float hi)
float math.abs(float v)
float math.sqrt(float v)
float math.sin(float rad); math.cos(float rad); math.atan2(float y, float x)
```

---

## Engine world-to-screen helpers

All return `bool` — `false` means behind camera or off-screen.

```angelscript
bool source2.w2s(process@ p, uint64 view_matrix_addr, vec3 world, float& sx, float& sy)
bool unreal.w2s(process@ p,  uint64 camera_addr,      vec3 world, float& sx, float& sy)
bool unity.w2s(process@ p,   uint64 camera_addr,      vec3 world, float& sx, float& sy)
bool source.w2s(process@ p,  uint64 view_matrix_addr, vec3 world, float& sx, float& sy)
// &out is equivalent to & for out-parameters
```

`view_matrix_addr` = pointer to 16 floats (column-major 4×4).  
`camera_addr` for Unreal = pointer to `FMinimalViewInfo` or `APlayerCameraManager`.

---

## Filesystem

Sandboxed to `%AppData%\Roaming\scripts\`. Max 2 directory levels deep.

```angelscript
file@ f = fs.open(string path, string mode)  // "r" "w" "a" "rb" "wb"
string f.read_all()
string f.read_line()
f.write(string s)
f.write_bytes(array<uint8>@ data)
f.close()

bool          fs.exists(string path)
fs.mkdir(string path)
fs.delete(string path)
array<string>@ fs.list(string dir)    // lists files in directory
```

---

## Input

```angelscript
// Keyboard
bool  input.key_down(int vk)       // true while held
bool  input.key_pressed(int vk)    // true on press edge (single tick)
bool  input.key_released(int vk)   // true on release edge (single tick)

// Mouse state
bool  input.mouse_down(int btn)    // btn: 0=LMB 1=RMB 2=MMB
vec2  input.mouse_pos()            // screen coordinates
float input.mouse_scroll()         // scroll delta this tick (positive = up)

// Mouse output
mouse.move(int dx, int dy)         // relative, raw input
mouse.move_to(int x, int y)        // absolute screen position
mouse.click(int btn)               // instantaneous click
mouse.scroll(int delta)
```

**Common VK codes:**

| Name | Code | Name | Code |
|------|------|------|------|
| `VK_LBUTTON` | 1 | `VK_RBUTTON` | 2 |
| `VK_SHIFT` | 16 | `VK_CONTROL` | 17 |
| `VK_MENU` (Alt) | 18 | `VK_CAPITAL` | 20 |
| `VK_SPACE` | 32 | `VK_INSERT` | 45 |
| `VK_DELETE` | 46 | `VK_HOME` | 36 |
| `VK_F1`–`VK_F12` | 112–123 | `VK_NUMPAD0`–`9` | 96–105 |
| `'A'`–`'Z'` | 65–90 | `'0'`–`'9'` | 48–57 |

---

## Audio

```angelscript
audio.play(string path)                  // .wav relative to scripts folder
audio.play(string path, float volume)    // volume: 0.0–1.0
audio.stop()
```

---

## AngelScript built-ins

### string

```angelscript
string s = "hello " + name;   // concatenation
s.length()            // uint
s.empty()             // bool
s.find(string sub)    // int — first index or -1
s.substr(int start, int len)
s.replace(string from, string to)
array<string>@ s.split(string delim)
s.to_lower()
s.to_upper()
int   s.to_int()
float s.to_float()
```

### array<T>

```angelscript
array<uint64> a;
a.length()                 // uint
a.push_back(val)
a.pop_back()
a.insert_at(uint i, val)
a.remove_at(uint i)
a.resize(uint n)
a[i]                       // no bounds check — crashes if i >= length()
a.sort()                   // primitives; sorts in-place ascending
```

Array of handles: `array<entity@>` — stores object references, not values.

### function handles

```angelscript
// Lambdas (no captures unless annotated)
function@ cb = function() { alert("hello"); };

// Closure capturing outer variable
int count = 0;
function@ inc = [count]() { count++; };   // captures by value at definition time
```

---

## Alert / debug output

```angelscript
alert(string msg)              // shows overlay popup
print(string msg)              // writes to Echo console/log
```
