# Devirtualization workflow

Step-by-step commands for recovering native code from VMProtect-protected binaries.
For tool reference see `skills/echo-ecosystem.md`; for integration with Echo see `echo-reverse.md`.

## Prerequisites

```bash
# vmp-lazy-unpack (OEP finder)
git clone https://github.com/x86rc/vmp-lazy-unpack && cd vmp-lazy-unpack
pip install -r requirements.txt

# Triton (symbolic execution)
pip install triton          # or build from source for latest
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
python unpack.py --target /path/to/protected.exe --out /tmp/unpacked.exe

# Output:
#   OEP: 0x140123456
#   Sections decrypted: .text, .rdata
#   Dump saved: /tmp/unpacked.exe
```

If the tool can't find OEP, run the binary in x64dbg with a hardware breakpoint on execute at a page that should contain `.text` — VMP will land there after decryption.

---

## Step 2 — Recover handler semantics (Triton)

Triton performs symbolic execution (running code with symbolic rather than concrete values) to work out what each VMP handler actually computes.

```bash
cd VMProtect-devirtualization

# Analyze a single virtualized function at the given RVA
python devirt.py \
    --binary /tmp/unpacked.exe \
    --rva 0x123456 \
    --output /tmp/handler_ir.json

# Batch all detected handlers
python devirt_batch.py \
    --binary /tmp/unpacked.exe \
    --output /tmp/all_handlers/
```

Each output file is a JSON IR representation of one handler's semantics.

---

## Step 3 — Full devirtualization (NoVmp)

NoVmp takes the unpacked binary, runs VTIL-based lifting and optimization, and outputs a reconstructed native binary.

```bash
NoVmp.exe \
    --input  /tmp/unpacked.exe \
    --output /tmp/devirt.exe \
    --verbose

# Optional: dump VTIL IR before optimization (for manual inspection)
NoVmp.exe --input /tmp/unpacked.exe --dump-vtil /tmp/vtil_pre_opt/

# Optional: dump VTIL IR after optimization
NoVmp.exe --input /tmp/unpacked.exe --dump-vtil-opt /tmp/vtil_post_opt/
```

The output binary has VMP stubs replaced with reconstructed native code. It won't run (relocation tables differ) but it disassembles cleanly.

---

## Step 4 — Deobfuscate OLLVM layers (LLVM)

If the binary also uses OLLVM (control-flow flattening, mixed-boolean-arithmetic, bogus branches), apply LLVM opt passes on the recovered IR.

```bash
# Compile the target to LLVM IR first (only possible if you have source or a Clang build)
# For binary-only: use retdec or llvm-mctoll to lift to LLVM IR
retdec-decompiler /tmp/devirt.exe --output /tmp/devirt.ll

# Run deobfuscation passes (ollvm-deobfuscator or custom pass)
git clone https://github.com/llvm/llvm-project   # needed for opt
opt -load ./libDeobfuscator.so \
    -deobf-cff -deobf-mba -deobf-bogus \
    /tmp/devirt.ll -o /tmp/clean.ll -S

# Recompile to native
llc /tmp/clean.ll -o /tmp/clean.s
clang /tmp/clean.s -o /tmp/clean.exe
```

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
uint64 fn = proc.scan_ida("48 8B 0D ? ? ? ? 48 85 C9 74 ? 4C 8B 01", "game.exe");
if (fn == 0) {
    alert("sig not found — game may still be VMP protected or sig needs update");
    return false;
}
console_log(fmt("function at: 0x{:X}", fn));
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| vmp-lazy-unpack fails to find OEP | VMP version > 3.x with new unpacking stubs | Use x64dbg hardware exec breakpoint manually |
| Triton times out on a handler | Handler is too long or loops | Increase `--max-steps`; split at basic-block boundaries |
| NoVmp output crashes on load | Import table not rebuilt | Run `pe-bear` or `CFF Explorer` → rebuild imports |
| OLLVM pass fails to compile | retdec IR version mismatch with opt | Pin LLVM version to match retdec's output (LLVM 14) |
| Echo sig not found post-devirt | Game loads VMP at runtime still | Sig must be extracted from the live decrypted image, not the devirt binary |
