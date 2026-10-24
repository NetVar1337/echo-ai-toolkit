// Menu UI template – demonstrates all common element types

tab@          t;
checkbox@     cb_enable;
slider@       sl_fov;
color_picker@ cp_color;
combobox@     cmb_mode;
button@       btn_reset;

bool main() {
    t          = menu.add_tab("MyScript");
    auto st    = t.add_subtab("Main");
    auto cat   = st.add_category("Settings");

    cb_enable = cat.add_checkbox("Enable",     false, "myscript.enable");
    sl_fov    = cat.add_slider("FOV radius",   0.0f, 360.0f, 90.0f, "myscript.fov");
    cp_color  = cat.add_color_picker("Color",  color(255,255,0,255), "myscript.color");
    cmb_mode  = cat.add_combobox("Mode",       array<string> = {"Silent", "Smooth", "Raw"}, 0, "myscript.mode");
    btn_reset = cat.add_button("Reset defaults", @do_reset);

    cb_enable.set_tooltip("Toggle the whole script on/off");
    on_render(@draw);
    return true;
}

void do_reset() {
    sl_fov.set(90.0f);
    cp_color.set(color(255,255,0,255));
    cmb_mode.set(0);
}

void draw() {
    if (!cb_enable.get()) return;

    float fov   = sl_fov.get();
    color c     = cp_color.get();
    int   mode  = cmb_mode.get();

    renderer.circle(960.0f, 540.0f, fov, 64, c);
    renderer.text(10.0f, 10.0f, fmt("mode: {}", mode), null, color(255,255,255,255));
}

void on_unload() {}
