shader_type spatial;
render_mode cull_back, diffuse_lambert;

varying vec3 point;

void vertex() {
	point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grain(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	float u = point.z;
	float y = point.y;
	float scene = grain(vec2(floor(u / 12.0), step(0.0, point.x)));
	vec3 light = mix(vec3(0.47, 0.27, 0.10), vec3(0.20, 0.33, 0.31), step(0.78, scene));
	float luminous_top = smoothstep(1.1, 2.95, y);
	float columns = 0.80 + 0.11 * sin(u * 1.77 + scene * 7.8) + 0.09 * sin(u * 3.48);
	float glass = 0.05 * sin(u * 0.92 - y * 2.28);
	float objects = grain(vec2(floor(u * 6.0), floor(y * 1.69)));
	float object_height = 0.17 + objects * 0.22;
	float display = (1.0 - step(object_height, fract(y * 1.69))) * smoothstep(0.24, 0.36, objects);
	float shelf = 1.0 - smoothstep(0.035, 0.070, abs(fract(y * 1.69) - 0.96));
	float furnishing = mix(display * 0.36 + shelf * 0.16, display * 0.12, step(0.51, scene));
	float lobby_wall = 0.94 + sin(u * 1.12) * 0.062;
	float interior = (0.42 + luminous_top * 0.43) * columns * (1.0 - furnishing);
	ALBEDO = light * interior * lobby_wall + vec3(0.038, 0.054, 0.062) * (1.0 + glass);
	EMISSION = light * (0.13 + interior * 0.71);
	ROUGHNESS = 0.42;
	METALLIC = 0.29;
}
