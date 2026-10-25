// web-mv integration — exposes a live memory view to the browser viewer
// Repo: https://github.com/cy-gnus/web-mv
//
// Echo ships a built-in JSON-over-WebSocket memory server. You attach to the
// game and open the socket; the runtime then answers the viewer's requests.
//
//   bool process::open_socket(const string url);
//
// Requirements: a process must be attached first, and only one socket may be
// open at a time (open_socket() returns false otherwise).
//
// Wire protocol — every frame is a JSON object with a "type" and an optional
// integer "id" (defaults to 0) that is echoed back in the response.
//
//   request  {"type":"ping","id":1}
//   response {"type":"ping_result","id":1,"attached":true,"pid":1234,"base":"0x7ff6..."}
//
//   request  {"type":"read","id":2,"address":"0x7ff600001000","size":16}
//   response {"type":"read_result","id":2,"success":true,
//             "address":"0x7ff600001000","size":16,"data":"48895c2408574883ec20..."}
//
//   request  {"type":"read_batch","id":3,
//             "reads":[{"address":"0x7ff600001000","size":8},
//                      {"address":"0x7ff600002000","size":4}]}
//   response {"type":"read_batch_result","id":3,"success":true,
//             "results":[{"success":true,"address":"0x7ff600001000","data":"4883ec28..."},
//                        {"success":false,"address":"0x7ff600002000","data":""}]}
//
//   request  {"type":"modules","id":4}
//   response {"type":"modules_result","id":4,"success":true,
//             "modules":[{"name":"game.exe","base":"0x7ff600000000","size":10485760}]}
//
//   request  {"type":"sig_scan","id":5,"sig":"4883ec28ff15","mask":"xxxxxx",
//             "module":"game.exe","find_all":false}
//   response {"type":"sig_scan_result","id":5,"success":true,
//             "results":["0x7ff600012340"]}
//
//   request  {"type":"sig_scan_ida","id":6,"pattern":"48 83 EC 28 FF 15 ? ? ? ? 85 C0"}
//   response {"type":"sig_scan_ida_result","id":6,"success":true,
//             "results":["0x7ff600012340"]}
//
//   request  {"type":"string_scan","id":7,"text":"PlayerController","find_all":true}
//   response {"type":"string_scan_result","id":7,"success":true,
//             "results":["0x7ff601a04bc0"]}
//
//   request  {"type":"resolve_relative","id":8,"address":"0x7ff600012340","offset":3,"inst_size":7}
//   response {"type":"resolve_relative_result","id":8,"success":true,"address":"0x7ff60001f000"}
//
//   request  {"type":"rtti_resolve","id":9,"address":"0x1f3a0000b40"}
//   response {"type":"rtti_resolve_result","id":9,"success":true,"name":"class PlayerController"}
//
//   request  {"type":"enumerate_functions","id":11,"module":"game.exe"}
//   response {"type":"enumerate_functions_result","id":11,"success":true,"count":2,
//             "results":[{"address":"0x7ff600001000","size":128,"method":0}]}
//
//   request  {"type":"disassemble","id":12,"address":"0x7ff600001000","size":64}
//   response {"type":"disassemble_result","id":12,"success":true,"complete":true,"count":2,
//             "results":[{"address":"0x7ff600001000","length":4,"bytes":"4883ec28",
//                         "text":"sub rsp, 0x28"}]}
//
//   error    {"type":"error","id":1,"code":1002,"message":"invalid or missing arguments",
//             "detail":"read requires 'address' and 'size'"}
//
// Error codes: 1000 unknown type, 1001 not attached, 1002 invalid arguments,
// 1003 module not found, 1004 size out of range, 1005 memory read failed,
// 1006 function enumeration failed, 1007 disassembly failed.

const string GAME_EXE = "game.exe";
const string SOCKET_URL = "ws://127.0.0.1:9000";

bool main() {
    attach_data ad = process::attach(GAME_EXE);
    if (ad.pid == 0) {
        alert::show(GAME_EXE + " not found");
        return false;
    }

    // The socket answers the viewer's JSON requests out of the attached
    // process — memory reads, module list, sig scans, disassembly.
    if (!process::open_socket(SOCKET_URL)) {
        alert::show("Failed to open " + SOCKET_URL +
                    " (no process attached, or a socket is already open)");
        process::detach();
        return false;
    }

    console::log("web-mv socket open on " + SOCKET_URL);
    return true;
}

void on_unload() {
    process::detach();
}

// ─── User code: region list for the viewer ───────────────────────────────────
// The built-in "modules" route already reports every module, so this is only
// needed if you want to hand the viewer a custom set of named regions.
void build_regions_json() {
    json_obj@ arr = json::array();
    array<module_entry>@ mods = process::get_module_list();
    if (mods is null) return;

    for (uint i = 0; i < mods.length(); i++) {
        json_obj@ entry = json_obj();
        entry.set("name", mods[i].name);
        entry.set("base", util::to_hex(mods[i].base));
        entry.set("size", mods[i].size);
        arr.push(entry);
    }

    console::log(json::stringify(arr, true));
}
