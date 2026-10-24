# Contributing

## Adding an agent

Agents live in `.claude/agents/`. Claude Code loads them as system prompts when invoked.

Create `.claude/agents/echo-<name>.md` with this frontmatter:

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

Required sections: at minimum one section covering the core task the agent handles, with code examples if it generates code.

Then add keyword routing in `hooks/register.tsx`:

```typescript
// In AGENTS:
'echo-<name>': 'One-line description shown in /echo-help',

// In KEYWORDS:
[/\b(keyword1|keyword2|keyword3)\b/i, 'echo-<name>'],
```

Add a snippet entry to `AGENT_INFO` in `hooks/pane.tsx` for the side panel:

```typescript
'echo-<name>': {
  desc: 'Short description',
  snippets: ['api.call1()', 'api.call2()'],
},
```

Update the agent table in `README.md` and `CLAUDE.md`.

---

## Adding a skill

Skills live in `skills/`. They are reference documents loaded by agents when relevant.

Create `skills/<topic>.md`. No required frontmatter — just Markdown.

Reference it from the relevant agent file:

```markdown
See `skills/<topic>.md` for ...
```

---

## Adding a template

Templates live in `templates/` as `.as` (AngelScript) files. Users copy them to `%AppData%\Roaming\scripts\` and load directly in Echo.

Requirements:
- `bool main()` that returns `false` on error with an `alert()`
- `void on_unload()` that nulls out the process handle
- Named offset constants (`const uint32 OFFSET_FOO = 0x10`) — no magic numbers inline
- Comments on every offset explaining the struct/field it accesses
- Header comment naming the game, dependencies, and where to get current offsets

---

## Plugin (hooks/)

The plugin has two modules: `hooks/register.tsx` (commands, keyword routing, state) and `hooks/pane.tsx` (side panel rendering).

`register.tsx` writes the active agent to shared state when it changes:

```typescript
($.state as Record<string, unknown>)['echo-ai-toolkit:agent'] = name;
$.ui.status(`Echo: ${name}`);
```

`pane.tsx` reads from it in the `ui.render` hook:

```typescript
const agent = ($.state as Record<string, unknown>)['echo-ai-toolkit:agent'] as string | null;
```

**Test:** `claude plugin test hooks/` runs `hooks/register.test.tsx`.

**Validate:** `claude plugin validate .`

**Install:**
```
/plugin install echo-ai-toolkit --marketplace NetVar1337/echo-ai-toolkit
```

---

## Commit style

Follow existing commits: `Pass N: short summary` for multi-file passes, single-line imperative for small fixes. No trailing attribution lines.
