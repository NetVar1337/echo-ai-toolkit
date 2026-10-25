# Echo AI Toolkit — project context

This is the Echo AI Toolkit. It documents the Echo Universal API (AngelScript) and
ships agents, skills, templates, and verified reference material.

## Layout

| Path | What it is |
|---|---|
| `agents/*.md` | 12 specialist agent definitions |
| `skills/<name>/SKILL.md` | 18 reference skills, loaded on demand |
| `templates/*.as` | 15 runnable AngelScript templates |
| `reference/api.md` | complete API reference, 22 namespaces |
| `reference/_API_CONTRACT.md` | old→new API mapping, 12 rules, language rules |
| `llms.txt` | single-file context bundle for other models |
| `pi/` | this Pi profile (SYSTEM.md, APPEND_SYSTEM.md, prompts, skills) |

## Verification

Two guards exist; both run in CI. Use them instead of trusting prose:

```bash
python3 scripts/check_api.py --root . --api-index /tmp/echo-api-index.md
python3 scripts/check_angelscript.py --root . \
  --checker "$PWD/scripts/angelscript/check" --workdir /tmp
```

The second compiles every `templates/*.as` against an Echo API stub and
grammar-checks every doc code block. Build it once with
`./scripts/angelscript/build.sh`.

## Regenerating the API index

```bash
curl -fsSL https://echo-23.gitbook.io/angel/llms-full.txt -o /tmp/echo-llms-full.txt
# extraction snippet is in reference/_API_CONTRACT.md, appendix
```

## Conventions

- Agents are self-contained system prompts — no external lookups.
- Every skill needs `name` + `description` frontmatter; the description is what the
  model routes on, so state what it does **and when to use it**.
- Game-specific offsets are placeholders. Say so.
- Prefer deleting dead code to commenting it out.
