shader_type spatial;
render_mode cull_back, diffuse_lambert;

uniform vec4 blue : source_color = vec4(0.12, 0.34, 0.44, 1.0);
uniform float motion = 0.0;
uniform float detail : hint_range(0.0, 1.0) = 1.0;
varying vec2 position_xz;

void vertex() {
	position_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float shift = TIME * motion;
	float interference = sin(position_xz.x * 0.26 + position_xz.y * 0.19 - shift * 0.66);
	float broad = sin(position_xz.y * 1.16 + position_xz.x * 0.37 + shift * 0.79 + interference * 1.46);
	float ripple = sin(position_xz.x * 1.32 - position_xz.y * 3.20 + shift * 1.09 + broad * 1.31);
	float foam = smoothstep(0.78, 0.97, broad * 0.52 + ripple * 0.28 + interference * 0.20);
	float fresnel = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.5);
	vec3 deep = blue.rgb * (0.64 + 0.10 * broad + 0.10 * ripple * detail + 0.06 * interference);
	ALBEDO = mix(deep, vec3(0.56, 0.78, 0.88), fresnel * 0.55 + foam * detail * 0.22);
	EMISSION = vec3(0.06, 0.13, 0.17) * (0.28 + foam * detail * 0.65 + fresnel * 0.35);
	ROUGHNESS = clamp(0.18 + ripple * 0.10, 0.08, 0.38);
	METALLIC = 0.32;
}
