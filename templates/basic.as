// Minimal Echo script template
// Drop in %AppData%\Roaming\scripts\, reopen menu to load
//
// Every Echo script needs `bool main()` — it is the entry point and the script
// will not compile without it. Return true on success, false to unload.
// `on_unload()` is optional and runs when the script is unloaded.

bool main() {
    create_thread(0, @setup);   // one-shot thread: runs the callback once, then exits
    return true;
}

void setup() {
    alert::show("Script loaded!");
}

void on_unload() {
    // clean up here (release resources, undo target-process writes, ...)
}
