shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 shards = vec2(4.0, 4.0);
uniform float seed_value = 0.0;
uniform float fall_strength = 0.7;
uniform float drift_strength = 0.2;
uniform float rotation_strength = 0.5;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	vec2 idx = floor(uv * shards);
	vec2 center = (idx + 0.5) / shards;
	float h1 = hash21(idx + seed_value);
	float h2 = hash21(idx + seed_value + 71.17);
	float h3 = hash21(idx + seed_value + 137.29);
	float delay = h1 * 0.45;
	float t = clamp((progress - delay) / max(1.0 - delay, 0.001), 0.0, 1.0);
	float tt = t * t;
	float rot = (h2 - 0.5) * 2.0 * rotation_strength * t;
	float c = cos(rot);
	float s = sin(rot);
	vec2 offset = vec2((h3 - 0.5) * 2.0 * drift_strength * t, fall_strength * tt);
	vec2 rel = uv - center - offset;
	vec2 src = center + vec2(c * rel.x + s * rel.y, -s * rel.x + c * rel.y);
	vec4 col = vec4(0.0);
	if (all(equal(floor(src * shards), idx))) {
		col = texture(TEXTURE, src);
		vec2 f = fract(uv * shards);
		float edge_dist = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		float crack = (1.0 - smoothstep(0.0, 0.04, edge_dist))
			* smoothstep(0.0, 0.06, progress)
			* (1.0 - smoothstep(0.15, 0.35, progress));
		col.rgb += crack * 0.6 * col.a;
		col.a *= 1.0 - t;
	}
	COLOR = col;
}
