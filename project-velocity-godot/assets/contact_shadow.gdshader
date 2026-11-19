shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float opacity : hint_range(0.0, 1.0) = 0.56;
uniform vec4 tint : source_color = vec4(0.02, 0.03, 0.05, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float mask = 1.0 - smoothstep(0.18, 1.0, r);
	ALBEDO = tint.rgb;
	ALPHA = mask * mask * opacity;
}
