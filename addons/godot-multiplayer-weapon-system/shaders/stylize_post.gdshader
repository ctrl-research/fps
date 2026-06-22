// Dithered two-tone post-process (Mortal Sin-style).
//
// Surfaces keep their clean lit colour; where they fall into SHADOW they become a
// darker shade tone, broken up by a screen-space noise dither. Sky exclusion:
// while the effect is on, DayNightSky clears the 3D background to a magenta
// SENTINEL; those pixels render as a smooth gradient and are never dithered.
//
// Everything is kept inside fragment() with SCREEN_UV used directly and no early
// return — Godot's shader compiler chokes on built-ins passed to helper functions
// and on some early-return forms, which broke earlier versions.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float shade_strength : hint_range(0.0, 1.0) = 0.30;
uniform float shadow_low : hint_range(0.0, 1.0) = 0.06;
uniform float shadow_high : hint_range(0.0, 1.0) = 0.20;
uniform float grain_size : hint_range(1.0, 6.0) = 2.0;
uniform float light_contrast : hint_range(0.5, 4.0) = 3.0;

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

	// Sky branch: smooth vertical gradient, never dithered.
	float h = clamp(SCREEN_UV.y, 0.0, 1.0);
	vec3 sky_top = mix(vec3(0.01, 0.02, 0.06), vec3(0.20, 0.42, 0.82), sky_day);
	vec3 sky_hor = mix(vec3(0.04, 0.06, 0.13), vec3(0.70, 0.80, 0.95), sky_day);
	sky_hor = mix(sky_hor, vec3(0.95, 0.45, 0.20), sky_sunset);
	vec3 sky_col = mix(sky_top, sky_hor, smoothstep(0.0, 0.55, h));

	// World branch: dithered two-tone shading.
	float l = clamp((luma(src) - 0.5) * light_contrast + 0.5, 0.0, 1.0);
	float shade_term = smoothstep(shadow_low, shadow_high, l);
	float lit = step(hash(floor(SCREEN_UV / SCREEN_PIXEL_SIZE / grain_size)), shade_term);
	vec3 world_col = mix(src * shade_strength, src, lit);

	COLOR = vec4(mix(world_col, sky_col, float(is_sky)), 1.0);
}
