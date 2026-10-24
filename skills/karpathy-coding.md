# Karpathy Coding Principles for Echo Development

**Source:** multica-ai/andrej-karpathy-skills — 4 principles distilled from Karpathy's coding philosophy.

Apply these when writing, reviewing, or extending Echo AngelScript scripts.

---

## 1. Think Before Coding

Understand the full problem before writing a single line.

**For Echo work this means:**
- Read the target game's memory layout before writing readers — know the struct, the pointer chain, the data type
- Know which AC is active before choosing techniques (see echo-anticheat agent)
- Trace the full chain (GObjects → Actor → Component → FTransform) mentally before coding it
- Identify what can fail (null pointers, ASLR, page unreadable) before writing the loop

**Anti-pattern:**
```angelscript
// Bad: write first, debug pointer chains later
uint64 player = proc.read<uint64>(base + 0x1234);
float hp      = proc.read<float>(player + 0x330);  // may crash if player == 0
```

**Right:**
```angelscript
// Good: think through all pointer levels, add null checks
uint64 player = proc.read<uint64>(base + OFF_LOCALPLAYER);
if (player == 0) return false;
float hp = proc.read<float>(player + OFF_HEALTH);
```

---

## 2. Simplicity First

The simplest code that works correctly is the best code.

**For Echo work this means:**
- One pattern scan per module, not one per struct field
- Hardcode verified offsets as named constants; don't build a dynamic offset resolver unless you need it
- Skip abstractions that will never be used in a 200-line game script
- Prefer `proc.read<float>` over a generic wrapper when you only call it in two places

**Complexity budget rule:**
> Before adding a class, ask: does this script benefit from it? For a 150-line CS2 ESP, no.  
> For a 600-line multi-game framework shared across scripts, yes.

```angelscript
// Over-engineered (for a single game script):
class OffsetManager {
    hash_map<string, uint64> offsets;
    void register(string key, uint64 val) { offsets[key] = val; }
    uint64 get(string key) { return offsets[key]; }
};

// Right (for a single game script):
const uint64 OFF_HEALTH        = 0x330;
const uint64 OFF_TEAM          = 0x3B8;
const uint64 OFF_LOCALPLAYER   = 0x1234;
```

---

## 3. Surgical Changes

Change exactly what needs to change. No more.

**For Echo scripts after a game patch:**
1. Run binary diff → identify exactly which functions changed
2. Update only the `proc.scan_ida()` pattern string for each broken function
3. Verify one value (health ≈ 100 at spawn)
4. Commit: "update patterns for 2025-11-01 patch"

**Anti-pattern (patching too wide):**
```angelscript
// Bad: rewrote the whole entity loop because one offset changed
// Good: changed only the scan pattern on line 12
```

**Applied to new features:**
- Adding a triggerbot? Touch only the aim loop. Don't touch ESP, menu, or memory readers.
- Fixing a W2S pop? Fix W2S. Don't refactor the draw loop.

---

## 4. Goal-Driven Execution

Every line of code serves the current stated goal. No gold-plating.

**For Echo work this means:**
- The goal of a CS2 ESP script is: draw boxes, bones, health. Not: support 12 games, have config persistence, draw fancy gradients.
- The goal of an aimbot script is: move mouse toward nearest enemy. Not: build a configurable aim framework with plugins.
- Always ask: does this line move the script closer to working in the game right now?

**Checklist before adding anything:**
1. Does the user's stated goal require this?
2. Will this be used today?
3. Can I add it later in 5 minutes if needed?

If any answer is no, skip it and add a comment if it's worth remembering:

```angelscript
// shortcut: single game target — no multi-game offset routing; add if porting to Rust/Apex
```

---

## Applying the 4 principles together — example

**Task:** "Add distance labels to the ESP"

**Before coding:**
- Think: distance = `(enemy_pos - local_pos).length()`. Already have both. No new memory reads.
- Simple: one `renderer.text` call with `fmt("{:.0f}m", dist/100.0)`.
- Surgical: add 3 lines to the existing entity draw loop.
- Goal-driven: don't add a distance-based color scale unless asked.

```angelscript
// In entity draw loop, after drawing the box:
float dist_m = (enemy_pos - local_pos).length() / 100.0;
renderer.text(screen_feet.x, screen_feet.y + 2, fmt("{:.0f}m", dist_m), color_white, font_small);
```

**What was skipped:**
- Distance-fade transparency (not asked)
- Distance-based ESP toggle (not asked)
- Custom font/size per distance range (not asked)

---

## Install

This skill is part of the [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) Claude Code skills package:

```
/skills install multica-ai/andrej-karpathy-skills
```

Installs all 4 Karpathy principles as a Claude Code skill set, automatically applied to every new code task in the session.
