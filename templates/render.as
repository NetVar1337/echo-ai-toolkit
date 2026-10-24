// Render / ESP template

font_handle@ fnt;
tab@         my_tab;
checkbox@    esp_on;
color_picker@ esp_color;

bool main() {
    fnt = renderer.load_font("Verdana", 12, false);

    my_tab    = menu.add_tab("ESP");
    auto cat   = my_tab.add_category("Settings");
    esp_on    = cat.add_checkbox("Enable ESP", true, "esp.enable");
    esp_color = cat.add_color_picker("Color", color(255, 0, 0, 200), "esp.color");

    on_render(@draw);
    return true;
}

void draw() {
    if (!esp_on.get()) return;
    color c = esp_color.get();

    // Example: draw a box around a fixed screen position
    // Replace with real world-to-screen projected coords
    float sx = 640.0f;
    float sy = 360.0f;
    float w  = 40.0f;
    float h  = 80.0f;

    renderer.rect_outlined(sx - w * 0.5f, sy - h, w, h, 1.5f, c);
    renderer.text(sx, sy - h - 14.0f, "Player", fnt, c);
}

void on_unload() {}
