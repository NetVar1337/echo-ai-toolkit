// Minimal Echo script template
// Drop in %AppData%\Roaming\scripts\, reopen menu to load

bool main() {
    create_thread(0, @setup);
    return true;
}

void setup() {
    alert("Script loaded!");
}

void on_unload() {
    // clean up here
}
