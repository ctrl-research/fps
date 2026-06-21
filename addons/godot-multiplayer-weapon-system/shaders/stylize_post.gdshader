// Global comic-book stylise post-process.
//
// Two effects over the rendered 3D frame:
//   1. Dynamic colour remapping — Classic posterises luminance (keeping hue),
//        Realistic does a saturation + contrast grade.
//   2. Sobel edge outline — luminance edge-detect that inks comic outlines.
//
// Sky exemption (no depth buffer on gl_compatibility): a mode using DayNightSky
// clears the 3D background to a SENTINEL colour instead of an engine sky. Where
// the rendered pixel is that sentinel, this shader reconstructs the procedural
// sky from the camera ray and outputs it un-stylised, so the sky stays smooth
// while the world is stylised. Mounted below the HUD by PostProcess.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// 0 = Classic posterise, 1 = Realistic grade.
uniform int color_mode = 0;
uniform float classic_bands : hint_range(2.0, 8.0) = 4.0;

uniform bool outline_enabled = true;
uniform float outline_thickness : hint_range(0.5, 4.0) = 1.6;
uniform float outline_threshold : hint_range(0.02, 1.0) = 0.30;
uniform vec3 outline_color : source_color = vec3(0.0);

uniform float contrast : hint_range(0.5, 2.5) = 1.18;
uniform float saturation : hint_range(0.0, 2.5) = 1.4;

// Sky reconstruction (driven by PostProcess / DayNightSky).
uniform bool sky_enabled = false;
uniform vec3 sky_sentinel : source_color = vec3(1.0, 0.0, 1.0);
uniform vec3 sky_sun_dir = vec3(0.0, -1.0, 0.0);  // light travel direction
uniform float sky_day = 1.0;       // 1 = day, 0 = night
uniform float sky_sunset = 0.0;    // peaks at sunset
uniform mat3 cam_basis;
uniform float cam_tan = 0.5;       // tan(vertical_fov / 2)
uniform float cam_aspect = 1.78;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 classic_posterize(vec3 c) {
	float l = luma(c);
	float ql = (floor(l * classic_bands) + 0.5) / classic_bands;
	return clamp(c * (ql / max(l, 0.001)), 0.0, 1.0);
}

vec3 realistic_grade(vec3 c) {
	vec3 sat = mix(vec3(luma(c)), c, saturation);
	return clamp((sat - 0.5) * contrast + 0.5, 0.0, 1.0);
}

float sobel(vec2 uv, vec2 px) {
	float tl = luma(texture(screen_tex, uv + vec2(-px.x, -px.y)).rgb);
	float t  = luma(texture(screen_tex, uv + vec2(0.0, -px.y)).rgb);
	float tr = luma(texture(screen_tex, uv + vec2(px.x, -px.y)).rgb);
	float l  = luma(texture(screen_tex, uv + vec2(-px.x, 0.0)).rgb);
	float r  = luma(texture(screen_tex, uv + vec2(px.x, 0.0)).rgb);
	float bl = luma(texture(screen_tex, uv + vec2(-px.x, px.y)).rgb);
	float b  = luma(texture(screen_tex, uv + vec2(0.0, px.y)).rgb);
	float br = luma(texture(screen_tex, uv + vec2(px.x, px.y)).rgb);
	float gx = -tl - 2.0 * l - bl + tr + 2.0 * r + br;
	float gy = -tl - 2.0 * t - tr + bl + 2.0 * b + br;
	return sqrt(gx * gx + gy * gy);
}

// --- Procedural sky (mirrors DayNightSky's sky shader) ---
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

vec3 compute_sky(vec3 dir) {
	float up = clamp(dir.y, 0.0, 1.0);
	vec3 day_top = vec3(0.20, 0.42, 0.82);
	vec3 day_hor = vec3(0.70, 0.80, 0.95);
	vec3 night_top = vec3(0.01, 0.02, 0.06);
	vec3 night_hor = vec3(0.04, 0.06, 0.13);
	vec3 sunset = vec3(0.95, 0.45, 0.20);

	vec3 top = mix(night_top, day_top, sky_day);
	vec3 hor = mix(night_hor, day_hor, sky_day);
	hor = mix(hor, sunset, sky_sunset * (1.0 - up));
	vec3 col = mix(hor, top, pow(up, 0.5));

	vec3 to_sun = -normalize(sky_sun_dir);
	float sd = dot(normalize(dir), to_sun);
	col += vec3(1.0, 0.95, 0.85) * smoothstep(0.9990, 0.9997, sd) * 6.0;
	col += vec3(1.0, 0.9, 0.7) * pow(max(sd, 0.0), 48.0) * 0.4 * sky_day;

	if (dir.y > 0.02) {
		vec2 uv = dir.xz / (dir.y + 0.2) * 1.2 + TIME * 0.006;
		float c = smoothstep(0.45, 0.85, fbm(uv)) * smoothstep(0.02, 0.25, dir.y);
		vec3 cloud = mix(vec3(0.08, 0.09, 0.13), vec3(1.0), sky_day);
		cloud = mix(cloud, sunset, sky_sunset * 0.5);
		col = mix(col, cloud, c * 0.8);
	}
	return col;
}

vec3 ray_from_uv(vec2 uv) {
	vec2 ndc = uv * 2.0 - 1.0;
	vec3 v = vec3(ndc.x * cam_tan * cam_aspect, -ndc.y * cam_tan, -1.0);
	return normalize(cam_basis * v);
}

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	// Sentinel background = sky: reconstruct it un-stylised.
	if (sky_enabled && distance(src, sky_sentinel) < 0.15) {
		COLOR = vec4(compute_sky(ray_from_uv(SCREEN_UV)), 1.0);
		return;
	}
	vec3 col = (color_mode == 0) ? classic_posterize(src) : realistic_grade(src);
	if (outline_enabled) {
		float e = sobel(SCREEN_UV, SCREEN_PIXEL_SIZE * outline_thickness);
		col = mix(col, outline_color, step(outline_threshold, e));
	}
	COLOR = vec4(col, 1.0);
}
