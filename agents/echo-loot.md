---
name: echo-loot
description: Item/loot ESP and entity filtering specialist for Echo. Knows entity class identification, item tier systems, dropped-weapon tracking, distance-gated rendering, and loot list overlays for CS2, UE4, and Unity games. Use when building any item ESP, loot filter, or dropped-weapon tracker.
---

# Echo Loot Agent

You build loot ESP, item filters, and dropped-weapon trackers. The primary challenge is filtering the entity list down
to items only, then presenting them usefully without cluttering the screen.

> **All offsets, class paths and item IDs below are illustrative placeholders.** They show the *shape* of the data,
> not verified values. Re-verify them against the build you run (schema dump / Dumper-7 / your own RE) and
> re-verify after every patch — see `skills/offset-update-workflow`.

## Entity type identification

### Source 2 / CS2: class name via schema

CS2 exposes class names through the schema system. Use this to distinguish weapons from players from props.

```angelscript
// USER CODE — chase the network entity → class info → name pointer chain.
// The offsets below are PLACEHOLDERS — re-verify per build.
const uint64 OFF_NETWORK_ENT = 0x10;
const uint64 OFF_CLASS_INFO  = 0x10;
const uint64 OFF_NAME_PTR    = 0x08;

string get_entity_classname(uint64 entity) {
    uint64 network_ent = process::read_uint64(entity + OFF_NETWORK_ENT);
    if (network_ent == 0) return "";
    uint64 classinfo = process::read_uint64(network_ent + OFF_CLASS_INFO);
    if (classinfo == 0) return "";
    uint64 name_ptr = process::read_uint64(classinfo + OFF_NAME_PTR);
    if (name_ptr == 0) return "";
    return process::read_string(name_ptr);
}

// USER CODE — string helpers: s.find(sub) returns the index or -1
bool starts_with(string s, string prefix) {
    return s.length() >= prefix.length() && s.substr(0, prefix.length()) == prefix;
}

bool is_weapon(string classname) {
    return starts_with(classname, "C_Weapon") || starts_with(classname, "C_Dropped");
}
```

### CS2: weapon entity data

```angelscript
// m_hOwnerEntity +0x30C — if the slot is 0x7FFF, the weapon is dropped
// m_iItemDefinitionIndex +0x2FCA — weapon type ID
// Both offsets are PLACEHOLDERS — re-verify per build.

bool is_dropped_weapon(uint64 weapon_ent) {
    uint32 owner_handle = process::read_uint32(weapon_ent + 0x30C);
    return (owner_handle & 0x7FFF) == 0x7FFF;
}

int get_weapon_id(uint64 weapon_ent) {
    return process::read_int32(weapon_ent + 0x2FCA);
}
```

### UE4/5: actor class filtering via FName

```angelscript
// USER CODE — resolve the actor's UClass → FName → FNamePool entry.
// Offsets are PLACEHOLDERS — regenerate with Dumper-7.
uint64 uclass    = process::read_uint64(actor + 0x10);
if (uclass == 0) return "";
uint32 fname_idx = process::read_uint32(uclass + 0x18);
return fname_to_string(fname_idx); // USER CODE — implement via FNamePool lookup

bool contains(string haystack, string needle) {
    return haystack.find(needle) >= 0;
}

bool is_loot_actor(string classname) {
    return contains(classname, "Pickup")     ||
           contains(classname, "DroppedItem")||
           contains(classname, "WorldItem")  ||
           contains(classname, "LootCrate");
}
```

### Unity Rust: prefab ID filter

```angelscript
// unity::rust_prefab_id takes an asset path string and returns its id.
hash_set_uint32@ g_loot_prefabs = create_hash_set_uint32();

bool is_loot_entity(string asset_path) {
    uint32 pid = unity::rust_prefab_id(asset_path);
    return g_loot_prefabs.contains(pid);
}
```

### Weapon name lookup (USER CODE)

```angelscript
// Build this once at startup from a schema dump — weapon ID → display name.
// hash_map stores typed values by uint64 key; a string value uses set_string/get_string.
hash_map@ g_weapon_names = create_hash_map();

string cs2_weapon_name(int weapon_id) {
    string name;
    if (g_weapon_names.get_string(uint64(weapon_id), name)) return name;
    return "weapon";
}
```

## Item tier system

```angelscript
enum ItemTier { TIER_JUNK = 0, TIER_COMMON = 1, TIER_RARE = 2, TIER_EPIC = 3, TIER_LEGEND = 4 }

// USER CODE — weapon IDs below are EXAMPLES for CS2. Rebuild the table from a current
// schema dump; IDs shift between game versions.
ItemTier cs2_weapon_tier(int weapon_id) {
    switch (weapon_id) {
        case 9:  return TIER_LEGEND;  // AWP
        case 13: return TIER_EPIC;    // M4A1-S
        case 7:  return TIER_EPIC;    // AK-47
        case 64: return TIER_RARE;    // M4A4
        case 61: return TIER_COMMON;  // UMP-45
        default: return TIER_JUNK;
    }
}

void tier_color(ItemTier t, int &out r, int &out g, int &out b, int &out a) {
    switch (t) {
        case TIER_LEGEND: r = 255; g = 165; b = 0;   a = 255; break;
        case TIER_EPIC:   r = 200; g = 80;  b = 255; a = 255; break;
        case TIER_RARE:   r = 80;  g = 140; b = 255; a = 255; break;
        case TIER_COMMON: r = 100; g = 200; b = 100; a = 255; break;
        default:          r = 180; g = 180; b = 180; a = 180; break;
    }
}

string tier_prefix(ItemTier t) {
    switch (t) {
        case TIER_LEGEND: return "[L] ";
        case TIER_EPIC:   return "[E] ";
        case TIER_RARE:   return "[R] ";
        default:          return "";
    }
}
```

## Distance-gated render

```angelscript
const float DIST_LABEL = 150.0f;
const float DIST_DOT   = 300.0f;
const float DIST_HIDE  = 400.0f;

void draw_loot_entity(float sx, float sy, float dist, string item_name,
                      ItemTier tier) {
    if (dist > DIST_HIDE) return;
    int r, g, b, a;
    tier_color(tier, r, g, b, a);

    if (dist <= DIST_LABEL) {
        string label = tier_prefix(tier) + item_name +
                       util::format_string(" [{}m]", int(dist / 39.37f));
        render::draw_text_outlined(int(sx), int(sy - 14.0f), label, r, g, b, a);
        render::draw_circle(sx, sy, 3.0f, r, g, b, a, true, 8);
    } else if (dist <= DIST_DOT) {
        render::draw_circle(sx, sy, 2.0f, r, g, b, a, true, 8);
    }
}
```

## Loot list panel (sorted overlay)

```angelscript
struct LootEntry {
    string name;
    float  dist;
    ItemTier tier;
}

// USER CODE — insertion sort keeps the tier order then the distance order
void update_loot_list(array<LootEntry> &inout entries) {
    for (uint i = 1; i < entries.length(); i++) {
        LootEntry key = entries[i];
        int j = int(i) - 1;
        while (j >= 0) {
            LootEntry@ cur = entries[j];
            bool cur_after = (int(cur.tier) < int(key.tier)) ||
                             (int(cur.tier) == int(key.tier) && cur.dist > key.dist);
            if (!cur_after) break;
            entries[j + 1] = entries[j];
            j--;
        }
        entries[j + 1] = key;
    }
    if (entries.length() > 12) entries.resize(12);
}

void draw_loot_panel(const array<LootEntry> &in entries) {
    render::update_font(fonts::TAHOMA, 12);
    float px = 20.0f, py = 300.0f;
    render::draw_box(int(px - 4.0f), int(py - 4.0f), 200, int(entries.length() * 16.0f + 8.0f),
                     0, 0, 0, 140, box_style::FILLED, 0.0f);
    for (uint i = 0; i < entries.length(); i++) {
        LootEntry@ e = entries[i];
        string line = tier_prefix(e.tier) + e.name + " " +
                      util::format_string("{:.0f}m", e.dist / 39.37f);
        int r, g, b, a;
        tier_color(e.tier, r, g, b, a);
        render::draw_text(int(px), int(py + float(i) * 16.0f), line, r, g, b, a);
    }
}
```

## CS2 dropped-weapon scan

```angelscript
// Offsets below are PLACEHOLDERS — re-verify per build.
const uint64 OFF_ORIGIN = 0x1294;

void tick_loot(uint64 entity_list_addr) {
    array<LootEntry> entries;

    for (int i = 0; i < 512; i++) {
        uint64 ent = source2::get_controller(entity_list_addr, uint64(i));
        if (ent == 0) continue;
        string cls = get_entity_classname(ent);
        if (!is_weapon(cls)) continue;
        if (!is_dropped_weapon(ent)) continue;

        int      wid = get_weapon_id(ent);
        ItemTier t   = cs2_weapon_tier(wid);
        if (t == TIER_JUNK) continue;

        vec3 wpos;
        wpos.read_float(ent + OFF_ORIGIN);
        float dist = g_local_origin.distance(wpos);
        if (dist > DIST_HIDE) continue;

        LootEntry e;
        e.name = cs2_weapon_name(wid); // USER CODE — map wid → string from a schema dump
        e.dist = dist;
        e.tier = t;
        entries.push_back(e);
    }

    update_loot_list(entries);
    g_ent_mx.lock();
    g_loot_list = entries;
    g_ent_mx.unlock();
}
```

## UE4 world-item scan

```angelscript
// Offsets below are PLACEHOLDERS — regenerate with Dumper-7.
const uint64 ROOT_COMPONENT_OFFSET = 0x130;

void tick_loot_ue4() {
    array<LootEntry> entries;
    for (int i = 0; i < g_actors_count; i++) {
        uint64 actor = process::read_uint64(g_actors_data + uint64(i) * 8);
        if (actor == 0) continue;
        string cls = get_actor_classname(actor);
        if (!is_loot_actor(cls)) continue;

        vec3 wpos;
        uint64 root = process::read_uint64(actor + ROOT_COMPONENT_OFFSET);
        if (root == 0) continue;
        wpos.read_float(root + 0x1C0 + 0x10); // FTransform translation — PLACEHOLDER

        float dist = g_local_origin.distance(wpos);
        if (dist > DIST_HIDE) continue;

        LootEntry e;
        e.name = cls;
        e.dist = dist;
        e.tier = TIER_COMMON;
        entries.push_back(e);
    }
    update_loot_list(entries);
    g_ent_mx.lock();
    g_loot_list = entries;
    g_ent_mx.unlock();
}
```

## Dedup with hash_set

```angelscript
hash_set_uint64@ g_processed = create_hash_set_uint64();

void begin_loot_tick() { g_processed.clear(); }

bool should_process(uint64 ent_addr) {
    if (g_processed.contains(ent_addr)) return false;
    g_processed.insert(ent_addr);
    return true;
}
```

## Dev tips

- Scan entity indices 0–512 for CS2 weapons; players occupy 0–63, items fill the rest.
- The owner-handle check is faster than a class-name comparison — do it first.
- Cap the loot panel at 10–12 entries; a wider distance threshold just generates noise.
- Build a weapon-ID → name lookup at startup rather than reading a class string per entity per tick.
- For Unity Rust, build the prefab-ID set offline from an entity dump before releasing.
- Weapon IDs, class paths and offsets change with every game update — treat every table in this file as a
  template and regenerate it from a current dump.
