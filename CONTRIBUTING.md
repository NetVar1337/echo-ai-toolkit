# Contributing

## The one rule that matters

**Only the real Echo API.** The API is namespaced:

```angelscript
process::read_uint64(addr)
process::find_signature(base, "48 8B 0D ? ? ? ?")
render::draw_box(x, y, w, h, 255, 0, 0, 255, box_style::FILLED, 0.0f)
ui::add_checkbox("Enable", false)
source2::w2s(world_pos, view_matrix, screen)   // bool; screen is a vec2 out-param
```

`reference/api.md` is the complete reference; `reference/_API_CONTRACT.md` maps the old
invented names to the real ones. CI runs `scripts/check_api.py` and fails the build if
invented API reappears.

```bash
python3 scripts/check_api.py --root . --api-index /tmp/echo-api-index.md
```

To regenerate the index locally:

```bash
curl -fsSL https://echo-23.gitbook.io/angel/llms-full.txt -o /tmp/echo-llms-full.txt
# then use the extraction snippet in reference/_API_CONTRACT.md
```

---

## Adding an agent

Agents live in `agents/`. Claude Code loads them as system prompts when invoked.

Create `agents/echo-<name>.md` with this frontmatter:

```markdown
---
name: echo-<name>
description: One sentence. What this agent does and when to use it.
---

# Agent Title

Short paragraph: what the agent specializes in, what context it needs.

## <Section>
...
```

Required: at least one section covering the core task, with code examples if it generates code.

Then register it in `hooks/register.tsx` — **all three** places:

```typescript
// 1. AGENTS — the description shown in /echo-help
'echo-<name>': 'One-line description',

// 2. AGENT_INFO — the side panel quick-reference
'echo-<name>': {
  desc: 'Short description',
  snippets: ['process::read_uint64(addr)', 'render::draw_box(...)'],
},

// 3. KEYWORDS — ordered most-specific first so broad terms don't shadow narrower ones
[/\b(keyword1|keyword2)\b/i, 'echo-<name>'],
```

Also update the agent tables in `README.md` and `CLAUDE.md`.

CI fails if an `agents/*.md` file has no matching entry in `hooks/register.tsx`.

---

## Adding a skill

Skills live in `skills/<name>/SKILL.md`. They are reference documents loaded on demand.

`SKILL.md` **requires** YAML frontmatter:

```markdown
---
name: <name>
description: One sentence. What this covers and when it should be loaded.
---

# Skill Title
...
```

The `description` is what the model matches against, so make it specific and mention the
trigger terms a user might use.

Reference it from the relevant agent file:

```markdown
See `skills/<name>/SKILL.md` for ...
```

---

## Adding a template

Templates live in `templates/` as `.as` (AngelScript) files. Users copy them to
`%AppData%\Roaming\scripts\` and load directly in Echo.

Requirements:
- `bool main()` that returns `false` on error, with an `alert::show(...)` explaining why
- `void on_unload()` that releases resources
- Named offset constants (`const uint32 OFFSET_FOO = 0x10;`) — no magic numbers inline
- Comments on every offset explaining the struct/field it accesses
- Header comment naming the game, dependencies, and where to get current offsets
- **State clearly that offsets are placeholders** requiring per-patch verification

---

## Plugin hooks

`hooks/register.tsx` is one module for commands, keyword routing, side panel, and state.

State uses atoms from `claude-code`:

```typescript
import { atom, read, update } from 'claude-code';
const agentAtom = atom({ plugin: 'echo-ai-toolkit', key: 'agent' } as const, null as AgentName | null);

await update($, agentAtom, () => name);   // write
const agent = await read($, agentAtom);   // read
```

**Test:** `claude plugin test hooks/` runs `hooks/register.test.tsx`.
**Validate:** `claude plugin validate .`

---

## Commit style

Follow existing commits: single-line imperative for small fixes, a short summary for
multi-file changes. No trailing attribution lines.
