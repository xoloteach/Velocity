shader_type spatial;
render_mode cull_back, diffuse_lambert;

uniform vec4 base : source_color = vec4(0.19, 0.22, 0.26, 1.0);
uniform float reflections : hint_range(0.0, 1.0) = 0.8;
uniform float wetness : hint_range(0.0, 1.0) = 0.7;
uniform float material_detail : hint_range(0.0, 1.0) = 0.5;
varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float grain(vec2 p) {
	vec3 state = fract(vec3(p.xyx) * 0.1031);
	state += dot(state, state.yzx + 33.33);
	return fract((state.x + state.y) * state.z);
}

void fragment() {
	vec2 grit_coord = floor(world_xz * 54.0);
	float grit = grain(grit_coord);
	float large = 0.5;
	float puddle = 0.55;
	float tire_wear = max(0.0, 1.0 - abs(abs(world_xz.x) - 3.7) * 0.95) * 0.55 + max(0.0, 1.0 - abs(abs(world_xz.x) - 5.1) * 1.6) * 0.45;
	float seam = 0.0;
	if (material_detail > 0.1) {
		large = grain(floor(world_xz * 1.25));
		float wave = sin(world_xz.x * 0.44 + sin(world_xz.y * 0.11) * 1.5) * cos(world_xz.y * 0.16 + sin(world_xz.x * 0.28));
		puddle = smoothstep(0.18, 0.78, wave * 0.5 + 0.5);
		float crack_x = abs(fract(world_xz.x * 0.125) - 0.5);
		float crack_z = abs(fract(world_xz.y * 0.0625) - 0.5);
		seam = (1.0 - smoothstep(0.0, 0.009, crack_x)) * 0.45 + (1.0 - smoothstep(0.0, 0.008, crack_z)) * 0.35;
	}
	vec3 surface = base.rgb * (0.86 + 0.16 * grit + 0.07 * large - tire_wear * 0.10 - puddle * wetness * 0.14 - seam * 0.18);
	ALBEDO = surface;
	ROUGHNESS = mix(0.92, 0.24, puddle * wetness);
	METALLIC = mix(0.04, 0.22, puddle * wetness);

	// Warm sodium/amber & cool cyan metropolitan puddle reflections along avenues
	float lane = 1.0 - smoothstep(0.10, 6.4, abs(abs(world_xz.x) - 6.0));
	float repeat_distance = abs(mod(world_xz.y + 4.0, 24.0) - 12.0);
	float near_station = 1.0 - smoothstep(0.3, 12.0, abs(world_xz.y + 52.4));
	float near_crossing = 1.0 - smoothstep(0.2, 10.0, abs(world_xz.y + 4.0));
	float along = max(1.0 - smoothstep(0.25, 11.5, repeat_distance), max(near_station, near_crossing));
	float zone = step(-315.0, world_xz.y) * step(world_xz.y, 60.0);
	float reach = lane * along * along;
	float smear = 0.55;
	if (material_detail > 0.1) {
		smear = 0.32 + 0.68 * smoothstep(0.30, 0.85, sin(world_xz.x * 4.2 + sin(world_xz.y * 0.65) * 0.48) * 0.5 + 0.5);
	}
	float road_reflect = zone * reflections * wetness * reach * (0.35 + 0.65 * puddle) * smear;
	vec3 tint = mix(vec3(0.38, 0.16, 0.055), vec3(0.055, 0.18, 0.26), step(0.0, world_xz.x));
	EMISSION = tint * road_reflect + vec3(0.005, 0.009, 0.015) * wetness * puddle;
}
