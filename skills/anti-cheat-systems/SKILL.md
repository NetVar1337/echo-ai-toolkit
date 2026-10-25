---
name: anti-cheat-systems
description: What anti-cheat and integrity systems check at a high level — module and driver enumeration, handle and memory-access patterns, memory integrity, thread inspection, overlay presence, input injection, API hooking — plus how to build overlays responsibly on supported APIs. Use for detection-awareness and safe-coding questions, not for evasion.
---

# Anti-Cheat Systems Reference

Educational reference: what integrity (anti-cheat) systems look for, and how to build overlays that behave responsibly. Used by the `echo-anticheat` agent.

The goal of this document is **understanding the detection surface**, so tooling can be built on supported, non-invasive foundations. It is not a catalogue of bypasses.

For background reading on driver internals, use mcp-gamehacking:
```
get_agent_briefing("anti-cheat-analyst")
read_subagent("ac-driver-analyzer")
```

---

## What integrity systems check

Every modern integrity system, user-mode or kernel-mode, is built from the same handful of observation points:

| Observation | How it is done | Typical example |
|---|---|---|
| **Module / driver enumeration** | Enumerate loaded modules, kernel drivers, and injected images; compare against a known-good list | `EasyAntiCheat.sys`, `vgk.sys`, `BEDaisy.sys` |
| **Handle & memory-access patterns** | Walk the kernel handle table for `OpenProcess(PROCESS_VM_READ)` handles opened by unexpected processes; correlate handle count against known debuggers | EAC, BattlEye, Vanguard |
| **Memory integrity** | Hash or scan game memory regions for unsigned or self-modifying executable pages | VAC, EAC, BattlEye |
| **Thread / context inspection** | Periodic thread-context snapshots (RIP, register state) to spot execution outside the expected image | EAC, BattlEye (interrupt-based callbacks) |
| **Overlay / injection presence** | Enumerate overlay DLLs, injection modules, and known rendering overlays in the target's module list | VAC, EAC |
| **Input injection** | Detect synthetic input timing and correlation with on-screen targeting; server-side input validation | Server-side + most client ACs |
| **API hooking integrity** | Verify IAT/EAT/hook prologues, `syscall` stubs, and page protections on critical API functions | EAC, BattlEye |
| **Firmware / page-table protection** | CR3 and page-table monitoring, hardware identifiers, boot-time integrity | Vanguard |

Behavior is also judged server-side: input timing, movement telemetry, and account-level statistics can flag a client even when every local check passes.

---

## Systems at a glance

| System | Driver | Notes |
|---|---|---|
| **VAC** (Valve Anti-Cheat) | None — user-mode | Module hashing, ConVar hashing, process enumeration, game-memory integrity. Enforcement is delayed, so bans often arrive hours or days later. |
| **EAC** (Easy Anti-Cheat) | `EasyAntiCheat.sys` | Handle-table scanning, interrupt-based context sampling, memory-region integrity, signature scanning, network inspection. |
| **BattlEye** | `BEDaisy.sys` | Process enumeration and hashing, handle scanning, context sampling, server-pushed checks that change over time. |
| **Vanguard** (Riot) | `vgk.sys` | Loads at boot, CR3/page-table protection, hardware-level identification, boot-time integrity, screenshot analysis. |
| **Ricochet** (Activision) | Kernel driver, encrypted comms | Memory integrity, handle scanning, process enumeration. |
| **FACEIT** | Kernel-level service | Kernel-integrity checks, client-side and server-side analysis. |
| **Byfron** (Roblox) | Hypervisor-based | Hypervisor-level memory access monitoring and memory encryption. |
| **XignCode / EQU8 / ACE** | Regional kernel ACs | Common in APAC titles; driver-based handle and memory checks. |

---

## Echo's exposure surface

Echo is an **external** overlay: it reads the target process from outside and never injects code, loads a driver, or patches the game image. What an integrity system can observe:

1. A `ReadProcessMemory`-style handle from the overlay process to the game process.
2. The overlay process itself appearing in process enumeration.
3. The rendering overlay's DLL appearing in the system-wide module list.
4. Synthetic input, if the script generates input at all.

Everything else is invisible to a local integrity system. That is why **how** an overlay behaves still matters: repeated reads, handle churn, and synthetic input are all legitimate-looking signals that can be treated as abuse.

```angelscript
// Non-invasive reads only. One handle for the session, cached values, no writes.
bool main() {
    attach_data ad = process::attach("game.exe");
    if (ad.pid == 0) return false;

    uint64 base = process::get_module_base("game.exe");
    if (base == 0) return false;

    uint64 entity_list = process::find_signature(base, "48 8B 0D ? ? ? ? 48 85 C9");
    if (entity_list == 0) return false;

    // Read-only access. process::write_* is never needed for a passive overlay.
    return true;
}
```

---

## Building responsibly

**Prefer supported paths.**
- Use the game's official API, mod framework, or documented telemetry where one exists (Steamworks, official SDKs, Unreal/Unity modding layers). Anything that requires bypassing integrity checks is out of scope for legitimate tooling.
- Treat anti-cheat bypass research as confined to hardware you own, in an isolated lab, under a written authorization scope.

**Read only what you need.**
- Cache values in script globals and refresh them at a modest rate; a 64 Hz thread re-reading every entity of a 64-player match generates far more traffic than a 4 Hz cache refreshed incrementally.
- Use `process::read_buffer` for multi-field reads of one struct instead of many separate reads.
- Never write to the target process from an overlay. `process::write_*` exists, but a passive overlay has no legitimate use for it.

**Do not inject synthetic input.**
- Never call `input::key_press`, `input::key_release`, `input::key_tap`, `input::mouse_move`, or `input::mouse_click` against a protected game. Server-side input validation and client-side synthetic-input detection both exist specifically for this, and no user-visible feature justifies it.
- Never hook, patch, or otherwise alter the target process, its modules, or its threads.

**Do not hide anything.**
- Do not attempt to make the overlay, its process, or its modules invisible to the target or to the operating system. Concealment is itself a detection signal, and it turns a legitimate tool into an adversarial one.
- Do not load unsigned or vulnerable drivers, and do not attempt to obtain Ring 0.

**Respect the platform's terms.**
- Anti-cheat vendors publish rules about permitted tools for each title; check them before shipping anything.
- Competitive titles generally prohibit memory readers of any kind. If a title's policy forbids it, do not ship it for that title.

**Document intent.**
- Keep a header note in each script stating what it reads, at what rate, and that it is read-only. It makes review trivial and makes intent verifiable.

---

## When a finding is legitimate

Report anti-cheat issues as **defects in the integrity system** — false positives that ban legitimate players, driver vulnerabilities, or integrity checks that can be triggered by unrelated software (overlays, recording tools, accessibility software, other anti-cheat products). Those are reportable to the vendor.

Anything that only works by hiding from the integrity system is not a defect; it is the intended behaviour of that system.
