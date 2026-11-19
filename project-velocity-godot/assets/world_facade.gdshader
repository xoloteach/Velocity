shader_type spatial;
render_mode cull_back, diffuse_lambert;

uniform vec4 mortar : source_color = vec4(0.28, 0.32, 0.36, 1.0);
uniform vec4 tint : source_color = vec4(0.17, 0.30, 0.38, 1.0);
uniform vec4 window_light : source_color = vec4(0.91, 0.63, 0.29, 1.0);
uniform vec2 bay = vec2(1.75, 3.16);
uniform float lamps : hint_range(0.0, 1.0) = 0.8;
varying vec3 point;
varying vec3 normal_world;

void vertex() {
	point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_world = MODEL_NORMAL_MATRIX * NORMAL;
}

float seed_for(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	float along = abs(normal_world.x) > 0.5 ? point.z : point.x;
	vec2 coordinate = vec2(along, point.y + 0.11) / bay;
	vec2 cell = fract(coordinate);
	vec2 cell_id = floor(coordinate);
	float seed = seed_for(cell_id);
	float floor_seed = seed_for(vec2(cell_id.y, floor(along * 0.08)));
	float wall_face = 1.0 - step(0.55, abs(normal_world.y));

	// Architectural pilasters, horizontal floor spandrels & crisp window framing
	float border = step(0.13, cell.x) * (1.0 - step(0.87, cell.x));
	float window_band = step(0.24, cell.y) * (1.0 - step(0.86, cell.y));
	float mullion_v = step(0.022, abs(cell.x - 0.50));
	float mullion_h = step(0.022, abs(cell.y - 0.58));
	float glass = border * window_band * mullion_v * mullion_h * wall_face;

	// Stone sill shadow & architectural spandrel ledge
	float sill = smoothstep(0.18, 0.23, cell.y) * (1.0 - step(0.24, cell.y)) * border;
	float cornice_band = smoothstep(0.0, 0.09, cell.y) * (1.0 - smoothstep(0.10, 0.16, cell.y));
	float pilaster = 1.0 - smoothstep(0.0, 0.13, min(cell.x, 1.0 - cell.x));

	// Ground contact ambient occlusion at base of buildings
	float ground_ao = mix(0.62, 1.0, smoothstep(0.0, 6.5, point.y));
	float height_grad = mix(0.88, 1.08, smoothstep(4.0, 42.0, point.y));
	vec3 wall = mortar.rgb * (0.76 + floor_seed * 0.14 + cornice_band * 0.16 + pilaster * 0.10 - sill * 0.22) * ground_ao * height_grad;

	// Glass fresnel reflection + interior room depth / blinds
	float fresnel = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.4);
	vec3 sky_refl = mix(tint.rgb * 0.48, vec3(0.42, 0.56, 0.72), fresnel * 0.65);
	float blind_line = smoothstep(0.45, 0.90, cell.y) * step(0.42, seed);
	vec3 dark_glass = mix(sky_refl * (0.62 + cell.y * 0.45), tint.rgb * 0.28, blind_line * 0.55);

	// Natural warm/cool interior lighting occupancy (avoid garish solid yellow grid)
	float lit_prob = step(0.66, fract(seed * 1.73 + floor_seed * 0.41));
	float blind_mask = 1.0 - step(0.76, cell.y) * step(0.5, seed);
	float activated = lit_prob * blind_mask * lamps;
	vec3 room_hue = mix(window_light.rgb, vec3(0.76, 0.88, 1.0), step(0.84, seed) * 0.65);
	float interior_depth = 0.45 + 0.55 * (1.0 - abs(cell.x - 0.5) * 1.4) * (0.65 + 0.35 * cell.y);
	vec3 lit_pane = mix(dark_glass, room_hue * (0.58 + 0.34 * interior_depth), activated * 0.82);

	ALBEDO = mix(wall, lit_pane, glass);
	EMISSION = room_hue * glass * activated * (0.28 + seed * 0.36) * interior_depth;
	ROUGHNESS = mix(0.86, 0.22, glass);
	METALLIC = mix(0.04, 0.38, glass);
}
