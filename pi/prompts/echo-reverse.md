---
description: Reverse-engineer a binary toward a working Echo script
argument-hint: "[binary or target function]"
---
Read `skills/reverse-workflow/SKILL.md` and `reference/api.md` first.

Work this target: ${@:-an unknown game binary, goal is the entity list and local player}

Sequence:
1. `process::get_module_base` then `process::find_signature` to locate the anchor
2. `process::get_relative_address` — remember it returns the operand address, so read
   the pointer with `process::read_uint64`
3. confirm the pointer chain by reading each hop and checking for 0
4. only then write the Echo script

For each step say what you would run and what output would confirm it. Do not present
an offset as verified until it has been read from a live process.
