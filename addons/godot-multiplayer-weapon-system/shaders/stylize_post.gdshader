// Dithered two-tone post-process (Mortal Sin-style).
//
// FLAT two-tone: each surface renders as one of two fixed brightness levels of
// its own colour (lit tone / shade tone). The actual lighting only drives the
// per-pixel DITHER density between them — so there are no smooth shading
// gradients; all shading is conveyed by the grain. Hue preserved so team colours
// stay readable.
//
// Sky exclusion: while the effect is on, DayNightSky clears the 3D background to
// a magenta SENTINEL; those pixels render as a smooth gradient, never dithered.
// Kept inline + branchless (no helper functions taking built-ins, no early
// return) — that form is what compiles reliably here.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float shade_strength : hint_range(0.0, 1.0) = 0.50;  // shadow tone brightness
uniform float lit_strength : hint_range(0.3, 1.2) = 0.95;    // lit tone brightness
uniform float shadow_low : hint_range(0.0, 1.0) = 0.02;      // dither range start
uniform float shadow_high : hint_range(0.0, 1.0) = 0.90;     // dither range end
uniform float grain_size : hint_range(1.0, 6.0) = 2.0;       // dither grain in pixels
uniform float light_contrast : hint_range(0.5, 4.0) = 1.4;   // how sharply lit/shade split
uniform float saturation : hint_range(0.0, 2.5) = 1.4;       // colour punch (Mortal Sin palette)

// Sky exclusion (driven by PostProcess / DayNightSky).
uniform bool sky_enabled = false;
uniform float sky_day = 1.0;
uniform float sky_sunset = 0.0;
uniform float sky_red = 0.0;     // 0 = clear, 1 = fully red sky (late rounds)
// Camera ray basis (vec3 columns) so the sky can be reconstructed per pixel with
// world-direction clouds. Fed each frame by PostProcess.
uniform vec3 cam_basis_x = vec3(1.0, 0.0, 0.0);
uniform vec3 cam_basis_y = vec3(0.0, 1.0, 0.0);
uniform vec3 cam_basis_z = vec3(0.0, 0.0, 1.0);
uniform float cam_tan = 0.5;
uniform float cam_aspect = 1.78;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise + fbm (pure functions, no built-ins) for drifting sky clouds.
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

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;

	bool is_sky = sky_enabled && src.r > 0.25 && src.b > 0.25 && src.g < 0.2 && abs(src.r - src.b) < 0.25;

	// Sky: reconstruct the world view direction for this pixel, shade a gradient by
	// elevation, then add drifting fbm clouds (the cloud fbm only runs on sky
	// pixels). Never dithered.
	vec2 ndc = SCREEN_UV * 2.0 - 1.0;
	vec3 vdir = vec3(ndc.x * cam_tan * cam_aspect, -ndc.y * cam_tan, -1.0);
	vec3 dir = normalize(vdir.x * cam_basis_x + vdir.y * cam_basis_y + vdir.z * cam_basis_z);
	float up = clamp(dir.y, 0.0, 1.0);
	vec3 sky_top = mix(vec3(0.01, 0.02, 0.06), vec3(0.20, 0.42, 0.82), sky_day);
	vec3 sky_hor = mix(vec3(0.04, 0.06, 0.13), vec3(0.70, 0.80, 0.95), sky_day);
	sky_hor = mix(sky_hor, vec3(0.95, 0.45, 0.20), sky_sunset);
	vec3 sky_col = mix(sky_hor, sky_top, pow(up, 0.5));
	if (is_sky && dir.y > 0.02) {
		vec2 cuv = dir.xz / (dir.y + 0.2) * 1.2 + TIME * 0.006;
		float c = smoothstep(0.45, 0.85, fbm(cuv)) * smoothstep(0.02, 0.25, dir.y);
		vec3 cloud = mix(vec3(0.08, 0.09, 0.13), vec3(1.0), sky_day);
		cloud = mix(cloud, vec3(0.95, 0.45, 0.20), sky_sunset * 0.5);
		sky_col = mix(sky_col, cloud, c * 0.85);
	}
	// Late-round redness: blend the whole sky toward a bright red.
	vec3 red_top = vec3(0.42, 0.04, 0.03);
	vec3 red_hor = vec3(0.88, 0.13, 0.06);
	vec3 red_col = mix(red_hor, red_top, pow(up, 0.6));
	sky_col = mix(sky_col, red_col, sky_red);

	// World: two FLAT tones of the surface colour; lighting -> dither density.
	float l = luma(src);
	vec3 chroma = src / max(l, 0.08);                          // colour at unit brightness
	chroma = clamp(mix(vec3(1.0), chroma, saturation), 0.0, 2.0);  // punch up saturation
	vec3 lit_tone = clamp(chroma * lit_strength, 0.0, 1.0);
	vec3 shade_tone = clamp(chroma * shade_strength, 0.0, 1.0);
	float t = smoothstep(shadow_low, shadow_high, clamp((l - 0.5) * light_contrast + 0.5, 0.0, 1.0));
	// Suppress lit dots in (near-)solid shadow so stray low-hash cells don't show
	// as persistent white specks; the grain still lives in the lit/shade band.
	float lit = step(hash(floor(SCREEN_UV / SCREEN_PIXEL_SIZE / grain_size)), t) * step(0.02, t);
	vec3 world_col = mix(shade_tone, lit_tone, lit);

	COLOR = vec4(mix(world_col, sky_col, float(is_sky)), 1.0);
}
