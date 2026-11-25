shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 tint : source_color;
uniform vec4 highlight : source_color;
uniform int enchantment;
varying vec3 item_position;

void vertex() {
	item_position = VERTEX;
}

float ribbon(float phase, float width) {
	return pow(0.5 + 0.5 * cos(phase * TAU), width);
}

void fragment() {
	vec3 p = item_position;
	float band;
	float detail;
	if (enchantment == 1) {
		float slide = dot(p, vec3(1.0, 1.25, 0.64)) - TIME * 0.41;
		band = ribbon(slide, 5.0);
		detail = ribbon(slide * 2.0 + 0.23, 12.0) * band;
	} else if (enchantment == 2) {
		float slide = dot(p, vec3(0.9, -1.35, 0.85)) + TIME * 0.63;
		band = max(ribbon(slide, 8.0), 0.65 * ribbon(slide - 0.16, 14.0));
		detail = band * (0.55 + 0.45 * sin(TIME * 4.5));
	} else {
		float scan = dot(p, vec3(-0.42, 2.25, 0.62)) - TIME * 0.82;
		band = ribbon(scan, 15.0);
		detail = band * ribbon(dot(p, vec3(3.0, 0.5, 3.0)) + TIME * 0.29, 3.0);
	}
	ALBEDO = mix(tint.rgb, highlight.rgb, detail);
	ALPHA = 0.035 + 0.55 * band;
}
