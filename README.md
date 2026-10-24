# echo-ai-toolkit

AI development toolkit for the [Echo Universal API](https://echo-23.gitbook.io/angel) — an AngelScript scripting platform with process memory access, Discord overlay rendering, Zydis disassembly, and Unicorn emulation.

## What's in here

| Path | What it is |
|------|------------|
| `.claude/agents/echo-dev.md` | Claude Code agent with the full Echo API baked in |
| `templates/basic.as` | Minimal script skeleton |
| `templates/render.as` | ESP / overlay rendering starter |
| `templates/menu.as` | Full menu UI with all element types |
| `templates/memory.as` | Process attach + pattern scan + tick loop |
| `reference/api.md` | Quick API cheatsheet (all namespaces) |

## Using the Claude Code agent

If you have [Claude Code](https://claude.com/claude-code), clone this repo and open it as your working directory. The `echo-dev` agent is automatically available:

```
cd echo-ai-toolkit
claude
```

Inside the session you can invoke it directly:

```
Agent: echo-dev — write me a script that reads player health via pattern scan and draws an ESP box
```

Or just describe what you want and Claude will pick it up from the context.

### Without Claude Code

The agent file at `.claude/agents/echo-dev.md` is plain Markdown. Paste its contents into any AI assistant's system prompt to give it Echo API knowledge. The LLM-optimized upstream docs are also at:

```
https://echo-23.gitbook.io/angel/llms-full.txt
```

## Templates

Copy a template to `%AppData%\Roaming\scripts\`, edit it, then close and reopen the in-game menu to load. No compile step.

```
templates/
  basic.as    minimal entry point
  render.as   ESP box + text rendering
  menu.as     checkbox / slider / color picker / combobox / button
  memory.as   attach + IDA-style pattern scan + RIP-resolve + read loop
```

## Quick-start

```
1. Copy templates/basic.as  →  %AppData%\Roaming\scripts\hello.as
2. Edit it
3. Reopen the in-game menu
4. Select hello from the script list
```

## Reference

[`reference/api.md`](reference/api.md) — full table of every namespace and call.

Upstream docs: https://echo-23.gitbook.io/angel
