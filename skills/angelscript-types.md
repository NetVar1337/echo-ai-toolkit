# AngelScript Type System — Echo Embedding Reference

Echo scripts run on an embedded AngelScript 2.x engine. Key differences from C++/C#/Python that LLMs get wrong:

---

## Handle types (`@`)

`@` is a reference-counted handle (like a smart pointer). Most Echo objects are handles.

```angelscript
process@ p = process.attach("game.exe");   // handle — can be null
module_info@ m = proc.get_module("x.dll"); // handle — null if not found

if (m is null) return;                     // null check: 'is null', not == null
if (m !is null) { ... }
```

**Value vs handle:**

| Form | Semantics | Null possible |
|------|-----------|---------------|
| `vec3 v` | value (stack/inline) | no |
| `process@ p` | handle (heap ref) | yes |
| `array<uint64>@ a` | handle to array | yes |
| `array<uint64> a` | value array (inline) | no |

Assigning a handle copies the reference, not the object:
```angelscript
module_info@ a = proc.get_module("x.dll");
module_info@ b = a;    // b and a point to the same object
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

// No format string by default — use fmt():
string msg = fmt("health: {:.1f}", hp);
```

---

## array<T>

```angelscript
// Declare
array<uint64> addrs;                    // empty, grows dynamically
array<uint64> addrs(10);                // preallocated with 10 default-init elements
array<uint64> addrs = {0x1234, 0x5678}; // initializer list

// Access
addrs.length()                          // uint — no .size()
addrs[i]                                // no bounds check — crash if OOB
addrs.push_back(val)
addrs.pop_back()
addrs.resize(n)
addrs.insert_at(i, val)
addrs.remove_at(i)
addrs.sort()                            // ascending, primitives

// Passing arrays — always use @& in or &out for efficiency
void process_list(array<uint64>@ &in addrs) { ... }
bool get_results(array<uint64>@ &out results) { ... }
```

**`array<T>@` vs `array<T>`:**
- `array<T>@` — handle to a heap array; can be null; use for return values and out-params
- `array<T>` — value array; always valid; use for local variables

---

## Anonymous functions / closures

```angelscript
// Simple lambda (no captures)
function@ cb = function() { alert("hello"); };
create_thread(64, cb);

// Lambda with capture (capture list in brackets)
int count = 0;
function@ inc = [count]() { count++; };   // captures count BY VALUE at definition

// The captured value is a copy; mutations inside don't affect the outer 'count'
// For shared mutable state, use a global variable or pass via @
```

**Closures cannot capture `@` handles directly.** Use a global variable:
```angelscript
// BAD
process@ p = process.attach("game.exe");
function@ cb = [p]() { p.read<uint64>(0x1234); };  // may not capture @ handles

// GOOD
process@ g_proc = null;
void main() {
    g_proc = process.attach("game.exe");
    create_thread(64, function() { g_proc.read<uint64>(0x1234); });
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
base_class@ base = get_object();
derived_class@ d = cast<derived_class>(base);
if (d is null) { /* cast failed */ }
```

---

## No exceptions

AngelScript has no try/catch. Error handling is by return values:

```angelscript
// proc.read returns default-constructed T (0 / 0.0f / false) on failure
// proc.scan_ida returns 0 on no match
// proc.get_module returns null if module not found
// ws.connect returns null on connection failure

// Pattern: check every result
process@ p = process.attach("game.exe");
if (p is null) return;

module_info@ m = proc.get_module("client.dll");
if (m is null) return;

uint64 addr = proc.scan_ida("48 8B ...", "client.dll");
if (addr == 0) return;
```

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
        health = proc.read<float>(addr + 0x334);
    }
}

enum Team { NONE = 0, CT = 3, T = 2 }
Team t = Team::CT;
if (int(t) == 3) { ... }
```

---

## Template types (Echo built-ins only)

AngelScript in Echo exposes template types for the math library. You cannot define your own template types.

```angelscript
vec2; vec3; vec4         // template over float
mat3x4; mat4x4          // matrix types
array<T>                 // built-in array template

// OK: array<uint64>, array<float>, array<vec3>, array<entity_data>
// OK: array<array<uint64>>   (array of arrays)
```

---

## Common mistakes by C++/Python LLMs

| Mistake | Correct form |
|---------|-------------|
| `if (ptr == null)` | `if (ptr is null)` |
| `arr.size()` | `arr.length()` |
| `float f = 1.5;` | `float f = 1.5f;` |
| `uint32 addr = proc.get_module("x").base;` | `uint64 addr = ...` |
| `string msg = "val: " + val;` | `string msg = fmt("val: {}", val);` |
| `auto x = proc.read(addr);` | `uint64 x = proc.read<uint64>(addr);` (explicit T) |
| `nullptr` | `null` |
| `delete ptr;` | N/A — handles are reference-counted |
