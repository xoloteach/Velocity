shader_type sky;

uniform vec4 zenith : source_color = vec4(0.10, 0.17, 0.32, 1.0);
uniform vec4 haze : source_color = vec4(0.46, 0.34, 0.42, 1.0);
uniform vec4 soft_cloud : source_color = vec4(0.76, 0.48, 0.38, 1.0);
uniform float celestial = 1.0;
uniform float daylight = 0.0;
uniform float cloud_detail : hint_range(0.0,1.0) = 0.6;

float speck(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float cloud_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(point));
	return mix(mix(speck(cell), speck(cell + vec2(1.0, 0.0)), blend.x), mix(speck(cell + vec2(0.0, 1.0)), speck(cell + vec2(1.0, 1.0)), blend.x), blend.y);
}

void sky() {
	vec3 ray = normalize(EYEDIR);
	float height = max(ray.y, 0.0);
	float above = smoothstep(-0.18, 0.06, ray.y);
	vec3 background = mix(haze.rgb, zenith.rgb, pow(smoothstep(0.0, 0.72, height), 0.56));
	background = mix(zenith.rgb * 0.58, background, above);

	// Warm golden-hour / city horizon atmospheric glow
	float horizon_band = exp(-height * 9.5) * above;
	vec3 glow_tint = mix(soft_cloud.rgb * 0.45, vec3(0.95, 0.78, 0.58) * 0.32, daylight);
	background += glow_tint * horizon_band * 0.48;

	// Layered clouds with subtle slow drift
	vec2 cloud_dir = ray.xz / (0.20 + height) + vec2(3.2 + TIME * 0.006, -1.8 + TIME * 0.003);
	float cloud = 0.0;
	if (cloud_detail > 0.0) {
		float coarse = cloud_noise(cloud_dir * vec2(1.9, 1.15));
		float mid = cloud_noise(cloud_dir * vec2(3.8, 2.5) + 3.7);
		float fine = cloud_detail > 0.7 ? cloud_noise(cloud_dir * vec2(7.5, 5.1) - 1.9) : 0.5;
		cloud = smoothstep(0.48, 0.74, coarse * 0.58 + mid * 0.28 + fine * 0.14);
	}
	float horizon_tint = 1.0 - smoothstep(0.02, 0.58, height);
	float light_side = smoothstep(-0.82, 0.52, ray.x + ray.z * 0.28);
	background = mix(background, soft_cloud.rgb * (0.85 + 0.30 * light_side), cloud * horizon_tint * (0.18 + 0.28 * light_side) * above);

	// Moon & stars at night/dusk, crisp solar halo in daytime
	vec3 body_dir = normalize(vec3(-0.14, 0.28, -0.94));
	float body_dot = dot(ray, body_dir);
	float night = (1.0 - daylight) * celestial;
	float moon_disc = smoothstep(0.99958, 0.99970, body_dot);
	float moon_halo = pow(smoothstep(0.960, 0.9999, body_dot), 2.5);
	float stars = step(0.991, speck(floor(SKY_COORDS * 560.0))) * smoothstep(0.18, 0.90, height);
	vec3 night_sky = vec3(0.82, 0.88, 0.98) * (moon_disc * 0.82 + moon_halo * 0.14 + stars * 0.28) * night;

	vec3 sun_dir = normalize(vec3(0.42, 0.46, -0.78));
	float sun_dot = dot(ray, sun_dir);
	float sun_disc = smoothstep(0.9991, 0.9995, sun_dot);
	float sun_halo = pow(smoothstep(0.90, 0.9999, sun_dot), 4.0);
	vec3 day_sky = vec3(1.0, 0.92, 0.74) * (sun_disc * 0.90 + sun_halo * 0.26) * daylight * celestial;

	COLOR = background + night_sky + day_sky;
}
