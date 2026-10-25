---
name: echo-triggerbot
description: Triggerbot specialist for Echo. Covers crosshair-on-enemy detection (W2S FOV check and entity AABB), shot delay variance, burst fire, multi-button modes, per-hitbox targeting, scoped-weapon handling, and AC-safe timing patterns. Use when building any auto-fire or shoot-on-crosshair feature.
---

# Echo Triggerbot Agent

A triggerbot fires when the crosshair is on an enemy — no aim movement involved. Detection is
done by checking whether a valid enemy entity projects to within a small pixel or angular radius
of the screen center each tick.

---

## Detection: W2S FOV check (recommended)

Project the target hitbox to screen; fire when the screen distance to center is below a threshold.

```angelscript
const float TRIG_PIX_RADIUS = 6.0f;
const float SCR_CX = 960.0f;
const float SCR_CY = 540.0f;

bool crosshair_on_entity(uint64 ent, uint64 view_mat_addr) {
    uint64 skel  = proc.read<uint64>(ent + OFF_SKELETON);
    uint64 bones = proc.read<uint64>(skel + OFF_BONE_ARR);
    uint64 addr  = bones + uint64(BONE_CHEST) * 0x20 + 0x10;
    vec3 wpos(proc.read<float>(addr),
              proc.read<float>(addr + 4),
              proc.read<float>(addr + 8));

    float sx, sy;
    if (!source2.w2s(proc, view_mat_addr, wpos, sx, sy)) return false;

    float dx = sx - SCR_CX, dy = sy - SCR_CY;
    return (dx*dx + dy*dy) <= (TRIG_PIX_RADIUS * TRIG_PIX_RADIUS);
}
```

**Threshold tuning:**
- `≤ 5px` — head-only effective; very tight
- `6–12px` — chest/body; good for rifles
- `> 15px` — too wide; fires before crosshair visually reaches the model

---

## Detection: angular FOV check (resolution-independent)

```angelscript
const float TRIG_FOV_DEG = 1.5f;

bool crosshair_on_entity_fov(vec3 enemy_pos, vec3 local_pos, vec2 local_angles) {
    float dx = enemy_pos.x - local_pos.x;
    float dy = enemy_pos.y - local_pos.y;
    float dz = enemy_pos.z - local_pos.z;
    float horiz = sqrt(dx*dx + dy*dy);
    float pitch  = -math.rad_to_deg(atan2(dz, horiz));
    float yaw    = math.rad_to_deg(atan2(dy, dx));
    float dp     = math.normalize_angle(pitch - local_angles.x);
    float dy2    = math.normalize_angle(yaw   - local_angles.y);
    return sqrt(dp*dp + dy2*dy2) <= TRIG_FOV_DEG;
}
```

---

## Shot delay and variance

Fire immediately-on-detection = periodic signal = trivially flagged. Always add randomized delay.

```angelscript
const uint DELAY_MIN_MS = 40;
const uint DELAY_MAX_MS = 110;
const uint HOLD_MS      = 80;   // button hold duration

uint64 g_fire_at    = 0;
uint64 g_release_at = 0;
bool   g_waiting    = false;

void triggerbot_tick(bool on_target) {
    uint64 now = time.now();

    if (g_release_at != 0 && now >= g_release_at) {
        mouse.key_up(0x01);
        g_release_at = 0;
        return;
    }

    if (g_waiting && now >= g_fire_at) {
        g_waiting = false;
        if (on_target) {           // verify still on target at fire time
            mouse.key_down(0x01);
            g_release_at = now + HOLD_MS;
        }
        return;
    }

    if (on_target && !g_waiting && g_release_at == 0) {
        uint delay = uint(random.int(int(DELAY_MIN_MS), int(DELAY_MAX_MS)));
        g_fire_at = now + delay;
        g_waiting = true;
    }

    if (!on_target) g_waiting = false;
}
```

**Key invariant:** re-check `on_target` at `g_fire_at` — the enemy may have moved during the delay.

---

## Burst mode

```angelscript
const int  BURST_COUNT   = 2;
const uint BURST_GAP_MS  = 180;
const uint BURST_COOL_MS = 350;

int    g_burst_fired    = 0;
uint64 g_burst_next_ms  = 0;
uint64 g_burst_cool_end = 0;

void burst_tick(bool on_target) {
    uint64 now = time.now();
    if (now < g_burst_cool_end) return;
    if (!on_target) { g_burst_fired = 0; return; }
    if (now < g_burst_next_ms) return;

    if (g_burst_fired < BURST_COUNT) {
        mouse.key_tap(0x01);
        g_burst_fired++;
        g_burst_next_ms = now + BURST_GAP_MS;
    } else {
        g_burst_fired    = 0;
        g_burst_cool_end = now + BURST_COOL_MS;
    }
}
```

---

## Multi-button modes

```angelscript
combobox@ t_mode;   // {"Hold", "Toggle", "Always"}
keybind@  t_key;
bool      g_toggle = false;

bool trig_active() {
    int m = t_mode.get();
    if (m == 0) return input.key_down(t_key.get());
    if (m == 1) { if (input.key_pressed(t_key.get())) g_toggle = !g_toggle; return g_toggle; }
    return true;
}
```

---

## Per-hitbox targeting

| Target | Bone | Use case | AC risk |
|--------|------|----------|---------|
| Chest  | 7 | Rifles, SMGs — large hitbox | Low |
| Head   | 9 | AWP, headshot-only mode | Medium (high hit rate) |
| Neck   | 8 | Smaller than chest, better hit% than head | Low |
| Pelvis | 5 | Crouch-spam targets | Low |

```angelscript
combobox@ t_hitbox;  // {"Chest", "Head", "Neck", "Pelvis"}
int[] HITBOX_BONES = {7, 9, 8, 5};
int get_target_bone() { return HITBOX_BONES[t_hitbox.get()]; }
```

---

## CS2 specifics

### Scoped weapon gate (AWP)

```angelscript
const uint64 OFF_IS_SCOPED    = 0x1000;  // m_bIsScoped
const uint64 OFF_WEAPON_HANDLE= 0xCE8;
const uint64 OFF_ITEM_DEF_IDX = 0x2FAA;
const uint16 AWP_DEF          = 9;       // verify against current cs2-dumper

bool fire_allowed(uint64 local_player) {
    uint64 wpn_handle = proc.read<uint64>(local_player + OFF_WEAPON_HANDLE);
    uint64 wpn = proc.read<uint64>(entity_list + (wpn_handle & 0x7FFF) * 0x78);
    if (wpn == 0) return true;
    uint16 def = proc.read<uint16>(wpn + OFF_ITEM_DEF_IDX);
    if (def == AWP_DEF)
        return proc.read<bool>(local_player + OFF_IS_SCOPED);
    return true;
}
```

### Shots-fired gate (semi-auto)

```angelscript
const uint64 OFF_SHOTS_FIRED = 0x1374;  // m_iShotsFired
int g_last_shots = 0;

bool weapon_ready(uint64 local_player) {
    int shots = proc.read<int>(local_player + OFF_SHOTS_FIRED);
    bool ready = (shots == g_last_shots);
    g_last_shots = shots;
    return ready;
}
```

---

## Full CS2 triggerbot — minimal wiring

```angelscript
// Assumes entity_list, view_mat_addr, local_player found by do_scan()
// (share globals with esp.as or copy the scan block from esp-bones.as)

const uint64 OFF_SKELETON = 0x168;
const uint64 OFF_BONE_ARR = 0x80;
const uint64 OFF_TEAM     = 0x3CB;
const uint64 OFF_LIFE     = 0x338;
const int    BONE_CHEST   = 7;
const float  TRIG_R       = 7.0f;

bool g_toggle2    = false;
bool g_waiting2   = false;
uint64 g_fire_at2 = 0;
uint64 g_rel_at2  = 0;

tab@      tab_t;
checkbox@ t_on;
combobox@ t_mode2;
keybind@  t_key2;
slider@   t_dmin, t_dmax;

bool main() {
    tab_t  = menu.add_tab("Trigger");
    auto c = tab_t.add_category("Settings");
    t_on   = c.add_checkbox("Enable",    false,              "t.on");
    t_mode2= c.add_combobox("Mode",      {"Hold","Toggle","Always"}, 0, "t.mode");
    t_key2 = c.add_keybind("Key",        0x05,               "t.key");
    t_dmin = c.add_slider("Delay min ms",20.0f,200.0f,45.0f, "t.dmin");
    t_dmax = c.add_slider("Delay max ms",20.0f,300.0f,110.0f,"t.dmax");

    proc = process.attach("cs2.exe");
    if (proc is null) { alert("cs2.exe not found"); return false; }

    create_thread(0,   @do_scan);
    create_thread(128, @tick);
    return true;
}

bool mode_active() {
    if (!t_on.get()) return false;
    int m = t_mode2.get();
    if (m == 0) return input.key_down(t_key2.get());
    if (m == 1) { if (input.key_pressed(t_key2.get())) g_toggle2 = !g_toggle2; return g_toggle2; }
    return true;
}

bool scan_on_target() {
    if (entity_list == 0 || view_mat_addr == 0 || local_player == 0) return false;
    uint64 lp = proc.read<uint64>(local_player);
    if (lp == 0) return false;
    int lp_team = proc.read<int>(lp + OFF_TEAM);

    for (int i = 1; i < 64; i++) {
        uint64 chunk = proc.read<uint64>(entity_list + uint64(i >> 9) * 8);
        if (chunk == 0) continue;
        uint64 ent = proc.read<uint64>(chunk + uint64(i & 0x1FF) * 120);
        if (ent == 0 || ent == lp) continue;
        if (proc.read<uint8>(ent + OFF_LIFE) != 0) continue;
        if (proc.read<int>(ent + OFF_TEAM) == lp_team) continue;

        uint64 skel = proc.read<uint64>(ent + OFF_SKELETON);
        uint64 barr = proc.read<uint64>(skel + OFF_BONE_ARR);
        uint64 ba   = barr + uint64(BONE_CHEST) * 0x20 + 0x10;
        vec3 wp(proc.read<float>(ba), proc.read<float>(ba+4), proc.read<float>(ba+8));

        float sx, sy;
        if (!source2.w2s(proc, view_mat_addr, wp, sx, sy)) continue;
        float dx = sx - 960.0f, dy = sy - 540.0f;
        if (dx*dx + dy*dy <= TRIG_R * TRIG_R) return true;
    }
    return false;
}

void tick() {
    uint64 now = time.now();

    if (g_rel_at2 != 0 && now >= g_rel_at2) {
        mouse.key_up(0x01); g_rel_at2 = 0; return;
    }

    if (!mode_active()) { g_waiting2 = false; return; }

    bool tgt = scan_on_target();

    if (g_waiting2 && now >= g_fire_at2) {
        g_waiting2 = false;
        if (tgt) { mouse.key_down(0x01); g_rel_at2 = now + 75; }
        return;
    }

    if (tgt && !g_waiting2 && g_rel_at2 == 0) {
        uint d = uint(random.int(int(t_dmin.get()), int(t_dmax.get())));
        g_fire_at2 = now + d;
        g_waiting2 = true;
    }

    if (!tgt) g_waiting2 = false;
}

void on_unload() { proc = null; }
```

---

## AC-safe patterns

- **Never fire on the same tick as detection** — minimum 20ms delay even in "fast" mode
- **Randomize delay** over a ≥ 60ms window (`max - min >= 60`)
- **Re-verify on_target at fire time** — prevents phantom shots when enemy moves during delay
- **Cap burst count ≤ 3** — sustained auto-fire at weapon RPM is a statistical signal
- **Don't combine with RCS in the same tick** — two simultaneous mouse moves stand out
- **Skip ~15% of triggers** randomly: `if (random.int(0, 6) == 0) { g_waiting = false; return; }`
- **Use a side-mouse button** (`0x05` X1) — main fire button events are more scrutinized

## mcp-gamehacking queries

```
search_skills("triggerbot detection")
search_skills("cs2 triggerbot offset")
get_agent_briefing("cs2-specialist")
read_subagent("detection-assessor")
```
