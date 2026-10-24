// web-mv integration — exposes a live memory view endpoint the browser viewer connects to
// Repo: https://github.com/cy-gnus/web-mv
// Setup: git clone web-mv, npm install, npm start → open http://localhost:3000
//        In web-mv config set: host = "127.0.0.1", port = 9000 (or whatever you choose)

process@ proc    = null;
server@  srv     = null;

// --- Config ---
const uint16 WEB_MV_PORT = 9000;

// Regions the browser viewer can read (name → base, size)
// Add entries for whatever you want visible in the viewer
struct MemRegion {
    string name;
    uint64 base;
    uint32 size;
}

array<MemRegion> regions;

bool main() {
    proc = process.attach("game.exe");
    if (proc is null) { alert("game.exe not found"); return false; }

    // Register readable regions
    MemRegion client_dll;
    client_dll.name = "client.dll";
    client_dll.base = proc.get_module("client.dll").base;
    client_dll.size = proc.get_module("client.dll").size;
    regions.push_back(client_dll);

    // Start the HTTP server web-mv polls
    srv = net.listen(WEB_MV_PORT);
    if (srv is null) { alert("Failed to bind port " + WEB_MV_PORT); return false; }

    create_thread(0, @serve_loop);
    return true;
}

// Serve web-mv's two endpoints:
//   GET /regions           → JSON list of named regions with base+size
//   GET /read?addr=X&size=Y → raw bytes from process memory
void serve_loop() {
    while (true) {
        request@ req = srv.accept();
        if (req is null) { sleep(5); continue; }

        string path = req.path();

        if (path == "/regions") {
            string json = "[";
            for (uint i = 0; i < regions.size(); i++) {
                if (i > 0) json += ",";
                json += "{\"name\":\"" + regions[i].name + "\","
                      + "\"base\":" + regions[i].base + ","
                      + "\"size\":" + regions[i].size + "}";
            }
            json += "]";
            req.reply(200, "application/json", json);

        } else if (path.starts_with("/read")) {
            uint64 addr = uint64(req.param("addr"));
            uint32 sz   = min(uint32(req.param("size")), 4096u); // cap at 4 KB per request
            if (addr == 0 || sz == 0) { req.reply(400, "text/plain", "bad params"); continue; }

            array<uint8> buf = proc.read_bytes(addr, sz);
            req.reply(200, "application/octet-stream", buf);

        } else {
            req.reply(404, "text/plain", "not found");
        }
    }
}

void on_unload() {
    if (srv !is null) srv.close();
    proc = null;
}
