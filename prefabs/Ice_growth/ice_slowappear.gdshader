// grow.gdshader
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2  grow_dir = vec2(1.0, 0.0);
uniform vec4  edge_color : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform float edge_soft  : hint_range(0.001, 0.2) = 0.015;
uniform float edge_glow  : hint_range(0.0, 2.0)   = 1.0;
uniform float glow_strength : hint_range(0.0, 1.0) = 1.0;   // 新增

void fragment() {
    vec4 base = COLOR * texture(TEXTURE, UV);

    float axis = UV.x * abs(grow_dir.x) + UV.y * abs(grow_dir.y);
    if (grow_dir.x < 0.0 || grow_dir.y < 0.0) {
        axis = 1.0 - axis;
    }

    float d = progress - axis;
    float visible = smoothstep(-edge_soft, edge_soft, d);

    // 关键：乘以 glow_strength
    float glow = (1.0 - smoothstep(0.0, edge_soft * 3.0, abs(d))) * edge_glow * glow_strength;

    vec3 col = mix(base.rgb, edge_color.rgb, glow);
    float a = clamp(base.a * visible + glow * 0.6, 0.0, 1.0);

    COLOR = vec4(col, a);
}