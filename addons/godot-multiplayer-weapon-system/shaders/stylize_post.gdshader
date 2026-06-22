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

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;

	bool is_sky = sky_enabled && src.r > 0.25 && src.b > 0.25 && src.g < 0.2 && abs(src.r - src.b) < 0.25;

	// Sky: smooth vertical gradient, never dithered.
	float h = clamp(SCREEN_UV.y, 0.0, 1.0);
	vec3 sky_top = mix(vec3(0.01, 0.02, 0.06), vec3(0.20, 0.42, 0.82), sky_day);
	vec3 sky_hor = mix(vec3(0.04, 0.06, 0.13), vec3(0.70, 0.80, 0.95), sky_day);
	sky_hor = mix(sky_hor, vec3(0.95, 0.45, 0.20), sky_sunset);
	vec3 sky_col = mix(sky_top, sky_hor, smoothstep(0.0, 0.55, h));

	// World: two FLAT tones of the surface colour; lighting -> dither density.
	float l = luma(src);
	vec3 chroma = src / max(l, 0.08);                          // colour at unit brightness
	chroma = clamp(mix(vec3(1.0), chroma, saturation), 0.0, 2.0);  // punch up saturation
	vec3 lit_tone = clamp(chroma * lit_strength, 0.0, 1.0);
	vec3 shade_tone = clamp(chroma * shade_strength, 0.0, 1.0);
	float t = smoothstep(shadow_low, shadow_high, clamp((l - 0.5) * light_contrast + 0.5, 0.0, 1.0));
	float lit = step(hash(floor(SCREEN_UV / SCREEN_PIXEL_SIZE / grain_size)), t);
	vec3 world_col = mix(shade_tone, lit_tone, lit);

	COLOR = vec4(mix(world_col, sky_col, float(is_sky)), 1.0);
}
