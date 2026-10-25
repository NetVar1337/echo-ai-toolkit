---
name: angelscript-types
description: The AngelScript 2.x type system as embedded in Echo: '@' object handles vs value types, is-null checks, array<T> value vs handle semantics, cast<T>(), closures, and the absence of exceptions. Read before writing Echo code that handles objects — LLMs routinely get these wrong.
---

# AngelScript Type System — Echo Embedding Reference

Echo scripts run on an embedded AngelScript 2.x engine. Key differences from C++/C#/Python that LLMs get wrong:

---

## Handle types (`@`)

`@` is a reference-counted handle (like a smart pointer). Most Echo objects are handles.

```angelscript
array<uint8>@ bytes = process::read_bytes(addr, 64);   // handle — null on failure
memory_buffer@ buf = process::read_buffer(addr, 64);    // handle — null on failure
u_bone_array bones = unreal::read_bones(mesh, 0x120, 0x128, 0x160);  // value, use bones.valid()

if (bytes is null) return;                              // null check: 'is null', not == null
if (buf !is null) { ... }
```

**Value vs handle:**

| Form | Semantics | Null possible |
|------|-----------|---------------|
| `vec3 v` | value (stack/inline) | no |
| `int32 n` | value | no |
| `array<uint8>@ a` | handle to array | yes |
| `mutex@ m` | handle to mutex | yes |
| `array<uint8> a` | value array (inline copy) | no |

Assigning a handle copies the reference, not the object:
```angelscript
array<uint8>@ a = process::read_bytes(addr, 64);
array<uint8>@ b = a;    // b and a point to the same array
```

Assigning a **value** array performs a shallow copy of the buffer — it is not a deep copy.
Element values are copied, but handle elements (`array<X@>`) stay shared:
```angelscript
array<uint8> a = {1, 2, 3};
array<uint8> b = a;    // b holds the same element values
```

`process::attach()` does **not** return a handle — it returns a plain struct:
```angelscript
attach_data ad = process::attach("game.exe");
if (ad.pid == 0) return false;   // ad.base_address / ad.peb_address are plain uint64
```

---

## Primitive types

| Type | C++ equiv | Size | Range |
|------|-----------|------|-------|
| `uint8` | uint8_t | 1 | 0–255 |
| `uint16` | uint16_t | 2 | 0–65535 |
| `uint32` / `uint` | uint32_t | 4 | 0–4294967295 |
| `uint64` | uint64_t | 8 | 0–18446744073709551615 |
| `int8` | int8_t | 1 | -128–127 |
| `int16` | int16_t | 2 | -32768–32767 |
| `int32` / `int` | int32_t | 4 | -2147483648–2147483647 |
| `int64` | int64_t | 8 | full 64-bit signed |
| `float` | float | 4 | ~7 decimal digits |
| `double` | double | 8 | ~15 decimal digits |
| `bool` | bool | 1 | true / false |

**Use `uint64` for all process addresses.** `uint32` silently truncates 64-bit addresses.

---

## string

```angelscript
string s = "hello";
string t = s + " world";   // concatenation with +
s.length()                 // uint, not int
s[0]                       // uint8 (char code)

// Formatting: util::format_string with {} placeholders
string msg = util::format_string("health: {:.1f}", hp);
string hex = util::to_hex(addr);        // "0x7FF6A0001234"
```

`util::format_string` supports `{}` (next arg), `{0}` (by index), `{{`/`}}` (literals),
`{:<8}` / `{>8}` / `{08}` (alignment/width) and `{:.2}` (precision). Up to 8 arguments.
Invalid or out-of-range placeholders render as `{?}`. `util::format_string` is the only
formatting helper.

---

## array<T>

```angelscript
// Declare
array<uint64> addrs;                    // empty, grows dynamically
array<uint64> addrs(10);                // preallocated with 10 default-init elements
array<uint64> addrs = {0x1234, 0x5678}; // initializer list

// Access
addrs.length()                          // uint — no .size(), no .getSize()
addrs[i]                                // out-of-range index raises an exception
addrs.insertLast(val)                   // append
addrs.insertAt(uint i, val)             // insert at index
addrs.removeAt(uint i)                  // remove at index
addrs.removeLast()                      // remove last element
addrs.removeRange(uint start, uint count)
addrs.resize(uint n)
addrs.reverse()
addrs.sortAsc()                         // ascending — `sort` always needs a comparator
addrs.sortDesc()
addrs.sort(compareFunc)                 // custom comparator
addrs.find(val)                         // index of first match, negative if none
addrs.findByRef(val)                    // index of matching reference

// Passing arrays — `const ... &in` for inputs, `... &out` for outputs
void process_list(const array<uint64>@ &in addrs) { ... }
bool get_results(array<uint64> &out results) { ... }
```

**`array<T>@` vs `array<T>`:**
- `array<T>@` — handle to an array object; can be null; use for return values and for
  holding a reference to an array object
- `array<T>` — value array; always valid; use for local variables and for out-params
  (`array<T> &out` — an out-param is never a handle)

Echo API functions that return arrays return handles, so null-check them:
```angelscript
array<uint8>@ bytes = process::read_bytes(addr, 64);
if (bytes is null) return;          // failed read

array<module_entry>@ mods = process::get_module_list();
if (mods is null) return;
for (uint i = 0; i < mods.length(); i++) {
    print(mods[i].name);
}
```

A value array of handles is fine — `array<entity@> entities;`.

---

## Anonymous functions / callbacks

Named functions are declared normally; a function reference is written with a leading `@`:

```angelscript
void my_tick() {
    print("tick");
}

bool main() {
    create_thread(64, @my_tick);      // pass @my_tick
    on_render(@my_tick);
    return true;
}
```

A function handle's type comes from a declared *funcdef* — there is no `void()` type.
Echo's callback funcdef for `create_thread`/`on_render` is `thread_callback`:

```angelscript
void thread_callback() {}            // funcdef declaration

bool main() {
    thread_callback@ cb = @my_tick;   // stored handle
    create_thread(64, cb);            // ticking threads are created from main()
    return true;
}
```

Anonymous functions are written inline as `function(...) { ... }`:

```angelscript
bool main() {
    create_thread(64, function() {
        print("anonymous tick");
    });
    return true;
}
```

**Do not rely on capturing enclosing locals.** An anonymous function is not a scoped closure
over the surrounding stack — it has no reliable access to the local variables of the function
it was written in. Share state through globals, a `mutex@`, or an `atomic_*@` instead.

```angelscript
// BAD — the inner function cannot see the local `count`
bool bad_example() {
    int count = 0;
    create_thread(64, function() { count++; });   // not a captured local
    return true;
}

// GOOD — a global, guarded by a mutex
mutex@ g_lock = create_mutex();
int g_count = 0;

bool main() {
    create_thread(64, function() {
        g_lock.lock();
        g_count++;
        g_lock.unlock();
    });
    return true;
}
```

For a lock-free counter, use the atomic types:

```angelscript
atomic_int32@ g_counter = atomic_int32(0);

void tick() {
    int prev = g_counter.load();
    g_counter.store(prev + 1);
}
```

---

## Type casting

```angelscript
// Implicit numeric widening (safe)
uint32 a = 5;
uint64 b = a;          // ok: widening

// Explicit narrowing (truncates — no overflow check)
uint64 big = 0x1234567890;
uint32 small = uint32(big);  // truncates to low 32 bits

// float ↔ int
float f = float(42);
int n = int(3.7f);     // truncates toward zero (= 3, not 4)

// Handle cast (returns null if incompatible)
class base_t {}
class derived_t : base_t {}

base_t@ base = ...;
derived_t@ d = cast<derived_t>(base);
if (d is null) { /* cast failed */ }
```

`cast<T>()` is the only way to downcast; it returns `null` on failure rather than throwing.

---

## No exceptions

AngelScript has no try/catch and Echo raises nothing. Error handling is by return values
and null handles:

```angelscript
// Typed reads return a default value (0 / 0.0f / false) on failure.
// Use the out-parameter overloads to tell failure from a genuine zero:
uint64 val = 0;
if (!process::read_uint64(addr, val)) return;   // false == read failed

// Signature scans return 0 when nothing matches
uint64 sig = process::find_signature(base, "48 8B 0D ? ? ? ?");
if (sig == 0) return;

// Module lookup returns 0 when the module is not loaded
uint64 base = process::get_module_base("client.dll");
if (base == 0) return;

// Byte reads return a null handle on failure
array<uint8>@ bytes = process::read_bytes(addr, 64);
if (bytes is null) return;

// W2S helpers return false when the point is off-screen or behind the camera
vec2 screen;
if (!source2::w2s(world_pos, view_matrix, screen)) return;

// Attach returns a struct whose pid is 0 on failure
attach_data ad = process::attach("game.exe");
if (ad.pid == 0) return false;
```

Pattern: check every result. Never assume a value is valid because it is non-zero.

---

## Numeric literals

```angelscript
uint64 a = 0xDEADBEEF;          // hex
uint64 b = 12345678u;           // unsigned suffix
float  c = 1.5f;                // float suffix (required for float literals)
double d = 1.5;                 // double (no suffix)
bool   e = true;                // not True, not 1

// Arithmetic promotion — mixing types follows C-like rules
uint64 offset = 0x10;
uint64 addr = base + uint64(index) * 8 + offset;  // explicit cast to avoid uint32 overflow
```

---

## Classes and enums

```angelscript
class Entity {
    uint64 address;
    float  health;

    void read(uint64 addr) {
        address = addr;
        health = process::read_float(addr + 0x334);
    }
}

enum Team { NONE = 0, CT = 3, T = 2 }
Team t = Team::CT;
if (int(t) == 3) { ... }
```

A script class is a reference type: `Entity e = ...` creates an instance and `Entity@ e`
is a handle to it. An array of class instances therefore holds handles — `array<Entity@>`.

---

## Template types (Echo built-ins only)

AngelScript in Echo exposes vector and matrix value types. You cannot define your own
template types.

```angelscript
vec2; vec3; vec4          // float vectors — value types, not handles
matrix3x3; matrix3x4; matrix4x4
array<T>                  // built-in array template

// OK: array<uint64>, array<float>, array<vec3>, array<entity@>
// OK: array<array<uint64>>   (array of arrays)

// Vector methods
v3.length(); v3.length_squared(); v3.normalize(); v3.dot(other);
v3.add(other); v3.subtract(other); v3.multiply(scalar);
v3.distance(other); v3.lerp(other, t);   // lerp lives on the vector, not on math::

// Vector memory access (reads from the attached process)
vec3 p; p.read_float(address);    // 3 floats
p.write_float(address);

// Matrix element access and memory reads
matrix4x4 m4;
float v = m4[1][1];
m4[0][0] = 1.0f;
bool ok = m4.read(address);        // 16 floats from the attached process
bool ok2 = m4.read_double(address);
```

`v2.lerp(other, t)` is the only lerp — there is no `math::lerp`.

---

## Entry point

Every Echo script must define `bool main()`. The script does not compile without it.

```angelscript
void on_unload() {
    // optional teardown — reference counting frees script objects automatically
}

bool main() {
    return true;   // true  = script loaded
                   // false = unload the script / signal failure
}
```

`main()` is also the only place ticking threads may be created
(`create_thread` with 1–128 tps); one-shot threads (tps 0) may be created from any context.

---

## Common mistakes by C++/Python LLMs

| Mistake | Correct form |
|---------|-------------|
| `if (ptr == null)` | `if (ptr is null)` |
| `arr.size()` | `arr.length()` |
| `float f = 1.5;` | `float f = 1.5f;` |
| `uint32 addr = module_base;` | `uint64 addr = process::get_module_base("x");` |
| `string msg = "val: " + val;` | `string msg = util::format_string("val: {}", val);` |
| `uint64 x = process::read_int64(addr);` | `uint64 x = process::read_uint64(addr);` (read the type you mean) |
| `nullptr` | `null` |
| `delete ptr;` | N/A — handles are reference-counted |
| `main()` with no return type | `bool main()` returning `true`/`false` |
| `vec3@ p;` | `vec3 p;` — vectors are value types |
| `mutex m;` | `mutex@ m = create_mutex();` |
