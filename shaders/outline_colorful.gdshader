shader_type canvas_item;

// 选中提示描边（彩虹版）：把物体自带黑色描边整条点亮为流动彩虹，
// 不再画细虚线。识别「自带黑色描边」的逻辑同 outline.gdshader。

// 判定“自带黑色描边”的亮度阈值。
uniform float dark_threshold : hint_range(0.0, 0.6) = 0.25;
// 彩虹流动速度（对应 Colorful 里的 TIME * 0.5）。
uniform float hue_speed : hint_range(0.0, 2.0) = 0.5;
// 彩虹在贴图上的分布密度（对应 Colorful 里的 (UV.x + UV.y) * 0.25）。
uniform float hue_spread : hint_range(0.0, 2.0) = 0.25;

vec3 hsv2rgb(vec3 c)
{
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float a = tex.a;
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));

	// 自带黑色描边：不透明且足够暗 → 整条描边点亮。
	float dark = 1.0 - smoothstep(dark_threshold - 0.08, dark_threshold + 0.08, lum);
	float on_outline = step(0.5, a) * dark;

	// 彩虹颜色：套用 Colorful.gdshader 的 HSV 效果。
	float hue = (UV.x + UV.y) * hue_spread + mod(TIME * hue_speed, 1.0);
	vec3 rainbow = hsv2rgb(vec3(hue, 0.6, 1.0));

	COLOR = vec4(rainbow, on_outline);
}
