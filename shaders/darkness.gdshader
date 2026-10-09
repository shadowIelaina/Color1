shader_type canvas_item;

// 塞尔达式迷宫暗房遮罩：一整块黑色，在光源处挖出透明圆洞。
// 洞内露出正常亮度的场景，洞外纯黑；边缘由 softness 软化。
// 本 shader 挂在覆盖全世界的 Polygon2D 上（节点在原点），
// 所以顶点 VERTEX 即世界坐标，直接和 light_pos（也是世界坐标）比较。

uniform vec4 dark_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float darkness : hint_range(0.0, 1.0) = 0.0; // 0 = 无黑暗，1 = 全黑
uniform float softness : hint_range(0.0, 0.5) = 0.18; // 光斑边缘软化（占半径比例）
uniform int light_count = 0;
uniform vec2 light_pos[16];
uniform float light_radius[16];

varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

void fragment() {
	float coverage = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= light_count) {
			break;
		}
		float r = max(light_radius[i], 0.001);
		float d = distance(world_pos, light_pos[i]);
		coverage = max(coverage, 1.0 - smoothstep(r * (1.0 - softness), r, d));
	}
	float a = darkness * (1.0 - coverage);
	COLOR = vec4(dark_color.rgb, a * dark_color.a);
}
