---
name: devirt-workflow
description: Step-by-step commands for recovering native code from VMProtect-protected binaries: vmp-lazy-unpack OEP discovery, Triton semantics, NoVmp VTIL lifting, LLVM passes, and producing radare2 signatures. Use when a target binary is VMProtect-packed and needs devirtualizing.
---

# Devirtualization workflow

Step-by-step commands for recovering native code from VMProtect-protected binaries.
For tool reference see `skills/echo-ecosystem/SKILL.md`; for integration with Echo see `echo-reverse.md`.

## Prerequisites

```bash
# vmp-lazy-unpack (OEP finder / unpacker)
git clone https://github.com/x86rc/vmp-lazy-unpack && cd vmp-lazy-unpack
py -m pip install -e .

# Triton (symbolic execution)
pip install triton-library   # NOT `pip install triton` — that is OpenAI's GPU compiler
# https://github.com/JonathanSalwan/Triton

# VMProtect-devirtualization scripts (Triton-based)
git clone https://github.com/JonathanSalwan/VMProtect-devirtualization

# NoVmp (full devirt via VTIL)
# Requires Visual Studio 2022 + LLVM toolchain
git clone --recursive https://github.com/can1357/NoVmp && cd NoVmp
mkdir build && cd build && cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release

# VTIL-Core (IR optimizer, optional standalone use)
git clone --recursive https://github.com/vtil-project/VTIL-Core
```

---

## Step 1 — Find OEP (vmp-lazy-unpack)

VMP encrypts the binary's sections and decrypts them at runtime before jumping to the real entry point (OEP). vmp-lazy-unpack traces this.

```bash
cd vmp-lazy-unpack
py -m unpack "C:\path\to\protected.exe"

# Optional flags:
py -m unpack "C:\path\to\protected.exe" --32bit       # 32-bit target
py -m unpack "C:\path\to\unpacked.bin" --imports_only  # fix imports only
```

The tool emulates the VMProtect unpacker with Unicorn, rebuilds the IAT and dumps the
unpacked image. There is no `--target`/`--out` CLI — the input path is positional.

If the tool can't find OEP, run the binary in x64dbg with a hardware breakpoint on execute at a page that should contain `.text` — VMP will land there after decryption.

---

## Step 2 — Recover handler semantics (Triton)

`JonathanSalwan/VMProtect-devirtualization` has **no** `devirt.py` / `devirt_batch.py`. Its
entrypoint is a two-stage flow: record a VMP trace with the bundled Intel Pin tool, then
replay that trace with `attack_vmp.py` (Triton builds the path predicate of the trace and
lifts the result to LLVM-IR).

```bash
cd VMProtect-devirtualization

# 2a. Record a trace of the virtualized function with the bundled Pin tool.
#     -start / -end are the addresses of the virtualized function.
./pin/pin -t ./pin/source/tools/VMP_Trace/obj-intel64/VMP_Trace.so \
    -start 4198848 -end 4198895 \
    -- ./vmp_binaries/binaries/sample2.vmp.bin 1 2 \
    &> ./vmp_traces/sample2.vmp.trace

# 2b. Replay the trace and reconstruct the original code.
python attack_vmp.py --trace1 ./vmp_traces/sample2.vmp.trace --symsize 4
```

`--symsize` is the number of symbolic input variables. For a function whose result depends
on a user-controlled branch, record a second trace with different arguments and pass both:

```bash
python attack_vmp.py --trace1 ./vmp_traces/x.vmp.trace.1 --trace2 ./vmp_traces/x.vmp.trace.2 \
    --symsize 4 --vbraddr 0x80d905 --vbrflag af
```

Note the Pin step is mandatory — without a recorded trace there is nothing to replay.

---

## Step 3 — Full devirtualization (NoVmp)

NoVmp takes the **unpacked** binary (positional argument), lifts it with VTIL and by
default emits **optimized VTIL**, not a native binary. x64 recompilation is opt-in.

```bash
# Binary is positional. Optional flags:
NoVmp.exe /tmp/unpacked.exe \
    -base 0x14000000 \
    -vms 0x729B81 0x72521 \
    -sections .xxx0 .yyy0

# Opt into the experimental x64 recompiler:
NoVmp.exe /tmp/unpacked.exe -experimental:recompile

# Other switches:
NoVmp.exe /tmp/unpacked.exe -noopt              # disable optimization
NoVmp.exe /tmp/unpacked.exe -opt:constant       # optimize VMProtect Ultra constant obfuscation
```

- `-base` — original image base, required when the binary was dumped (e.g. with Scylla).
- `-vms` — relative addresses of the specific VMEnter routines to devirtualize.
- `-sections` — VMProtect section names, when automatic section discovery fails.

There is no `--input` / `--output` / `--verbose` / `--dump-vtil` / `--dump-vtil-opt`. The
upstream README calls the experimental compiler "a borderline broken demo" — treat
recompiled output as research material, not as a runnable binary.

---

## Step 4 — Deobfuscate OLLVM layers (LLVM)

If the binary also uses OLLVM (control-flow flattening, mixed-boolean-arithmetic, bogus branches), apply LLVM opt passes on the recovered IR.

```bash
# Lift the recovered binary to LLVM IR with retdec.
# -o sets the C output; the .ll (and .bc/.asm) are emitted alongside automatically.
retdec-decompiler /tmp/devirt.exe -o /tmp/devirt.c

# Run deobfuscation passes with opt (from an LLVM install; `opt` ships with LLVM,
# it is not obtained by cloning llvm-project)
opt -load ./libDeobfuscator.so \
    -deobf-cff -deobf-mba -deobf-bogus \
    /tmp/devirt.ll -o /tmp/clean.ll -S

# Recompile to native
llc /tmp/clean.ll -o /tmp/clean.s
clang /tmp/clean.s -o /tmp/clean.exe
```

The pass names above (`-deobf-cff`, `-deobf-mba`, `-deobf-bogus`) are from the
`ollvm-deobfuscator` project — verify the flags against the pass you actually build;
no upstream LLVM plugin was verifiable under those exact names.

For binary-only targets without source: use Unicorn emulation in the echo-reverse workflow instead of LLVM (see `echo-reverse.md` OLLVM section).

---

## Step 5 — Extract signatures (radare2 / IDA)

With the clean binary, extract byte patterns for the functions you care about.

```bash
# radare2: analyze and print function bytes
r2 /tmp/devirt.exe
[0x00400000]> aaa
[0x00400000]> s 0x<function_addr>
[0x00400000]> pD 64         # disassemble 64 bytes
[0x00400000]> p8 16         # print 16 raw bytes as hex

# Build an IDA-style sig: replace address offsets with ?
# e.g. "48 8B 0D ? ? ? ? 48 85 C9 74 ? 4C 8B 01"
```

With IDA MCP wired:
```
decompile function at 0x<addr>
```

---

## Step 6 — Validate in Echo

```angelscript
// Confirm the recovered sig finds the function in the live process
uint64 base = process::get_module_base("game.exe");
if (base == 0) return false;

uint64 fn = process::find_signature(base, "48 8B 0D ? ? ? ? 48 85 C9 74 ? 4C 8B 01");
if (fn == 0) {
    alert::show("sig not found — game may still be VMP protected or sig needs update");
    return false;
}
console::log("function at: " + util::to_hex(fn));
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| vmp-lazy-unpack fails to unpack | VMP version > 3.x with new unpacking stubs | Use x64dbg hardware exec breakpoint manually |
| Triton replay is slow or never finishes | The traced function is long or loops | Narrow the traced range with the Pin tool's `-start` / `-end`; `attack_vmp.py` has no `--max-steps` flag |
| NoVmp output crashes on load | Import table not rebuilt | Run `pe-bear` or `CFF Explorer` → rebuild imports |
| OLLVM pass fails to compile | retdec IR version mismatch with opt | Pin LLVM version to match retdec's output (LLVM 14) |
| Echo sig not found post-devirt | Game loads VMP at runtime still | Sig must be extracted from the live decrypted image, not the devirt binary |
