// esp-preview.as — starter template for echo-esp-preview layout API
// Source: speedsunderscore/echo-esp-preview
// Drop esp_preview.as into your project alongside this template.

namespace preview_ids {
    int name_label  = -1;
    int health_bar  = -1;
    int dist_label  = -1;
}

void main() {
    // Register bounding box: callback checks visibility each frame
    esp_layout::register_bounding_box(
        @is_visible,
        color(255, 100, 100, 200),   // occluded color
        color(255, 220, 220, 255)    // visible color
    );

    // register_label(text, enabled, col, col_occluded, position, font, font_size) → id
    preview_ids::name_label = esp_layout::register_label(
        "Name", true,
        color(255, 255, 255, 255), color(180, 180, 180, 180),
        LABEL_POS_TOP, FONT_DEFAULT, 13.0f
    );

    preview_ids::dist_label = esp_layout::register_label(
        "0m", true,
        color(220, 220, 100, 255), color(160, 160, 80, 180),
        LABEL_POS_BOTTOM, FONT_DEFAULT, 11.0f
    );

    // register_bar(enabled, col, col_occluded, position) → id
    preview_ids::health_bar = esp_layout::register_bar(
        true,
        color(80, 200, 80, 255), color(60, 140, 60, 180),
        BAR_POS_LEFT
    );
}

void on_render(render_t@ r) {
    for (int i = 0; i < entity_list_count(); i++) {
        entity@ ent = get_entity(i);
        if (ent is null || !ent.is_alive()) continue;

        // Update dynamic values each frame
        esp_layout::set_label_text(preview_ids::name_label, ent.name());
        esp_layout::set_label_text(preview_ids::dist_label, fmt("{}m", int(ent.distance())));
        esp_layout::set_bar_value(preview_ids::health_bar, float(ent.health()) / float(ent.max_health()));

        // get_label_info / get_bar_info return positions computed by esp_layout
        label_info_t@ name_info = esp_layout::get_label_info(preview_ids::name_label);
        label_info_t@ dist_info = esp_layout::get_label_info(preview_ids::dist_label);
        bar_info_t@   hp_info   = esp_layout::get_bar_info(preview_ids::health_bar);

        if (name_info !is null && name_info.visible)
            r.text(name_info.pos.x, name_info.pos.y, name_info.text, name_info.color);
        if (dist_info !is null && dist_info.visible)
            r.text(dist_info.pos.x, dist_info.pos.y, dist_info.text, dist_info.color);
        if (hp_info !is null && hp_info.visible)
            r.rect_filled(hp_info.x, hp_info.y, hp_info.w, hp_info.h, hp_info.color);
    }
}

bool is_visible(entity@ ent) {
    return ent !is null && ent.is_visible();
}
