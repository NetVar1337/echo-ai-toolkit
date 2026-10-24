# Anti-Cheat Systems Reference

This reference document covers the major anti-cheat systems used in competitive games, their kernel drivers, detection mechanisms, and known research. Used by the `echo-anticheat` agent.

For deep dives, use mcp-gamehacking:
```
get_agent_briefing("anti-cheat-analyst")
search_skills("vanguard detection")
read_subagent("ac-driver-analyzer")
```

---

## VAC (Valve Anti-Cheat)
- **Driver:** None (user-mode only)
- **Mechanism:** Module hash scanning, loaded DLL enumeration, ConVar hash checking, process enumeration, game memory integrity
- **Reporting:** Delayed (bans issued hours/days after detection)
- **Research:** `danielkrupinski/VAC-Bypass-Loader`, `danielkrupinski/vac-hooks`, `ianveig29/como-funciona-vac`, `gmh5225/VACDumper`
- **Emulators:** `ioncodes/vacation3-emu`, `gmh5225/Vac-Emulator`

## EAC (Easy Anti-Cheat)
- **Driver:** `EasyAntiCheat.sys`
- **Mechanism:** Handle scanning (OpenProcess), NMI callbacks, memory region integrity, thread stack analysis, signature scanning, network inspection
- **Detection categories:**
  - Handle-based: flags `OpenProcess(PROCESS_VM_READ)` from non-whitelisted processes
  - NMI: fires at random intervals, snaps thread RIPs; RIP in non-whitelisted region = flag
  - Memory: scans game process for unsigned executable regions
- **Research:** `BishopTopG/all-about-eac`, `19h/eac-analysis`, `Sinclairq/hierarchy-eac`, `gmh5225/EasyAntiCheat-Reversing`
- **Emulators/bypasses (educational):** `Rat431/EAC_Emu`, `CamxxCore/EasyAntiCheat-Emulator`, `thesecretclub/CVEAC-2020`

## BattlEye
- **Driver:** `BEDaisy.sys`
- **Mechanism:** Process enumeration + hashing, handle scanning, NMI callbacks, memory scanning, dynamic shellcode-based checks (pushed from BE servers), network packet inspection
- **Key feature:** Shellcode is downloaded and executed client-side dynamically, making static analysis outdated quickly
- **Research:** `dllcrt0/bedaisy-reversal`, `dllcrt0/battleye-decryption`, `experienceds/battleye-re`, `lguilhermee/Battleye-Shellcode-Dumper`, `es3n1n/be-shellcode-tester`
- **Emulators (educational):** `gmh5225/BE-Emulator`, `Hypercall/FakeEye`

## Vanguard (Riot)
- **Driver:** `vgk.sys` (Ring 0, loads at boot regardless of game state)
- **Mechanism:** CR3 page-table protection, HWID hardware banning, boot-time integrity, screenshot analysis, kernel-level process verification
- **Research:** `gmh5225/augur-riot`, `gmh5225/VanguardImportResolver`, `armvirus/VanguardTrace`, `gmh5225/vgk-illegal-pf-logger`

## Ricochet (Activision)
- **Driver:** Kernel driver with encrypted comms
- **Mechanism:** Memory integrity, handle scanning, process enumeration
- **Research:** `weak1337/ricochet_deobfuscator`, `gmh5225/AurumRE`, `gmh5225/ricochet-disabler`

## FACEIT
- **Driver:** Kernel-level AC service
- **Research:** `ekknod/EC_PRO-LAN`

## Byfron (Roblox)
- **Type:** Hypervisor-based
- **Mechanism:** HV-level memory access monitoring, memory encryption
- **Research:** `gmh5225/byfron-bypass`, `atrexus/vulkan` (related)

## XignCode / EQU8 / ACE
- Asian market kernel ACs
- **XignCode:** `gmh5225/XignCode-Dump`, `gmh5225/XignCode3-bypass`
- **EQU8:** `kkent030315/EQU8-PoC`, `hotline1337/equ8_bypass`
- **ACE:** `H3d9/sguard_limit`, `moeskia/fuckAce`

---

## Detection category reference

| Category | Mechanism | Which ACs | Echo exposure |
|----------|-----------|-----------|---------------|
| Handle scanning | OpenProcess in kernel handle table | EAC, BE, Vanguard | Yes (Echo opens game process) |
| NMI callbacks | Random-interval thread RIP snapshot | EAC, BE | No (Echo threads not in game) |
| Memory scanning | Scan game for injected code | VAC, EAC, BE | No (no injection) |
| Process enumeration | Hash/name of all running processes | VAC, EAC, BE | Yes (Echo process visible) |
| Behavioral analysis | Input timing, movement patterns | Most ACs + server-side | Yes (mouse input) |
| CR3 protection | Page-table monitoring | Vanguard | Yes (RPM blocked/logged) |
| Screenshot analysis | Screenshot validation | Vanguard, FACEIT | Low risk via Discord overlay |

---

## Educational bypass techniques (academic reference)

These are documented techniques from public research, linked from the awesome-game-security list:

- **Kernel vulnerable driver chain:** Load a signed-but-vulnerable driver to get Ring 0 execution, then manipulate kernel structures. Used by many public injectors. See `injection-methods` section of `game-hacking-techniques.md`.
- **DMA/FPGA:** Hardware-level memory access via PCIe DMA device (PCILeech/MemProcFS). No software handle visible to AC. Covered by `dma-attack-techniques` skill in mcp-gamehacking.
- **Hypervisor shadow:** Run game under a custom hypervisor that intercepts and filters EPT access logging. `hypervisor-researcher` agent in mcp-gamehacking.
- **Handle table manipulation:** From kernel, remove own process's handle entries from the handle table to hide from handle scans. Requires kernel access.

For all above: use mcp-gamehacking `get_agent_briefing("exploit-developer")` for implementation details.
