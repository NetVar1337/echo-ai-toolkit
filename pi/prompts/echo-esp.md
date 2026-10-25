---
description: Write Echo ESP code — boxes, skeletons, health bars, W2S
argument-hint: "[game or feature]"
---
Read `skills/echo-esp/SKILL.md` and `reference/api.md` before writing anything.

Write Echo AngelScript ESP code for: ${@:-a CS2/Source 2 player ESP with cornered boxes, a 12-bone skeleton, a health bar, and distance labels}

Requirements:
- `bool main()` returning true, `void on_unload()` teardown
- entity reads on a tick thread, drawing on `on_render(@cb)` only
- share entity state through a `mutex@` (lock_shared on the render side)
- W2S via `source2::w2s(pos, view_matrix, screen)` — check the bool
- colours as four separate ints `r, g, b, a`
- name every offset as a `const uint64 OFF_*` with a comment, and label it a
  placeholder that must be re-derived per patch
