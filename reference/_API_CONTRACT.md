# Echo Universal API — CORRECTION CONTRACT (authoritative)

**Status: this file is the single source of truth for every rewrite task in this repo.**

Ground truth: `https://echo-23.gitbook.io/angel/llms-full.txt` (fetched 2026-10-25).
Full signature index: `/tmp/echo-api-index.json`, built by `scripts/build_api_index.py`
(see the appendix).

## THE CORE PROBLEM

Every agent, skill, and template in this repo was written against an **invented API**.
None of it compiles against the real Echo runtime. The old API names below do **not exist**.

| OLD (invented — DO NOT USE) | REAL (use this) |
|---|---|
| `proc.read<uint64>(addr)` | `process::read_uint64(addr)` |
| `proc.read<uint32>(addr)` | `process::read_uint32(addr)` |
| `proc.read<int32>(addr)` | `process::read_int32(addr)` |
| `proc.read<int64>(addr)` | `process::read_int64(addr)` |
| `proc.read<float>(addr)` | `process::read_float(addr)` |
| `proc.read<double>(addr)` | `process::read_double(addr)` |
| `proc.read<string>(addr)` | `process::read_string(addr)` |
| `proc.read_bytes(addr, n)` | `process::read_bytes(addr, n)` → `array<uint8>@` |
| `proc.write<T>(addr, val)` | `process::write_uint64(addr, val)` / `write_int32` / `write_float` / `write_bytes` |
| `proc.scan_ida("48 8B 0D ? ? ? ?")` | `process::find_signature(base, "48 8B 0D ? ? ? ?")` — **needs a base address** |
| `proc.scan(sig, mask)` | `process::find_signature(base, sig, mask)` |
| `proc.get_module("game.exe")` | `process::get_module_base("game.exe")` → `uint64` |
| `proc.get_modules()` | `process::get_module_list()` → `array<module_entry>@` |
| `proc.get_export(base, name)` | `process::get_module_export(base, name)` |
| `proc.resolve_rip(addr, 3, 7)` | `process::get_relative_address(addr, 3, 7)` |
| `proc.query_regions()` | `process::virtual_query(addr)` → one `memory_region` |
| `proc.virtual_query(addr)` | `process::virtual_query(addr)` (correct already) |
| `proc.is_running()` | `process::is_alive()` |
| `proc.attach("game.exe")` | `process::attach("game.exe")` → `attach_data` |
| `proc.detach()` | `process::detach()` |
| `proc.dump(...)` | `process::dump(name)` / `process::dump(module, name)` |
| `proc.read_buffer(a, n)` | `process::read_buffer(a, n)` → `memory_buffer@` (correct already) |
| `proc.disasm_range(addr, n)` | read bytes → `zydis::disasm(bytes, insns)` |
| `proc.scan_string(...)` | no such API — use `process::read_string` or `zydis` |
| `proc.read_wstring(...)` | no such API — `process::read_bytes` + manual UTF-16 decode |
| `proc.valid` | no such API — `process::is_alive()` |
| `renderer.draw_rect_filled(x,y,w,h,col)` | `render::draw_box(x,y,w,h,r,g,b,a, box_style::FILLED, 0.0f)` |
| `renderer.draw_rect_outlined(...)` | `render::draw_box(..., box_style::OUTLINED, 0.0f)` |
| `renderer.rect(...)` / `renderer.rect_outlined(...)` | `render::draw_box(..., box_style::NORMAL\|OUTLINED, 0.0f)` |
| `renderer.draw_circle_filled(x,y,r,col)` | `render::draw_circle(x,y,r,r,g,b,a, true, 32)` |
| `renderer.draw_circle(...)` | `render::draw_circle(x,y,r,r,g,b,a, false, 32)` |
| `renderer.circle(...)` | `render::draw_circle(...)` |
| `renderer.draw_line(x1,y1,x2,y2,col,t)` | `render::draw_line(x1,y1,x2,y2,r,g,b,a,t)` |
| `renderer.line(...)` | `render::draw_line(...)` |
| `renderer.text(x,y,str,col,font)` | `render::draw_text(x,y,str,r,g,b,a)` |
| `renderer.text_outlined(...)` | `render::draw_text_outlined(x,y,str,r,g,b,a)` |
| `renderer.measure_text(s)` | `render::calculate_text_size(s)` → `vec2` |
| `renderer.width()` / `renderer.height()` | `render::get_viewport_size()` → `vec2` (`.x`, `.y`) |
| `renderer.load_font(...)` | `render::load_font(bytes, out handle, hint)` |
| `renderer.draw_hue_bar(...)` | `render::draw_hue_bar(x,y,w,h,r,g,b,a)` |
| `renderer.draw_hue_bar_static(...)` | `render::draw_hue_bar_static(x,y,w,h,r,g,b,a)` |
| `renderer.draw_convex_poly(...)` | `render::draw_convex_poly(points, r,g,b,a, filled)` |
| `renderer.draw_concave_poly(...)` | `render::draw_concave_poly(points, r,g,b,a)` |
| `renderer.draw_polyline(...)` | `render::draw_polyline(points, r,g,b,a, thickness, closed)` |
| `renderer.draw_triangle_filled(...)` | `render::draw_triangle(x1,y1,x2,y2,x3,y3,r,g,b,a,true)` |
| `renderer.triangle(...)` | `render::draw_triangle(..., false)` |
| `renderer.rect_gradient(...)` | `render::draw_gradient_box(x,y,w,h,r1,g1,b1,a1,r2,g2,b2,a2,horizontal)` |
| `renderer.draw_rect_gradient(...)` | `render::draw_gradient_box(...)` |
| `renderer.set_anti_aliasing(b)` | `render::set_anti_aliasing(b)` (correct already) |
| `menu.add_tab(label)` | `ui::add_tab(label)` |
| `menu.checkbox(label, def)` | `checkbox c = ui::add_checkbox(label, def)` then `ui::get(c)` / `ui::set(c, v)` |
| `menu.slider_float(...)` | `slider s = ui::add_slider(label, def, min, max, step, tag)` (INT only) |
| `menu.register` / `menu.begin` / `menu.end` | no such API — use `ui::add_tab`/`add_subtab`/`add_category` |
| `menu.save_config("x")` | `ui::config_path("folder")` then config tab appears automatically |
| `ui::add_tab` is wrong-order | `ui::add_tab` → `ui::add_subtab` → `ui::add_category` → elements |
| `math.calc_fov(a, b)` | `math::calculate_fov(a, b)` |
| `math.lerp(a, b, t)` | `v2.lerp(other, t)` on vectors; plain math has no `lerp` |
| `math.smooth_angles(...)` | `math::smooth_angles(cur, tgt, angle_range::R_180, smoothing, min_speed, max_speed)` |
| `math.angle_diff(a,b)` | `math::angle_diff(a, b)` (correct already) |
| `emu.emu_start(...)` | `uc::start(h, begin, until, timeout, count)` |
| `emu.*` | `uc::*` (uc::create, uc::mem_map, uc::mem_write, uc::reg_write64, ...) |
| `zydis.disasm_range(...)` | `zydis::disasm(bytes, insns)` / `zydis::disasm_func(bytes, rip, insns)` |
| `source2.w2s(proc, addr, pos, sx, sy)` | `source2::w2s(world_pos, view_matrix, out screen_pos)` → `bool` |
| `unreal.w2s(...)` | `unreal::w2s(world_pos, f_view_cache, out screen_pos)` |
| `unity.w2s(...)` | `unity::w2s(world_pos, view_matrix, out screen_pos)` |
| `iw_engine.w2s(...)` | `iw_engine::w2s(world_pos, cam_loc, matrix3x3, fov_x, fov_y, out screen_pos)` |
| `input.key_down(vk)` | `input::key_active(vk)` (held) / `key_press` / `key_release` / `key_tap` |
| `input.key_down` as a *set* | `input::key_press(vk)` / `input::key_release(vk)` |
| `mouse.move(dx, dy)` | `input::mouse_move(x, y)` (absolute) |
| `mouse.button(...)` | `input::mouse_click()` / `mouse_press()` / `mouse_release()` |
| `console.log(...)` | `console::log(...)` (correct already) |
| `print(...)` | `print(...)` — global, correct already |
| `alert.show(...)` | `alert::show(...)` |
| `http.get(url)` | `http::get(url, callback)` — async, callback-based |
| `ws.connect(url)` | `ws::connect(url, callbacks)` |
| `json.parse(s)` | `json::parse(s)` (correct already) |
| `hash_map` / `hash_set` | `hash_map` / `hash_set` types (see Hash map/Hash set sections) |
| `file.read(f)` | `file::read(f, out string)` (out-param form) |
| `mutex()` | `create_mutex()` |
| `main()` returning void | `bool main()` — **must return true/false** |
| `sleep(ms)` | **does not exist** — use a tick thread (`create_thread(tps, cb)`) or a `util::time_now()` gate |
| `proc.read<T>` templated reads | per-type functions, or `process::read_buffer()` for bulk |

## NON-NEGOTIABLE RULES

1. **Every API call you write must exist in the real index.** If unsure, it does not exist.
2. **Colour arguments are 4 separate ints** `r, g, b, a` — there is no `color` struct parameter
   on render calls. (`struct color { int r,g,b,a; }` exists only for `ui::get`/`ui::set` on a
   colour picker.)
3. **W2S functions write to an out-parameter** and return `bool`. Never return screen coords.
   ```angelscript
   vec2 screen;
   if (!source2::w2s(world_pos, view_matrix, screen)) return;
   ```
4. **`process::find_signature` needs a base address.** Get it with
   `process::get_module_base("game.exe")` first.
5. **Render calls only work inside the render thread.** Use `on_render(@cb)` to register.
   `render::get_fps`, `render::get_viewport_size`, `render::is_foreground` are the exceptions
   (callable anywhere).
6. **`bool main()` is mandatory** and must return `true` on success / `false` to unload.
7. **UI element order matters**: `ui::add_tab` → `ui::add_subtab` → `ui::add_category` →
   then elements. Elements attach to the most recent category.
8. **UI values are read through handles**: `bool v = ui::get(checkbox);` and written with
   `ui::set(checkbox, v);`.
9. **No exceptions** in AngelScript. `is null` / `is null` handle checks, never try/catch.
10. **AngelScript handles use `@`**: `mutex@ m = create_mutex();`, `array<uint8>@ b = ...`.
    `is null` is the null check.
11. **Never invent a helper.** If a convenience function is needed, write it out in the
    template and mark it as user code, not as API.
12. **Do not keep both APIs.** Migrate fully — no comments showing "old way" side by side.

## AngelScript language rules (Echo embeds AngelScript 2.x)

These are language facts, not Echo API. Getting them wrong means the script does not compile.

| Wrong | Right |
|---|---|
| `struct Foo { ... };` | `class Foo { ... };` — `struct` is not a keyword |
| `array<Foo> items;` | `array<Foo@> items;` — script classes are reference types |
| `a.push_back(v)` | `a.insertLast(v)` |
| `a.pop_back()` | `a.removeLast()` |
| `a.insert_at(i, v)` | `a.insertAt(i, v)` |
| `a.remove_at(i)` | `a.removeAt(i)` |
| `a.sort()` | `a.sortAsc()` / `a.sortDesc()` / `a.sort(function(a,b){...})` |
| `void()@ cb = @fn;` | `thread_callback@ cb = @fn;` — a funcdef must be declared |
| `h == null` | `h is null` |
| `a.size()` | `a.length()` |

The registered array's full method set:
`length()`, `resize(uint)`, `reverse()`, `insertAt(uint, T)`, `insertLast(T)`,
`removeAt(uint)`, `removeLast()`, `removeRange(uint, uint)`, `sortAsc()`, `sortDesc()`,
`sort(compareFunc, ...)`, `find(T)`, `findByRef(T)`.

Other language facts:
- Arrays are reference types; `=` is a **shallow** copy of the buffer.
- `array<T>` is a value, `array<T>@` is a handle to the array object.
- Only **declarations** are allowed at file scope. Any executable statement must live
  inside a function.
- `create_thread(tps, cb)` with `tps` 1–128 may only be called from `main()`; `tps` 0 runs
  the callback once and exits.
- There are no exceptions. Indexing an array out of range is a hard error, not a catchable
  exception.
- AngelScript has no `sin`/`cos`/`sqrt`/`abs`/`min`/`max` builtins — use `vec2.length()`,
  `math::forward_vector()`, `math::angles_to_vec()` and explicit user-code helpers.

Ground truth: <https://www.angelcode.com/angelscript/sdk/docs/manual/doc_datatypes_arrays.html>

Additional grammar facts (all verified against the AngelScript 2.38.0 compiler):

| Construct | Verdict |
|---|---|
| `int x[3] = {1,2,3};` | **Illegal.** Use `array<int> x = {1,2,3};` |
| `float m[16];` as a class member | **Illegal.** Use `array<float>` |
| `void()@ cb = @fn;` | **Illegal.** Use a declared funcdef: `thread_callback@ cb = @fn;` |
| `x is not null` | **Illegal.** Use `x !is null` / `x is null` |
| `float &hp` (bare `&`) | **Illegal on a primitive.** Use `float &out hp` (note the space) |
| `EntityData@ out` | **Illegal** — `out` is a reserved keyword |
| nested function definitions | **Illegal.** Hoist to file scope or make it a class method |
| `class X { ... }` | Correct. `struct` is not a keyword — not even at file scope |
| `array<X>` of a script class | Legal, but holds values. Use `array<X@>` for handle semantics |
| `create_thread(tps, @fn)` | Only from `main()`, and only for `tps` 1–128 |
| `m4[1][1]` on a matrix | Legal — `matrix4x4` is host-registered with 2-D indexing |

The compile check is `python3 scripts/check_angelscript.py`; it builds every
`templates/*.as` against an Echo API stub and grammar-checks the doc blocks.


## CANONICAL SNIPPETS (copy these exactly)

### Script skeleton
```angelscript
void on_unload() {
    // teardown
}

bool main() {
    return true;
}
```

### Threading
```angelscript
mutex@ g_lock = create_mutex();

void tick() {
    g_lock.lock();
    // ... shared state
    g_lock.unlock();
}

bool main() {
    create_thread(64, @tick);   // 1-128 tps, 0 = run once
    on_render(@render_tick);
    return true;
}
```

### Process attach + read
```angelscript
bool main() {
    attach_data ad = process::attach("cs2.exe");
    if (ad.pid == 0) return false;

    uint64 base = process::get_module_base("cs2.exe");
    if (base == 0) return false;

    uint64 health = process::read_uint64(ad.base_address + 0x1234);
    float hp = process::read_float(ad.base_address + 0x1240);
    return true;
}
```

### Signature scan
```angelscript
uint64 base = process::get_module_base("game.exe");
uint64 sig = process::find_signature(base, "48 8B 0D ? ? ? ?");
if (sig == 0) return false;
uint64 target = process::get_relative_address(sig, 3, 7);
```

### Render
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

### Menu
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

### World to screen
```angelscript
vec2 screen;
if (!source2::w2s(world_pos, view_matrix, screen)) return;   // off-screen or behind camera
```

### Zydis
```angelscript
array<uint8>@ bytes = process::read_bytes(addr, 64);
if (bytes is null) return;
array<disasm_insn@> insns;
if (!zydis::disasm(bytes, addr, insns)) return;
for (uint i = 0; i < insns.length(); i++) {
    print(insns[i].text);
}
```

### Unicorn
```angelscript
uint64 h = uc::create();
if (h == 0) return;
uc::mem_map(h, 0x1000, 0x1000, uc::prot::all);
uc::mem_write(h, 0x1000, bytes);
uc::reg_write64(h, x86_reg::rip, 0x1000);
uc::start(h, 0x1000, 0x1000 + 0x100, 1000000, 0);
uc::close(h);
```

## APPENDIX — regenerating the index

```bash
curl -fsSL https://echo-23.gitbook.io/angel/llms-full.txt -o /tmp/echo-llms-full.txt
python3 scripts/build_api_index.py /tmp/echo-llms-full.txt -o /tmp/echo-api-index.json
```

The index is JSON: `namespaced` (every `ns::fn` the docs show), `globals` (bare functions such as
`create_thread`), and `lines` (the raw doc line for each namespaced call, useful when adding a
declaration to the compile stub).
