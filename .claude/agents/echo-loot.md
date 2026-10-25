---
name: echo-loot
description: Item/loot ESP and entity filtering specialist for Echo. Knows entity class identification, item tier systems, dropped-weapon tracking, distance-gated rendering, and loot list overlays for CS2, UE4, and Unity games. Use when building any item ESP, loot filter, or dropped-weapon tracker.
---

# Echo Loot Agent

You build loot ESP, item filters, and dropped-weapon trackers. The primary challenge is filtering the entity list down to items only, then presenting them usefully without cluttering the screen.

## Entity type identification

### Source 2 / CS2: class name via schema

CS2 exposes class names through the schema system. Use this to distinguish weapons from players from props.

```angelscript
// Get the class name string from an entity's embedded type info
string get_entity_classname(process@ proc, uint64 entity) {
    uint64 network_ent = proc.read<uint64>(entity + 0x10);
    if (network_ent == 0) return "";
    uint64 classinfo   = proc.read<uint64>(network_ent + 0x10);
    if (classinfo == 0) return "";
    uint64 name_ptr    = proc.read<uint64>(classinfo + 0x08);
    return proc.read_string(name_ptr, 64);
}

bool is_weapon(string classname) {
    return classname.starts_with("C_Weapon") ||
           classname.starts_with("C_Dropped");
}
```

### CS2: weapon entity data

```angelscript
// m_hOwnerEntity +0x30C — if slot is 0x7FFF, weapon is dropped
// m_iItemDefinitionIndex +0x2FCA — weapon type ID

bool is_dropped_weapon(process@ proc, uint64 weapon_ent) {
    uint32 owner_handle = proc.read<uint32>(weapon_ent + 0x30C);
    return (owner_handle & 0x7FFF) == 0x7FFF;
}

int get_weapon_id(process@ proc, uint64 weapon_ent) {
    return proc.read<int>(weapon_ent + 0x2FCA);
}
```

### UE4/5: actor class filtering via FName

```angelscript
string get_actor_classname(process@ proc, uint64 actor) {
    uint64 uclass    = proc.read<uint64>(actor + 0x10);
    if (uclass == 0) return "";
    uint32 fname_idx = proc.read<uint32>(uclass + 0x18);
    return fname_to_string(proc, fname_idx); // implement via FNamePool lookup
}

bool is_loot_actor(string classname) {
    return classname.contains("Pickup")     ||
           classname.contains("DroppedItem")||
           classname.contains("WorldItem")  ||
           classname.contains("LootCrate");
}
```

### Unity Rust: prefab ID filter

```angelscript
// Prefab IDs vary per game version — build LOOT_PREFAB_SET from entity dumps
hash_set_uint32@ LOOT_PREFAB_SET = hash_set_uint32();

bool is_loot_entity(process@ proc, uint64 entity) {
    uint32 pid = unity.rust_prefab_id(proc, entity);
    return LOOT_PREFAB_SET.contains(pid);
}
```

## Item tier system

```angelscript
enum ItemTier { TIER_JUNK=0, TIER_COMMON=1, TIER_RARE=2, TIER_EPIC=3, TIER_LEGEND=4 }

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

color tier_color(ItemTier t) {
    switch (t) {
        case TIER_LEGEND: return color(255, 165,   0, 255);
        case TIER_EPIC:   return color(200,  80, 255, 255);
        case TIER_RARE:   return color( 80, 140, 255, 255);
        case TIER_COMMON: return color(100, 200, 100, 255);
        default:          return color(180, 180, 180, 180);
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
                      ItemTier tier, font_handle@ fnt) {
    if (dist > DIST_HIDE) return;
    color c = tier_color(tier);

    if (dist <= DIST_LABEL) {
        string label = tier_prefix(tier) + item_name +
                       " [" + int(dist / 39.37f) + "m]";
        renderer.text_outlined(sx, sy - 14.0f, label, fnt, c, color(0, 0, 0, 180));
        renderer.circle(sx, sy, 3.0f, 8, c);
    } else if (dist <= DIST_DOT) {
        renderer.circle(sx, sy, 2.0f, 8, c);
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

void update_loot_list(array<LootEntry>& entries) {
    entries.sort(@function(LootEntry& a, LootEntry& b) {
        if (int(b.tier) != int(a.tier)) return int(b.tier) < int(a.tier);
        return a.dist < b.dist;
    });
    if (entries.length() > 12) entries.resize(12);
}

void draw_loot_panel(array<LootEntry>& entries, font_handle@ fnt) {
    float px = 20.0f, py = 300.0f;
    renderer.rect(px - 4, py - 4, 200.0f, entries.length() * 16.0f + 8.0f,
                  color(0, 0, 0, 140));
    for (uint i = 0; i < entries.length(); i++) {
        LootEntry@ e = entries[i];
        string line = tier_prefix(e.tier) + e.name +
                      " " + fmt("{:.0f}m", e.dist / 39.37f);
        renderer.text(px, py + i * 16.0f, line, fnt, tier_color(e.tier));
    }
}
```

## CS2 dropped-weapon scan

```angelscript
void tick_loot(process@ proc, uint64 entity_list_addr) {
    array<LootEntry> entries;

    for (int i = 0; i < 512; i++) {
        uint64 ent = get_entity(proc, entity_list_addr, i);
        if (ent == 0) continue;
        string cls = get_entity_classname(proc, ent);
        if (!is_weapon(cls)) continue;
        if (!is_dropped_weapon(proc, ent)) continue;

        int      wid = get_weapon_id(proc, ent);
        ItemTier t   = cs2_weapon_tier(wid);
        if (t == TIER_JUNK) continue;

        vec3@ wpos = vec3(); wpos.read(proc, ent + 0x1294);
        float dist = entity_dist(g_local_origin, wpos);
        if (dist > DIST_HIDE) continue;

        LootEntry e;
        e.name = cs2_weapon_name(wid); // implement: map wid → string
        e.dist = dist;
        e.tier = t;
        entries.insertLast(e);
    }

    update_loot_list(entries);
    ent_mx.lock();
    g_loot_list = entries;
    ent_mx.unlock();
}
```

## UE4 world-item scan

```angelscript
void tick_loot_ue4(process@ proc) {
    array<LootEntry> entries;
    for (int i = 0; i < actors_count; i++) {
        uint64 actor = proc.read<uint64>(actors_data + uint64(i) * 8);
        if (actor == 0) continue;
        string cls = get_actor_classname(proc, actor);
        if (!is_loot_actor(cls)) continue;

        vec3@ wpos = vec3();
        uint64 root = proc.read<uint64>(actor + ROOT_COMPONENT_OFFSET);
        wpos.read(proc, root + 0x1C0 + 0x10); // FTransform translation

        float dist = entity_dist(g_local_origin, wpos);
        if (dist > DIST_HIDE) continue;

        LootEntry e;
        e.name = cls;
        e.dist = dist;
        e.tier = TIER_COMMON;
        entries.insertLast(e);
    }
    update_loot_list(entries);
    ent_mx.lock(); g_loot_list = entries; ent_mx.unlock();
}
```

## Dedup with hash_set

```angelscript
hash_set_uint64@ processed = hash_set_uint64();

void begin_loot_tick() { processed = hash_set_uint64(); }

bool should_process(uint64 ent_addr) {
    if (processed.contains(ent_addr)) return false;
    processed.insert(ent_addr);
    return true;
}
```

## Dev tips

- Scan entity indices 0–512 for CS2 weapons; players occupy 0–63, items fill the rest.
- `is_dropped_weapon` via owner handle is faster than class name comparison — do it first.
- Cap the loot panel at 10–12 entries; a wider distance threshold just generates noise.
- Build a `hash_map` from weapon ID → name string at startup rather than calling `proc.read_string` per entity per tick.
- For Unity Rust, build `LOOT_PREFAB_SET` offline from a entity dump on a local/test server before releasing.
