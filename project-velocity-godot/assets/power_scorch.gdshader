shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float remaining = 1.0;
uniform float pattern = 0.0;

void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float distance_to_center = length(point);
	float angle = atan(point.y, point.x);
	float rim_noise = 0.11 * sin(angle * 13.0 + pattern) + 0.055 * cos(angle * 29.0 - pattern);
	float mark = 1.0 - smoothstep(0.40 + rim_noise, 0.85 + rim_noise, distance_to_center);
	float crack = smoothstep(0.82, 1.0, sin(angle * 15.0 + pattern + distance_to_center * 15.0));
	float heat = max(0.0, (remaining - 0.73) * 3.7);
	vec3 carbon = vec3(0.025, 0.018, 0.017);
	vec3 orange = vec3(1.0, 0.32, 0.10);
	ALBEDO = mix(carbon, orange, crack * heat);
	ALPHA = mark * min(0.72, remaining * 1.7);
}
