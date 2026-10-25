// esp-preview.as — starter template for the echo-esp-preview layout helper
// Source: https://github.com/speedsunderscore/echo-esp-preview
//
// Drop the upstream `esp_preview.as` drop-in into your project next to this
// file. It provides two things:
//
//   * the global `g_preview` object — register your ESP elements once in
//     main() and let the user drag them around in the menu preview
//   * the `esp_layout` namespace — stateless helpers that turn the preview
//     layout into concrete screen positions at render time
//
// The drop-in is a THIRD-PARTY library, not the Echo API. Everything in this
// file that touches Echo uses the real API: ui::add_* for elements,
// on_render(@fn) for the render thread, and render:: calls with separate
// r, g, b, a ints.
//
// The entity list below is deliberately game-agnostic — the preview helper
// knows nothing about your game's entity types, so you fill that part in.

namespace preview_ids {
    int name_label  = -1;
    int dist_label  = -1;
    int health_bar  = -1;
}

// UI handles the preview registers (the drop-in takes handles, not raw values)
checkbox     g_name_enabled;
checkbox     g_dist_enabled;
checkbox     g_bar_enabled;
checkbox     g_box_enabled;
color_picker g_name_col;
color_picker g_name_col_occ;
color_picker g_dist_col;
color_picker g_dist_col_occ;
color_picker g_bar_col;
color_picker g_bar_col_occ;
color_picker g_box_col;
color_picker g_box_col_occ;

// Sides: 0 = top, 1 = right, 2 = bottom, 3 = left
const int SIDE_TOP    = 0;
const int SIDE_RIGHT  = 1;
const int SIDE_BOTTOM = 2;
const int SIDE_LEFT   = 3;

// ─── User code: your game's entities ─────────────────────────────────────────
// Replace this with the real entity enumeration for your game. The preview
// helper only needs a name, a distance, health and a visibility flag.
class preview_entity {
    string m_name;
    float  m_distance;
    float  m_health;
    float  m_max_health;
    bool   m_alive;
    bool   m_visible;
}

array<preview_entity@> g_entities;

// Example entity source — replace with your own (process reads, SDK objects, ...)
void refresh_entities() {
    array<preview_entity@> next;
    preview_entity@ e = preview_entity();
    e.m_name = "PlayerOne";
    e.m_distance = 42.0f;
    e.m_health = 75.0f;
    e.m_max_health = 100.0f;
    e.m_alive = true;
    e.m_visible = true;
    next.insertLast(e);
    g_entities = next;
}

// ─── Setup ───────────────────────────────────────────────────────────────────
bool main() {
    ui::config_path("echo_esp_preview");

    ui::add_tab("ESP");
    ui::add_category("Labels");
    g_name_enabled = ui::add_checkbox("Name", true, "esp.name.on");
    g_name_col     = ui::add_color_picker("Name colour", 255, 255, 255, 255, true, "esp.name.col");
    g_name_col_occ = ui::add_color_picker("Name occluded", 180, 180, 180, 180, false, "esp.name.occ");

    ui::add_category("Distance");
    g_dist_enabled = ui::add_checkbox("Distance", true, "esp.dist.on");
    g_dist_col     = ui::add_color_picker("Distance colour", 220, 220, 100, 255, true, "esp.dist.col");
    g_dist_col_occ = ui::add_color_picker("Distance occluded", 160, 160, 80, 180, false, "esp.dist.occ");

    ui::add_category("Bars");
    g_bar_enabled = ui::add_checkbox("Health bar", true, "esp.bar.on");
    g_bar_col     = ui::add_color_picker("Bar colour", 80, 200, 80, 255, true, "esp.bar.col");
    g_bar_col_occ = ui::add_color_picker("Bar occluded", 60, 140, 60, 180, false, "esp.bar.occ");

    ui::add_category("Box");
    g_box_enabled = ui::add_checkbox("Bounding box", true, "esp.box.on");
    g_box_col     = ui::add_color_picker("Box colour", 255, 100, 100, 200, true, "esp.box.col");
    g_box_col_occ = ui::add_color_picker("Box occluded", 255, 220, 220, 255, false, "esp.box.occ");

    // Register the elements with the preview helper. Only one bounding box is
    // allowed, so register_bounding_box() returns nothing.
    g_preview.register_bounding_box(g_box_enabled, g_box_col, g_box_col_occ);

    preview_ids::name_label = g_preview.register_label(
        "Name", g_name_enabled, g_name_col, g_name_col_occ,
        SIDE_TOP, fonts::TAHOMA, 13);

    preview_ids::dist_label = g_preview.register_label(
        "0m", g_dist_enabled, g_dist_col, g_dist_col_occ,
        SIDE_BOTTOM, fonts::TAHOMA, 11);

    preview_ids::health_bar = g_preview.register_bar(
        g_bar_enabled, g_bar_col, g_bar_col_occ, SIDE_LEFT);

    // Restore the user's saved layout (call after all registrations)
    g_preview.load("esp_preview.json");

    create_thread(16, @refresh_entities);
    on_render(@draw);
    return true;
}

// ─── Render ──────────────────────────────────────────────────────────────────
void draw() {
    // Draw the in-menu preview widget itself
    g_preview.draw();

    for (uint i = 0; i < g_entities.length(); i++) {
        preview_entity@ ent = g_entities[i];
        if (ent is null || !ent.m_alive) continue;

        // Project the entity to a screen bounding box (user code — replace
        // with your game's own world-to-screen result)
        vec2 screen = project(ent);
        float box_w = 40.0f;
        float box_h = 80.0f;
        float bbox_x = screen.x - box_w * 0.5f;
        float bbox_y = screen.y - box_h;

        draw_box_for(ent, bbox_x, bbox_y, box_w, box_h);
        draw_name_for(ent, bbox_x, bbox_y, box_w, box_h);
        draw_distance_for(ent, bbox_x, bbox_y, box_w, box_h);
        draw_bar_for(ent, bbox_x, bbox_y, box_w, box_h);
    }
}

// ─── Draw helpers (user code) ───────────────────────────────────────────────
void draw_box_for(preview_entity@ ent, float x, float y, float w, float h) {
    box_info_t info = g_preview.get_box_info();
    if (!info.enabled) return;

    color clr = ent.m_visible ? info.col : info.col_occluded;
    box_style style = info.style_index == 1 ? box_style::CORNERED : box_style::OUTLINED;
    render::draw_box(int(x), int(y), int(w), int(h),
                     clr.r, clr.g, clr.b, clr.a, style, 0.0f);
}

void draw_name_for(preview_entity@ ent, float x, float y, float w, float h) {
    label_info_t info = g_preview.get_label_info(preview_ids::name_label);
    if (!info.enabled) return;

    color clr = ent.m_visible ? info.col : info.col_occluded;
    render::update_font(info.font, info.font_size);
    vec2 size = render::calculate_text_size(ent.m_name);
    vec2 anchor = anchor_for(x, y, w, h, info, size);
    render::update_font(info.font, info.font_size);
    render::draw_text_outlined(int(anchor.x), int(anchor.y), ent.m_name,
                               clr.r, clr.g, clr.b, clr.a);
}

void draw_distance_for(preview_entity@ ent, float x, float y, float w, float h) {
    label_info_t info = g_preview.get_label_info(preview_ids::dist_label);
    if (!info.enabled) return;

    color clr = ent.m_visible ? info.col : info.col_occluded;
    string text = util::format_string("{}m", int(ent.m_distance));
    render::update_font(info.font, info.font_size);
    vec2 size = render::calculate_text_size(text);
    vec2 anchor = anchor_for(x, y, w, h, info, size);
    render::update_font(info.font, info.font_size);
    render::draw_text_outlined(int(anchor.x), int(anchor.y), text,
                               clr.r, clr.g, clr.b, clr.a);
}

void draw_bar_for(preview_entity@ ent, float x, float y, float w, float h) {
    bar_info_t info = g_preview.get_bar_info(preview_ids::health_bar);
    if (!info.enabled) return;

    float pct = ent.m_max_health > 0.0f ? ent.m_health / ent.m_max_health : 0.0f;
    if (pct < 0.0f) pct = 0.0f;
    if (pct > 1.0f) pct = 1.0f;

    color base = ent.m_visible ? info.col : info.col_occluded;
    color fill = (info.has_style && info.style_index == 0 && ent.m_visible)
               ? health_to_color(ent.m_health, ent.m_max_health, base.a)
               : base;

    vec2 pos, size;
    esp_layout::bar_rect(x, y, w, h, info, pos, size);
    int bx = int(pos.x), by = int(pos.y);
    int bw = int(size.x), bh = int(size.y);

    render::draw_box(bx, by, bw, bh, 0, 0, 0, base.a / 2, box_style::FILLED, 0.0f);

    bool vertical = (info.position == SIDE_RIGHT || info.position == SIDE_LEFT);
    if (vertical) {
        int inner_h = bh - 2;
        int fill_h = int(float(inner_h) * pct);
        int fill_top = by + 1 + (inner_h - fill_h);
        if (fill_h > 0)
            render::draw_box(bx + 1, fill_top, bw - 2, fill_h,
                             fill.r, fill.g, fill.b, fill.a, box_style::FILLED, 0.0f);
    } else {
        int inner_w = bw - 2;
        int fill_w = int(float(inner_w) * pct);
        if (fill_w > 0)
            render::draw_box(bx + 1, by + 1, fill_w, bh - 2,
                             fill.r, fill.g, fill.b, fill.a, box_style::FILLED, 0.0f);
    }
}

color health_to_color(float health, float max_health, int alpha) {
    float pct = max_health > 0.0f ? health / max_health : 0.0f;
    if (pct < 0.0f) pct = 0.0f;
    if (pct > 1.0f) pct = 1.0f;
    color c;
    c.r = int(255.0f * (1.0f - pct));
    c.g = int(255.0f * pct);
    c.b = 0;
    c.a = alpha;
    return c;
}

// ─── Layout helpers ──────────────────────────────────────────────────────────
// The preview tells us which side an item lives on and its stack index. The
// drop-in's esp_layout namespace turns that into a pixel position.
//
// "prior" is the height of everything already stacked on the same side, which
// only you can measure — it depends on your label text. Walk your own list of
// label ids and measure each one.
vec2 anchor_for(float x, float y, float w, float h, label_info_t info, vec2 my_size) {
    array<int> bar_ids;
    bar_ids.insertLast(preview_ids::health_bar);
    int bar_offset = esp_layout::label_bar_offset(info.position, bar_ids);

    float prior = 0.0f;
    array<int> label_ids;
    label_ids.insertLast(preview_ids::name_label);
    label_ids.insertLast(preview_ids::dist_label);
    for (uint i = 0; i < label_ids.length(); i++) {
        label_info_t other = g_preview.get_label_info(label_ids[i]);
        if (!other.enabled) continue;
        if (other.position != info.position) continue;
        if (other.slot >= info.slot) continue;   // only items ahead of this one
        prior += measure_label_height(label_ids[i]) + esp_layout::label_row_spacing;
    }

    return esp_layout::anchor_for_side(x, y, w, h, info.position, bar_offset, prior, my_size);
}

float measure_label_height(int id) {
    label_info_t info = g_preview.get_label_info(id);
    render::update_font(info.font, info.font_size);
    if (id == preview_ids::name_label)
        return render::calculate_text_size("PlayerOne").y;
    if (id == preview_ids::dist_label)
        return render::calculate_text_size("0m").y;
    return 0.0f;
}

// ─── User code: project an entity to the screen ──────────────────────────────
vec2 project(preview_entity@ ent) {
    return vec2(960.0f, 540.0f);
}

void on_unload() {
    // Persist the user's layout when the script unloads
    g_preview.save("esp_preview.json");
}
