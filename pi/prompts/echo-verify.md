---
description: Run the repo's API and AngelScript checks and fix what they report
---
Run both guards and fix every finding:

```bash
python3 scripts/build_api_index.py /tmp/echo-llms-full.txt -o /tmp/echo-api-index.json
python3 scripts/check_api.py --root . --api-index /tmp/echo-api-index.json
python3 scripts/check_angelscript.py --root . --checker "$PWD/scripts/angelscript/check" --workdir /tmp
```

If the API index is missing, regenerate it with the snippet in
`reference/_API_CONTRACT.md`. If the checker binary is missing, run
`./scripts/angelscript/build.sh` once.

Report the before and after counts. Do not claim a fix without re-running.
