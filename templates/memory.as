// Memory reading template – attach, scan, tick loop

process@ proc;
uint64   hp_addr = 0;
float    hp_cached = 0.0f;
mutex@   mx = mutex();

bool main() {
    proc = process.attach("target.exe");
    if (proc is null) {
        alert("Attach failed");
        return false;
    }

    create_thread(0,  @on_attach);
    create_thread(16, @tick);       // 16 tps – memory reads don't need high rate
    on_render(@draw);
    return true;
}

void on_attach() {
    // Scan for signature once; cache the resolved address
    uint64 sig = proc.scan("F3 0F 10 05 ?? ?? ?? ?? F3 0F 58 C8", "target.exe");
    if (sig == 0) { alert("Signature not found"); return; }

    hp_addr = proc.resolve_rip(sig, 4, 8);
    alert(fmt("hp_addr = 0x{:X}", hp_addr));
}

void tick() {
    if (hp_addr == 0) return;

    float v = proc.read<float>(hp_addr);
    mx.lock();
    hp_cached = v;
    mx.unlock();
}

void draw() {
    mx.lock_shared();
    float hp = hp_cached;
    mx.unlock_shared();

    renderer.text(10.0f, 30.0f, fmt("HP: {:.1f}", hp), null, color(255, 255, 255, 255));
}

void on_unload() {
    proc = null;
}
