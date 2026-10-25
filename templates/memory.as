// Memory reading template – attach, scan, tick loop
//
// Notes:
//  - process::attach() returns an attach_data struct, not a handle.
//  - process::find_signature() needs a BASE address: get it with
//    process::get_module_base("module.dll") first.
//  - process::virtual_query() returns ONE region; advance with base + size to
//    walk the whole address space.

uint64 g_hp_addr   = 0;
float  g_hp_cached = 0.0f;
mutex@ g_mx = create_mutex();

bool main() {
    attach_data ad = process::attach("target.exe");
    if (ad.pid == 0) {
        alert::show("Attach failed");
        return false;
    }

    create_thread(0,  @on_attach);
    create_thread(16, @tick);       // 16 tps – memory reads don't need high rate
    on_render(@draw);
    return true;
}

void on_attach() {
    uint64 base = process::get_module_base("target.exe");
    if (base == 0) {
        alert::show("target.exe not found");
        return;
    }

    // Scan for a signature once; cache the resolved address
    uint64 sig = process::find_signature(base, "F3 0F 10 05 ? ? ? ? F3 0F 58 C8");
    if (sig == 0) {
        alert::show("Signature not found");
        return;
    }

    g_hp_addr = process::get_relative_address(sig, 4, 8);
    alert::show("hp_addr = " + util::to_hex(g_hp_addr));
}

void tick() {
    if (g_hp_addr == 0) return;

    float v = process::read_float(g_hp_addr);

    g_mx.lock();
    g_hp_cached = v;
    g_mx.unlock();
}

void draw() {
    g_mx.lock_shared();
    float hp = g_hp_cached;
    g_mx.unlock_shared();

    render::draw_text(10, 30, "HP: " + util::format_string("{:.1}", hp),
                      255, 255, 255, 255);
}

// ── Region walk ──────────────────────────────────────────────────────────────
// process::virtual_query() describes the contiguous region containing the
// address. base + size lands on the next region (possibly an unmapped hole).
void dump_regions(uint64 start_addr) {
    uint64 addr = start_addr;
    for (int i = 0; i < 16; i++) {
        memory_region r = process::virtual_query(addr);
        if (r.size == 0) break;

        console::log(util::to_hex(r.base) +
                     " size=" + util::format_string("{}", r.size) +
                     " present=" + (r.present ? "yes" : "no") +
                     " rw=" + (r.writable ? "yes" : "no") +
                     " x=" + (r.executable ? "yes" : "no"));

        addr = r.base + r.size;
    }
}

// ── Bulk read ────────────────────────────────────────────────────────────────
// read_buffer() fetches a block once; the memory_buffer accessors then read
// fields out of it without another driver round-trip.
void dump_fields(uint64 addr) {
    memory_buffer@ buf = process::read_buffer(addr, 32);
    if (buf is null) return;

    console::log("u32@0  = " + util::format_string("{}", buf.read_uint32(0)));
    console::log("u32@4  = " + util::format_string("{}", buf.read_uint32(4)));
    console::log("f32@8  = " + util::format_string("{}", buf.read_float(8)));
    console::log("u64@16 = " + util::format_string("{}", buf.read_uint64(16)));
}

void on_unload() {
    process::detach();
}
