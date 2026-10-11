shader_type canvas_item;

uniform float tilt : hint_range(-90.0, 90.0) = 30.0;
uniform float stretch : hint_range(0.5, 4.0) = 1.5;
uniform vec2 shadow_shift = vec2(0.0, 0.0);
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.4);
uniform float blur_near : hint_range(0.0, 8.0) = 4.0;
uniform float blur_far : hint_range(0.0, 4.0) = 0.5;
uniform float fade_distance : hint_range(0.0, 3.0) = 1.5;

varying vec2 main_uv;

void vertex() {
    vec2 uv_min = vec2(-2.0, -1.0);
    vec2 uv_max = vec2(3.0, 5.0);
    vec2 uv_size = uv_max - uv_min;
    main_uv = uv_min + UV * uv_size;
    // 修复：按主图中心对齐，而不是整个 UV 空间中心
    VERTEX = (main_uv - 0.5) * (1.0 / TEXTURE_PIXEL_SIZE);
}

void fragment() {
    vec4 main_tex = texture(TEXTURE, main_uv);
    float main_a = main_tex.a
        * step(0.0, main_uv.x) * step(main_uv.x, 1.0)
        * step(0.0, main_uv.y) * step(main_uv.y, 1.0);
    vec4 main_color = vec4(main_tex.rgb, main_a);

    vec2 pivot = vec2(0.5, 1.0);
    vec2 p = main_uv - shadow_shift;
    vec2 d_stretched = p - pivot;
    vec2 d_rot = vec2(d_stretched.x, d_stretched.y / stretch);

    float rad = radians(-(180.0 + tilt));
    vec2 d_s = vec2(d_rot.x * cos(rad) - d_rot.y * sin(rad),
                    d_rot.x * sin(rad) + d_rot.y * cos(rad));
    vec2 src = pivot + d_s;

    float dist = length(d_stretched);
    float t = clamp(dist / fade_distance, 0.0, 1.0);
    float blur = mix(blur_near, blur_far, t);
    float fade = mix(0.5, 1.0, t);

    vec2 ts = TEXTURE_PIXEL_SIZE * blur;
    float shadow_a = 0.0;
    vec2 s;

    s = src + vec2(-ts.x, -ts.y);
    shadow_a += texture(TEXTURE, s).a * step(0.0, s.x) * step(s.x, 1.0) * step(0.0, s.y) * step(s.y, 1.0);
    s = src + vec2(0.0, -ts.y);
    shadow_a += texture(TEXTURE, s).a * step(0.0, s.x) * step(s.x, 1.0) * step(0.0, s.y) * step(s.y, 1.0);
    s = src + vec2(ts.x, -ts.y);
    shadow_a += texture(TEXTURE, s).a * step(0.0, s.x) * step(s.x, 1.0) * step(0.0, s.y) * step(s.y, 1.0);
    s = src + vec2(-ts.x, 0.0);
    shadow_a += texture(TEXTURE, s).a * step(0.0, s.x) * step(s.x, 1.0) * step(0.0, s.y) * step(s.y, 1.0);
    s = src;
    shadow_a += texture(TEXTURE, s).a * step(0.0, s.x) * step(s.x, 1.0) * step(0.0, s.y) * step(s.y, 1.0);
    s = src + vec2(ts.x, 0.0);
    shadow_a += texture(TEXTURE, s).a * step(0.0, s.x) * step(s.x, 1.0) * step(0.0, s.y) * step(s.y, 1.0);
    s = src + vec2(-ts.x, ts.y);
    shadow_a += texture(TEXTURE, s).a * step(0.0, s.x) * step(s.x, 1.0) * step(0.0, s.y) * step(s.y, 1.0);
    s = src + vec2(0.0, ts.y);
    shadow_a += texture(TEXTURE, s).a * step(0.0, s.x) * step(s.x, 1.0) * step(0.0, s.y) * step(s.y, 1.0);
    s = src + vec2(ts.x, ts.y);
    shadow_a += texture(TEXTURE, s).a * step(0.0, s.x) * step(s.x, 1.0) * step(0.0, s.y) * step(s.y, 1.0);

    shadow_a /= 9.0;
    shadow_a *= fade;

    vec4 shadow_color_v = vec4(shadow_color.rgb, shadow_a * shadow_color.a);
    // × COLOR：自定义 shader 覆盖默认 shader 会吞掉 modulate/self_modulate，
    // 乘回 COLOR 才能让树的冻结/燃烧持续着色生效（影子是黑的 ×0 不受影响）。
    COLOR = mix(shadow_color_v, main_color, main_color.a) * COLOR;
}