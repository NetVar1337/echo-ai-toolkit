---
name: echo-triggerbot
description: Triggerbot specialist for Echo. Covers crosshair-on-enemy detection (W2S FOV check and entity AABB), shot delay variance, burst fire, multi-button modes, per-hitbox targeting, scoped-weapon handling, and AC-safe timing patterns. Use when building any auto-fire or shoot-on-crosshair feature.
---

# Echo Triggerbot Agent

A triggerbot fires when the crosshair is on an enemy — no aim movement involved. Detection is
done by checking whether a valid enemy entity projects to within a small pixel or angular radius
of the screen center each tick.

> **All offsets and signatures below are illustrative placeholders.** Re-verify each one against the build you
> actually run and re-verify after every patch — see `skills/offset-update-workflow`. Firing uses
> `input::mouse_press()` / `input::mouse_release()` / `input::mouse_click()`; there is no VK-coded mouse API.

---

## Detection: W2S FOV check (recommended)

Project the target hitbox to screen; fire when the screen distance to center is below a threshold.

```angelscript
// Offsets below are PLACEHOLDERS — re-verify per build.
const uint64 OFF_SKELETON   = 0x168;
const uint64 OFF_BONE_ARRAY = 0x80;
const uint64 BONE_ENTRY_SIZE = 0x20;

const float TRIG_PIX_RADIUS = 6.0f;

bool crosshair_on_entity(uint64 ent, const matrix4x4 &in vm, vec2 screen_center) {
    uint64 skel  = process::read_uint64(ent + OFF_SKELETON);
    if (skel == 0) return false;
    uint64 bones = process::read_uint64(skel + OFF_BONE_ARRAY);
    if (bones == 0) return false;

    uint64 addr = bones + uint64(BONE_CHEST) * BONE_ENTRY_SIZE + 0x10;
    vec3 wpos;
    wpos.read_float(addr);

    // W2S writes to an out-param and returns bool
    vec2 screen;
    if (!source2::w2s(wpos, vm, screen)) return false;

    float dx = screen.x - screen_center.x;
    float dy = screen.y - screen_center.y;
    return (dx * dx + dy * dy) <= (TRIG_PIX_RADIUS * TRIG_PIX_RADIUS);
}
```

**Threshold tuning:**
- `≤ 5px` — head-only effective; very tight
- `6–12px` — chest/body; good for rifles
- `> 15px` — too wide; fires before crosshair visually reaches the model

---

## Detection: angular FOV check (resolution-independent)

```angelscript
const double TRIG_FOV_DEG = 1.5;

bool crosshair_on_entity_fov(vec3 enemy_pos, vec3 local_pos, vec2 local_angles) {
    vec2 aim = math::calculate_angle(local_pos, enemy_pos);
    double dp = math::angle_diff(local_angles.x, aim.x);
    double dy = math::angle_diff(local_angles.y, aim.y);
    double dp2 = dp * dp;
    double dy2 = dy * dy;
    return vec2(float(dp2), float(dy2)).length() <= float(TRIG_FOV_DEG);
}
```

---

## Shot delay and variance

Firing on the exact tick of detection produces a perfectly periodic signal. Always add a randomised delay.

```angelscript
const uint DELAY_MIN_MS = 40;
const uint DELAY_MAX_MS = 110;
const uint HOLD_MS      = 80;   // button hold duration

uint64 g_fire_at    = 0;
uint64 g_release_at = 0;
bool   g_waiting    = false;

void triggerbot_tick(bool on_target) {
    uint64 now = util::time_now();

    if (g_release_at != 0 && now >= g_release_at) {
        input::mouse_release();
        g_release_at = 0;
        return;
    }

    if (g_waiting && now >= g_fire_at) {
        g_waiting = false;
        if (on_target) {           // verify still on target at fire time
            input::mouse_press();
            g_release_at = now + HOLD_MS;
        }
        return;
    }

    if (on_target && !g_waiting && g_release_at == 0) {
        uint delay = uint(util::random_int(int(DELAY_MIN_MS), int(DELAY_MAX_MS)));
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
    uint64 now = util::time_now();
    if (now < g_burst_cool_end) return;
    if (!on_target) { g_burst_fired = 0; return; }
    if (now < g_burst_next_ms) return;

    if (g_burst_fired < BURST_COUNT) {
        input::mouse_click();
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
combobox t_mode;   // {"Hold", "Toggle", "Always"}
bool     g_toggle = false;
bool     g_last_key = false;

bool trig_active() {
    int m = int(ui::get(t_mode));
    if (m == 0) return input::key_active(0x05);              // X1 held
    if (m == 1) {
        // Toggle mode — key_toggled reflects OS toggle keys (caps lock), not press edges,
        // so track the press edge yourself.
        bool now = input::key_active(0x05);
        if (now && !g_last_key) g_toggle = !g_toggle;
        g_last_key = now;
        return g_toggle;
    }
    return true;
}
```

---

## Per-hitbox targeting

Bone indices are game-specific — verify them for your game and version.

| Target | Bone | Use case |
|--------|------|----------|
| Chest  | 7 | Rifles, SMGs — large hitbox |
| Head   | 9 | AWP, headshot-only mode |
| Neck   | 8 | Smaller than chest, better hit% than head |
| Pelvis | 5 | Crouch-spam targets |

```angelscript
combobox t_hitbox;  // {"Chest", "Head", "Neck", "Pelvis"}

int get_target_bone() {
    array<int> hitbox_bones = {7, 9, 8, 5};
    return hitbox_bones[int(ui::get(t_hitbox))];
}
```

---

## CS2 specifics

### Scoped weapon gate (AWP)

```angelscript
// Offsets below are PLACEHOLDERS — re-verify per build.
const uint64 OFF_IS_SCOPED     = 0x1000;  // m_bIsScoped
const uint64 OFF_WEAPON_HANDLE = 0xCE8;
const uint64 OFF_ITEM_DEF_IDX  = 0x2FAA;
const int    AWP_DEF           = 9;       // verify against a current CS2 dumper

bool fire_allowed(uint64 local_player, uint64 entity_list) {
    uint32 wpn_handle = process::read_uint32(local_player + OFF_WEAPON_HANDLE);
    uint64 wpn = get_entity(entity_list, int(wpn_handle & 0x7FFF));
    if (wpn == 0) return true;
    int def = process::read_int32(wpn + OFF_ITEM_DEF_IDX);
    if (def == AWP_DEF)
        return process::read_uint8(local_player + OFF_IS_SCOPED) != 0;
    return true;
}
```

### Shots-fired gate (semi-auto)

```angelscript
const uint64 OFF_SHOTS_FIRED = 0x1374;  // m_iShotsFired
int g_last_shots = 0;

bool weapon_ready(uint64 local_player) {
    int shots = process::read_int32(local_player + OFF_SHOTS_FIRED);
    bool ready = (shots == g_last_shots);
    g_last_shots = shots;
    return ready;
}
```

---

## Full CS2 triggerbot — minimal wiring

```angelscript
// Assumes entity_list, view_matrix_addr and local_player found by do_scan()
// (share globals with the ESP agent, or copy its scan block).

const uint64 OFF_TEAM = 0x3CB;
const uint64 OFF_LIFE = 0x338;
const int    BONE_CHEST = 7;
const float  TRIG_R = 7.0f;

bool   g_toggle2    = false;
bool   g_waiting2   = false;
uint64 g_fire_at2   = 0;
uint64 g_rel_at2    = 0;

checkbox g_enabled;
combobox g_mode;
slider   g_delay_min;
slider   g_delay_max;

uint64 entity_list      = 0;
uint64 view_matrix_addr = 0;
uint64 local_player     = 0;

// USER CODE — chunked entity-list lookup for Source 2. The stride/offset are PLACEHOLDERS.
uint64 get_entity(uint64 entity_list_addr, int index) {
    uint64 chunk = process::read_uint64(entity_list_addr + uint64(index >> 9) * 8);
    if (chunk == 0) return 0;
    return process::read_uint64(chunk + uint64(index & 0x1FF) * 120);
}

bool main() {
    ui::config_path("triggerbot");
    ui::add_tab("Trigger");
    ui::add_category("Settings");
    g_enabled   = ui::add_checkbox("Enable", false, "t.on");
    g_mode      = ui::add_combobox("Mode", {"Hold", "Toggle", "Always"}, 0, "t.mode");
    g_delay_min = ui::add_slider("Delay min ms", 20, 20, 200, 5, "ms", "t.dmin");
    g_delay_max = ui::add_slider("Delay max ms", 110, 20, 300, 5, "ms", "t.dmax");

    attach_data ad = process::attach("cs2.exe");
    if (ad.pid == 0) { alert::show("cs2.exe not found"); return false; }

    create_thread(0,   @do_scan);
    create_thread(128, @tick);
    return true;
}

void do_scan() {
    uint64 client_base = process::get_module_base("client.dll");
    if (client_base == 0) { alert::show_tag("client.dll not found", "error"); return; }

    // Signatures below are PLACEHOLDERS — re-verify per patch.
    uint64 ent_sig = process::find_signature(client_base, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 48");
    if (ent_sig == 0) { alert::show_tag("Entity list pattern broken", "error"); return; }
    entity_list = process::get_relative_address(ent_sig, 3, 7);

    uint64 vm_sig = process::find_signature(client_base, "48 8D 05 ? ? ? ? 48 89 05 ? ? ? ? 48");
    if (vm_sig != 0) view_matrix_addr = process::get_relative_address(vm_sig, 3, 7);

    uint64 lp_sig = process::find_signature(client_base, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 8B 01");
    if (lp_sig != 0) local_player = process::get_relative_address(lp_sig, 3, 7);
}

bool mode_active() {
    if (!ui::get(g_enabled)) return false;
    int m = int(ui::get(g_mode));
    if (m == 0) return input::key_active(0x05);
    if (m == 1) {
        bool now = input::key_active(0x05);
        if (now && !g_last_key) g_toggle2 = !g_toggle2;
        g_last_key = now;
        return g_toggle2;
    }
    return true;
}

bool scan_on_target() {
    if (entity_list == 0 || view_matrix_addr == 0 || local_player == 0) return false;
    uint64 lp = process::read_uint64(local_player);
    if (lp == 0) return false;
    int lp_team = process::read_int32(lp + OFF_TEAM);

    matrix4x4 vm;
    if (!vm.read(view_matrix_addr)) return false;
    vec2 center = render::get_viewport_size();
    center.x *= 0.5f;
    center.y *= 0.5f;

    for (int i = 1; i < 64; i++) {
        uint64 ent = get_entity(entity_list, i);
        if (ent == 0 || ent == lp) continue;
        if (process::read_uint8(ent + OFF_LIFE) != 0) continue;
        if (process::read_int32(ent + OFF_TEAM) == lp_team) continue;

        uint64 skel = process::read_uint64(ent + OFF_SKELETON);
        if (skel == 0) continue;
        uint64 barr = process::read_uint64(skel + OFF_BONE_ARRAY);
        if (barr == 0) continue;
        uint64 ba = barr + uint64(BONE_CHEST) * BONE_ENTRY_SIZE + 0x10;
        vec3 wp;
        wp.read_float(ba);

        vec2 screen;
        if (!source2::w2s(wp, vm, screen)) continue;
        float dx = screen.x - center.x, dy = screen.y - center.y;
        if (dx * dx + dy * dy <= TRIG_R * TRIG_R) return true;
    }
    return false;
}

void tick() {
    uint64 now = util::time_now();

    if (g_rel_at2 != 0 && now >= g_rel_at2) {
        input::mouse_release();
        g_rel_at2 = 0;
        return;
    }

    if (!mode_active()) { g_waiting2 = false; return; }

    bool tgt = scan_on_target();

    if (g_waiting2 && now >= g_fire_at2) {
        g_waiting2 = false;
        if (tgt) { input::mouse_press(); g_rel_at2 = now + 75; }
        return;
    }

    if (tgt && !g_waiting2 && g_rel_at2 == 0) {
        uint d = uint(util::random_int(int(ui::get(g_delay_min)), int(ui::get(g_delay_max))));
        g_fire_at2 = now + d;
        g_waiting2 = true;
    }

    if (!tgt) g_waiting2 = false;
}

void on_unload() { process::detach(); }
```

---

## Timing patterns

- **Never fire on the same tick as detection** — minimum 20ms delay even in "fast" mode
- **Randomise the delay** over a ≥ 60ms window (`max - min >= 60`)
- **Re-verify `on_target` at fire time** — prevents phantom shots when the enemy moves during the delay
- **Cap burst count ≤ 3** — sustained auto-fire at weapon RPM is a mechanical signature
- **Don't combine with RCS in the same tick** — two simultaneous mouse moves stand out in the input log
- **Skip some triggers randomly**: `if (util::random_int(0, 6) == 0) { g_waiting = false; return; }`
- **Use a side mouse button** (`0x05` X1) for the trigger key — it keeps the main fire button free

## mcp-gamehacking queries

```
search_skills("triggerbot detection")
search_skills("cs2 triggerbot offset")
get_agent_briefing("cs2-specialist")
read_subagent("detection-assessor")
```
