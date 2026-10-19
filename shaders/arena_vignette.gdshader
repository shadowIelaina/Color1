shader_type canvas_item;

uniform vec4 edge_color : source_color = vec4(0.01, 0.02, 0.04, 0.85);
uniform float inner : hint_range(0.0, 1.0) = 0.28;
uniform float outer : hint_range(0.0, 1.0) = 0.72;

void fragment() {
	float d = distance(UV, vec2(0.5));
	float a = smoothstep(inner, outer, d);
	COLOR = vec4(edge_color.rgb, edge_color.a * a);
}
