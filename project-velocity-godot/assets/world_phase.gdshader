shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 cyan : source_color = vec4(0.41, 0.88, 1.0, 1.0);
uniform float motion = 1.0;
varying vec3 point;

void vertex() {
	point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 coordinate = vec2(point.z, point.y) * 1.75;
	vec2 mask = fract(coordinate + vec2(0.0, TIME * motion * 0.56));
	float stroke = max(1.0 - smoothstep(0.045, 0.14, min(mask.x, 1.0 - mask.x)),
		1.0 - smoothstep(0.037, 0.115, min(mask.y, 1.0 - mask.y)));
	float wave = 0.54 + 0.38 * sin((point.y + point.z * 0.22) * 8.0 - TIME * motion * 2.2);
	ALBEDO = mix(vec3(0.035, 0.18, 0.24), cyan.rgb, max(stroke * 0.75, wave * 0.25));
	EMISSION = cyan.rgb * (stroke * 0.26 + wave * 0.12);
}
