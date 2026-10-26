# Echo Universal API — Complete Reference

Source of truth: https://echo-23.gitbook.io/angel/llms-full.txt (fetched 2026-10-25)
Single-file LLM bundle: `llms.txt` in this repo root
Correction rules: `reference/_API_CONTRACT.md`

Every call in this file exists in the real Echo runtime. If a call is not listed here, it
does not exist — do not invent one.

---

## Script lifecycle

| Symbol | Signature | Notes |
|--------|-----------|-------|
| `main` | `bool main()` | **Mandatory** entry point. Return `true` on success, `false` to unload the script. A script without `bool main()` does not compile. |
| `on_unload` | `void on_unload()` | Optional. Runs when the script is unloaded — undo writes, release resources. Globals/handles are reference-counted and cleaned up automatically. |
| `print` | `void print(? msg)` | Global. Writes to the Echo console/log. `?` accepts any type. |
| Script location | — | `%AppData%\Roaming\scripts\<name>.as` |
| Reload | — | Close and reopen the overlay menu to refresh the script list |

There is **no `sleep()`**. Periodic work is a tick thread — `create_thread(tps, cb)` with
`tps` 1–128 — and a one-shot task is `create_thread(0, cb)`. Delay inside a tick is a
`util::time_now()` gate, not a sleep.

```angelscript
void on_unload() {
    // teardown
}

bool main() {
    return true;
}
```

---

## Threading

| Symbol | Signature | Notes |
|--------|-----------|-------|
| `create_thread` | `void create_thread(int tps, thread_callback@ cb)` | Ticking threads (tps **1–128**) can only be created from `main()`. One-shot threads (tps `0`) can be created from any context. Drift-free; tick time accumulates. `0` = run once and exit. |
| `on_render` | `void on_render(thread_callback@ cb)` | Registers a callback invoked every frame on the render thread. **All `render::` drawing calls must happen here.** |
| `create_mutex` | `mutex@ create_mutex()` | Handle is `mutex@`. Null check with `is null`. |

`thread_callback` funcdef: `void thread_callback() {}`

### mutex@ methods

| Method | Notes |
|--------|-------|
| `m.lock()` | Exclusive lock, blocks until available |
| `m.unlock()` | Release exclusive lock |
| `m.try_lock()` | Non-blocking acquire, returns `bool` |
| `m.lock_shared()` | Shared lock (multiple concurrent readers) |
| `m.unlock_shared()` | Release shared lock |

### Atomics

Lock-free thread-safe primitives, acquire/release memory ordering.

| Symbol | Signature |
|--------|-----------|
| `atomic_bool@` | `atomic_bool(bool value)` |
| `atomic_int32@` | `atomic_int32(int value)` |
| `atomic_uint32@` | `atomic_uint32(uint value)` |
| `atomic_int64@` | `atomic_int64(int64 value)` |
| `atomic_uint64@` | `atomic_uint64(uint64 value)` |
| `atomic_float@` | `atomic_float(float value)` |
| `atomic_double@` | `atomic_double(double value)` |

Methods: `.load()` → current value; `.store(value)`; `.exchange(value)` → previous value;
`.compare_exchange(expected, desired)` → observed value (equals `expected` on success).

```angelscript
mutex@ g_lock = create_mutex();
int g_shared_counter = 0;
atomic_int32@ g_atomic_counter = atomic_int32(0);

void fast_tick() {
    g_lock.lock();
    g_shared_counter++;
    g_lock.unlock();
}

void render_tick() {
    g_lock.lock_shared();
    int shared = g_shared_counter;
    g_lock.unlock_shared();
    print("shared: " + shared + " atomic: " + g_atomic_counter.load());
}

bool main() {
    create_thread(128, @fast_tick);
    on_render(@render_tick);
    return true;
}
```

**Sharing rule:** unsynchronised global access across threads can race the AngelScript
engine and take the process down. Build a snapshot locally, then swap it in under the mutex;
readers take their own handle and read lock-free afterwards.

---

## Process

```cpp
struct attach_data {
    uint64 pid;
    uint64 peb_address;
    uint64 base_address;
}

struct module_entry {
    string name;
    uint64 base;
    uint64 size;
}

struct memory_region {
    uint64 base;
    uint64 size;
    bool present;
    bool writable;
    bool executable;
}
```

The process API has direct access to physical memory. Page protections and copy-on-write
have no effect. The target process is never injected into.

### Attach / lifecycle

| Signature | Returns | Notes |
|-----------|---------|-------|
| `attach_data process::attach(string name)` | attach_data | Attach by image name. `pid == 0` means failure. |
| `attach_data process::attach(uint32 pid)` | attach_data | Attach by PID. `pid == 0` means failure. |
| `void process::detach()` | — | Detach. |
| `bool process::is_alive()` | bool | Target still running? Use this instead of a cached `valid` flag. |

### Reads — value form (returns default on failure)

| Signature | Failure value |
|-----------|---------------|
| `array<uint8>@ process::read_bytes(uint64 address, uint32 size)` | `null` |
| `int8 process::read_int8(uint64 address)` | `0` |
| `uint8 process::read_uint8(uint64 address)` | `0` |
| `int16 process::read_int16(uint64 address)` | `0` |
| `uint16 process::read_uint16(uint64 address)` | `0` |
| `int32 process::read_int32(uint64 address)` | `0` |
| `uint32 process::read_uint32(uint64 address)` | `0` |
| `int64 process::read_int64(uint64 address)` | `0` |
| `uint64 process::read_uint64(uint64 address)` | `0` |
| `float process::read_float(uint64 address)` | `0.0` |
| `double process::read_double(uint64 address)` | `0.0` |
| `string process::read_string(uint64 address)` | `""` — null-terminated, 256 char max. Use `read_bytes` for wide strings. |

### Reads — out-param form (returns true on success)

`bool process::read_int8(uint64 address, int8 &out)` and the same for `uint8`, `int16`,
`uint16`, `int32`, `uint32`, `int64`, `uint64`, `float`, `double`, `string`.

### Writes (all return true on success)

| Signature | Notes |
|-----------|-------|
| `bool process::write_bytes(array<uint8> bytes, uint64 address)` | Bytes **first**, address second. |
| `bool process::write_int8(uint64 address, int8 value)` | |
| `bool process::write_uint8(uint64 address, uint8 value)` | |
| `bool process::write_int16(uint64 address, int16 value)` | |
| `bool process::write_uint16(uint64 address, uint16 value)` | |
| `bool process::write_int32(uint64 address, int32 value)` | |
| `bool process::write_uint32(uint64 address, uint32 value)` | |
| `bool process::write_int64(uint64 address, int64 value)` | |
| `bool process::write_uint64(uint64 address, uint64 value)` | |
| `bool process::write_float(uint64 address, float value)` | |
| `bool process::write_double(uint64 address, double value)` | |

### Modules

| Signature | Returns | Notes |
|-----------|---------|-------|
| `uint64 process::get_module_base(string name)` | uint64 | `0` if not found. **Required base for `find_signature`.** |
| `uint32 process::get_module_size(uint64 base)` | uint32 | `0` if not found. |
| `uint64 process::get_module_export(uint64 base, string name)` | uint64 | `0` if not found. |
| `array<module_entry>@ process::get_module_list()` | handle array | `null` on failure. |

### Pattern scanning

| Signature | Returns |
|-----------|---------|
| `uint64 process::find_signature(uint64 base, string sig, string mask)` | `0` if not found |
| `uint64 process::find_signature(uint64 base, string sig, string mask, uint64 range_offset, uint64 range_length)` | `0` if not found |
| `uint64 process::find_signature(uint64 base, string sig)` | IDA-style pattern, `0` if not found |
| `uint64 process::find_signature(uint64 base, string sig, uint64 range_offset, uint64 range_length)` | IDA-style pattern, `0` if not found |
| `array<uint64>@ process::find_signatures(uint64 base, string sig, string mask)` | handle array of hits |
| `array<uint64>@ process::find_signatures(uint64 base, string sig, string mask, uint64 range_offset, uint64 range_length)` | handle array of hits |
| `array<uint64>@ process::find_signatures(uint64 base, string sig)` | IDA-style, all hits |
| `array<uint64>@ process::find_signatures(uint64 base, string sig, uint64 range_offset, uint64 range_length)` | IDA-style, all hits |
| `uint64 process::get_relative_address(uint64 address, uint32 offset, uint32 inst_size)` | Resolves RIP-relative operand |

Masked form: `sig` is hex bytes, `mask` uses `x` to match and `?` to wildcard.
IDA form: wildcards are `?` or `??`.

```angelscript
uint64 base = process::get_module_base("game.exe");
if (base == 0) return false;
uint64 sig = process::find_signature(base, "48 8B 0D ? ? ? ?");
if (sig == 0) return false;
uint64 target = process::get_relative_address(sig, 3, 7);
```

### Regions / dumps / socket

| Signature | Notes |
|-----------|-------|
| `memory_region process::virtual_query(uint64 address)` | Contiguous region with uniform flags containing the address. When `present == false`, `base`/`size` still describe the unmapped hole — advance by `base + size` to enumerate all regions including gaps. |
| `bool process::dump(string filename)` | Dump main executable into the `dmp` folder inside the scripts folder. |
| `bool process::dump(string module_name, string filename)` | Dump a specific module. |
| `bool process::open_socket(const string url)` | Opens a **WebSocket client** to `url` and starts a background receive loop. Requires an attached process; only one connection at a time. Returns `false` if no process is attached or a connection is already active. |

The process socket speaks JSON over UTF-8 WebSocket frames. Every request carries a
`"type"` string and an optional integer `"id"` (default `0`) echoed in the response.

| Route | Request fields | Response fields |
|-------|----------------|-----------------|
| `ping` | — | `attached`, `pid`, `base` (hex string) |
| `read` | `address` (hex string), `size` | `success`, `address`, `size`, `data` (lowercase hex) |
| `read_batch` | `reads[]` of `{address,size}` (≤ 64 KiB each) | `success`, `results[]` of `{success,address,data}` |
| `modules` | — | `success`, `modules[]` of `{name,base,size}` |
| `sig_scan` | `sig`, `mask`, `module`, `find_all` | `success`, `results[]`, `module`, `sig`, `mask` |
| `sig_scan_ida` | `pattern`, `module`, `find_all` | `success`, `results[]`, `module`, `pattern` |
| `string_scan` | `text`, `module`, `find_all` | `success`, `results[]`, `module`, `text` |
| `resolve_relative` | `address`, `offset`, `inst_size` | `success`, `address` |
| `rtti_resolve` | `address` | `success`, `address`, `name` |
| `rtti_resolve_batch` | `addresses[]` | `success`, `results[]` of `{success,name}` |
| `enumerate_functions` | `module` | `success`, `module`, `count`, `results[]` of `{address,size,method}` |
| `disassemble` | `address`, `size` | `success`, `complete`, `address`, `count`, `results[]` of `{address,length,bytes,text}` |

Error route: `{"type":"error","id":N,"code":1002,"message":"...","detail":"..."}`.
Codes: 1000 unknown type, 1001 not attached, 1002 bad arguments, 1003 module not found,
1004 size out of range (1..1048576), 1005 read failed, 1006 enumeration failed,
1007 disassembly failed.

---

## Memory buffer

`memory_buffer@ process::read_buffer(uint64 address, uint64 size)` — bulk read for
efficient multi-field access. **Returns `null` on failure.** One buffer read, then many
offset reads, beats many single reads for struct layouts.

| Method | Notes |
|--------|-------|
| `uint8 memory_buffer::read_uint8(uint64 offset)` | |
| `uint16 memory_buffer::read_uint16(uint64 offset)` | |
| `uint32 memory_buffer::read_uint32(uint64 offset)` | |
| `uint64 memory_buffer::read_uint64(uint64 offset)` | |
| `int8 memory_buffer::read_int8(uint64 offset)` | |
| `int16 memory_buffer::read_int16(uint64 offset)` | |
| `int32 memory_buffer::read_int32(uint64 offset)` | |
| `int64 memory_buffer::read_int64(uint64 offset)` | |
| `float memory_buffer::read_float(uint64 offset)` | |
| `double memory_buffer::read_double(uint64 offset)` | |
| `vec2 memory_buffer::read_vec2_float(uint64 offset)` | |
| `vec2 memory_buffer::read_vec2_double(uint64 offset)` | |
| `vec3 memory_buffer::read_vec3_float(uint64 offset)` | |
| `vec3 memory_buffer::read_vec3_double(uint64 offset)` | |
| `vec4 memory_buffer::read_vec4_float(uint64 offset)` | |
| `vec4 memory_buffer::read_vec4_double(uint64 offset)` | |
| `uint64 memory_buffer::size()` | Bytes in the buffer |

```angelscript
memory_buffer@ buf = process::read_buffer(entity, 64);
if (buf is null) return;
float hp = buf.read_float(0x334);
vec3 origin = buf.read_vec3_float(0x138);
```

---

## Zydis disassembler

```cpp
struct disasm_operand {
    int type;            // op_type value
    int visibility;      // op_visibility value
    int action;          // op_action bitmask
    int reg;             // valid when type == op_type::reg
    bool imm_is_signed;
    bool imm_is_relative;
    uint64 imm_value;
    int mem_segment;
    int mem_base;
    int mem_index;
    uint8 mem_scale;
    int64 mem_disp;
    bool mem_has_disp;
}

struct disasm_insn {
    uint64 runtime_address;
    uint8 length;
    int mnemonic;
    string text;            // Intel syntax
    uint8 operand_count;
    uint8 operand_count_visible;
    disasm_operand get_op(uint8 idx) const;  // default operand if out of range
}
```

| Signature | Returns | Notes |
|-----------|---------|-------|
| `string zydis::reg_name(int reg)` | string | Name for `disasm_operand::reg`. |
| `bool zydis::disasm(const array<uint8>@ &in bytes, array<disasm_insn@> &out insns)` | bool | Disassemble all bytes. |
| `bool zydis::disasm(const array<uint8>@ &in bytes, uint64 rip, array<disasm_insn@> &out insns)` | bool | `rip` sets the base address — affects display and resolves RIP-relative operands. |
| `bool zydis::disasm_func(const array<uint8>@ &in bytes, array<disasm_insn@> &out insns)` | bool | Disassemble until the first `ret`/`iret`. Returns `false` if the 4096-instruction limit is hit without a return. |
| `bool zydis::disasm_func(const array<uint8>@ &in bytes, uint64 rip, array<disasm_insn@> &out insns)` | bool | Same, with base address. |

Enums: `op_type::unused|reg|mem|ptr|imm`;
`op_visibility::invalid|explicit|implicit|hidden`;
`op_action::read|write|readwrite|condread|condwrite|read_condwrite|condread_write`.

```angelscript
array<uint8>@ bytes = process::read_bytes(addr, 64);
if (bytes is null) return;
array<disasm_insn@> insns;
if (!zydis::disasm(bytes, addr, insns)) return;
for (uint i = 0; i < insns.length(); i++) {
    print(insns[i].text);
}
```

---

## Unicorn emulator

Handles are opaque `uint64`. `0` means creation failed. `uc::close(h)` releases the handle,
its mappings and its hooks; handles left open are cleaned up on script unload.
The emulator is **x86_64 only** — there is no mode parameter and all register access goes
through `x86_reg`.

### Create / run

| Signature | Notes |
|-----------|-------|
| `uint64 uc::create()` | Standalone emulator. `0` on failure. |
| `uint64 uc::create_process()` | Emulator backed by the **currently attached process**: pages fault in on demand using the process virtual memory layout, mapped at region granularity with correct Win32 protection flags. If a region overlaps an already-mapped area only the faulting page is mapped. Write faults to unmapped regions are **not** auto-mapped and stop emulation. The process is never modified. `0` if no process is attached. |
| `void uc::close(uint64 h)` | Release handle, mappings, hooks. |
| `bool uc::setup_stack(uint64 h, uint64 base, uint64 size, uint64 stop_address)` | Maps a stack and sets `rsp` to the top; writes `stop_address` there so `ret` halts emulation. |
| `int uc::start(uint64 h, uint64 begin, uint64 end, uint64 timeout = 0, uint64 count = 0)` | Timeout in **microseconds**, `count` in instructions (`0` = unlimited). Returns a `uc::error` value; `uc::error::ok` on clean exit. |
| `void uc::stop(uint64 h)` | Stop a running emulation from inside a hook. |
| `bool uc::flush_code(uint64 h)` | Invalidate the translation cache after self-modifying code. |
| `uint32 uc::last_error(uint64 h)` | Last error code after a failed `start()`. |
| `uint64 uc::fault_address(uint64 h)` | Faulting address after a failed `start()`. |

### Hooks

| Signature | Notes |
|-----------|-------|
| `bool uc::hook_code(uint64 h, code_hook_fn@ cb, uint64 begin = 1, uint64 end = 0)` | `begin > end` (the default) means the hook fires for all addresses. |
| `bool uc::hook_memory_unmapped(uint64 h, mem_hook_fn@ cb, uint64 begin = 1, uint64 end = 0)` | |

Callback funcdefs — **return `false` from a code hook to stop emulation**:

```cpp
bool code_hook_fn(uint64 h, uint64 address, uint32 size) {}
bool mem_hook_fn(uint64 h, uc::mem_type type, uint64 address, uint32 size, uint64 value) {}
```

### Registers

| Signature | Notes |
|-----------|-------|
| `bool uc::reg_read64(uint64 h, x86_reg reg, uint64 &out val)` | |
| `bool uc::reg_write64(uint64 h, x86_reg reg, uint64 val)` | |
| `bool uc::reg_read128(uint64 h, x86_reg reg, array<uint8> &out data)` | XMM — array must be exactly 16 bytes. |
| `bool uc::reg_write128(uint64 h, x86_reg reg, const array<uint8> &in data)` | |
| `bool uc::reg_read256(uint64 h, x86_reg reg, array<uint8> &out data)` | YMM — array must be exactly 32 bytes. |
| `bool uc::reg_write256(uint64 h, x86_reg reg, const array<uint8> &in data)` | |

`x86_reg` members: `rax rbx rcx rdx rsi rdi rbp rsp rip eflags r8..r15`; segment
`cs ds es fs gs ss fs_base gs_base`; control `mxcsr`; `xmm0..xmm15`; `ymm0..ymm15`.

### Memory

| Signature | Notes |
|-----------|-------|
| `bool uc::mem_map(uint64 h, uint64 address, uint64 size, uint perms)` | |
| `bool uc::mem_unmap(uint64 h, uint64 address, uint64 size)` | |
| `bool uc::mem_protect(uint64 h, uint64 address, uint64 size, uint perms)` | |
| `bool uc::mem_write(uint64 h, uint64 address, const array<uint8> &in data)` | |
| `bool uc::mem_read(uint64 h, uint64 address, uint32 size, array<uint8> &out data)` | |
| `int uc::mem_query(uint64 h, uint64 address)` | `uc::prot` bitmask, or `-1` if unmapped. For `create_process()` handles an unmapped address falls back to the host process protection. |
| `bool uc::mem_regions(uint64 h, array<uc_memory_region> &out regions)` | Every mapped region. |

Enums: `uc::prot::none|read|write|exec|all` (bitwise-OR combinable);
`uc::mem_type::read|write|fetch|read_unmapped|write_unmapped|fetch_unmapped|read_prot|write_prot|fetch_prot`;
`uc::error::ok|nomem|arch|handle|mode|version|read_unmapped|write_unmapped|fetch_unmapped|fetch_prot|read_prot|write_prot|map|hook|insn_invalid`.

```angelscript
uint64 h = uc::create();
if (h == 0) return;
uc::mem_map(h, 0x1000, 0x1000, uc::prot::read | uc::prot::exec);
uc::mem_write(h, 0x1000, bytes);
uc::reg_write64(h, x86_reg::rip, 0x1000);
int err = uc::start(h, 0x1000, 0x1100, 1000000, 0);
if (err != uc::error::ok) { uc::close(h); return false; }
uc::close(h);
```

---

## SIMD & bit operations

All SSE functions take/return `array<uint8>` of exactly **16 bytes** (128 bits).
All are global functions (no namespace prefix).

### Bit rotation / byte swap

`uint8 rol8(uint8, int)`, `uint8 ror8(uint8, int)`, `uint16 rol16/ror16`,
`uint32 rol32/ror32`, `uint64 rol64/ror64`;
`uint16 bswap16(uint16)`, `uint32 bswap32(uint32)`, `uint64 bswap64(uint64)`.

### Bit manipulation

`int popcnt32(uint32)`, `int popcnt64(uint64)`;
`int lzcnt32(uint32)`, `int lzcnt64(uint64)` (leading zeros from MSB);
`int tzcnt32(uint32)`, `int tzcnt64(uint64)` (trailing zeros from LSB).

### SSE logical

`mm_xor_si128(a, b, &out)`, `mm_or_si128(a, b, &out)`, `mm_and_si128(a, b, &out)`,
`mm_andnot_si128(a, b, &out)` (`(~a) & b`).

### SSE shift

`mm_slli_epi16`, `mm_srli_epi16`, `mm_slli_epi32`, `mm_srli_epi32`, `mm_slli_epi64`,
`mm_srli_epi64` — each `(array<uint8> a, int imm8, array<uint8> &out result)`;
`mm_slli_si128(a, int imm8, &out)` / `mm_srli_si128` — byte-granular shifts.

### SSE shuffle / unpack

`mm_shuffle_epi8(a, b, &out)` (pshufb), `mm_shuffle_epi32(a, int imm8, &out)` (pshufd),
`mm_shufflehi_epi16(a, int imm8, &out)`, `mm_shufflelo_epi16(a, int imm8, &out)`;
`mm_unpackhi_epi8/16/32/64(a, b, &out)`, `mm_unpacklo_epi8/16/32/64(a, b, &out)`.

### SSE arithmetic

`mm_add_epi8/16/32/64(a, b, &out)`, `mm_sub_epi8/16/32/64(a, b, &out)`,
`mm_mullo_epi16(a, b, &out)`, `mm_mullo_epi32(a, b, &out)`.

### SSE set / broadcast / extract / compare

`mm_setzero_si128(&out)`;
`mm_set_epi64x(int64 e1, int64 e0, &out)`, `mm_set_epi32(int32 e3, e2, e1, e0, &out)`;
`mm_set1_epi64x(int64, &out)`, `mm_set1_epi32(int32, &out)`, `mm_set1_epi16(int16, &out)`,
`mm_set1_epi8(int8, &out)`; `broadcast_qword(uint64, &out)`, `broadcast_dword(uint32, &out)`;
`int64 mm_extract_epi64(array<uint8>, int index)`, `int mm_extract_epi32(...)`,
`int mm_extract_epi16(...)`, `int mm_extract_epi8(...)`;
`mm_cmpeq_epi8/16/32(a, b, &out)` — result bytes are `0xFF` for a match, `0x00` otherwise.

---

## Render

**All drawing calls work only inside the render thread** (`on_render(@cb)`).
Exceptions callable from any context: `render::get_fps`, `render::get_frametime`,
`render::is_foreground`, `render::get_viewport_size`, `render::load_font`,
`render::load_image`.

**Colour arguments are four separate ints `r, g, b, a` (0–255)** — there is no colour
struct parameter on render calls.

### General

| Signature | Returns | Notes |
|-----------|---------|-------|
| `float render::get_fps()` | float | Any context. |
| `float render::get_frametime()` | float | Any context. |
| `bool render::is_foreground()` | bool | Any context. True when the overlay is visible on screen. |
| `vec2 render::get_viewport_size()` | vec2 | Any context. `.x` = width, `.y` = height. |
| `bool render::get_viewport_size(int &out width, int &out height)` | bool | Any context. Out-param form. |
| `void render::set_anti_aliasing(bool enabled)` | — | Current frame; can be toggled between draw calls. |

### Fonts

```cpp
enum fonts { PROGGY, TAHOMA, TAHOMA_PX, TAHOMA_BOLD, TAHOMA_BOLD_PX, SMALLEST_PIXEL_7, TAHOMISH };
enum font_hint { NONE, AUTO, MONO };
struct font_handle { int index; }
```

| Signature | Notes |
|-----------|-------|
| `bool render::load_font(const array<uint8> &in, font_handle &out, font_hint = font_hint::AUTO)` | Any context. Loads raw font bytes. |
| `void render::update_font(font_handle font, int size)` | Render context only. |
| `void render::update_font(fonts font, int size)` | Render context only. |

### Images

| Signature | Notes |
|-----------|-------|
| `bool render::load_image(string data, image &out obj)` | Any context. Encoded image bytes. |
| `void render::draw_image(image obj, int x, int y, int w, int h)` | Render context. |
| `void render::draw_image(image obj, int x, int y, int w, int h, int r, int g, int b, int a)` | Render context, tinted. |

### Text

| Signature | Notes |
|-----------|-------|
| `vec2 render::calculate_text_size(string text)` | `.x` = width, `.y` = height. |
| `void render::draw_text(int x, int y, string text, int r, int g, int b, int a)` | |
| `void render::draw_text_outlined(int x, int y, string text, int r, int g, int b, int a)` | |
| `void render::draw_text_shadow(int x, int y, string text, int r, int g, int b, int a)` | 1px down/right shadow. |

### Rectangles

```cpp
enum box_style { NORMAL, OUTLINED, FILLED, FILLED_OUTLINED, CORNERED, CORNERED_FILLED };
```

| Signature | Notes |
|-----------|-------|
| `void render::draw_box(int x, int y, int width, int height, int r, int g, int b, int a, box_style style, float rounding)` | For `CORNERED*` styles `rounding` acts as corner ratio (0.05–0.45). |
| `void render::draw_gradient_box(int x, int y, int width, int height, int r1, int g1, int b1, int a1, int r2, int g2, int b2, int a2, bool horizontal)` | `horizontal == true` → gradient runs left→right, else top→bottom. |
| `bbox_2d render::calculate_2d_bbox(vec3 origin, vec3 mins, vec3 maxs, matrix4x4 view_matrix)` | Projects a 3D box to screen. `bbox_2d` has `x, y, width, height, valid`. |
| `bbox_2d render::calculate_2d_bbox_unity(vec3 origin, vec3 center, vec3 extents, matrix4x4 view_matrix)` | Unity variant — takes centre and half-sizes (extents), left-handed Y-up. |

### Lines and shapes

| Signature | Notes |
|-----------|-------|
| `void render::draw_line(float x1, float y1, float x2, float y2, int r, int g, int b, int a, float thickness = 1.0f)` | |
| `void render::draw_line_outlined(float x1, float y1, float x2, float y2, int r, int g, int b, int a, float thickness = 1.0f)` | |
| `void render::draw_circle(float x, float y, float radius, int r, int g, int b, int a, bool filled = false, int segments = 32)` | |
| `void render::draw_triangle(float x1, float y1, float x2, float y2, float x3, float y3, int r, int g, int b, int a, bool filled = false)` | |

### Polygons

| Signature | Notes |
|-----------|-------|
| `void render::draw_concave_poly(array<vec2> points, int r, int g, int b, int a)` | Filled concave polygon. |
| `void render::draw_convex_poly(array<vec2> points, int r, int g, int b, int a, bool filled)` | |
| `void render::draw_polyline(array<vec2> points, int r, int g, int b, int a, float thickness, bool closed)` | |

### Hue bar

| Signature | Notes |
|-----------|-------|
| `void render::draw_hue_bar(int x, int y, int w, int h, int r, int g, int b, int a)` | Animated, follows the menu animation. |
| `void render::draw_hue_bar_static(int x, int y, int w, int h, int r, int g, int b, int a)` | |

```angelscript
void render_tick() {
    vec2 vp = render::get_viewport_size();
    render::draw_box(100, 100, 200, 50, 255, 0, 0, 255, box_style::FILLED, 0.0f);
    render::draw_box(100, 100, 200, 50, 255, 0, 0, 255, box_style::OUTLINED, 0.0f);
    render::draw_line(0, 0, vp.x, vp.y, 255, 255, 255, 255, 1.0f);
    render::draw_circle(50, 50, 10, 0, 255, 0, 255, true, 32);
    render::draw_text(10, 10, "hello", 255, 255, 255, 255);
    vec2 ts = render::calculate_text_size("hello");
}
```

---

## Menu (UI)

```cpp
struct ui_info { bool open; float dpi_scale; float x, y, w, h; color accent; };
struct active_bind { string category; string label; };
struct color { int r, g, b, a; };
enum sub_tab_side { middle, left, right };
enum category_pos { automatic, left_full, right_full, left_top, left_bottom, right_top, right_bottom };
enum label_style { none, warning, dangerous };
```

### General

| Signature | Returns | Notes |
|-----------|---------|-------|
| `bool ui::is_open()` | bool | |
| `float ui::get_scale()` | float | DPI scale. |
| `color ui::get_accent()` | color | |
| `ui_info ui::get_info()` | ui_info | |
| `string ui::get_tab()` | string | Active tab label. |
| `string ui::get_sub_tab()` | string | Active sub-tab label. |
| `void ui::config_path(string folder_name)` | — | Sets the config directory for the loaded script. Pick a unique folder name. A config tab appears automatically for saving/loading configs. |
| `void ui::add_tab(string label)` | — | |
| `void ui::add_tab(string label, sub_tab_side side)` | — | `middle` → sub-tab bar along the top (categories added directly to the tab are ignored); `left`/`right` → sub-tab bar on that side. |
| `void ui::add_subtab(string label)` | — | Branches off the most recently created tab. |
| `void ui::add_category(string label)` | — | Added to the most recently created tab or sub-tab. |
| `void ui::add_category(string label, category_pos pos)` | — | `automatic` distributes categories across columns (up to 2 per column); `left_full`/`right_full` take a full column; `left_top`/`left_bottom`/`right_top`/`right_bottom` take half a column with a resize grip between paired halves. |
| `bool ui::get_active_binds(array<active_bind> &out binds)` | bool | Currently active key binds. |

**Ordering matters:** `ui::add_tab` → `ui::add_subtab` → `ui::add_category` → elements.
Elements attach to the most recently created category.

### Elements

| Signature | Notes |
|-----------|-------|
| `checkbox ui::add_checkbox(string label, bool default_value, string config_key = "")` | `config_key` optional — auto-generated from tab/sub-tab/category/label (lowercased, sanitised) when omitted. |
| `checkbox ui::add_checkbox(string label, bool default_value, checkbox_callback@ callback = nullptr, string config_key = "")` | Same, with an optional change callback. |
| `slider ui::add_slider(string label, int default_val, int min_val, int max_val, int step, string tag = "", string config_key = "")` | **Integers only.** `tag` is the unit suffix shown next to the value. |
| `color_picker ui::add_color_picker(string label, int r, int g, int b, int a, bool stick = true, string config_key = "")` | `stick` attaches the picker to the checkbox above it (max 3 per checkbox). |
| `combobox ui::add_combobox(string label, array<string> options, int default_idx, string config_key = "")` | |
| `combobox ui::add_combobox(string label, array<string> options, int default_idx, combobox_callback@ callback = nullptr, string config_key = "")` | |
| `multi_select ui::add_multi_select(string label, array<string> options, string config_key = "")` | |
| `button ui::add_button(string label, button_callback@ callback = nullptr)` | |

### Getters / setters

| Signature | Returns |
|-----------|---------|
| `bool ui::get(checkbox)` | Current value |
| `int ui::get(slider)` | Current value |
| `color ui::get(color_picker)` | `struct color { int r, g, b, a; }` |
| `uint64 ui::get(combobox)` | Selected **index** |
| `bool ui::get(multi_select, uint64 index)` | Whether the option at `index` is selected |
| `void ui::set(checkbox, bool value)` | |
| `void ui::set(slider, int value)` | |
| `void ui::set(color_picker, color value)` | |
| `void ui::set(combobox, uint64 index)` | |
| `void ui::set(multi_select, uint64 index, bool value)` | |

### Visibility, tooltips, style

`void ui::set_visible(checkbox|slider|color_picker|combobox|multi_select|button, bool visible)`;
`void ui::add_tooltip(checkbox|slider|color_picker|combobox|multi_select, string text)`;
`void ui::set_label_style(checkbox, label_style style)`.

```angelscript
checkbox g_enabled = false;
slider g_fov = 60;

bool main() {
    ui::config_path("my_script");
    ui::add_tab("Main");
    ui::add_category("Options");
    g_enabled = ui::add_checkbox("Enable", false);
    g_fov = ui::add_slider("FOV", 60, 5, 300, 5, "deg");
    return true;
}

void tick() {
    bool on = ui::get(g_enabled);
    int fov = ui::get(g_fov);
    ui::set(g_enabled, on);
}
```

---

## General / utility

### Identity and environment

| Signature | Notes |
|-----------|-------|
| `string util::get_username()` | Forum username. |
| `void util::disable_capture_protection()` | Unlocks the anti-capture menu element. |

### Strings and encoding

| Signature | Notes |
|-----------|-------|
| `string util::wide_to_string(array<uint8> bytes, bool stop_at_null = false)` | UTF-16LE bytes → UTF-8 string. |
| `string util::to_hex(number, bool prefix = true)` | Formats an integer as hex; `prefix` prepends `0x`. |
| `string util::hex_encode(string str)` / `string util::hex_encode(array<uint8> bytes)` | Lowercase hex. `"Hello"` → `"48656c6c6f"`. |
| `string util::hex_decode(string str)` / `string util::hex_decode(array<uint8> bytes)` | **Empty string on failure.** |
| `string util::base64_encode(string str)` / `string util::base64_encode(array<uint8> bytes)` | |
| `string util::base64_decode(string str)` / `string util::base64_decode(array<uint8> bytes)` | **Empty string on failure.** |

### Hashing

| Signature | Notes |
|-----------|-------|
| `uint64 hash::fnv1a(string str)` | 64-bit FNV-1a. |
| `uint32 hash::crc32(string str)` | 32-bit CRC32. |

### Time

| Signature | Notes |
|-----------|-------|
| `uint64 util::tickcount()` | Milliseconds since system boot. |
| `string util::system_time(bool use_12h = false)` | `"16:32"` or `"4:32 PM"`. |
| `uint64 util::time_now()` | Precise timestamp for `time_ms`/`time_us`/`time_ns`. |
| `double util::time_ms(uint64 start, uint64 end)` | Elapsed milliseconds. |
| `double util::time_us(uint64 start, uint64 end)` | Elapsed microseconds. |
| `double util::time_ns(uint64 start, uint64 end)` | Elapsed nanoseconds. |

### Random

`void util::seed_random(uint64 seed)` — seed `0` resets to default, any non-zero value gives
a custom sequence.
`int util::random_int(int min, int max)`, `float util::random_float(float, float)`,
`double util::random_double(double, double)`, `int64 util::random_i64(int64, int64)`,
`uint64 util::random_u64(uint64, uint64)` — all inclusive range `[min, max]`.

### ZIP

`array<zip_entry>@ util::zip_parse(string data)` — parses a raw zip binary (e.g. from
`http::get` or `file::read`) and returns all file entries. The zip must be flat (no
subdirectories); directory entries are skipped. File writes still go through the
filesystem API.

```cpp
struct zip_entry { string name; string data; }
```

### String formatting

`string util::format_string(string fmt, ...)` — `{}` placeholders, `{{`/`}}` for literals.
Options after a colon: `{:<8}` left-align width 8, `{:>8}` right-align (default),
`{:08}` zero-pad width 8, `{:.2}` two decimals, `{0:<8.2}` index + alignment + width +
precision. Shorthand without a colon: `{.2}` precision only, `{0.3}` index + precision.
Invalid or out-of-range placeholders produce `{?}`. Width capped at 1024, precision at 17,
up to 8 arguments.

---

## Logging

| Signature | Notes |
|-----------|-------|
| `void alert::show(string msg)` | Overlay popup. |
| `void alert::show(string msg, int r, int g, int b)` | Coloured. |
| `void alert::show(string msg, int r, int g, int b, float duration)` | Duration in seconds. |
| `void alert::show(string msg, int r, int g, int b, float duration, bool rainbow)` | |
| `void alert::show_tag(string msg, string tag)` | Tagged — a later call with the same tag **updates** the existing alert instead of creating a new one. |
| `void alert::show_tag(string msg, string tag, int r, int g, int b)` | |
| `void alert::show_tag(string msg, string tag, int r, int g, int b, float duration)` | |
| `void alert::show_tag(string msg, string tag, int r, int g, int b, float duration, bool rainbow)` | |
| `void alert::dismiss()` | Clear all alerts. |
| `void alert::dismiss(string tag)` | Dismiss a specific tagged alert. |
| `void print(? msg)` | Global console output, any type. |
| `void console::log(? msg)` | |
| `void console::log(? msg, int r, int g, int b)` | |
| `void console::warn(? msg)` | |
| `void console::error(? msg)` | |
| `void console::clear()` | |

```angelscript
alert::show_tag("Health: 50", "health_alert", 255, 255, 0);
alert::dismiss("health_alert");
console::warn("something looks off");
print("quick message");
```

---

## Filesystem

Sandboxed file I/O. Paths are relative to the data directory. Max file size 512 MB.
Directory depth is limited to 2 levels; executable extensions are blocked.

| Signature | Notes |
|-----------|-------|
| `bool file::exists(string filename)` | |
| `bool file::write(string filename, string data)` | |
| `bool file::append(string filename, string data)` | |
| `bool file::read(string filename, string &out data)` | **Out-param form.** |
| `bool file::remove(string filename)` | |
| `bool file::size(string filename, uint64 &out size)` | Out-param form. |
| `bool file::write_bytes(string filename, array<uint8> data)` | |
| `bool file::append_bytes(string filename, array<uint8> data)` | |
| `array<uint8>@ file::read_bytes(string filename)` | `null` on failure. |
| `bool dir::exists(string name)` | Directory management is limited to one level deep inside the data directory. |
| `bool dir::create(string name)` | |
| `bool dir::remove(string name)` | |
| `array<string>@ dir::list(string name)` | |

---

## Input (WinAPI)

### Mouse

| Signature | Notes |
|-----------|-------|
| `void input::mouse_move(int x, int y)` | **Absolute** screen position, not a relative delta. |
| `bool input::mouse_press()` | Mouse button down. |
| `bool input::mouse_release()` | Mouse button up. |
| `bool input::mouse_click()` | Down + up. |
| `void input::mouse_pos(int &out x, int &out y)` | Out-param form. |

### Keyboard

| Signature | Notes |
|-----------|-------|
| `bool input::key_active(int vk_code)` | True while the key is **held**. |
| `bool input::key_toggled(int vk_code)` | True if the key is toggled on (e.g. caps lock). |
| `void input::key_press(int vk_code)` | **Send** a key-down to the target. |
| `void input::key_release(int vk_code)` | **Send** a key-up to the target. |
| `void input::key_tap(int vk_code)` | **Send** key-down + key-up atomically. |

There is no separate "pressed this frame" edge detector — `key_active` is the held state.
`key_press`/`key_release`/`key_tap` are *output* (they inject input), not state queries.

Common VK codes: `VK_LBUTTON` 1, `VK_RBUTTON` 2, `VK_SHIFT` 16, `VK_CONTROL` 17,
`VK_MENU` 18, `VK_CAPITAL` 20, `VK_SPACE` 32, `VK_HOME` 36, `VK_INSERT` 45,
`VK_DELETE` 46, `'0'`–`'9'` 48–57, `'A'`–`'Z'` 65–90, `VK_NUMPAD0`–`9` 96–105,
`VK_F1`–`VK_F12` 112–123.

---

## JSON serialization

One object type for both objects and arrays.

```cpp
enum json_type { null_value, boolean, number, string, object, array };
```

### Global functions

| Signature | Notes |
|-----------|-------|
| `json_obj@ json::array()` | Creates an array-mode object — use `push()` to append, `get_*_at()` to read. |
| `json_obj@ json::parse(string text, string &out error)` | **Returns `null` on failure**, reason in `error`. |
| `string json::stringify(json_obj@ obj, bool beautify = false)` | |

### Inspection

`bool has(string key)`; `uint length()` (keys for objects, elements for arrays);
`json_type type(string key)`; `json_type type_at(uint index)`; `array<string>@ keys()`.

### Getters — default value if the key is missing or the type mismatches

`get_string(key)`, `get_float(key)`, `get_double(key)`, `get_int(key)`, `get_uint(key)`,
`get_int64(key)`, `get_uint64(key)`, `get_bool(key)`, `json_obj@ get_obj(key)` (`null` if
missing or not an object/array).

Index-based equivalents: `get_string_at(uint index)`, `get_float_at`, `get_double_at`,
`get_int_at`, `get_uint_at`, `get_int64_at`, `get_uint64_at`, `get_bool_at`,
`json_obj@ get_obj_at(uint index)` (null if out of range).

### Setters

`set(string key, ...)` overloads for `string, float, double, int, uint, int64, uint64,
bool, json_obj@` — overwrites an existing key.
`void set_null(string key)`; `void remove(string key)` (no-op if the key does not exist).

### Array push — only valid on objects created with `json::array()`, no-op otherwise

`push(string)`, `push(float)`, `push(double)`, `push(int)`, `push(uint)`, `push(int64)`,
`push(uint64)`, `push(bool)`, `push(json_obj@)`, `push_null()`.

```angelscript
json_obj@ msg = json_obj();
msg.set("from", "alice");
msg.set("attempts", 1);

json_obj@ ciphers = json::array();
ciphers.push("aes-256");
msg.set("ciphers", ciphers);

string err;
json_obj@ received = json::parse(json::stringify(msg), err);
if (received is null) {
    print("parse failed: " + err);
    return false;
}
```

---

## Hash set

O(1) insert / lookup / removal of unique values.

Available types: `hash_set_float@`, `hash_set_double@`, `hash_set_int32@`,
`hash_set_uint32@`, `hash_set_int64@`, `hash_set_uint64@`. The docs show two construction
forms — the type constructor (`hash_set_uint64()`) and the named factory
(`create_hash_set_uint64()`, and the matching factory for each other type).

| Method | Returns | Notes |
|--------|---------|-------|
| `bool .insert(value)` | bool | `true` if inserted, `false` if already present. |
| `bool .erase(value)` | bool | `true` if removed, `false` if not found. |
| `bool .contains(value)` | bool | |
| `uint .size()` | uint | |
| `bool .empty()` | bool | |
| `void .clear()` | — | |

```angelscript
hash_set_uint64@ entity_cache = create_hash_set_uint64();
entity_cache.insert(entity_id);
if (!entity_cache.contains(entity_id)) { /* first sighting */ }
entity_cache.erase(entity_id);
```

---

## Hash map

Dynamically typed key-value map with `uint64` keys.

```cpp
enum hmap_type { unset, boolean, i32, u32, i64, u64, f32, f64, string };
```

`hash_map@ create_hash_map()`.

### Setters (overwrite any existing value at that key)

`void .set_bool(uint64 key, bool value)`, `.set_int32`, `.set_uint32`, `.set_int64`,
`.set_uint64`, `.set_float`, `.set_double`, `.set_string`.

### Getters — `true` only if the key exists **and** the type matches

`bool .get_bool(uint64 key, bool &out)`, `.get_int32`, `.get_uint32`, `.get_int64`,
`.get_uint64`, `.get_float`, `.get_double`, `.get_string` — all with an `&out` parameter.

### Operations

`bool .contains(uint64 key)` (any type), `bool .erase(uint64 key)`,
`hmap_type .get_type(uint64 key)`, `uint .size()`, `bool .empty()`, `void .clear()`.

```angelscript
hash_map@ map = create_hash_map();
map.set_string(1, "hello");
map.set_int32(2, 42);

string s;
if (map.get_string(1, s)) { print("string: " + s); }
```

---

## Async HTTP

Requests are non-blocking: you pass a callback instead of receiving a value.

```cpp
struct http_response {
    int status_code;
    string body;
    string error;
}
```

Callback funcdef: `void response_callback(http_response@ response) {}`

| Signature | Notes |
|-----------|-------|
| `void http::get(string url, response_callback@ cb)` | Fires the request on a background thread, invokes the callback on completion. **Only callable from `main()`.** |
| `void http::post(string url, string body, string content_type, response_callback@ cb)` | Only callable from `main()`. |
| `void http::get(string url)` | Fire-and-forget, no response. Callable from any context, including `on_unload()`. |
| `void http::post(string url, string body, string content_type)` | Fire-and-forget. |

User-agent `prism/1.0`, timeout 10 s, redirects followed automatically.

```angelscript
void on_response(http_response@ res) {
    if (res.error != "") { print("GET error: " + res.error); return; }
    print("GET status: " + res.status_code);
    print(res.body);
}

bool main() {
    http::get("https://example.com/get", @on_response);
    return true;
}
```

---

## WebSocket

Persistent WebSocket client. **All callbacks fire on the connection thread** — protect any
shared state.

```cpp
void connect_callback() {}
void message_callback(string msg) {}
void disconnect_callback() {}
void error_callback(string msg) {}
```

| Signature | Notes |
|-----------|-------|
| `void ws::connect(string url, connect_callback@ on_open, message_callback@ on_message, disconnect_callback@ on_disconnect, error_callback@ on_error)` | |
| `void ws::reconnect()` | |
| `void ws::disconnect()` | |
| `bool ws::is_connected()` | |
| `void ws::send(string msg)` | |

```angelscript
void on_open() { ws::send("hello"); }
void on_message(string msg) { print(msg); }
void on_disconnect() { ws::reconnect(); }
void on_error(string msg) { print("error: " + msg); }

bool main() {
    ws::connect("wss://echo.websocket.org", @on_open, @on_message, @on_disconnect, @on_error);
    return true;
}
```

---

## Clipping

2D polygon boolean operations, offsetting and path simplification.

```cpp
enum clip_type { INTERSECTION, UNION, DIFFERENCE, XOR };
enum fill_rule { EVEN_ODD, NON_ZERO, POSITIVE, NEGATIVE };
enum join_type { MITER, SQUARE, BEVEL, ROUND };
enum end_type { ET_POLYGON, ET_JOINED, ET_BUTT, ET_SQUARE, ET_ROUND };
```

`clip_paths@ clip_paths()` — ref-counted container of paths; operations mutate it in place.

| Method | Notes |
|--------|-------|
| `void clip_paths.add_path(const array<vec2> &in points)` | Polygon or polyline. |
| `array<vec2>@ clip_paths.get_path(uint index)` | |
| `uint clip_paths.path_count()` | |
| `void clip_paths.clear()` | |
| `clip_paths@ clip_paths.clone()` | New object with a copy of all paths. |
| `void clip_paths.boolean_op(clip_paths@ clips, clip_type, fill_rule = NON_ZERO)` | Mutates this object. |
| `void clip_paths.inflate(double delta, join_type = ROUND, end_type = ET_POLYGON)` | Positive = outset, negative = inset. `ET_POLYGON` for closed polygons, `ET_BUTT`/`ET_ROUND` for open polylines. |
| `void clip_paths.simplify(double epsilon = 0.1)` | Removes vertices within `epsilon` of their neighbours. |
| `void clip_paths.union_self(fill_rule = NON_ZERO)` | Merges overlapping paths; useful to clean up self-intersecting input before drawing. |

---

## Tracing

### BVH tree

```cpp
struct triangle { vec3 p1; vec3 p2; vec3 p3; }
```

`bvh_tree@ create_bvh_tree()` — ref-counted, returns `null` on allocation failure.
Thread-safe for concurrent `is_occluded()` calls; **any mutation invalidates the tree
until `build()` is called again**.

| Method | Notes |
|--------|-------|
| `void bvh_tree.add_triangle(const vec3 &in p1, const vec3 &in p2, const vec3 &in p3)` | |
| `void bvh_tree.add_triangles(const array<triangle> &in tris)` | |
| `bool bvh_tree.build()` | `false` if no triangles were added. |
| `bool bvh_tree.is_occluded(const vec3 &in from, const vec3 &in to)` | `true` if the segment is blocked by any triangle. `false` if the tree is not built. |
| `void bvh_tree.clear()` | Removes triangles and nodes, resets to unbuilt. |
| `uint64 bvh_tree.triangle_count()` | |
| `bool bvh_tree.is_ready()` | |

### One-off intersection tests

| Signature | Notes |
|-----------|-------|
| `bool trace::ray_triangle(const triangle &in tri, const vec3 &in origin, const vec3 &in dir, double max_t)` | Möller–Trumbore. |
| `bool trace::ray_bbox(const vec3 &in origin, const vec3 &in dir, const vec3 &in box_min, const vec3 &in box_max, double max_t)` | Slab method. |
| `bool trace::ray_sphere(const vec3 &in origin, const vec3 &in dir, const vec3 &in center, double radius, double max_t)` | Analytic. |
| `bool trace::ray_capsule(const vec3 &in origin, const vec3 &in dir, const vec3 &in capsule_min, const vec3 &in capsule_max, double radius, double max_t)` | Closest-point. |

---

## Helpers (math)

### Constants

`math::PI`, `math::TAU` (2π), `math::RAD2DEG`, `math::DEG2RAD`;
`angle_range::R_180` (normalise to [-180, 180]), `angle_range::R_360` (normalise to [0, 360]).

### Matrices and directions

| Signature | Returns |
|-----------|---------|
| `matrix4x4 math::multiply_matrix(matrix4x4 a, matrix4x4 b)` | Product |
| `matrix4x4 math::rotation_matrix(vec3 rotation, vec3 origin)` | Rotation matrix from euler angles + origin |
| `vec3 math::rotated_vector(vec3 point, vec4 quaternion)` | Rotated point |
| `vec3 math::forward_vector(vec2 angles)` | From (pitch, yaw) |
| `vec3 math::right_vector(vec2 angles)` | |
| `vec3 math::up_vector(vec2 angles)` | |

### Angles

| Signature | Returns | Notes |
|-----------|---------|-------|
| `vec2 math::vec_to_angles(vec3 direction)` | (pitch, yaw) | |
| `vec3 math::angles_to_vec(vec2 angles)` | direction | |
| `double math::normalize_angle(double angle, angle_range range)` | | |
| `double math::angle_diff(double a, double b)` | | Shortest angular difference. |
| `double math::calculate_fov(vec2 a, vec2 b)` | degrees | FOV between two angle sets. |
| `vec2 math::calculate_angle(vec3 from, vec3 to)` | (pitch, yaw) | Angle from one position to another. |
| `vec2 math::clamp_angles(vec2 angles, angle_range range)` | | Pitch clamped to [-89, 89], yaw normalised. |
| `vec2 math::smooth_angles(vec2 current, vec2 target, angle_range range, double smoothing [0.0-1.0], double min_speed [1.0-45.0], double max_speed [1.0-45.0])` | | Smoothing 0 = fast, 1 = slow. Tune min/max speed to your tick rate. |

### Unreal helpers

| Signature | Returns |
|-----------|---------|
| `vec2 math::unreal_rotation_to_radians(vec3 camera_rot)` | (pitch_rad, yaw_rad) |
| `double math::unreal_calculate_fov(vec3 camera_rot, vec3 camera_pos, vec3 target_pos)` | FOV in degrees, 0 = looking directly at the target |
| `vec2 math::unreal_calculate_angle(vec3 camera_rot, vec3 camera_pos, vec3 target_pos)` | Angle delta in degrees to add to the current rotation |
| `vec2 math::unreal_smooth_rotation(vec3 camera_rot, vec3 camera_pos, vec3 target_pos, double smoothing, double min_speed, double max_speed)` | Smoothed deltas in radians to add to the current rotation |

---

## Vector 2D / 3D / 4D

`vec2`, `vec3`, `vec4` are value types with `x, y, z, w` component access.

| Method | Applies to | Notes |
|--------|------------|-------|
| `v.is_empty()` | all | True if the vector is zero. |
| `v.length()` | all | Magnitude. |
| `v.length_squared()` | all | Squared magnitude, no sqrt. |
| `v.normalize()` | all | Normalised vector (length 1). |
| `v.dot(other)` | all | Dot product. |
| `v.add(other)` | all | |
| `v.subtract(other)` | all | |
| `v.multiply(scalar)` | all | |
| `v.distance(other)` | all | |
| `v.lerp(other, t)` | all | Linear interpolation, `t` 0.0–1.0. |
| `v.read_float(address)` | all | Read from memory as float[N]. |
| `v.read_double(address)` | all | Read from memory as double[N]. |
| `v.write_float(address)` | all | Write to memory as float[N]. |
| `v.write_double(address)` | all | Write to memory as double[N]. |

---

## Matrixes

`matrix4x4`, `matrix3x4`, `matrix3x3` — float elements, row/column index access.

| Signature | Notes |
|-----------|-------|
| `matrix4x4 matrix4x4()` | Construct. |
| `matrix3x4 matrix3x4()` | Construct. |
| `matrix3x3 matrix3x3()` | Construct. |
| `float m[row][col]` | Element read/write. |
| `bool m.read(address)` | Read matrix from memory (float). |
| `bool m.read_double(address)` | Read matrix from memory (double). |

`matrix3x3` view-matrix convention (IW engine): row 0 = `axis_forward` (camera forward),
row 1 = `axis_right`, row 2 = `axis_up`.

---

## Source engine

| Signature | Returns | Notes |
|-----------|---------|-------|
| `bool source::w2s(vec3 world_pos, matrix4x4 view_matrix, vec2 &out screen_pos)` | bool | `false` = off-screen or behind camera. |
| `uint64 source::get_entity(uint64 entity_list_address, uint64 index)` | uint64 | Entity address, `0` if invalid. |
| `bool source2::w2s(vec3 world_pos, matrix4x4 view_matrix, vec2 &out screen_pos)` | bool | `false` = off-screen or behind camera. |
| `uint64 source2::get_controller(uint64 entity_list_address, uint64 index)` | uint64 | Controller address, `0` if invalid. |
| `uint64 source2::get_pawn(uint64 entity_list_address, uint64 controller_address, uint64 pawn_offset)` | uint64 | Pawn address, `0` if invalid. |

---

## Unreal engine

```cpp
f_view_info view_info;
view_info.location = vec3(0, 0, 0);  // camera world position
view_info.rotation = vec3(0, 0, 0);  // camera rotation (pitch, yaw, roll)
view_info.fov = 90.0f;
```

| Signature | Returns | Notes |
|-----------|---------|-------|
| `f_view_cache build_view_cache(f_view_info camera, bool vertical_fov = false)` | f_view_cache | Build the cache **once per frame** before iterating entities — avoids recomputing the rotation matrix and FOV per entity. `vertical_fov = true` for games needing a different FOV solution. |
| `bool unreal::w2s(vec3 world_pos, f_view_cache cache, vec2 &out screen_pos)` | bool | `false` = off-screen or behind camera. |
| `u_bone_array unreal::read_bones(uint64 skeletal_mesh, uint64 bone_array_offset, uint64 bone_array_cached_offset, uint64 component_offset)` | u_bone_array | Cached fallback. Call `bones.valid()` before use; `bones.count()`; `bones[110]` by raw bone index. |
| `u_bone_array unreal::read_bones(uint64 skeletal_mesh, uint64 bone_array_offset, uint64 component_offset)` | u_bone_array | No cached fallback — bones may flicker. |

### ftransform

```cpp
ftransform bone_transform;
bone_transform.read(bone_address);   // read transform from memory
vec3 pos = bone_transform.transform_to_world(ftransform parent_transform);
```

`rotation` is a quaternion (x, y, z, w), `translation` the world position, `scale_3d` the
scale vector.

---

## Unity engine

| Signature | Returns | Notes |
|-----------|---------|-------|
| `bool unity::w2s(vec3 world_pos, matrix4x4 view_matrix, vec2 &out screen_pos)` | bool | `false` = off-screen or behind camera. |
| `vec3 unity::rust_transform_position(uint64 transform_address)` | vec3 | World position from a Rust transform object. |
| `uint32 unity::rust_prefab_id(string name)` | uint32 | Prefab ID derived from its name, e.g. `"assets/bundled/prefabs/autospawn/resource/ores/stone-ore.prefab"`. |

---

## IW engine

| Signature | Returns | Notes |
|-----------|---------|-------|
| `bool iw_engine::w2s(vec3 world_pos, vec3 camera_location, matrix3x3 view_matrix, float fov_x, float fov_y, vec2 &out screen_pos)` | bool | `false` = off-screen or behind camera. |

---

## AngelScript built-ins

### string

`s.length()`, `s.empty()`, `s.find(string sub)`, `s.substr(int start, int len)`,
`s.replace(string from, string to)`, `array<string>@ s.split(string delim)`,
`s.to_lower()`, `s.to_upper()`, `s.to_int()`, `s.to_float()`.
Concatenation with `+` works. `formatInt(value, "0H", 16)` formats an integer.

### array\<T\>

`a.length()`, `a.resize(uint n)`, `a.reverse()`, `a.insertAt(uint i, val)`,
`a.insertLast(val)`, `a.removeAt(uint i)`, `a.removeLast()`,
`a.removeRange(uint start, uint count)`, `a.sortAsc()`, `a.sortDesc()`,
`a.sort(compareFunc)`, `a.find(val)`, `a.findByRef(val)`.
Those are the only array methods. There are no C++-style push/pop methods, no snake_case
insert/remove variants, and the comparator form of `sort` is the only one.

`a[i]` raises an exception when `i >= a.length()`. Echo scripts are exception-free, so an
out-of-range index is a hard error — check the length before indexing.

Arrays are reference types: `=` performs a shallow copy of the buffer, not a deep copy.
Arrays of handles (`array<entity@>`) store references, so the elements stay shared.

### Handles

`mutex@ m = create_mutex();`, `array<uint8>@ bytes = process::read_bytes(addr, 16);`.
`is null` is the null check — never `== null`.

`array<T>@` is a handle to a reference-type array object: it can be null, it is what Echo
API functions that return arrays give you, and assigning it copies the reference rather
than the buffer. The plain value form `array<T>` is never null and is what out-parameters
take — write `array<T> &out`, not `array<T>@ &out`.

---

## Top mistakes

1. `void main()` — the entry point must be `bool main()` returning `true`/`false`.
2. Invented namespaces — anything other than `process::`, `render::`, `ui::`, `uc::`,
   `zydis::`, `util::`, `file::`, `dir::`, `input::`, `json::`, `http::`, `ws::`,
   `console::`, `alert::`, `math::`, `hash::`, `trace::`, `source::`, `source2::`,
   `unreal::`, `unity::`, `iw_engine::` — does not exist. The old→new mapping is in
   `reference/_API_CONTRACT.md`.
3. Colour structs on render calls — colours are four ints `r, g, b, a`.
4. `process::find_signature` without a base address — get `process::get_module_base` first.
5. W2S returning coordinates — W2S writes to an out-param and returns `bool`.
6. Drawing outside `on_render(@cb)` — render calls only work on the render thread.
7. `ui::add_checkbox(...)` treated as a value — you must keep the handle and use
   `ui::get`/`ui::set`.
8. UI elements registered before `ui::add_tab`/`add_subtab`/`add_category`.
9. `arr.size()` instead of `arr.length()`; `if (h == null)` instead of `if (h is null)`.
10. `uint32` for addresses — always `uint64`.
