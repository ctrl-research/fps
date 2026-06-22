// Dithered two-tone post-process (Mortal Sin-style).
//
// Surfaces keep their clean lit colour; where they fall into SHADOW they become a
// darker shade tone, and the lit/shade boundary is broken up by a screen-space
// noise dither — the granular shadow look. Hue preserved so team colours stay
// readable. All params are live-tunable from Settings via PostProcess.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float shade_strength : hint_range(0.0, 1.0) = 0.40;  // brightness of the shadow tone
uniform float shadow_low : hint_range(0.0, 1.0) = 0.12;      // below this = solid shade
uniform float shadow_high : hint_range(0.0, 1.0) = 0.45;     // above this = solid lit colour
uniform float grain_size : hint_range(1.0, 6.0) = 2.0;       // dither grain size in pixels
uniform float light_contrast : hint_range(0.5, 3.0) = 1.0;   // pushes surfaces toward two tones

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Static screen-space hash noise -> per-pixel dither threshold.
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	float l = luma(src);
	// Contrast around mid-grey so flat lighting still splits into lit/shadow.
	l = clamp((l - 0.5) * light_contrast + 0.5, 0.0, 1.0);
	// 0 in shadow, 1 in light; grain lives in the band between low and high.
	float shade_term = smoothstep(shadow_low, shadow_high, l);
	vec2 cell = floor(SCREEN_UV / SCREEN_PIXEL_SIZE / grain_size);
	float lit = step(hash(cell), shade_term);
	COLOR = vec4(mix(src * shade_strength, src, lit), 1.0);
}
