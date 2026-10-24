# mcp-gamehacking Integration

This toolkit integrates with [mcp-gamehacking](https://github.com/1llu50ry/mcp-gamehacking) — an MCP server that gives Claude access to over 4,100 game hacking skills, 75 specialist agents, 161 subagents, 114 plugins, and 148 prompt templates.

Combined with this toolkit's Echo-specific agents, you get both deep game-engine/AC knowledge (mcp-gamehacking) and Echo AngelScript code generation (this toolkit).

---

## Installation

```bash
git clone https://github.com/1llu50ry/mcp-gamehacking
cd mcp-gamehacking
npm install
npm run build
```

Then edit `.mcp.json` at the root of this repo and replace `PATH_TO_MCP_GAMEHACKING` with the absolute path to your clone:

```json
{
  "mcpServers": {
    "gamehacking": {
      "command": "node",
      "args": ["/absolute/path/to/mcp-gamehacking/dist/index.js"]
    }
  }
}
```

Restart Claude Code — the `gamehacking` MCP server will appear in your tool list.

---

## Available MCP tools (16)

### Workflow tools
| Tool | What it does |
|------|-------------|
| `research_technique` | End-to-end research on a technique; returns ranked skills by relevance |
| `analyze_project` | Full analysis of a skill's source code and SKILL.md |
| `get_agent_briefing` | Loads an agent definition + its subagents and plugins |

### Skill tools
| Tool | What it does |
|------|-------------|
| `list_skills` | List and filter the 4100+ skills |
| `read_skill` | Read a skill's SKILL.md |
| `read_source` | Read source code in 50KB pages |
| `search_skills` | Scored keyword search across names, descriptions, topics |
| `skill_stats` | Library statistics |

### Component tools
| Tool | What it does |
|------|-------------|
| `list_agents` / `read_agent` | Browse 75 agent definitions |
| `list_subagents` / `read_subagent` | Browse 161 subagent definitions |
| `list_plugins` / `read_plugin` | Browse 114 plugin definitions |
| `list_prompts` / `read_prompt` | Browse 148 prompt templates |

---

## Most useful queries for Echo development

### CS2 / Source 2

```
get_agent_briefing("cs2-specialist")
research_technique("cs2 entity system traversal")
search_skills("source2 view matrix")
read_subagent("bone-mapper")           ← CS2 bone index table
read_subagent("offset-finder")         ← cross-reference offsets across archives
read_subagent("binary-differ")         ← track offset changes across CS2 updates
```

### Anti-cheat awareness

```
get_agent_briefing("anti-cheat-analyst")
search_skills("battleye detection evasion")
search_skills("vanguard bypass cr3")
search_skills("eac kernel driver analysis")
read_subagent("ac-driver-analyzer")
read_subagent("detection-assessor")    ← risk assessment per AC
```

### Memory / RE

```
get_agent_briefing("reverse-engineer")
research_technique("pattern scanning IDA style")
research_technique("struct recovery from memory dump")
read_subagent("struct-recovery")
read_subagent("pattern-scanner")       ← sig generation and validation
research_technique("unicorn emulation encrypted reads")
```

### Aimbot architecture

```
get_agent_briefing("cheat-developer")
search_skills("aimbot smoothing prediction")
search_skills("recoil compensation cs2")
research_technique("velocity prediction bullet travel")
```

### Other games

```
get_agent_briefing("valorant-specialist")
get_agent_briefing("fortnite-specialist")
get_agent_briefing("apex-specialist")
get_agent_briefing("unreal-engine-specialist")
get_agent_briefing("unity-specialist")
```

### Injection / hooks (for non-Echo approaches)

```
get_agent_briefing("injection-specialist")
get_agent_briefing("hooking-specialist")
research_technique("manual map DLL injection")
research_technique("EPT hook")
```

---

## Example workflow: CS2 ESP from scratch

1. **Understand the target:**
   ```
   get_agent_briefing("cs2-specialist")
   ```

2. **Get current offsets:**
   ```
   search_skills("cs2 offsets 2024")
   read_subagent("offset-finder")
   ```

3. **Get bone indices:**
   ```
   read_subagent("bone-mapper")
   ```

4. **Write the ESP:** Use `echo-esp` agent (this toolkit):
   ```
   Agent: echo-esp — write a CS2 ESP with box, skeleton, health bar
   ```

5. **Assess detection risk:**
   ```
   read_subagent("detection-assessor")
   Agent: echo-anticheat — what's the risk of running this against CS2 VAC?
   ```

6. **Track offsets after updates:**
   ```
   read_subagent("binary-differ")
   ```

---

## Agent reference (23 of 75 documented)

| Agent | Specialization |
|-------|---------------|
| `reverse-engineer` | Disassembly, struct recovery, offset hunting, patching |
| `exploit-developer` | Kernel exploits, vulnerable-driver chains, EFI persistence |
| `anti-cheat-analyst` | BattlEye, EAC, Vanguard, VAC, FACEIT internals |
| `malware-analyst` | Cheat binary analysis, unpacking, IOC extraction |
| `cheat-developer` | Visuals, aim assist, overlay rendering across engines |
| `driver-developer` | Windows kernel drivers, IOCTL, memory read/write |
| `hypervisor-researcher` | Intel VMX, AMD SVM, hypervisor-based memory access |
| `android-researcher` | Zygisk, KernelSU, Frida, IL2CPP, native hooking |
| `network-analyst` | Game protocol analysis, packet capture, MITM |
| `cs2-specialist` | CS2 / Source 2 internals |
| `valorant-specialist` | Valorant, UE4 fork, Vanguard interaction |
| `fortnite-specialist` | Fortnite, UE5, EAC interaction |
| `apex-specialist` | Apex Legends, Source-fork internals |
| `unreal-engine-specialist` | UE4/UE5 object systems, SDK generation |
| `unity-specialist` | Unity Mono/IL2CPP, metadata |
| `source-engine-specialist` | Source 1/2 ConVars, NetVars, ClientClass |
| `injection-specialist` | Manual mapping, reflective loading, APC, EFI |
| `hooking-specialist` | VMT, IAT, inline, EPT, syscall hooks |
| `obfuscation-analyst` | VMProtect, Themida, OLLVM |
| `windows-internals-agent` | EPROCESS, PEB/TEB, syscalls, object manager |
| `ida-specialist` | IDA scripting, plugins, FLIRT, type libraries |
| `ghidra-specialist` | Ghidra scripting, P-code, extensions |
| `dma-specialist` | DMA/FPGA memory access tooling |

---

## Subagent reference (16 of 161 documented)

| Subagent | Purpose |
|----------|---------|
| `offset-finder` | Cross-references offsets across archived sources |
| `code-analyzer` | Classifies techniques, hook methods, stealth measures |
| `pattern-scanner` | Generates and validates IDA-style byte patterns |
| `detection-assessor` | Estimates detection risk per AC system |
| `struct-recovery` | Rebuilds C++ structs from memory dumps or IDA |
| `binary-differ` | Diffs game builds to track offset changes |
| `source-grep` | Searches all archived source projects |
| `hook-planner` | Plans hook chains for an objective |
| `vtable-mapper` | Maps virtual function tables |
| `bone-mapper` | Maps skeleton bone indices per game |
| `ac-driver-analyzer` | Deep analysis of AC kernel drivers |
| `syscall-stub-generator` | Direct and indirect syscall stubs |
| `stack-spoofer` | Call stack spoofing |
| `shellcode-encoder` | Shellcode encoding to avoid signatures |
| `vulnerability-scanner` | Finds exploitable flaws in drivers/binaries |
| `import-resolver` | Resolves imports for manually-mapped modules |
