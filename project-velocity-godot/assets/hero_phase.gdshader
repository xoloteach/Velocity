shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform vec3 core_tint : source_color = vec3(0.32, 0.86, 1.0);
uniform vec3 edge_tint : source_color = vec3(1.0, 0.78, 0.44);
uniform float pulse_speed = 9.0;

void fragment() {
	float ndv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, 2.2);
	float scan = 0.5 + 0.5 * sin(UV.y * 42.0 - TIME * pulse_speed);
	float shimmer = 0.72 + 0.28 * sin(TIME * 16.0 + UV.x * 14.0);
	vec3 col = mix(core_tint, edge_tint, clamp(fresnel * 1.15 + scan * 0.22, 0.0, 1.0));
	ALBEDO = col * 0.65;
	EMISSION = col * (0.85 + fresnel * 1.7 + scan * 0.35) * shimmer;
	ROUGHNESS = 0.22;
	METALLIC = 0.15;
	ALPHA = clamp(0.28 + fresnel * 0.58 + scan * 0.12, 0.24, 0.90);
}
