# Ponytail — Lazy Senior Dev Philosophy

**Source:** DietrichGebert/ponytail — Claude Code plugin that enforces minimum-code discipline.

Active in this toolkit by default. Install the plugin for automatic enforcement:
```
/plugin install ponytail --marketplace DietrichGebert/ponytail
```

---

## Core rule

The best code is the code never written. Solve the whole problem with the least new code.

---

## Before writing anything

1. **Does it need to exist?** Skip features, options, flexibility nobody asked for.
2. **Already in this codebase?** Use the existing helper the same way surrounding code does.
3. **Standard API or platform feature?** Use it.
4. **Installed dependency?** Use it. Never add a dependency for a few lines.
5. **Can it be one line a reader gets at a glance?** One line.
6. Otherwise: the minimum code that works.

---

## Applied to Echo scripts

**A bug fix on a 200-line CS2 script:**
- Find the broken pattern string → update one `proc.scan_ida()` call → done
- Do not refactor the entity loop because you're "in there anyway"
- Do not extract helpers unless they're called 3+ times

**Adding a feature to an existing template:**
- Adding distance labels? Three lines in the existing draw loop. Not a new class.
- Adding triggerbot? Touch only the aim loop. Not the ESP, menu, or readers.
- Adding bones? One skeleton function. Not a bone manager system.

**Starting a new script:**
- For a single game, single purpose: flat procedural code — named constants, no classes
- Complexity budget: class earns its existence at ~600 lines or 3+ callers

---

## The shortest complete diff

Finish every part the task needs — callers, null checks, the thing that uses what you just wrote. Lazy about the **solution**, never about the **change itself**.

```angelscript
// Bad: rewrote the whole entity loop because one offset changed
// Good: changed only the scan pattern on line 12

// shortcut: single game target — no multi-game offset routing; add if porting to Apex
const uint32 OFF_HEALTH = 0x334;
```

A `shortcut:` comment names the known limit and when to upgrade — that's a decision, not tech debt.

---

## What to cut

- Dead code — delete it, don't comment it out
- Speculative features no one asked for
- Abstractions with one implementation
- Config options nobody sets
- Near-copies of existing helpers (use the original)
- Functions that exist only to make another function shorter

---

## What never to cut

- Null checks on every pointer read from external process memory (`if (ptr == 0) return;`)
- Error handling that prevents a crash when `proc.read` fails on an unmapped page
- Any guard before a multi-level deref chain

---

## Ponytail levels

| Level | Behaviour |
|-------|-----------|
| `full` (default) | All the rules above; balanced between correctness and leanness |
| `lite` | Only the most critical lean rules; less aggressive |
| `ultra` | Maximum leanness; every line is questioned |

Switch: `/ponytail lite` · `/ponytail full` · `/ponytail ultra`  
Stop: `stop ponytail` or `normal mode`
