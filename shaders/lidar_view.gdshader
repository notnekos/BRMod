shader_type canvas_item;
render_mode unshaded, blend_disabled;

float difference(vec4 center, vec4 neighbor) {
	return max(abs(center.a - neighbor.a), length(center.rgb - neighbor.rgb));
}

float noise(vec2 p) {
	return fract(sin(dot(p, vec2(17.13, 43.73))) * 43758.54);
}

vec3 point_color(float scan_class) {
	if (scan_class < 0.5) return vec3(0.14, 0.60, 0.51);
	if (scan_class < 1.5) return vec3(0.40, 0.86, 0.76);
	if (scan_class < 2.5) return vec3(0.71, 1.0, 0.90);
	if (scan_class < 3.5) return vec3(1.0, 0.70, 0.24);
	if (scan_class < 4.5) return vec3(1.0, 0.45, 0.84);
	return vec3(0.37, 0.84, 1.0);
}

void fragment() {
	vec2 pitch = vec2(3.0, 3.0);
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec2 tile_pos = UV / (texel * pitch);
	vec2 tile = floor(tile_pos);
	vec2 offset = texel * vec2(3.5, 3.5);
	vec2 sample_uv = (tile + 0.5) * pitch * texel;
	vec4 center = texture(TEXTURE, sample_uv);
	float edge = 0.0;
	edge = max(edge, difference(center, texture(TEXTURE, sample_uv + vec2(offset.x, 0.0))));
	edge = max(edge, difference(center, texture(TEXTURE, sample_uv - vec2(offset.x, 0.0))));
	edge = max(edge, difference(center, texture(TEXTURE, sample_uv + vec2(0.0, offset.y))));
	edge = max(edge, difference(center, texture(TEXTURE, sample_uv - vec2(0.0, offset.y))));

	vec2 within_tile = fract(tile_pos);
	float dot_mask = step(0.12, within_tile.x) * step(within_tile.x, 0.78)
		* step(0.17, within_tile.y) * step(within_tile.y, 0.75);
	float scatter = noise(tile);
	float line = 1.0 - smoothstep(0.0, 0.11, fract(UV.y - TIME * 0.35));
	float signal = smoothstep(0.032, 0.112, edge) * step(0.045, scatter);
	float scan_class = dot(step(vec3(0.50), center.rgb), vec3(1.0, 2.0, 4.0));
	vec3 glow = point_color(scan_class) * signal * dot_mask * step(0.5, center.a);
	glow *= (0.56 + 0.36 * scatter + 0.25 * line);
	COLOR = vec4(vec3(0.003, 0.009, 0.012) + glow, 1.0);
}
