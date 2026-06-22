// Dithered two-tone post-process (Mortal Sin-style).
//
// Surfaces keep their clean lit colour; where they fall into SHADOW they become a
// darker shade tone, and the lit/shade boundary is broken up by a screen-space
// noise dither — the granular shadow look. Hue preserved so team colours stay
// readable. All params are live-tunable from Settings via PostProcess.
//
// Sky exclusion: when DayNightSky has the effect on it clears the 3D background to
// a magenta SENTINEL. Sentinel pixels are drawn as a smooth sky gradient and are
// NEVER dithered, so the skybox stays clean.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float shade_strength : hint_range(0.0, 1.0) = 0.30;  // brightness of the shadow tone
uniform float shadow_low : hint_range(0.0, 1.0) = 0.06;      // below this = solid shade
uniform float shadow_high : hint_range(0.0, 1.0) = 0.20;     // above this = solid lit colour
uniform float grain_size : hint_range(1.0, 6.0) = 2.0;       // dither grain size in pixels
uniform float light_contrast : hint_range(0.5, 4.0) = 3.0;   // pushes surfaces toward two tones

// Sky exclusion (driven by PostProcess / DayNightSky).
uniform bool sky_enabled = false;
uniform float sky_day = 1.0;       // 1 = day, 0 = night
uniform float sky_sunset = 0.0;    // peaks at sunset

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// High-quality hash (Dave Hoskins) — white-noise dither with no visible tiling,
// even at fine grain.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth vertical sky gradient (screen-space; no camera matrix or noise).
vec3 sky_gradient(vec2 uv) {
	float h = clamp(uv.y, 0.0, 1.0);          // 0 = screen top, 1 = bottom
	vec3 top = mix(vec3(0.01, 0.02, 0.06), vec3(0.20, 0.42, 0.82), sky_day);
	vec3 hor = mix(vec3(0.04, 0.06, 0.13), vec3(0.70, 0.80, 0.95), sky_day);
	hor = mix(hor, vec3(0.95, 0.45, 0.20), sky_sunset);
	return mix(top, hor, smoothstep(0.0, 0.55, h));
}

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	// Sky (magenta sentinel) -> smooth gradient, never dithered.
	if (sky_enabled && src.r > 0.25 && src.b > 0.25 && src.g < 0.2 && abs(src.r - src.b) < 0.25) {
		COLOR = vec4(sky_gradient(SCREEN_UV), 1.0);
		return;
	}
	float l = luma(src);
	// Contrast around mid-grey so flat lighting still splits into lit/shadow.
	l = clamp((l - 0.5) * light_contrast + 0.5, 0.0, 1.0);
	// 0 in shadow, 1 in light; grain lives in the band between low and high.
	float shade_term = smoothstep(shadow_low, shadow_high, l);
	vec2 cell = floor(SCREEN_UV / SCREEN_PIXEL_SIZE / grain_size);
	float lit = step(hash(cell), shade_term);
	COLOR = vec4(mix(src * shade_strength, src, lit), 1.0);
}
