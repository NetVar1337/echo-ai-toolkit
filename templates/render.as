// Render / ESP template
//
// Render calls only work inside the render thread, so every draw call must be
// registered with on_render(). Colours are 4 separate ints: r, g, b, a.
// Box styles come from box_style:: (NORMAL, OUTLINED, FILLED, FILLED_OUTLINED,
// CORNERED, CORNERED_FILLED).

checkbox    g_esp_on;
color_picker g_esp_color;

bool main() {
    ui::config_path("echo_render_template");

    // UI order matters: tab -> subtab -> category -> elements
    ui::add_tab("ESP");
    ui::add_category("Settings");
    g_esp_on    = ui::add_checkbox("Enable ESP", true, "esp.enable");
    g_esp_color = ui::add_color_picker("Color", 255, 0, 0, 200, true, "esp.color");

    on_render(@draw);
    return true;
}

void draw() {
    if (!ui::get(g_esp_on)) return;

    color c = ui::get(g_esp_color);

    // Example: draw a box around a fixed screen position.
    // Replace the fixed position with real world-to-screen projected coords.
    int sx = 640;
    int sy = 360;
    int w  = 40;
    int h  = 80;

    // Built-in font, size in pixels (render context only)
    render::update_font(fonts::TAHOMA, 12);

    render::draw_box(sx - w / 2, sy - h, w, h,
                     c.r, c.g, c.b, c.a, box_style::OUTLINED, 0.0f);

    render::draw_text(sx, sy - h - 14, "Player",
                      c.r, c.g, c.b, c.a);
}

void on_unload() {
    // nothing to release — the runtime drops handles automatically
}
