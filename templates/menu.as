// Menu UI template – demonstrates all common element types
//
// UI order matters: ui::add_tab -> ui::add_subtab -> ui::add_category ->
// elements. Elements attach to the most recently created category.
// Values are read/written through handles: ui::get(handle) / ui::set(handle, v).
// Sliders are integer-only in this API.

checkbox     g_cb_enable;
slider       g_sl_fov;
color_picker g_cp_color;
combobox     g_cmb_mode;
multi_select g_ms_filters;
button       g_btn_reset;

bool main() {
    ui::config_path("echo_menu_template");

    ui::add_tab("MyScript");
    ui::add_subtab("Main");
    ui::add_category("Settings");

    g_cb_enable = ui::add_checkbox("Enable", false, "myscript.enable");
    g_sl_fov    = ui::add_slider("FOV radius", 90, 0, 360, 5, "deg", "myscript.fov");
    g_cp_color  = ui::add_color_picker("Color", 255, 255, 0, 255, true, "myscript.color");
    g_cmb_mode  = ui::add_combobox("Mode", {"Silent", "Smooth", "Raw"}, 0, "myscript.mode");
    g_ms_filters = ui::add_multi_select("Filters", {"Visible", "Dormant", "Dead"}, "myscript.filters");
    g_btn_reset = ui::add_button("Reset defaults", @do_reset);

    ui::add_tooltip(g_cb_enable, "Toggle the whole script on/off");

    on_render(@draw);
    return true;
}

void do_reset() {
    ui::set(g_sl_fov, 90);
    ui::set(g_cp_color, color(255, 255, 0, 255));
    ui::set(g_cmb_mode, uint64(0));
    ui::set(g_ms_filters, uint64(0), false);
    ui::set(g_ms_filters, uint64(1), false);
    ui::set(g_ms_filters, uint64(2), false);
}

void draw() {
    if (!ui::get(g_cb_enable)) return;

    int   fov  = ui::get(g_sl_fov);
    color c    = ui::get(g_cp_color);
    uint64 mode = ui::get(g_cmb_mode);

    bool show_visible = ui::get(g_ms_filters, uint64(0));
    bool show_dormant = ui::get(g_ms_filters, uint64(1));
    bool show_dead    = ui::get(g_ms_filters, uint64(2));

    render::draw_circle(960, 540, fov, c.r, c.g, c.b, c.a, false, 64);
    render::draw_text(10, 10, "mode: " + util::format_string("{}", mode), 255, 255, 255, 255);

    if (show_visible) render::draw_text(10, 30, "visible", 255, 255, 255, 255);
    if (show_dormant) render::draw_text(10, 50, "dormant", 255, 255, 255, 255);
    if (show_dead)    render::draw_text(10, 70, "dead", 255, 255, 255, 255);
}

void on_unload() {
    // nothing to release
}
