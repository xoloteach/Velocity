shader_type spatial;
render_mode cull_back;

uniform vec4 mortar : source_color = vec4(0.17, 0.22, 0.25, 1);
uniform vec4 glass : source_color = vec4(0.045, 0.12, 0.17, 1);
uniform vec4 glow : source_color = vec4(0.84, 0.54, 0.27, 1);
varying vec3 point;
varying vec3 normal_world;

void vertex() {
	point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_world = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	float x = abs(normal_world.x) > 0.5 ? point.z : point.x;
	vec2 coord = vec2(x / 1.66, point.y / 2.62);
	vec2 cell = fract(coord);
	vec2 id = floor(coord);
	float seed = fract(sin(dot(id, vec2(14.311, 77.181))) * 13796.426);
	float pane = step(0.13, cell.x) * step(cell.x, 0.88) * step(0.22, cell.y)
		* step(cell.y, 0.90) * step(abs(cell.x - 0.52), 0.50)
		* step(0.027, abs(cell.x - 0.52)) * step(abs(normal_world.y), 0.5);
	float luminous = pane * step(0.80, seed);
	vec3 window = mix(glass.rgb * (0.72 + 0.3 * seed), glow.rgb * 0.62, luminous);
	ALBEDO = mix(mortar.rgb, window, pane);
	EMISSION = glow.rgb * luminous * 0.34;
	ROUGHNESS = mix(0.76, 0.43, pane);
	METALLIC = pane * 0.32;
}
