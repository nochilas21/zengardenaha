shader_type canvas_item;

uniform float sway_angle = 0.06;    // max bend in radians (0.06 is about 3.5 degrees)
uniform float sway_speed = 1.5;
uniform float phase = 0.0;
uniform float droop = 0.0;          // 0 healthy, 1 fully wilted
uniform float desaturate = 0.0;

void vertex() {
    vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;

    // local position of the sprite's bottom-center, whatever offset/centered you use
    vec2 pivot = VERTEX - (UV - vec2(0.5, 1.0)) * tex_size;

    float height = 1.0 - UV.y;   // 0 at base, 1 at top

    float wave = sin(TIME * sway_speed + phase)
               + 0.3 * sin(TIME * sway_speed * 2.3 + phase * 1.7);
    float angle = (wave * sway_angle + droop * 0.4) * height;

    vec2 d = VERTEX - pivot;
    float s = sin(angle);
    float c = cos(angle);
    VERTEX = pivot + vec2(d.x * c - d.y * s, d.x * s + d.y * c);
}

void fragment() {
    vec4 col = texture(TEXTURE, UV);
    float g = dot(col.rgb, vec3(0.3, 0.59, 0.11));
    col.rgb = mix(col.rgb, vec3(g) * vec3(0.8, 0.7, 0.5), desaturate);
    COLOR = col;
}