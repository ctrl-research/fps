// Dithered two-tone post-process (Mortal Sin-style).
//
// Surfaces keep their clean lit colour; only where they fall into SHADOW are they
// replaced by a darker shade tone, and the lit/shade boundary is broken up by a
// screen-space noise dither — giving the granular shadow look while lit areas
// stay solid (not a global grain). Hue preserved so team colours stay readable.
// Mounted below the HUD by PostProcess; shown only while a 3D camera is active.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float shade_strength : hint_range(0.0, 1.0) = 0.40;  // brightness of the shadow tone
uniform float shadow_low : hint_range(0.0, 1.0) = 0.12;      // below this = solid shade (clean dark)
uniform float shadow_high : hint_range(0.0, 1.0) = 0.45;     // above this = solid lit (clean colour)
uniform float grain_size : hint_range(1.0, 6.0) = 2.0;       // dither grain size in pixels

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
	// 0 in shadow, 1 in light; grain only lives in the band between low and high.
	float shade_term = smoothstep(shadow_low, shadow_high, l);
	vec2 cell = floor(SCREEN_UV / SCREEN_PIXEL_SIZE / grain_size);
	float lit = step(hash(cell), shade_term);
	COLOR = vec4(mix(src * shade_strength, src, lit), 1.0);
}
