class label_preview {
    int id;
    string text;
    checkbox enabled;
    color_picker col;
    color_picker col_occluded;
    int position;
    int outer_order;
    fonts font;
    int font_size;

    vec2 last_pos;
    vec2 last_size;
    bool drawn;
}

class bar_preview {
    int id;
    checkbox enabled;
    color_picker col;
    color_picker col_occluded;
    int position;

    bool has_style;
    int style_index;

    vec2 last_pos;
    vec2 last_size;
    bool drawn;
}

class image_preview {
    int id;
    checkbox enabled;
    image preview_img;
    int position;
    int outer_order;
    int size;

    vec2 last_pos;
    vec2 last_size;
    bool drawn;
}

class outer_ref {
    int kind;
    int idx;
    int order;
}

class label_info_t {
    bool enabled;
    int position;
    int slot;
    color col;
    color col_occluded;
    fonts font;
    int font_size;
}

class bar_info_t {
    bool enabled;
    int position;
    int slot;
    color col;
    color col_occluded;
    bool has_style;
    int style_index;
}

class box_info_t {
    bool enabled;
    color col;
    color col_occluded;
    int style_index;
}

class image_info_t {
    bool enabled;
    int position;
    int slot;
    int size;
}

class esp_preview {
    int width;
    int padding;
    int title_height;
    string title;

    int box_w_logical;
    int box_h_logical;

    int label_gap;
    int label_spacing;

    bool has_box;
    checkbox box_check;
    color_picker box_color;
    color_picker box_color_occluded;
    int box_style_index;

    bool show_occluded;

    vec2 toggle_vis_pos;
    vec2 toggle_vis_size;
    vec2 toggle_occ_pos;
    vec2 toggle_occ_size;
    bool toggle_drawn;

    bool popup_open;
    int popup_label_index;
    vec2 popup_pos;
    vec2 popup_size;
    vec2 popup_combo_header_pos;
    vec2 popup_combo_header_size;
    vec2 popup_minus_pos;
    vec2 popup_plus_pos;
    int popup_btn_size;
    vec2 popup_slider_track_pos;
    vec2 popup_slider_track_size;
    int popup_font_row_x;
    int popup_font_row_w;
    int popup_font_row_h;
    array<int> popup_font_row_y;
    bool popup_slider_dragging;
    bool popup_combo_expanded;
    array<fonts> popup_font_choices;
    array<string> popup_font_names;

    array<label_preview> labels;
    array<bar_preview> bars;
    array<image_preview> images;

    bool drag_active;
    int drag_index;
    int drag_offset_x;
    int drag_offset_y;
    int drag_target_side;
    int drag_target_slot;
    int drag_kind;
    bool lmb_last;
    bool rmb_last;

    int next_id;
    int next_outer_order;

    esp_preview() {
        width = 280;
        padding = 8;
        title_height = 25;
        title = "ESP Preview";
        box_w_logical = 120;
        box_h_logical = 240;
        has_box = false;
        box_style_index = 0;
        show_occluded = false;
        toggle_drawn = false;
        label_gap = 4;
        label_spacing = 2;
        drag_active = false;
        drag_index = -1;
        drag_target_side = -1;
        drag_target_slot = -1;
        drag_kind = 0;
        lmb_last = false;
        rmb_last = false;
        next_id = 0;
        next_outer_order = 0;

        popup_open = false;
        popup_label_index = -1;
        popup_slider_dragging = false;
        popup_combo_expanded = false;
        popup_font_choices.insertLast(fonts::PROGGY);
        popup_font_choices.insertLast(fonts::TAHOMA);
        popup_font_choices.insertLast(fonts::TAHOMA_PX);
        popup_font_choices.insertLast(fonts::TAHOMA_BOLD);
        popup_font_choices.insertLast(fonts::TAHOMA_BOLD_PX);
        popup_font_choices.insertLast(fonts::SMALLEST_PIXEL_7);
        popup_font_choices.insertLast(fonts::TAHOMISH);
        popup_font_names.insertLast("Proggy");
        popup_font_names.insertLast("Tahoma");
        popup_font_names.insertLast("Tahoma PX");
        popup_font_names.insertLast("Tahoma Bold");
        popup_font_names.insertLast("Tahoma Bold PX");
        popup_font_names.insertLast("Smallest Pixel 7");
        popup_font_names.insertLast("Tahomish");
    }

    void register_bounding_box(checkbox &in check, color_picker &in color, color_picker &in color_occluded) {
        box_check = check;
        box_color = color;
        box_color_occluded = color_occluded;
        has_box = true;
    }

    int register_label(const string &in text, checkbox &in enabled, color_picker &in col, color_picker &in col_occluded, int position, fonts font, int font_size) {
        label_preview lbl;
        lbl.id = next_id++;
        lbl.text = text;
        lbl.enabled = enabled;
        lbl.col = col;
        lbl.col_occluded = col_occluded;
        lbl.position = position;
        lbl.outer_order = next_outer_order++;
        lbl.font = font;
        lbl.font_size = font_size;
        lbl.drawn = false;
        labels.insertLast(lbl);
        return lbl.id;
    }

    int register_bar(checkbox &in enabled, color_picker &in col, color_picker &in col_occluded, int position) {
        bar_preview b;
        b.id = next_id++;
        b.enabled = enabled;
        b.col = col;
        b.col_occluded = col_occluded;
        b.position = position;
        b.has_style = false;
        bars.insertLast(b);
        return b.id;
    }

    int register_bar(checkbox &in enabled, color_picker &in col, color_picker &in col_occluded, int position, int initial_style) {
        bar_preview b;
        b.id = next_id++;
        b.enabled = enabled;
        b.col = col;
        b.col_occluded = col_occluded;
        b.position = position;
        b.has_style = true;
        b.style_index = initial_style;
        bars.insertLast(b);
        return b.id;
    }

    label_info_t get_label_info(int id) {
        label_info_t info;
        info.enabled = false;
        for (uint i = 0; i < labels.length(); i++) {
            if (labels[i].id != id) continue;

            info.enabled = ui::get(labels[i].enabled);
            info.position = labels[i].position;
            info.col = ui::get(labels[i].col);
            info.col_occluded = ui::get(labels[i].col_occluded);
            info.font = labels[i].font;
            info.font_size = labels[i].font_size;

            info.slot = 0;
            array<outer_ref> items = collect_outer_items(info.position, false);
            for (uint j = 0; j < items.length(); j++) {
                if (items[j].kind == 0 && items[j].idx == int(i)) {
                    info.slot = int(j);
                    break;
                }
            }
            return info;
        }
        return info;
    }

    bar_info_t get_bar_info(int id) {
        bar_info_t info;
        info.enabled = false;
        for (uint i = 0; i < bars.length(); i++) {
            if (bars[i].id != id) continue;

            info.enabled = ui::get(bars[i].enabled);
            info.position = bars[i].position;
            info.col = ui::get(bars[i].col);
            info.col_occluded = ui::get(bars[i].col_occluded);
            info.has_style = bars[i].has_style;
            info.style_index = bars[i].style_index;

            info.slot = 0;
            for (uint j = 0; j < i; j++) {
                if (bars[j].position == info.position && ui::get(bars[j].enabled)) info.slot++;
            }
            return info;
        }
        return info;
    }

    box_info_t get_box_info() {
        box_info_t info;
        info.enabled = false;
        if (!has_box) return info;
        info.enabled = ui::get(box_check);
        info.col = ui::get(box_color);
        info.col_occluded = ui::get(box_color_occluded);
        info.style_index = box_style_index;
        return info;
    }

    int register_image(checkbox &in enabled, image &in preview_img, int position, int size) {
        image_preview img;
        img.id = next_id++;
        img.enabled = enabled;
        img.preview_img = preview_img;
        img.position = position;
        img.outer_order = next_outer_order++;
        img.size = size;
        images.insertLast(img);
        return img.id;
    }

    image_info_t get_image_info(int id) {
        image_info_t info;
        info.enabled = false;
        for (uint i = 0; i < images.length(); i++) {
            if (images[i].id != id) continue;

            info.enabled = ui::get(images[i].enabled);
            info.position = images[i].position;
            info.size = images[i].size;

            info.slot = 0;
            array<outer_ref> items = collect_outer_items(info.position, false);
            for (uint j = 0; j < items.length(); j++) {
                if (items[j].kind == 1 && items[j].idx == int(i)) {
                    info.slot = int(j);
                    break;
                }
            }
            return info;
        }
        return info;
    }

    int side_image_offset(int side) {
        int total = 0;
        int count = 0;
        for (uint i = 0; i < images.length(); i++) {
            if (drag_active && drag_kind == 2 && int(i) == drag_index) continue;
            if (images[i].position != side) continue;
            if (!ui::get(images[i].enabled)) continue;
            total += images[i].size;
            count++;
        }
        if (count == 0) return 0;
        int between = 4;
        return total + (count - 1) * between + 2;
    }

    bool save(const string &in path) {
        json_obj@ root = json_obj();
        root.set("box_style", box_style_index);

        json_obj@ labels_arr = json::array();
        for (uint i = 0; i < labels.length(); i++) {
            json_obj@ entry = json_obj();
            entry.set("id", labels[i].id);
            entry.set("position", labels[i].position);
            entry.set("order", labels[i].outer_order);
            entry.set("font", int(labels[i].font));
            entry.set("font_size", labels[i].font_size);
            labels_arr.push(entry);
        }
        root.set("labels", labels_arr);

        json_obj@ bars_arr = json::array();
        for (uint i = 0; i < bars.length(); i++) {
            json_obj@ entry = json_obj();
            entry.set("id", bars[i].id);
            entry.set("position", bars[i].position);
            entry.set("style", bars[i].style_index);
            bars_arr.push(entry);
        }
        root.set("bars", bars_arr);

        json_obj@ images_arr = json::array();
        for (uint i = 0; i < images.length(); i++) {
            json_obj@ entry = json_obj();
            entry.set("id", images[i].id);
            entry.set("position", images[i].position);
            entry.set("order", images[i].outer_order);
            images_arr.push(entry);
        }
        root.set("images", images_arr);

        int slash = path.findLast("/");
        if (slash > 0) {
            string dir_part = path.substr(0, slash);
            if (!dir::exists(dir_part)) dir::create(dir_part);
        }

        return file::write(path, json::stringify(root, true));
    }

    bool load(const string &in path) {
        if (!file::exists(path)) return false;

        string data;
        if (!file::read(path, data)) return false;

        string err;
        json_obj@ root = json::parse(data, err);
        if (root is null) return false;

        if (root.has("box_style")) box_style_index = root.get_int("box_style");

        if (root.has("labels") && root.type("labels") == json_type::array) {
            json_obj@ saved = root.get_obj("labels");
            for (uint i = 0; i < saved.length(); i++) {
                json_obj@ entry = saved.get_obj_at(i);
                if (entry is null) continue;
                int saved_id = entry.get_int("id");

                for (uint j = 0; j < labels.length(); j++) {
                    if (labels[j].id != saved_id) continue;
                    labels[j].position = entry.get_int("position");
                    labels[j].font = fonts(entry.get_int("font"));
                    labels[j].font_size = entry.get_int("font_size");
                    if (entry.has("order")) labels[j].outer_order = entry.get_int("order");
                    break;
                }
            }
        }

        if (root.has("bars") && root.type("bars") == json_type::array) {
            json_obj@ saved = root.get_obj("bars");
            array<bar_preview> reordered;
            array<bool> used;
            used.resize(bars.length());
            for (uint i = 0; i < used.length(); i++) used[i] = false;

            for (uint i = 0; i < saved.length(); i++) {
                json_obj@ entry = saved.get_obj_at(i);
                if (entry is null) continue;
                int saved_id = entry.get_int("id");

                for (uint j = 0; j < bars.length(); j++) {
                    if (used[j] || bars[j].id != saved_id) continue;
                    bar_preview b = bars[j];
                    b.position = entry.get_int("position");
                    if (b.has_style) b.style_index = entry.get_int("style");
                    reordered.insertLast(b);
                    used[j] = true;
                    break;
                }
            }
            for (uint i = 0; i < bars.length(); i++) {
                if (!used[i]) reordered.insertLast(bars[i]);
            }
            bars = reordered;
        }

        if (root.has("images") && root.type("images") == json_type::array) {
            json_obj@ saved = root.get_obj("images");
            for (uint i = 0; i < saved.length(); i++) {
                json_obj@ entry = saved.get_obj_at(i);
                if (entry is null) continue;
                int saved_id = entry.get_int("id");

                for (uint j = 0; j < images.length(); j++) {
                    if (images[j].id != saved_id) continue;
                    images[j].position = entry.get_int("position");
                    if (entry.has("order")) images[j].outer_order = entry.get_int("order");
                    break;
                }
            }
        }

        int max_order = next_outer_order;
        for (uint i = 0; i < labels.length(); i++) {
            if (labels[i].outer_order >= max_order) max_order = labels[i].outer_order + 1;
        }
        for (uint i = 0; i < images.length(); i++) {
            if (images[i].outer_order >= max_order) max_order = images[i].outer_order + 1;
        }
        next_outer_order = max_order;

        return true;
    }

    color percent_color(float pct, int alpha) {
        if (pct < 0.0f) pct = 0.0f;
        if (pct > 1.0f) pct = 1.0f;

        color c;
        if (pct < 0.5f) {
            c.r = 255;
            c.g = int(255.0f * (pct * 2.0f));
            c.b = 0;
        } else {
            c.r = int(255.0f * (1.0f - (pct - 0.5f) * 2.0f));
            c.g = 255;
            c.b = 0;
        }
        c.a = alpha;
        return c;
    }

    bool is_occluded() {
        return show_occluded;
    }

    bool point_in_rect(int px, int py, int rx, int ry, int rw, int rh) {
        return px >= rx && px < rx + rw && py >= ry && py < ry + rh;
    }

    bool point_in_rect(int px, int py, const vec2 &in pos, const vec2 &in size) {
        return point_in_rect(px, py, int(pos.x), int(pos.y), int(size.x), int(size.y));
    }

    int side_bar_offset(int side) {
        int count = 0;
        for (uint i = 0; i < bars.length(); i++) {
            if (drag_active && drag_kind == 1 && int(i) == drag_index) continue;
            if (bars[i].position != side) continue;
            if (!ui::get(bars[i].enabled)) continue;
            count++;
        }
        if (count == 0) return 0;
        int bar_size = 4;
        int between = 2;
        int label_separation = 2;
        return count * bar_size + (count - 1) * between + label_separation;
    }

    void draw() {
        ui_info info = ui::get_info();
        if (!info.open) {
            drag_active = false;
            lmb_last = false;
            popup_open = false;
            return;
        }

        float scale = info.dpi_scale;
        color accent = info.accent;
        int border = 5;

        int x = int(info.x + info.w + padding * scale);
        int y = int(info.y - border);
        int w = int(width * scale);
        int h = int(info.h + (border * 2));
        int title_h = int(title_height * scale);

        array<uint8> shades = {10, 60, 40, 40, 60};
        for (int i = 0; i < int(shades.length()); i++) {
            uint8 c = shades[i];
            render::draw_box(x + i, y + i, w - i * 2, h - i * 2, c, c, c, 255, FILLED, 0.0f);
        }

        render::draw_box(x + border, y + border, w - border * 2, h - border * 2, 25, 25, 25, 255, FILLED, 0.0f);
        render::draw_box(x + border, y + border, w - border * 2, title_h - 1, 15, 15, 15, 255, FILLED, 0.0f);

        render::draw_hue_bar(
            x + border + 1, y + border + title_h, w - border * 2 - 2, 2,
            accent.r, accent.g, accent.b, accent.a
        );

        render::update_font(fonts::TAHOMA_BOLD_PX, int(13 * scale));
        render::draw_text_outlined(x + border + int(8 * scale), y + border + int(5 * scale), title, accent.r, accent.g, accent.b, accent.a);

        int content_x = x + border;
        int content_y = y + border + title_h + 2;
        int content_w = w - border * 2;
        int content_h = h - border * 2 - title_h - 2;

        render::update_font(fonts::TAHOMA_PX, int(10 * scale));
        string hint_line1 = "drag labels or bars to move them";
        string hint_line2 = "right click any element for style or font";
        vec2 line1_size = render::calculate_text_size(hint_line1);
        vec2 line2_size = render::calculate_text_size(hint_line2);
        int pad = int(6 * scale);
        int right_edge = content_x + content_w - pad;
        int line2_y = content_y + content_h - int(line2_size.y) - pad;
        int line1_y = line2_y - int(line1_size.y) - int(1 * scale);
        render::draw_text_shadow(right_edge - int(line1_size.x), line1_y, hint_line1, 130, 130, 130, 200);
        render::draw_text_shadow(right_edge - int(line2_size.x), line2_y, hint_line2, 130, 130, 130, 200);

        int box_w = int(box_w_logical * scale);
        int box_h = int(box_h_logical * scale);
        int box_x = content_x + (content_w - box_w) / 2;
        int box_y = content_y + (content_h - box_h) / 2;

        if (has_box && ui::get(box_check)) {
            color c = is_occluded() ? ui::get(box_color_occluded) : ui::get(box_color);
            box_style style = box_style_index == 1 ? CORNERED : OUTLINED;
            render::draw_box(box_x, box_y, box_w, box_h, c.r, c.g, c.b, c.a, style, 0.0f);
        }

        draw_bars(box_x, box_y, box_w, box_h);

        int gap = int(label_gap * scale);
        int spacing = int(label_spacing * scale);

        for (uint i = 0; i < labels.length(); i++) labels[i].drawn = false;
        for (uint i = 0; i < images.length(); i++) images[i].drawn = false;

        for (int side = 0; side < 4; side++) {
            draw_outer_items_side(side, box_x, box_y, box_w, box_h, gap, spacing, scale);
        }

        draw_state_toggle(content_x, content_y, content_h, accent, scale);

        draw_popup(content_x, content_y, content_w, content_h, scale, accent);

        handle_drag(box_x, box_y, box_w, box_h, gap, spacing, scale, accent);
    }

    int font_index_of(fonts f) {
        for (uint i = 0; i < popup_font_choices.length(); i++) {
            if (popup_font_choices[i] == f) return int(i);
        }
        return 0;
    }

    void draw_popup(int content_x, int content_y, int content_w, int content_h, float scale, color accent) {
        if (!popup_open) return;
        if (popup_label_index < 0 || popup_label_index >= int(labels.length())) {
            popup_open = false;
            return;
        }
        label_preview@ lbl = labels[popup_label_index];

        int pad = int(8 * scale);
        int row_h = int(16 * scale);
        int font_size = int(12 * scale);
        int btn_size = int(14 * scale);
        int section_gap = int(6 * scale);
        int title_row = int(15 * scale);

        popup_size = vec2(float(int(190 * scale)), float(pad + title_row + row_h + section_gap + title_row + btn_size + pad));

        if (popup_pos.x + popup_size.x > float(content_x + content_w)) popup_pos.x = float(content_x + content_w) - popup_size.x;
        if (popup_pos.y + popup_size.y > float(content_y + content_h)) popup_pos.y = float(content_y + content_h) - popup_size.y;
        if (popup_pos.x < float(content_x)) popup_pos.x = float(content_x);
        if (popup_pos.y < float(content_y)) popup_pos.y = float(content_y);

        int popup_x = int(popup_pos.x);
        int popup_y = int(popup_pos.y);
        int popup_w = int(popup_size.x);
        int popup_h = int(popup_size.y);

        render::draw_box(popup_x, popup_y, popup_w, popup_h, 15, 15, 15, 240, FILLED, 0.0f);
        render::draw_box(popup_x, popup_y, popup_w, popup_h, 60, 60, 60, 255, NORMAL, 0.0f);

        render::update_font(fonts::TAHOMA_PX, font_size);

        int cur_y = popup_y + pad;

        render::draw_text(popup_x + pad, cur_y, "Font", 200, 200, 200, 255);
        cur_y += title_row;

        popup_combo_header_pos = vec2(float(popup_x + pad), float(cur_y));
        popup_combo_header_size = vec2(float(popup_w - pad * 2), float(row_h));

        int header_x = int(popup_combo_header_pos.x);
        int header_y = int(popup_combo_header_pos.y);
        int header_w = int(popup_combo_header_size.x);
        int header_h = int(popup_combo_header_size.y);

        render::draw_box(header_x, header_y, header_w, header_h, 22, 22, 22, 255, FILLED, 0.0f);
        render::draw_box(header_x, header_y, header_w, header_h, 60, 60, 60, 255, NORMAL, 0.0f);

        string current_name = popup_font_names[font_index_of(lbl.font)];
        render::draw_text(header_x + int(6 * scale), header_y + int(2 * scale), current_name, 220, 220, 220, 255);

        int arrow_s = int(4 * scale);
        int arrow_cx = header_x + header_w - int(8 * scale) - arrow_s;
        int arrow_cy = header_y + header_h / 2;
        if (popup_combo_expanded) {
            render::draw_triangle(
                float(arrow_cx), float(arrow_cy + arrow_s / 2),
                float(arrow_cx + arrow_s * 2), float(arrow_cy + arrow_s / 2),
                float(arrow_cx + arrow_s), float(arrow_cy - arrow_s / 2),
                180, 180, 180, 255, true
            );
        } else {
            render::draw_triangle(
                float(arrow_cx), float(arrow_cy - arrow_s / 2),
                float(arrow_cx + arrow_s * 2), float(arrow_cy - arrow_s / 2),
                float(arrow_cx + arrow_s), float(arrow_cy + arrow_s / 2),
                180, 180, 180, 255, true
            );
        }

        cur_y += row_h + section_gap;

        render::draw_text(popup_x + pad, cur_y, "Size", 200, 200, 200, 255);

        string size_text = util::format_string("{}", lbl.font_size);
        vec2 size_text_size = render::calculate_text_size(size_text);
        render::draw_text(popup_x + popup_w - pad - int(size_text_size.x), cur_y, size_text, accent.r, accent.g, accent.b, 255);

        cur_y += title_row;

        int slider_x = popup_x + pad;
        int slider_y = cur_y;
        int slider_w_total = popup_w - pad * 2;

        popup_minus_pos = vec2(float(slider_x), float(slider_y));
        popup_plus_pos = vec2(float(slider_x + slider_w_total - btn_size), float(slider_y));
        popup_btn_size = btn_size;

        int track_x = slider_x + btn_size + int(4 * scale);
        int track_h = int(6 * scale);
        int track_y = slider_y + (btn_size - track_h) / 2;
        int track_w = int(popup_plus_pos.x) - track_x - int(4 * scale);
        popup_slider_track_pos = vec2(float(track_x), float(track_y));
        popup_slider_track_size = vec2(float(track_w), float(track_h));

        int minus_x = int(popup_minus_pos.x);
        int minus_y = int(popup_minus_pos.y);
        int plus_x = int(popup_plus_pos.x);
        int plus_y = int(popup_plus_pos.y);

        render::draw_box(minus_x, minus_y, btn_size, btn_size, 35, 35, 35, 255, FILLED, 0.0f);
        render::draw_box(minus_x, minus_y, btn_size, btn_size, 60, 60, 60, 255, NORMAL, 0.0f);
        vec2 minus_size = render::calculate_text_size("-");
        render::draw_text(minus_x + (btn_size - int(minus_size.x)) / 2, minus_y + (btn_size - int(minus_size.y)) / 2, "-", 220, 220, 220, 255);

        render::draw_box(plus_x, plus_y, btn_size, btn_size, 35, 35, 35, 255, FILLED, 0.0f);
        render::draw_box(plus_x, plus_y, btn_size, btn_size, 60, 60, 60, 255, NORMAL, 0.0f);
        vec2 plus_size = render::calculate_text_size("+");
        render::draw_text(plus_x + (btn_size - int(plus_size.x)) / 2, plus_y + (btn_size - int(plus_size.y)) / 2, "+", 220, 220, 220, 255);

        render::draw_box(track_x, track_y, track_w, track_h, 22, 22, 22, 255, FILLED, 0.0f);
        render::draw_box(track_x, track_y, track_w, track_h, 60, 60, 60, 255, NORMAL, 0.0f);

        float pct = float(lbl.font_size - 12) / float(40 - 12);
        if (pct < 0.0f) pct = 0.0f;
        if (pct > 1.0f) pct = 1.0f;
        int fill_w = int(pct * float(track_w - 2));
        if (fill_w > 0) {
            render::draw_box(track_x + 1, track_y + 1, fill_w, track_h - 2, accent.r, accent.g, accent.b, 220, FILLED, 0.0f);
        }

        popup_font_row_y.resize(0);
        if (popup_combo_expanded) {
            int font_count = int(popup_font_choices.length());
            int dd_x = int(popup_combo_header_pos.x);
            int dd_y = int(popup_combo_header_pos.y + popup_combo_header_size.y) + int(2 * scale);
            int dd_w = int(popup_combo_header_size.x);
            int dd_h = font_count * row_h + int(4 * scale);

            render::draw_box(dd_x, dd_y, dd_w, dd_h, 22, 22, 22, 255, FILLED, 0.0f);
            render::draw_box(dd_x, dd_y, dd_w, dd_h, 60, 60, 60, 255, NORMAL, 0.0f);

            popup_font_row_x = dd_x + 1;
            popup_font_row_w = dd_w - 2;
            popup_font_row_h = row_h;

            int inner_y = dd_y + int(2 * scale);
            for (int i = 0; i < font_count; i++) {
                bool selected = lbl.font == popup_font_choices[i];
                int row_y = inner_y + i * row_h;
                popup_font_row_y.insertLast(row_y);

                if (selected) {
                    render::draw_box(popup_font_row_x, row_y, popup_font_row_w, row_h, accent.r, accent.g, accent.b, 50, FILLED, 0.0f);
                }

                int text_r = selected ? accent.r : 200;
                int text_g = selected ? accent.g : 200;
                int text_b = selected ? accent.b : 200;
                render::draw_text(dd_x + int(8 * scale), row_y + int(2 * scale), popup_font_names[i], text_r, text_g, text_b, 255);
            }
        }
    }

    void slider_set_from_mouse(int mx) {
        if (popup_label_index < 0 || popup_label_index >= int(labels.length())) return;
        label_preview@ lbl = labels[popup_label_index];

        float pct = (float(mx) - popup_slider_track_pos.x) / popup_slider_track_size.x;
        if (pct < 0.0f) pct = 0.0f;
        if (pct > 1.0f) pct = 1.0f;
        int new_size = 12 + int(pct * 28.0f + 0.5f);
        if (new_size < 12) new_size = 12;
        if (new_size > 40) new_size = 40;
        lbl.font_size = new_size;
    }

    void draw_state_toggle(int content_x, int content_y, int content_h, color accent, float scale) {
        int pad = int(6 * scale);
        int font_size = int(11 * scale);

        render::update_font(fonts::TAHOMA_BOLD_PX, font_size);

        string vis_text = "visible";
        string sep_text = " / ";
        string occ_text = "occluded";

        vec2 vis_size = render::calculate_text_size(vis_text);
        vec2 sep_size = render::calculate_text_size(sep_text);
        vec2 occ_size = render::calculate_text_size(occ_text);

        int th = int(vis_size.y);
        int x = content_x + pad;
        int y = content_y + content_h - th - pad;

        color inactive_col;
        inactive_col.r = 120;
        inactive_col.g = 120;
        inactive_col.b = 120;
        inactive_col.a = 255;

        color sep_col;
        sep_col.r = 100;
        sep_col.g = 100;
        sep_col.b = 100;
        sep_col.a = 200;

        color vis_col = show_occluded ? inactive_col : accent;
        color occ_col = show_occluded ? accent : inactive_col;

        int vis_w = int(vis_size.x);
        int sep_w = int(sep_size.x);
        int occ_w = int(occ_size.x);

        render::draw_text_outlined(x, y, vis_text, vis_col.r, vis_col.g, vis_col.b, vis_col.a);
        render::draw_text_outlined(x + vis_w, y, sep_text, sep_col.r, sep_col.g, sep_col.b, sep_col.a);
        render::draw_text_outlined(x + vis_w + sep_w, y, occ_text, occ_col.r, occ_col.g, occ_col.b, occ_col.a);

        toggle_vis_pos = vec2(float(x), float(y));
        toggle_vis_size = vec2(float(vis_w), float(th));
        toggle_occ_pos = vec2(float(x + vis_w + sep_w), float(y));
        toggle_occ_size = vec2(float(occ_w), float(th));
        toggle_drawn = true;
    }

    void draw_images(int box_x, int box_y, int box_w, int box_h) {
        int gap_from_box = 2;
        int between = 4;

        for (uint i = 0; i < images.length(); i++) {
            images[i].drawn = false;
        }

        for (int side = 0; side < 4; side++) {
            int bar_zone = side_bar_offset(side);
            int start = bar_zone == 0 ? gap_from_box : (bar_zone + 2);

            array<int> indices;
            for (uint i = 0; i < images.length(); i++) {
                if (drag_active && drag_kind == 2 && int(i) == drag_index) continue;
                if (images[i].position != side) continue;
                if (!ui::get(images[i].enabled)) continue;
                indices.insertLast(int(i));
            }

            int cursor = start;
            for (uint k = 0; k < indices.length(); k++) {
                image_preview@ img = images[indices[k]];
                int s = img.size;

                int ix, iy;
                if (side == 0) {
                    ix = box_x + (box_w - s) / 2;
                    iy = box_y - cursor - s;
                } else if (side == 2) {
                    ix = box_x + (box_w - s) / 2;
                    iy = box_y + box_h + cursor;
                } else if (side == 1) {
                    ix = box_x + box_w + cursor;
                    iy = box_y;
                } else {
                    ix = box_x - cursor - s;
                    iy = box_y;
                }

                render::draw_image(img.preview_img, ix, iy, s, s);

                img.last_pos = vec2(float(ix), float(iy));
                img.last_size = vec2(float(s), float(s));
                img.drawn = true;

                cursor += s + between;
            }
        }
    }

    void draw_bars(int box_x, int box_y, int box_w, int box_h) {
        int gap_from_box = 2;
        int bar_size = 4;
        int between = 2;
        uint64 period = 4000;

        for (uint i = 0; i < bars.length(); i++) {
            bars[i].drawn = false;
        }

        for (int side = 0; side < 4; side++) {
            array<int> indices;
            for (uint i = 0; i < bars.length(); i++) {
                if (drag_active && drag_kind == 1 && int(i) == drag_index) continue;
                if (bars[i].position != side) continue;
                if (!ui::get(bars[i].enabled)) continue;
                indices.insertLast(int(i));
            }

            for (uint k = 0; k < indices.length(); k++) {
                bar_preview@ b = bars[indices[k]];

                uint64 t = (util::tickcount() + uint64(k) * 600) % period;
                float p = float(t) / float(period);
                float t01 = (p < 0.5f) ? p * 2.0f : 2.0f - p * 2.0f;
                float pct = t01 * t01 * (3.0f - 2.0f * t01);

                color c;
                if (is_occluded()) {
                    c = ui::get(b.col_occluded);
                } else if (b.has_style && b.style_index == 0) {
                    c = percent_color(pct, ui::get(b.col).a);
                } else {
                    c = ui::get(b.col);
                }
                int stack = int(k);

                int bx, by, bw, bh;
                if (side == 3) {
                    bx = box_x - gap_from_box - bar_size - stack * (bar_size + between);
                    by = box_y;
                    bw = bar_size;
                    bh = box_h;
                } else if (side == 1) {
                    bx = box_x + box_w + gap_from_box + stack * (bar_size + between);
                    by = box_y;
                    bw = bar_size;
                    bh = box_h;
                } else if (side == 0) {
                    bx = box_x;
                    by = box_y - gap_from_box - bar_size - stack * (bar_size + between);
                    bw = box_w;
                    bh = bar_size;
                } else {
                    bx = box_x;
                    by = box_y + box_h + gap_from_box + stack * (bar_size + between);
                    bw = box_w;
                    bh = bar_size;
                }

                render::draw_box(bx, by, bw, bh, 0, 0, 0, c.a / 2, FILLED, 0.0f);

                if (side == 1 || side == 3) {
                    int inner_h = bh - 2;
                    int fill_h = int(float(inner_h) * pct);
                    int fill_top = by + 1 + (inner_h - fill_h);
                    if (fill_h > 0) {
                        render::draw_box(bx + 1, fill_top, bw - 2, fill_h, c.r, c.g, c.b, c.a, FILLED, 0.0f);
                    }
                } else {
                    int inner_w = bw - 2;
                    int fill_w = int(float(inner_w) * pct);
                    if (fill_w > 0) {
                        render::draw_box(bx + 1, by + 1, fill_w, bh - 2, c.r, c.g, c.b, c.a, FILLED, 0.0f);
                    }
                }

                b.last_pos = vec2(float(bx), float(by));
                b.last_size = vec2(float(bw), float(bh));
                b.drawn = true;
            }
        }
    }

    void draw_labels(int side, int box_x, int box_y, int box_w, int box_h, int gap, int spacing, float scale, int bar_offset) {
        bool stack_up = (side == 0);

        int y_cursor;
        if (side == 0) y_cursor = box_y - gap - bar_offset;
        else if (side == 2) y_cursor = box_y + box_h + gap + bar_offset;
        else y_cursor = box_y;

        for (uint i = 0; i < labels.length(); i++) {
            label_preview@ lbl = labels[i];
            if (lbl.position != side) continue;
            if (!ui::get(lbl.enabled)) continue;
            if (drag_active && drag_kind == 0 && int(i) == drag_index) continue;

            render::update_font(lbl.font, int(lbl.font_size * scale));
            vec2 size = render::calculate_text_size(lbl.text);
            int tw = int(size.x);
            int th = int(size.y);

            int tx;
            if (side == 0 || side == 2) tx = box_x + (box_w - tw) / 2;
            else if (side == 1) tx = box_x + box_w + gap + bar_offset;
            else tx = box_x - gap - bar_offset - tw;

            int ty = stack_up ? y_cursor - th : y_cursor;

            color c = is_occluded() ? ui::get(lbl.col_occluded) : ui::get(lbl.col);
            render::draw_text_outlined(tx, ty, lbl.text, c.r, c.g, c.b, c.a);

            lbl.last_pos = vec2(float(tx), float(ty));
            lbl.last_size = vec2(float(tw), float(th));
            lbl.drawn = true;

            y_cursor = stack_up ? ty - spacing : ty + th + spacing;
        }
    }

    void handle_drag(int box_x, int box_y, int box_w, int box_h, int gap, int spacing, float scale, color accent) {
        bool lmb_now = input::key_active(0x01);
        bool lmb_pressed = lmb_now && !lmb_last;
        bool lmb_released = !lmb_now && lmb_last;
        lmb_last = lmb_now;

        bool rmb_now = input::key_active(0x02);
        bool rmb_pressed = rmb_now && !rmb_last;
        rmb_last = rmb_now;

        int mx, my;
        input::mouse_pos(mx, my);

        if (popup_open) {
            if (popup_slider_dragging) {
                if (lmb_now) {
                    slider_set_from_mouse(mx);
                } else {
                    popup_slider_dragging = false;
                }
                return;
            }

            bool inside_popup = point_in_rect(mx, my, popup_pos, popup_size);

            if (rmb_pressed) {
                if (popup_combo_expanded) popup_combo_expanded = false;
                else popup_open = false;
                return;
            }

            if (lmb_pressed) {
                label_preview@ lbl = labels[popup_label_index];

                if (popup_combo_expanded) {
                    if (mx >= popup_font_row_x && mx < popup_font_row_x + popup_font_row_w) {
                        for (uint i = 0; i < popup_font_row_y.length(); i++) {
                            int row_y = popup_font_row_y[i];
                            if (my >= row_y && my < row_y + popup_font_row_h) {
                                lbl.font = popup_font_choices[i];
                                popup_combo_expanded = false;
                                return;
                            }
                        }
                    }
                    popup_combo_expanded = false;
                    if (!inside_popup) popup_open = false;
                    return;
                }

                if (!inside_popup) {
                    popup_open = false;
                    return;
                }

                if (point_in_rect(mx, my, popup_combo_header_pos, popup_combo_header_size)) {
                    popup_combo_expanded = true;
                    return;
                }

                vec2 btn_dims = vec2(float(popup_btn_size), float(popup_btn_size));
                if (point_in_rect(mx, my, popup_minus_pos, btn_dims)) {
                    if (lbl.font_size > 12) lbl.font_size--;
                    return;
                }
                if (point_in_rect(mx, my, popup_plus_pos, btn_dims)) {
                    if (lbl.font_size < 40) lbl.font_size++;
                    return;
                }

                int track_pad = int(4 * scale);
                int track_hit_x = int(popup_slider_track_pos.x);
                int track_hit_y = int(popup_slider_track_pos.y) - track_pad;
                int track_hit_w = int(popup_slider_track_size.x);
                int track_hit_h = int(popup_slider_track_size.y) + track_pad * 2;
                if (point_in_rect(mx, my, track_hit_x, track_hit_y, track_hit_w, track_hit_h)) {
                    popup_slider_dragging = true;
                    slider_set_from_mouse(mx);
                    return;
                }
            }
            return;
        }

        if (rmb_pressed && !drag_active) {
            if (has_box && ui::get(box_check) && point_in_rect(mx, my, box_x, box_y, box_w, box_h)) {
                box_style_index = (box_style_index + 1) % 2;
                return;
            }
            for (uint i = 0; i < bars.length(); i++) {
                bar_preview@ b = bars[i];
                if (!b.drawn || !b.has_style) continue;
                if (!point_in_rect(mx, my, b.last_pos, b.last_size)) continue;

                b.style_index = (b.style_index + 1) % 2;
                return;
            }
            for (uint i = 0; i < labels.length(); i++) {
                label_preview@ lbl = labels[i];
                if (!lbl.drawn) continue;
                if (!point_in_rect(mx, my, lbl.last_pos, lbl.last_size)) continue;

                popup_open = true;
                popup_label_index = int(i);
                popup_pos = vec2(lbl.last_pos.x, lbl.last_pos.y + lbl.last_size.y + float(4 * scale));
                return;
            }
        }

        if (drag_active) {
            drag_target_side = compute_target_side(mx, my, box_x, box_y, box_w, box_h);

            if (drag_kind == 1) {
                drag_target_slot = compute_target_slot_bar(drag_target_side, mx, my);
                draw_drop_indicator_bar(drag_target_side, drag_target_slot, box_x, box_y, box_w, box_h);

                int gw, gh;
                if (drag_target_side == 1 || drag_target_side == 3) {
                    gw = 4;
                    gh = box_h;
                } else {
                    gw = box_w;
                    gh = 4;
                }
                int gx = mx - gw / 2;
                int gy = my - gh / 2;
                render::draw_box(gx, gy, gw, gh, 0, 0, 0, 80, FILLED, 0.0f);
                render::draw_box(gx + 1, gy + 1, gw - 2, gh - 2, 140, 140, 140, 100, FILLED, 0.0f);
            } else {
                drag_target_slot = compute_target_slot_outer(drag_target_side, mx, my);
                draw_drop_indicator_outer(drag_target_side, drag_target_slot, drag_kind, drag_index, box_x, box_y, box_w, box_h, gap, spacing);

                if (drag_kind == 0) {
                    label_preview@ lbl = labels[drag_index];
                    render::update_font(lbl.font, int(lbl.font_size * scale));
                    color c = is_occluded() ? ui::get(lbl.col_occluded) : ui::get(lbl.col);
                    render::draw_text_outlined(mx - drag_offset_x, my - drag_offset_y, lbl.text, c.r, c.g, c.b, 180);
                } else {
                    image_preview@ img = images[drag_index];
                    int s = img.size;
                    int gx = mx - s / 2;
                    int gy = my - s / 2;
                    render::draw_image(img.preview_img, gx, gy, s, s, 255, 255, 255, 180);
                }
            }

            if (lmb_released) {
                if (drag_kind == 1) apply_drop_bar(drag_index, drag_target_side, drag_target_slot);
                else apply_drop_outer(drag_kind, drag_index, drag_target_side, drag_target_slot);
                drag_active = false;
                drag_index = -1;
            }
            return;
        }

        if (lmb_pressed) {
            if (toggle_drawn) {
                if (point_in_rect(mx, my, toggle_vis_pos, toggle_vis_size)) {
                    show_occluded = false;
                    return;
                }
                if (point_in_rect(mx, my, toggle_occ_pos, toggle_occ_size)) {
                    show_occluded = true;
                    return;
                }
            }

            for (uint i = 0; i < labels.length(); i++) {
                label_preview@ lbl = labels[i];
                if (!lbl.drawn) continue;
                if (!point_in_rect(mx, my, lbl.last_pos, lbl.last_size)) continue;

                drag_active = true;
                drag_kind = 0;
                drag_index = int(i);
                drag_offset_x = mx - int(lbl.last_pos.x);
                drag_offset_y = my - int(lbl.last_pos.y);
                return;
            }
            for (uint i = 0; i < bars.length(); i++) {
                bar_preview@ b = bars[i];
                if (!b.drawn) continue;
                if (!point_in_rect(mx, my, b.last_pos, b.last_size)) continue;

                drag_active = true;
                drag_kind = 1;
                drag_index = int(i);
                drag_offset_x = mx - int(b.last_pos.x);
                drag_offset_y = my - int(b.last_pos.y);
                return;
            }
            for (uint i = 0; i < images.length(); i++) {
                image_preview@ img = images[i];
                if (!img.drawn) continue;
                if (!point_in_rect(mx, my, img.last_pos, img.last_size)) continue;

                drag_active = true;
                drag_kind = 2;
                drag_index = int(i);
                drag_offset_x = mx - int(img.last_pos.x);
                drag_offset_y = my - int(img.last_pos.y);
                return;
            }
        }
    }

    int compute_target_side(int mx, int my, int box_x, int box_y, int box_w, int box_h) {
        vec2 center = vec2(float(box_x) + float(box_w) * 0.5f, float(box_y) + float(box_h) * 0.5f);
        vec2 delta = vec2(float(mx), float(my)).subtract(center);
        float nx = delta.x * 2.0f / float(box_w);
        float ny = delta.y * 2.0f / float(box_h);
        float anx = nx < 0 ? -nx : nx;
        float any = ny < 0 ? -ny : ny;

        if (any > anx) return ny < 0 ? 0 : 2;
        return nx > 0 ? 1 : 3;
    }
    

    int compute_target_slot(int side, int my) {
        array<int> side_indices = collect_side(side);
        int slot = 0;
        for (uint i = 0; i < side_indices.length(); i++) {
            label_preview@ lbl = labels[side_indices[i]];
            float center_y = lbl.last_pos.y + lbl.last_size.y * 0.5f;
            bool before_mouse = (side == 0) ? (center_y > float(my)) : (center_y < float(my));
            if (before_mouse) slot++;
        }
        return slot;
    }

    int compute_target_slot_bar(int side, int mx, int my) {
        array<int> indices;
        for (uint i = 0; i < bars.length(); i++) {
            if (drag_kind == 1 && int(i) == drag_index) continue;
            if (bars[i].position != side) continue;
            if (!ui::get(bars[i].enabled)) continue;
            indices.insertLast(int(i));
        }

        int slot = 0;
        for (uint i = 0; i < indices.length(); i++) {
            bar_preview@ b = bars[indices[i]];
            float bcx = b.last_pos.x + b.last_size.x * 0.5f;
            float bcy = b.last_pos.y + b.last_size.y * 0.5f;

            bool before_mouse;
            if (side == 0) before_mouse = bcy > float(my);
            else if (side == 2) before_mouse = bcy < float(my);
            else if (side == 1) before_mouse = bcx < float(mx);
            else before_mouse = bcx > float(mx);

            if (before_mouse) slot++;
        }
        return slot;
    }

    array<int> collect_side(int side) {
        array<int> result;
        for (uint i = 0; i < labels.length(); i++) {
            if (drag_active && drag_kind == 0 && int(i) == drag_index) continue;
            if (labels[i].position != side) continue;
            if (!ui::get(labels[i].enabled)) continue;
            result.insertLast(int(i));
        }
        return result;
    }

    array<outer_ref> collect_outer_items(int side, bool exclude_dragged) {
        array<outer_ref> items;

        for (uint i = 0; i < labels.length(); i++) {
            if (exclude_dragged && drag_active && drag_kind == 0 && int(i) == drag_index) continue;
            if (labels[i].position != side) continue;
            if (!ui::get(labels[i].enabled)) continue;
            outer_ref r;
            r.kind = 0;
            r.idx = int(i);
            r.order = labels[i].outer_order;
            items.insertLast(r);
        }
        for (uint i = 0; i < images.length(); i++) {
            if (exclude_dragged && drag_active && drag_kind == 2 && int(i) == drag_index) continue;
            if (images[i].position != side) continue;
            if (!ui::get(images[i].enabled)) continue;
            outer_ref r;
            r.kind = 1;
            r.idx = int(i);
            r.order = images[i].outer_order;
            items.insertLast(r);
        }

        for (uint i = 1; i < items.length(); i++) {
            outer_ref key = items[i];
            int j = int(i) - 1;
            while (j >= 0 && items[uint(j)].order > key.order) {
                items[uint(j + 1)] = items[uint(j)];
                j--;
            }
            items[uint(j + 1)] = key;
        }

        return items;
    }

    void draw_outer_items_side(int side, int box_x, int box_y, int box_w, int box_h, int gap, int spacing, float scale) {
        array<outer_ref> items = collect_outer_items(side, true);
        if (items.length() == 0) return;

        int bar_offset = side_bar_offset(side);
        bool stack_up = (side == 0);

        int cursor;
        if (side == 0) cursor = box_y - bar_offset - gap;
        else if (side == 2) cursor = box_y + box_h + bar_offset + gap;
        else cursor = box_y;

        for (uint k = 0; k < items.length(); k++) {
            outer_ref ref = items[k];
            int item_w, item_h, item_x, item_y;

            if (ref.kind == 0) {
                label_preview@ lbl = labels[ref.idx];
                render::update_font(lbl.font, int(lbl.font_size * scale));
                vec2 text_size = render::calculate_text_size(lbl.text);
                item_w = int(text_size.x);
                item_h = int(text_size.y);

                if (side == 0 || side == 2) item_x = box_x + (box_w - item_w) / 2;
                else if (side == 1) item_x = box_x + box_w + bar_offset + gap;
                else item_x = box_x - bar_offset - gap - item_w;

                item_y = stack_up ? cursor - item_h : cursor;

                color c = is_occluded() ? ui::get(lbl.col_occluded) : ui::get(lbl.col);
                render::draw_text_outlined(item_x, item_y, lbl.text, c.r, c.g, c.b, c.a);

                lbl.last_pos = vec2(float(item_x), float(item_y));
                lbl.last_size = vec2(float(item_w), float(item_h));
                lbl.drawn = true;
            } else {
                image_preview@ img = images[ref.idx];
                item_w = img.size;
                item_h = img.size;

                if (side == 0 || side == 2) item_x = box_x + (box_w - item_w) / 2;
                else if (side == 1) item_x = box_x + box_w + bar_offset + gap;
                else item_x = box_x - bar_offset - gap - item_w;

                item_y = stack_up ? cursor - item_h : cursor;

                render::draw_image(img.preview_img, item_x, item_y, item_w, item_h);

                img.last_pos = vec2(float(item_x), float(item_y));
                img.last_size = vec2(float(item_w), float(item_h));
                img.drawn = true;
            }

            if (stack_up) cursor = item_y - spacing;
            else cursor = item_y + item_h + spacing;
        }
    }

    int compute_target_slot_outer(int side, int mx, int my) {
        array<outer_ref> items = collect_outer_items(side, true);
        int slot = 0;
        for (uint i = 0; i < items.length(); i++) {
            float cy;
            if (items[i].kind == 0) {
                label_preview@ lbl = labels[items[i].idx];
                cy = lbl.last_pos.y + lbl.last_size.y * 0.5f;
            } else {
                image_preview@ img = images[items[i].idx];
                cy = img.last_pos.y + img.last_size.y * 0.5f;
            }
            bool before_mouse = (side == 0) ? (cy > float(my)) : (cy < float(my));
            if (before_mouse) slot++;
        }
        return slot;
    }

    void draw_drop_indicator_outer(int side, int slot, int drag_kind_val, int drag_idx, int box_x, int box_y, int box_w, int box_h, int gap, int spacing) {
        array<outer_ref> items = collect_outer_items(side, true);
        int bar_offset = side_bar_offset(side);
        bool stack_up = (side == 0);

        int cursor;
        if (side == 0) cursor = box_y - bar_offset - gap;
        else if (side == 2) cursor = box_y + box_h + bar_offset + gap;
        else cursor = box_y;

        for (int i = 0; i < slot && i < int(items.length()); i++) {
            int item_h;
            if (items[i].kind == 0) item_h = int(labels[items[i].idx].last_size.y);
            else item_h = int(images[items[i].idx].last_size.y);
            if (stack_up) cursor -= item_h + spacing;
            else cursor += item_h + spacing;
        }

        int drop_w, drop_h;
        if (drag_kind_val == 0) {
            drop_w = int(labels[drag_idx].last_size.x);
            drop_h = int(labels[drag_idx].last_size.y);
        } else {
            drop_w = images[drag_idx].size;
            drop_h = images[drag_idx].size;
        }

        int drop_x, drop_y;
        if (side == 0 || side == 2) drop_x = box_x + (box_w - drop_w) / 2;
        else if (side == 1) drop_x = box_x + box_w + bar_offset + gap;
        else drop_x = box_x - bar_offset - gap - drop_w;
        drop_y = stack_up ? cursor - drop_h : cursor;

        render::draw_box(drop_x, drop_y, drop_w, drop_h, 0, 0, 0, 80, FILLED, 0.0f);
        render::draw_box(drop_x + 1, drop_y + 1, drop_w - 2, drop_h - 2, 140, 140, 140, 100, FILLED, 0.0f);
    }

    void apply_drop_outer(int kind, int drag_idx, int target_side, int target_slot) {
        if (kind == 0) labels[drag_idx].position = target_side;
        else images[drag_idx].position = target_side;

        array<outer_ref> items = collect_outer_items(target_side, true);
        if (target_slot > int(items.length())) target_slot = int(items.length());

        outer_ref dragged_ref;
        dragged_ref.kind = kind;
        dragged_ref.idx = drag_idx;
        dragged_ref.order = 0;
        items.insertAt(uint(target_slot), dragged_ref);

        for (uint i = 0; i < items.length(); i++) {
            int new_order = int(i + 1);
            if (items[i].kind == 0) labels[items[i].idx].outer_order = new_order;
            else images[items[i].idx].outer_order = new_order;
        }
    }

    void draw_drop_indicator(int side, int slot, int box_x, int box_y, int box_w, int box_h, int gap, int spacing, int bar_offset) {
        label_preview@ dragged = labels[drag_index];
        int text_w = int(dragged.last_size.x);
        int text_h = int(dragged.last_size.y);

        array<int> side_indices = collect_side(side);
        int count = int(side_indices.length());

        int slot_x;
        if (side == 0 || side == 2) slot_x = box_x + (box_w - text_w) / 2;
        else if (side == 1) slot_x = box_x + box_w + gap + bar_offset;
        else slot_x = box_x - gap - bar_offset - text_w;

        int slot_y;
        if (side == 0) {
            int y_cursor = box_y - gap - bar_offset;
            for (int i = 0; i < slot && i < count; i++) {
                y_cursor = int(labels[side_indices[i]].last_pos.y) - spacing;
            }
            slot_y = y_cursor - text_h;
        } else {
            int y_cursor;
            if (side == 2) y_cursor = box_y + box_h + gap + bar_offset;
            else y_cursor = box_y;

            for (int i = 0; i < slot && i < count; i++) {
                label_preview@ l = labels[side_indices[i]];
                y_cursor = int(l.last_pos.y + l.last_size.y) + spacing;
            }
            slot_y = y_cursor;
        }

        render::draw_box(slot_x, slot_y, text_w, text_h, 120, 120, 120, 80, FILLED, 0.0f);
    }

    void draw_drop_indicator_bar(int side, int slot, int box_x, int box_y, int box_w, int box_h) {
        int gap_from_box = 2;
        int bar_size = 4;
        int between = 2;
        int stack = slot;

        int bx, by, bw, bh;
        if (side == 3) {
            bx = box_x - gap_from_box - bar_size - stack * (bar_size + between);
            by = box_y;
            bw = bar_size;
            bh = box_h;
        } else if (side == 1) {
            bx = box_x + box_w + gap_from_box + stack * (bar_size + between);
            by = box_y;
            bw = bar_size;
            bh = box_h;
        } else if (side == 0) {
            bx = box_x;
            by = box_y - gap_from_box - bar_size - stack * (bar_size + between);
            bw = box_w;
            bh = bar_size;
        } else {
            bx = box_x;
            by = box_y + box_h + gap_from_box + stack * (bar_size + between);
            bw = box_w;
            bh = bar_size;
        }

        render::draw_box(bx, by, bw, bh, 0, 0, 0, 80, FILLED, 0.0f);
        render::draw_box(bx + 1, by + 1, bw - 2, bh - 2, 140, 140, 140, 100, FILLED, 0.0f);
    }

    void apply_drop(int drag_idx, int target_side, int target_slot) {
        label_preview moved = labels[drag_idx];
        moved.position = target_side;
        labels.removeAt(drag_idx);

        int insert_at = int(labels.length());
        int seen = 0;
        for (uint i = 0; i < labels.length(); i++) {
            if (labels[i].position != target_side) continue;
            if (seen == target_slot) {
                insert_at = int(i);
                break;
            }
            seen++;
        }
        labels.insertAt(insert_at, moved);
    }

    void apply_drop_bar(int drag_idx, int target_side, int target_slot) {
        bar_preview moved = bars[drag_idx];
        moved.position = target_side;
        bars.removeAt(drag_idx);

        int insert_at = int(bars.length());
        int seen = 0;
        for (uint i = 0; i < bars.length(); i++) {
            if (bars[i].position != target_side) continue;
            if (seen == target_slot) {
                insert_at = int(i);
                break;
            }
            seen++;
        }
        bars.insertAt(insert_at, moved);
    }

    int compute_target_slot_image(int side, int mx, int my) {
        array<int> indices;
        for (uint i = 0; i < images.length(); i++) {
            if (drag_kind == 2 && int(i) == drag_index) continue;
            if (images[i].position != side) continue;
            if (!ui::get(images[i].enabled)) continue;
            indices.insertLast(int(i));
        }

        int slot = 0;
        for (uint i = 0; i < indices.length(); i++) {
            image_preview@ img = images[indices[i]];
            float cx = img.last_pos.x + img.last_size.x * 0.5f;
            float cy = img.last_pos.y + img.last_size.y * 0.5f;

            bool before_mouse;
            if (side == 0) before_mouse = cy > float(my);
            else if (side == 2) before_mouse = cy < float(my);
            else if (side == 1) before_mouse = cx < float(mx);
            else before_mouse = cx > float(mx);

            if (before_mouse) slot++;
        }
        return slot;
    }

    void draw_drop_indicator_image(int side, int slot, int box_x, int box_y, int box_w, int box_h) {
        int gap_from_box = 2;
        int between = 4;
        int bar_zone = side_bar_offset(side);
        int start = bar_zone == 0 ? gap_from_box : (bar_zone + 2);

        image_preview@ dragged = images[drag_index];
        int s = dragged.size;

        array<int> indices;
        for (uint i = 0; i < images.length(); i++) {
            if (int(i) == drag_index) continue;
            if (images[i].position != side) continue;
            if (!ui::get(images[i].enabled)) continue;
            indices.insertLast(int(i));
        }

        int cursor = start;
        for (int i = 0; i < slot && i < int(indices.length()); i++) {
            cursor += images[indices[i]].size + between;
        }

        int ix, iy;
        if (side == 0) {
            ix = box_x + (box_w - s) / 2;
            iy = box_y - cursor - s;
        } else if (side == 2) {
            ix = box_x + (box_w - s) / 2;
            iy = box_y + box_h + cursor;
        } else if (side == 1) {
            ix = box_x + box_w + cursor;
            iy = box_y;
        } else {
            ix = box_x - cursor - s;
            iy = box_y;
        }

        render::draw_box(ix, iy, s, s, 0, 0, 0, 80, FILLED, 0.0f);
        render::draw_box(ix + 1, iy + 1, s - 2, s - 2, 140, 140, 140, 100, FILLED, 0.0f);
    }

    void apply_drop_image(int drag_idx, int target_side, int target_slot) {
        image_preview moved = images[drag_idx];
        moved.position = target_side;
        images.removeAt(drag_idx);

        int insert_at = int(images.length());
        int seen = 0;
        for (uint i = 0; i < images.length(); i++) {
            if (images[i].position != target_side) continue;
            if (seen == target_slot) {
                insert_at = int(i);
                break;
            }
            seen++;
        }
        images.insertAt(insert_at, moved);
    }
}

namespace esp_layout {
    const int bar_w = 4;
    const int bar_gap = 2;
    const int bar_between = 2;
    const int label_gap = 2;
    const float label_row_spacing = 2.0f;

    int bars_on_side(int side, const array<int> &in bar_ids) {
        int count = 0;
        
        for (uint i = 0; i < bar_ids.length(); i++) {
            bar_info_t info = g_preview.get_bar_info(bar_ids[i]);
            if (info.enabled && info.position == side) count++;
        }

        return count;
    }

    int label_bar_offset(int side, const array<int> &in bar_ids) {
        int count = bars_on_side(side, bar_ids);
        if (count == 0) return 0;

        int offset = count * bar_w + (count - 1) * bar_between + bar_gap;
        return offset;
    }

    void bar_rect(float bbox_x, float bbox_y, float bbox_w, float bbox_h, bar_info_t info, vec2 &out pos, vec2 &out size) {
        int slot = info.slot;
        if (info.position == 3) {
            pos.x = bbox_x - float(bar_gap) - float(bar_w) - float(slot) * float(bar_w + bar_between);
            pos.y = bbox_y;
            size.x = float(bar_w);
            size.y = bbox_h;
        } else if (info.position == 1) {
            pos.x = bbox_x + bbox_w + float(bar_gap) + float(slot) * float(bar_w + bar_between);
            pos.y = bbox_y;
            size.x = float(bar_w);
            size.y = bbox_h;
        } else if (info.position == 0) {
            pos.x = bbox_x;
            pos.y = bbox_y - float(bar_gap) - float(bar_w) - float(slot) * float(bar_w + bar_between);
            size.x = bbox_w;
            size.y = float(bar_w);
        } else {
            pos.x = bbox_x;
            pos.y = bbox_y + bbox_h + float(bar_gap) + float(slot) * float(bar_w + bar_between);
            size.x = bbox_w;
            size.y = float(bar_w);
        }
    }

    vec2 anchor_for_side(float bbox_x, float bbox_y, float bbox_w, float bbox_h, int side, int bar_offset, float prior, vec2 my_size) {
        if (side == 0) {
            float x = bbox_x + (bbox_w - my_size.x) * 0.5f;
            float y = bbox_y - float(bar_offset) - float(label_gap) - prior - my_size.y;
            return vec2(x, y);
        }
        if (side == 2) {
            float x = bbox_x + (bbox_w - my_size.x) * 0.5f;
            float y = bbox_y + bbox_h + float(bar_offset) + float(label_gap) + prior;
            return vec2(x, y);
        }
        if (side == 1) {
            float x = bbox_x + bbox_w + float(bar_offset) + float(label_gap);
            float y = bbox_y + prior;
            return vec2(x, y);
        }
        float x = bbox_x - float(bar_offset) - float(label_gap) - my_size.x;
        float y = bbox_y + prior;
        return vec2(x, y);
    }

    float image_item_height(int id) {
        image_info_t info = g_preview.get_image_info(id);
        return float(info.size);
    }

    vec2 image_item_size(int id) {
        image_info_t info = g_preview.get_image_info(id);
        return vec2(float(info.size), float(info.size));
    }
}

// Here is an example of how to use the esp_layout helpers to implement your custom layout from the ESP Preview.
// // namespace visuals {
// //     namespace example {
// //         array<int> bar_ids = {gui::example::healthbar_id}; // every bar this entity type can register, for offset math

// //         string label_text_for(int id, player_t@ p, local_player_t local_player) {
// //             if (id == gui::example::name_id) return p.name;
// //             if (id == gui::example::distance_id) return util::format_string("{}m", int(p.position.distance(local_player.position) * 0.0254f));
// //             return "";
// //         }

// //         vec2 outer_anchor(player_t@ p, local_player_t local_player, bounds_t bbox, int side, int slot, vec2 my_size) {
// //             int bar_offset = esp_layout::label_bar_offset(side, bar_ids);

// //             float prior = 0.0f;
// //             array<outer_item_summary_t> items = g_preview.get_outer_items(side);
// //             for (int i = 0; i < slot && i < int(items.length()); i++) {
// //                 outer_item_summary_t item = items[i];
// //                 label_info_t info = g_preview.get_label_info(item.id);
// //                 render::update_font(info.font, info.font_size);
// //                 vec2 size = render::calculate_text_size(label_text_for(item.id, p, local_player));
// //                 prior += size.y + esp_layout::LABEL_ROW_SPACING;
// //             }

// //             return esp_layout::anchor_for_side(bbox.x, bbox.y, bbox.w, bbox.h, side, bar_offset, prior, my_size);
// //         }

// //         void draw_bbox(player_t@ p, bounds_t bbox) {
// //             box_info_t info = g_preview.get_box_info();
// //             if (!info.enabled) return;

// //             color clr = p.is_visible ? info.col : info.col_occluded;
// //             box_style style = info.style_index == 1 ? CORNERED : OUTLINED;
// //             render::draw_box(int(bbox.x), int(bbox.y), int(bbox.w), int(bbox.h), clr.r, clr.g, clr.b, clr.a, style, 0);
// //         }

// //         void draw_name(player_t@ p, local_player_t local_player, bounds_t bbox) {
// //             label_info_t info = g_preview.get_label_info(gui::example::name_id);
// //             if (!info.enabled) return;

// //             color clr = p.is_visible ? info.col : info.col_occluded;
// //             render::update_font(info.font, info.font_size);
// //             vec2 text_size = render::calculate_text_size(p.name);
// //             vec2 anchor = outer_anchor(p, local_player, bbox, info.position, info.slot, text_size);
// //             render::update_font(info.font, info.font_size); // outer_anchor's measuring loop leaves the font state on the last item it measured, so re-apply ours here
// //             render::draw_text_outlined(int(anchor.x), int(anchor.y), p.name, clr.r, clr.g, clr.b, clr.a);
// //         }

// //         void draw_distance(player_t@ p, local_player_t local_player, bounds_t bbox) {
// //             label_info_t info = g_preview.get_label_info(gui::example::distance_id);
// //             if (!info.enabled) return;

// //             color clr = p.is_visible ? info.col : info.col_occluded;
// //             string dist_text = util::format_string("{}m", int(p.position.distance(local_player.position) * 0.0254f));
// //             render::update_font(info.font, info.font_size);
// //             vec2 text_size = render::calculate_text_size(dist_text);
// //             vec2 anchor = outer_anchor(p, local_player, bbox, info.position, info.slot, text_size);
// //             render::update_font(info.font, info.font_size);
// //             render::draw_text_outlined(int(anchor.x), int(anchor.y), dist_text, clr.r, clr.g, clr.b, clr.a);
// //         }

// //         color health_to_color(int64 health, int64 max_health, int alpha) {
// //             float pct = float(health) / float(max_health);
// //             if (pct < 0.0f) pct = 0.0f;
// //             if (pct > 1.0f) pct = 1.0f;
// //             color c;
// //             c.r = int(255 * (1.0f - pct));
// //             c.g = int(255 * pct);
// //             c.b = 0;
// //             c.a = alpha;
// //             return c;
// //         }

// //         void draw_healthbar(player_t@ p, bounds_t bbox) {
// //             bar_info_t info = g_preview.get_bar_info(gui::example::healthbar_id);
// //             if (!info.enabled) return;

// //             float pct = float(p.health) / float(p.max_health);
// //             if (pct < 0.0f) pct = 0.0f;
// //             else if (pct > 1.0f) pct = 1.0f;

// //             color base = p.is_visible ? info.col : info.col_occluded;
// //             color fill = (info.has_style && info.style_index == 0 && p.is_visible)
// //                 ? health_to_color(p.health, p.max_health, base.a)
// //                 : base;

// //             vec2 pos, size;
// //             esp_layout::bar_rect(bbox.x, bbox.y, bbox.w, bbox.h, info, pos, size);
// //             int bx = int(pos.x);
// //             int by = int(pos.y);
// //             int bw = int(size.x);
// //             int bh = int(size.y);

// //             render::draw_box(bx, by, bw, bh, 0, 0, 0, base.a / 2, FILLED, 0);

// //             bool vertical = (info.position == 1 || info.position == 3);
// //             if (vertical) {
// //                 int inner_h = bh - 2;
// //                 int fill_h = int(float(inner_h) * pct);
// //                 int fill_top = by + 1 + (inner_h - fill_h);
// //                 if (fill_h > 0) render::draw_box(bx + 1, fill_top, bw - 2, fill_h, fill.r, fill.g, fill.b, fill.a, FILLED, 0);
// //             } else {
// //                 int inner_w = bw - 2;
// //                 int fill_w = int(float(inner_w) * pct);
// //                 if (fill_w > 0) render::draw_box(bx + 1, by + 1, fill_w, bh - 2, fill.r, fill.g, fill.b, fill.a, FILLED, 0);
// //             }
// //         }
// //     }
// // }

esp_preview g_preview;