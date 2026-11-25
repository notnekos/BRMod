shader_type spatial;
render_mode unshaded, cull_disabled;

// One bit per channel identifies the surface. The low part holds normals and range.
uniform vec3 scan_class;

void fragment() {
	vec3 normal = normalize(NORMAL);
	float range = 1.0 - exp(-length(VERTEX) * 0.045);
	vec3 surface = vec3(normal.xy * 0.5 + 0.5, range);
	vec3 data = scan_class * 0.75 + 0.025 + surface * 0.16;
	ALBEDO = OUTPUT_IS_SRGB ? data : pow(data, vec3(2.2));
}
