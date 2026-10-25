// Echo API stub — mirrors /tmp/echo-api-spec.md for compile checking only.
// Class methods carry empty bodies because AngelScript script classes cannot
// declare bodiless members; the real host registers these types natively.
typedef float f32; typedef double f64;

funcdef void thread_callback();
funcdef void button_callback();
funcdef void checkbox_callback();
funcdef void combobox_callback();

class vec2 {
  f32 x; f32 y;
  vec2(){} vec2(f32 a,f32 b){ x=a; y=b; }
  f32 length() const { return 0.0f; } vec2 normalize() const { return vec2(); }
  f32 dot(const vec2 &in) const { return 0.0f; }
  vec2 add(const vec2 &in) const { return vec2(); }
  vec2 subtract(const vec2 &in) const { return vec2(); }
  vec2 multiply(f32) const { return vec2(); }
  f32 distance(const vec2 &in) const { return 0.0f; }
  vec2 lerp(const vec2 &in,f32) const { return vec2(); }
  bool is_empty() const { return false; }
  f32 length_squared() const { return 0.0f; }
  void read_float(uint64) {} void write_float(uint64) {}
}
class vec3 {
  f32 x; f32 y; f32 z;
  vec3(){} vec3(f32 a,f32 b,f32 c){ x=a; y=b; z=c; }
  f32 length() const { return 0.0f; } vec3 normalize() const { return vec3(); }
  f32 dot(const vec3 &in) const { return 0.0f; }
  vec3 add(const vec3 &in) const { return vec3(); }
  vec3 subtract(const vec3 &in) const { return vec3(); }
  vec3 multiply(f32) const { return vec3(); }
  f32 distance(const vec3 &in) const { return 0.0f; }
  vec3 lerp(const vec3 &in,f32) const { return vec3(); }
  bool is_empty() const { return false; }
  f32 length_squared() const { return 0.0f; }
}
class vec4 { f32 x; f32 y; f32 z; f32 w; vec4(){} }
class matrix3x3 { matrix3x3(){} bool read(uint64){return false;} bool read_double(uint64){return false;}
  array<float> &opIndex(uint i) { return cell; } array<float> cell; }
class matrix4x4 { matrix4x4(){} bool read(uint64){return false;} bool read_double(uint64){return false;}
  array<float> &opIndex(uint i) { return cell; } array<float> cell; }

class color {
  int r; int g; int b; int a;
  color(){}
  color(int a1,int a2,int a3,int a4){ r=a1; g=a2; b=a3; a=a4; }
}

class checkbox { checkbox(){} }
class slider { slider(){} }
class color_picker { color_picker(){} }
class combobox { combobox(){} }
class multi_select { multi_select(){} }
class button { button(){} }

enum box_style { NORMAL, OUTLINED, FILLED, FILLED_OUTLINED, CORNERED, CORNERED_FILLED };
enum fonts { PROGGY, TAHOMA, TAHOMA_PX, TAHOMA_BOLD, TAHOMA_BOLD_PX, SMALLEST_PIXEL_7, TOMHOMISH };
enum font_hint { NONE, AUTO, MONO };
enum angle_range { R_180, R_360 };

class attach_data { uint64 pid; uint64 peb_address; uint64 base_address; }
class module_entry { string name; uint64 base; uint64 size; }
class memory_region { uint64 base; uint64 size; bool present; bool writable; bool executable; }
class memory_buffer {
  uint8 read_uint8(uint64) { return 0; } uint16 read_uint16(uint64) { return 0; }
  uint32 read_uint32(uint64) { return 0; } uint64 read_uint64(uint64) { return 0; }
  int8 read_int8(uint64) { return 0; } int16 read_int16(uint64) { return 0; }
  int32 read_int32(uint64) { return 0; } int64 read_int64(uint64) { return 0; }
  float read_float(uint64) { return 0.0f; } double read_double(uint64) { return 0.0; }
  vec2 read_vec2_float(uint64) { return vec2(); }
  vec3 read_vec3_float(uint64) { return vec3(); }
  vec4 read_vec4_float(uint64) { return vec4(); }
  uint64 size() { return 0; }
}

class json_obj {
  json_obj(){}
  bool has(string key) { return false; }
  uint length() { return 0; }
  array<string>@ keys() { array<string> a; return a; }
  void set(string,string) {} void set(string,float) {} void set(string,double) {}
  void set(string,int) {} void set(string,uint) {} void set(string,int64) {}
  void set(string,uint64) {} void set(string,bool) {} void set(string,json_obj@) {}
  void push(json_obj@) {}
  void remove(string) {}
  string get_string(string) { return ""; }
  float get_float(string) { return 0; }
  double get_double(string) { return 0; }
  int get_int(string) { return 0; }
  uint get_uint(string) { return 0; }
  int64 get_int64(string) { return 0; }
  uint64 get_uint64(string) { return 0; }
  bool get_bool(string) { return false; }
  json_obj@ get_obj(string) { return null; }
  string get_string_at(uint) { return ""; }
  float get_float_at(uint) { return 0; }
  int get_int_at(uint) { return 0; }
  bool get_bool_at(uint) { return false; }
  json_obj@ get_obj_at(uint) { return null; }
}

namespace process {
  attach_data attach(string) { attach_data d; return d; }
  attach_data attach(uint32) { attach_data d; return d; }
  void detach() {} bool is_alive() { return false; }
  memory_buffer@ read_buffer(uint64,uint64) { return null; }
  array<uint8>@ read_bytes(uint64,uint32) { return null; }
  int8 read_int8(uint64) { return 0; } uint8 read_uint8(uint64) { return 0; }
  int16 read_int16(uint64) { return 0; } uint16 read_uint16(uint64) { return 0; }
  int32 read_int32(uint64) { return 0; } uint32 read_uint32(uint64) { return 0; }
  int64 read_int64(uint64) { return 0; } uint64 read_uint64(uint64) { return 0; }
  float read_float(uint64) { return 0.0f; } double read_double(uint64) { return 0.0; }
  string read_string(uint64) { return ""; }
  bool read_int8(uint64,int8 &in) { return false; } bool read_uint8(uint64,uint8 &in) { return false; }
  bool read_int16(uint64,int16 &in) { return false; } bool read_uint16(uint64,uint16 &in) { return false; }
  bool read_int32(uint64,int32 &in) { return false; } bool read_uint32(uint64,uint32 &in) { return false; }
  bool read_int64(uint64,int64 &in) { return false; } bool read_uint64(uint64,uint64 &in) { return false; }
  bool read_float(uint64,float &in) { return false; } bool read_double(uint64,double &in) { return false; }
  bool read_string(uint64,string &in) { return false; }
  bool write_bytes(array<uint8>,uint64) { return false; }
  bool write_int8(uint64,int8) { return false; } bool write_uint8(uint64,uint8) { return false; }
  bool write_int16(uint64,int16) { return false; } bool write_uint16(uint64,uint16) { return false; }
  bool write_int32(uint64,int32) { return false; } bool write_uint32(uint64,uint32) { return false; }
  bool write_int64(uint64,int64) { return false; } bool write_uint64(uint64,uint64) { return false; }
  bool write_float(uint64,float) { return false; } bool write_double(uint64,double) { return false; }
  memory_region virtual_query(uint64) { memory_region r; return r; }
  uint64 get_module_base(string) { return 0; } uint32 get_module_size(uint64) { return 0; }
  uint64 get_module_export(uint64,string) { return 0; }
  array<module_entry>@ get_module_list() { return null; }
  uint64 find_signature(uint64,string) { return 0; }
  uint64 find_signature(uint64,string,string) { return 0; }
  uint64 find_signature(uint64,string,string,uint64,uint64) { return 0; }
  array<uint64>@ find_signatures(uint64,string) { return null; }
  array<uint64>@ find_signatures(uint64,string,string) { return null; }
  array<uint64>@ find_signatures(uint64,string,string,uint64,uint64) { return null; }
  uint64 get_relative_address(uint64,uint32,uint32) { return 0; }
  bool dump(string) { return false; } bool dump(string,string) { return false; }
  bool open_socket(string) { return false; }
}
namespace render {
  float get_fps() { return 0.0f; } float get_frametime() { return 0.0f; }
  bool is_foreground() { return false; }
  vec2 get_viewport_size() { return vec2(); } bool get_viewport_size(int &out,int &out) { return false; }
  void set_anti_aliasing(bool) {}
  bool load_font(const array<uint8> &in,int &out,int=0) { return false; }
  void update_font(fonts,int) {} void update_font(int,int) {}
  bool load_image(string,int &out) { return false; }
  void draw_image(int,int,int,int,int) {}
  vec2 calculate_text_size(string) { return vec2(); }
  void draw_text(int,int,string,int,int,int,int) {}
  void draw_text_outlined(int,int,string,int,int,int,int) {}
  void draw_text_shadow(int,int,string,int,int,int,int) {}
  void draw_box(int,int,int,int,int,int,int,int,box_style,float) {}
  void draw_gradient_box(int,int,int,int,int,int,int,int,int,int,int,int,bool) {}
  void draw_line(float,float,float,float,int,int,int,int,float=1.0f) {}
  void draw_line_outlined(float,float,float,float,int,int,int,int,float=1.0f) {}
  void draw_circle(float,float,float,int,int,int,int,bool=false,int=32) {}
  void draw_triangle(float,float,float,float,float,float,int,int,int,int,bool=false) {}
  void draw_concave_poly(array<vec2>,int,int,int,int) {}
  void draw_convex_poly(array<vec2>,int,int,int,int,bool) {}
  void draw_polyline(array<vec2>,int,int,int,int,float,bool) {}
  void draw_hue_bar(int,int,int,int,int,int,int,int) {}
  void draw_hue_bar_static(int,int,int,int,int,int,int,int) {}
}
namespace ui {
  class ui_info { bool open; float dpi_scale; float x; float y; float w; float h; color accent; }
  class active_bind { string category; string label; }
  bool is_open() { return false; } float get_scale() { return 1.0f; }
  color get_accent() { return color(); } ui_info get_info() { ui_info i; return i; }
  string get_tab() { return ""; } string get_sub_tab() { return ""; }
  void config_path(string) {}
  bool get_active_binds(array<active_bind> &out) { return false; }
  void add_tab(string) {} void add_tab(string,int) {}
  void add_subtab(string) {} void add_category(string) {} void add_category(string,int) {}
  checkbox add_checkbox(string,bool,string="") { checkbox c; return c; }
  checkbox add_checkbox(string,bool,checkbox_callback@=nullptr,string="") { checkbox c; return c; }
  slider add_slider(string,int,int,int,int,string="",string="") { slider v; return v; }
  color_picker add_color_picker(string,int,int,int,int,bool=true,string="") { color_picker c; return c; }
  combobox add_combobox(string,array<string>,int,string="") { combobox c; return c; }
  combobox add_combobox(string,array<string>,int,combobox_callback@=nullptr,string="") { combobox c; return c; }
  multi_select add_multi_select(string,array<string>,string="") { multi_select m; return m; }
  button add_button(string,button_callback@=nullptr) { button b; return b; }
  bool get(checkbox) { return false; } int get(slider) { return 0; }
  color get(color_picker) { return color(); } uint64 get(combobox) { return 0; }
  bool get(multi_select,uint64) { return false; }
  void set(checkbox,bool) {} void set(slider,int) {} void set(color_picker,color) {}
  void set(combobox,uint64) {} void set(multi_select,uint64,bool) {}
  void set_visible(checkbox,bool) {} void set_visible(slider,bool) {}
  void set_visible(color_picker,bool) {} void set_visible(combobox,bool) {}
  void set_visible(multi_select,bool) {} void set_visible(button,bool) {}
  void add_tooltip(checkbox,string) {} void add_tooltip(slider,string) {}
  void add_tooltip(color_picker,string) {} void add_tooltip(combobox,string) {}
  void add_tooltip(multi_select,string) {}
}
namespace util {
  string format_string(string,int) { return ""; }
  string format_string(string,uint) { return ""; }
  string format_string(string,uint16) { return ""; }
  string format_string(string,uint64) { return ""; }
  string format_string(string,int64) { return ""; }
  string format_string(string,float) { return ""; }
  string format_string(string,double) { return ""; }
  string format_string(string,bool) { return ""; }
  string format_string(string,string) { return ""; }
  string to_hex(uint64) { return ""; } string to_hex(int64) { return ""; }
  uint64 hex_decode(string) { return 0; } string hex_encode(string) { return ""; }
  string base64_encode(string) { return ""; } string base64_decode(string) { return ""; }
  string wide_to_string(array<uint8>,bool=false) { return ""; }
  float random_float(float,float) { return 0.0f; } int random_int(int,int) { return 0; }
  uint64 random_u64(uint64,uint64) { return 0; } int64 random_i64(int64,int64) { return 0; }
  double random_double(double,double) { return 0.0; } void seed_random(uint32) {}
  string system_time(bool use_12h=false) { return ""; } uint64 tickcount() { return 0; }
  uint64 time_ms(uint64,uint64) { return 0; } uint64 time_us(uint64,uint64) { return 0; }
  uint64 time_ns(uint64,uint64) { return 0; } uint64 time_now() { return 0; }
  string get_username() { return ""; }
}
namespace console {
  void log(string) {} void log(int) {} void log(uint) {} void log(uint64) {}
  void log(float) {} void log(double) {} void log(bool) {}
  void log(string,int,int,int) {} void log(string,int,int,int,int) {}
  void warn(string) {} void error(string) {} void clear() {}
}
namespace alert {
  void show(string) {} void show(string,int,int,int) {}
  void show(string,int,int,int,float) {} void dismiss() {}
}
namespace file {
  bool exists(string) { return false; } bool write(string,string) { return false; }
  bool append(string,string) { return false; } bool read(string,string &out) { return false; }
  bool remove(string) { return false; } bool size(string,uint64 &out) { return false; }
  bool write_bytes(string,array<uint8>) { return false; }
  bool append_bytes(string,array<uint8>) { return false; }
  array<uint8>@ read_bytes(string) { return null; }
}
namespace dir {
  bool exists(string) { return false; } bool create(string) { return false; }
  bool remove(string) { return false; } array<string>@ list(string) { return null; }
}
namespace input {
  void mouse_move(int,int) {} bool mouse_press() { return false; }
  bool mouse_release() { return false; } bool mouse_click() { return false; }
  void mouse_pos(int &out,int &out) {} bool key_active(int) { return false; }
  bool key_toggled(int) { return false; } void key_press(int) {}
  void key_release(int) {} void key_tap(int) {}
}
namespace hash {
  uint32 crc32(const array<uint8> &in) { return 0; }
  uint64 fnv1a(const array<uint8> &in) { return 0; }
}
namespace math {
  const double PI=3.14159265358979323846; const double TAU=6.28318530717958647692;
  const double RAD2DEG=57.29577951308232087680; const double DEG2RAD=0.01745329251994329577;
  matrix4x4 multiply_matrix(matrix4x4,matrix4x4) { return matrix4x4(); }
  matrix4x4 rotation_matrix(vec3,vec3) { return matrix4x4(); }
  vec3 rotated_vector(vec3,vec4) { return vec3(); }
  vec3 forward_vector(vec2) { return vec3(); }
  vec3 right_vector(vec2) { return vec3(); }
  vec3 up_vector(vec2) { return vec3(); }
  vec2 vec_to_angles(vec3) { return vec2(); }
  vec3 angles_to_vec(vec2) { return vec3(); }
  double normalize_angle(double,angle_range) { return 0.0; }
  double angle_diff(double,double) { return 0.0; }
  double calculate_fov(vec2,vec2) { return 0.0; }
  vec2 calculate_angle(vec3,vec3) { return vec2(); }
  vec2 clamp_angles(vec2,angle_range) { return vec2(); }
  vec2 smooth_angles(vec2,vec2,angle_range,double,double,double) { return vec2(); }
  vec2 unreal_rotation_to_radians(vec3) { return vec2(); }
  double unreal_calculate_fov(vec3,vec3,vec3) { return 0.0; }
  vec2 unreal_calculate_angle(vec3,vec3,vec3) { return vec2(); }
  vec2 unreal_smooth_rotation(vec3,vec3,vec3,double,double,double) { return vec2(); }
}
namespace source  { bool w2s(vec3,matrix4x4,vec2 &out) { return false; } uint64 get_entity(uint64,uint64) { return 0; } }
namespace source2 { bool w2s(vec3,matrix4x4,vec2 &out) { return false; } uint64 get_controller(uint64,uint64) { return 0; } uint64 get_pawn(uint64,uint64,uint64) { return 0; } }
namespace unity  { bool w2s(vec3,matrix4x4,vec2 &out) { return false; } }
f_view_cache build_view_cache(f_view_info i,bool b=false) { f_view_cache c; return c; }
namespace unreal {
  f_view_cache build_view_cache(f_view_info,bool=false) { f_view_cache c; return c; }
  bool w2s(vec3,f_view_cache,vec2 &out) { return false; }
}
namespace json {
  json_obj@ parse(string) { return null; }
  json_obj@ array() { return null; }
  json_obj@ object() { return null; }
  json_obj@ parse(string,string &out) { return null; }
  string stringify(json_obj@,bool=false) { return ""; }
}


// ── Third-party drop-in: echo-esp-preview (not Echo API) ─────────────────────
class label_info_t { bool enabled; int position; int slot; int font; int font_size; color col; color col_occluded; };
class bar_info_t { bool enabled; int position; int slot; bool has_style; int style_index; color col; color col_occluded; };
class box_info_t { bool enabled; int style_index; color col; color col_occluded; };
class preview_global {
  int register_bounding_box(checkbox,color_picker,color_picker) { return 0; }
  int register_label(string,checkbox,color_picker,color_picker,int,int,int) { return 0; }
  int register_bar(checkbox,color_picker,color_picker,int) { return 0; }
  label_info_t get_label_info(int) { label_info_t i; return i; }
  bar_info_t get_bar_info(int) { bar_info_t i; return i; }
  box_info_t get_box_info() { box_info_t i; return i; }
  void load(string) {} void save(string) {} void draw() {}
}
preview_global g_preview;
namespace esp_layout {
  void bar_rect(float,float,float,float,bar_info_t,vec2 &out,vec2 &out) {}
  int label_bar_offset(int,array<int>) { return 0; }
  vec2 anchor_for_side(float,float,float,float,int,int,float,vec2) { return vec2(); }
  const float label_row_spacing = 4.0f;
}

// Unreal helper types are used unqualified by scripts.
class f_view_info { vec3 location; vec3 rotation; float fov; f_view_info(){} };
class f_view_cache { int dummy; f_view_cache(){} };
class u_bone_array { int dummy; u_bone_array(){} bool valid(){return false;} uint32 count(){return 0;} };

// ── threading, mutex, atomics ────────────────────────────────────────────────
class mutex { void lock(){} void unlock(){} bool try_lock(){return false;} void lock_shared(){} void unlock_shared(){} };
mutex@ create_mutex() { return null; }
void create_thread(int tps, thread_callback@ cb) { }
void on_render(thread_callback@ cb) { }
void sleep(uint ms) { }

// ── http / websocket ─────────────────────────────────────────────────────────
funcdef void ws_open();
funcdef void ws_message(string);
funcdef void ws_close();
funcdef void ws_error(int,string);
class http_response { http_response(){} string body; int status; };
namespace http {
  void get(string url, http_response@ cb) { }
  void post(string url, string body, http_response@ cb) { }
}
namespace ws {
  void connect(string url, ws_open@ on_open, ws_message@ on_msg, ws_close@ on_disc, ws_error@ on_err) { }
  void disconnect() { }
  bool is_connected() { return false; }
  void send(string msg) { }
  void reconnect() { }
}
