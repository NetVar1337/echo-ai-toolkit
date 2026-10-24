# Echo Universal API – Quick Reference

Full docs: https://echo-23.gitbook.io/angel  
LLM-optimized: https://echo-23.gitbook.io/angel/llms-full.txt

---

## Script lifecycle

| Symbol | Notes |
|--------|-------|
| `bool main()` | Required entry point. Return `false` to unload. |
| `void on_unload()` | Optional teardown. |
| `.as` location | `%AppData%\Roaming\scripts\` |
| Reload | Close + reopen the in-game menu. |

---

## Threading

| Call | Description |
|------|-------------|
| `create_thread(tps, @cb)` | Tick callback; 1–128 tps, 0 = once. |
| `on_render(@cb)` | Per-frame render callback. |
| `mutex()` | `lock()`, `unlock()`, `lock_shared()`, `unlock_shared()` |
| `atomic_int(n)` | `load()`, `store()`, `exchange()`, `compare_exchange()` |

---

## Process

| Call | Description |
|------|-------------|
| `process.attach(name/pid)` | Returns `process@` or null. |
| `proc.get_module(name)` | Returns `module_info@` with `.base`, `.size`. |
| `proc.read<T>(addr)` | Read typed value from process. |
| `proc.write<T>(addr, val)` | Write typed value. |
| `proc.scan(pattern, module)` | Byte-mask scan. |
| `proc.scan_ida(pattern, module)` | IDA-style scan. |
| `proc.resolve_rip(addr, off, sz)` | Resolve RIP-relative operand. |
| `proc.query_regions()` | `array<region_info>@` |
| `proc.dump(module, path)` | Dump module to file. |

---

## Disassembly (Zydis)

| Call | Description |
|------|-------------|
| `disasm.decode(proc, addr)` | Single `instruction@` |
| `disasm.decode_linear(proc, addr, count)` | Linear block |
| `disasm.decode_function(proc, addr)` | Function-level |

`instruction@` fields: `.mnemonic`, `.operands_str`, `.length`

---

## Unicorn

| Call | Description |
|------|-------------|
| `emulator()` / `emulator(proc)` | Create emulator (optional process backing) |
| `emu.mem_map(addr, size, prot)` | Map region; prot: `UC_PROT_*` |
| `emu.mem_write(addr, bytes)` | Write bytes |
| `emu.reg_read/write(reg, val)` | Registers: `UC_X86_REG_*` |
| `emu.hook_code(@cb)` | `void cb(uint64, uint)` |
| `emu.hook_mem_read(@cb)` | `void cb(uint64, uint)` |
| `emu.start(entry, until, ms, max)` | Run |
| `emu.stop()` | Halt |

---

## Renderer

| Call | Description |
|------|-------------|
| `renderer.load_font(name, size, bold)` | Returns `font_handle@` |
| `renderer.text(x,y,str,font,col)` | Draw text |
| `renderer.text_outlined(...)` | With shadow/outline |
| `renderer.rect(x,y,w,h,col)` | Filled box |
| `renderer.rect_outlined(x,y,w,h,thick,col)` | Outlined box |
| `renderer.rect_gradient(x,y,w,h,tl,tr,bl,br)` | Gradient box |
| `renderer.line(x1,y1,x2,y2,thick,col)` | Line |
| `renderer.circle(x,y,r,segs,col)` | Circle |
| `renderer.triangle(...)` | Triangle |

`color(r,g,b,a)` — all values 0–255.

---

## Menu

| Call | Description |
|------|-------------|
| `menu.add_tab(name)` | Returns `tab@` |
| `tab.add_subtab(name)` | Returns `subtab@` |
| `subtab.add_category(name)` | Returns `category@` |
| `cat.add_checkbox(label, default, key?)` | `checkbox@` |
| `cat.add_slider(label, min, max, default, key?)` | `slider@` |
| `cat.add_color_picker(label, default, key?)` | `color_picker@` |
| `cat.add_combobox(label, items, default, key?)` | `combobox@` |
| `cat.add_button(label, @cb)` | `button@` |
| `el.set_visible(bool)` | Show/hide element |
| `el.set_tooltip(str)` | Hover tooltip |

Elements with a `key` are auto-saved/loaded via the built-in Config tab.

---

## Utilities

| Call | Description |
|------|-------------|
| `time.now()` | `uint64` milliseconds |
| `time.now_seconds()` | `float` seconds |
| `random.int(min,max)` | Inclusive range |
| `random.float(min,max)` | Float range |
| `encode.to_hex(data)` | Hex string |
| `encode.to_base64(data)` | Base64 string |
| `hash.crc32(data)` | `uint32` |
| `hash.fnv1a(data)` | `uint64` |
| `fmt("{} {}", a, b)` | `{}` interpolation |

---

## Networking

| Call | Description |
|------|-------------|
| `http.get(url, @cb)` | Async GET |
| `http.post(url, body, @cb)` | Async POST |
| `http.get_async(url)` | Fire and forget |
| `ws.connect(url)` | Returns `ws@` |
| `sock.on_message(@cb)` | `void cb(string)` |
| `sock.on_disconnect(@cb)` | `void cb()` |
| `sock.send(str)` | Send frame |

---

## Data / Math

| Area | Key types / calls |
|------|-------------------|
| JSON | `json.parse(str)`, `.get_int/float/string/bool(key)`, `.set(k,v)`, `.stringify()` |
| Hash map | `hash_map()` — `uint64` key; `.set()`, `.has()`, `.remove()` |
| Hash set | `hash_set()` — `uint64` key |
| Vectors | `vec2`, `vec3`, `vec4`; `.read(proc,addr)`, `.write(proc,addr)` |
| Matrix | `mat3x3`, `mat3x4`, `mat4x4`; `.transform(vec3)` |
| Angles | `math.rad_to_deg`, `.normalize_angle`, `.smooth_angle`, `.calc_fov` |

---

## Engine helpers (world-to-screen)

```angelscript
bool on = source2.w2s(proc, view_matrix_addr, world_pos, sx, sy);
bool on = unreal.w2s(proc,  camera_addr,      world_pos, sx, sy);
bool on = unity.w2s(proc,   camera_addr,      world_pos, sx, sy);
// source, iw helpers also available
```

---

## Filesystem

Sandboxed to scripts folder. Max 2 directory levels. Max 512 MB per file.

```angelscript
file@ f = fs.open("data/config.json", "r");  // "r", "w", "a"
string s = f.read_all();
f.close();
bool ok = fs.exists("path");
fs.mkdir("data");
```
