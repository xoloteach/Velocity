shader_type spatial;
render_mode cull_back, diffuse_lambert;

uniform float motion = 1.0;
varying vec2 ground;

void vertex() {
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 axis = ground * mat2(vec2(0.74, 0.67), vec2(-0.67, 0.74));
	float a = abs(fract((axis.x + axis.y * 0.21) / 6.7) - 0.5);
	float b = abs(fract((axis.y - axis.x * 0.31) / 6.1) - 0.5);
	float veins = 1.0 - smoothstep(0.004, 0.027, min(a, b));
	float tone = 0.51 + 0.25 * sin(axis.x * 0.37 + axis.y * 0.26) + 0.23 * sin(axis.y * 0.88);
	float pulse = 0.60 + 0.20 * sin(ground.y * 0.23 + ground.x * 0.35 - TIME * motion * 0.70);
	vec3 tint = mix(vec3(0.035, 0.093, 0.13), vec3(0.11, 0.067, 0.155), tone);
	ALBEDO = tint * (0.43 + tone * 0.18) + vec3(0.012, 0.017, 0.038);
	EMISSION = tint * (0.35 + veins * pulse * 0.63);
	ROUGHNESS = 0.75;
}
