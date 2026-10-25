---
name: offset-update-workflow
description: Post-patch offset recovery for Echo scripts: confirm the patch broke something, binary-diff to find the new instruction, reacquire the function, regenerate the pattern, and update one line per broken signature. Use when find_signature stops resolving after a game update.
---

# Offset update workflow

Use this after a game patch breaks your `process::find_signature` patterns. Goal: update one line per broken sig in under 10 minutes.

---

## Step 0 — Confirm the patch broke something

```angelscript
// Add this to your tick() to surface broken sigs immediately
if (entity_list == 0) {
    alert::show("entity_list sig returned 0 — patch broke it");
    return;
}
```

---

## Step 1 — Get the new binary

Steam games: copy the updated module before launching.

```bash
cp "C:/Program Files (x86)/Steam/steamapps/common/Counter-Strike Global Offensive/game/bin/win64/client.dll" \
   ~/re/cs2/client_new.dll
```

For Valorant: `VALORANT-Win64-Shipping.exe` in `%LocalAppData%\VALORANT\live\ShooterGame\Binaries\Win64\`.

---

## Step 2 — Binary diff to find what changed

Use `diaphora` (open source IDA plugin) or radare2:

```bash
# diaphora
idat64 -A -S"diaphora.py -o /tmp/old.sqlite" client_old.dll
idat64 -A -S"diaphora.py -o /tmp/new.sqlite" client_new.dll
python diaphora.py /tmp/old.sqlite /tmp/new.sqlite -o /tmp/diff.sqlite

# radare2 quick diff
r2 -c "aaa; pdd > /tmp/old_funcs.txt" client_old.dll
r2 -c "aaa; pdd > /tmp/new_funcs.txt" client_new.dll
diff /tmp/old_funcs.txt /tmp/new_funcs.txt | head -100
```

---

## Step 3 — Find the broken function in the new binary

Search for a string the broken function references:

```
# IDA: Search → Text → "C_BaseEntity"
# radare2:
r2 client_new.dll
[0x00400000]> aaa
[0x00400000]> iz~BaseEntity        # search strings
[0x00400000]> axt @ <string_addr>  # xrefs → lands in the function
```

---

## Step 4 — Extract a new unique byte sequence

```bash
# radare2: print 20 raw bytes at function start
[0x00400000]> s <function_addr>
[0x00400000]> p8 20

# confirm uniqueness (want exactly 1 match):
[0x00400000]> /x 48895C2410
```

---

## Step 5 — Build the IDA-style pattern

Replace bytes that contain addresses with `?`:

- `E8 xx xx xx xx` (CALL rel32) → `E8 ? ? ? ?`
- `48 8B 0D xx xx xx xx` (MOV RCX,[RIP+off]) → `48 8B 0D ? ? ? ?`
- `4C 8D 05 xx xx xx xx` (LEA R8,[RIP+off]) → `4C 8D 05 ? ? ? ?`

Example:
```
48 89 5C 24 10 57 48 83 EC 20 48 8B 0D A1 23 45 67
→
48 89 5C 24 10 57 48 83 EC 20 48 8B 0D ? ? ? ?
```

---

## Step 6 — Update the one line

```angelscript
// OLD (broken):
uint64 addr = process::find_signature(base, "48 8B 0D A1 23 45 67 48 85 C9 74 ? 4C 8B 01");

// NEW:
uint64 addr = process::find_signature(base, "48 89 5C 24 10 57 48 83 EC 20 48 8B 0D ? ? ? ?");
```

One line. Nothing else changes.

---

## Step 7 — Smoke test

```angelscript
uint64 base = process::get_module_base("client.dll");
if (base == 0) return false;

uint64 addr = process::find_signature(base, "48 89 5C 24 10 57 48 83 EC 20 48 8B 0D ? ? ? ?");
console::log("entity_system sig: " + util::to_hex(addr));   // must be non-zero
```

---

## Live offset sources

Check these before doing your own RE — community-run sources, no fixed update cadence:

| Game | Source |
|------|--------|
| CS2 | https://github.com/a2x/cs2-dumper |
| Apex | https://github.com/dword64/Apex-Legends-SDK-Remaster |

Load from JSON at runtime instead of hardcoding volatile pointers:

```angelscript
string raw;
if (!file::read("cs2_offsets.json", raw)) return;

string err;
json_obj@ o = json::parse(raw, err);
if (o is null) {
    console::error("offset json parse failed: " + err);
    return;
}

json_obj@ client = o.get_obj("client.dll");
if (client is null) return;
uint32 dwEntityList = client.get_uint("dwEntityList");
```

---

## Quick-reference: common broken sigs per game update

| Signal broke | What to look for in new binary |
|---|---|
| Entity list | String ref `"CL_GetLocalPlayer"` near the access |
| View matrix | `sin`/`cos` calls + 16 float writes in same function |
| Player health | Walk entity → component → `"CCSPlayerController"` |
| Bone matrix | String `"Bones"` or `0x200`-aligned allocation |
