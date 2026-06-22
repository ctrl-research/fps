// Dithered two-tone post-process (Mortal Sin-style).
//
// Each surface is flattened toward two tones — its lit colour and a darker shade
// colour — and the boundary between them is broken up by a screen-space noise
// dither, giving the granular/grainy shadow look. Hue is preserved so team
// colours (red/blue/yellow) stay readable. Mounted below the HUD by PostProcess;
// shown only while a 3D camera is active.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float shade_strength : hint_range(0.0, 1.0) = 0.42;  // brightness of the shadow tone
uniform float shadow_low : hint_range(0.0, 1.0) = 0.28;      // luma where shadow ends
uniform float shadow_high : hint_range(0.0, 1.0) = 0.60;     // luma where full light begins
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
	// Lighting flattened toward two bands.
	float shade_term = smoothstep(shadow_low, shadow_high, l);
	// Granular dither boundary between the lit and shade tones.
	vec2 cell = floor(SCREEN_UV / SCREEN_PIXEL_SIZE / grain_size);
	float dith = hash(cell);
	float lit = step(dith, shade_term);
	vec3 shade_col = src * shade_strength;
	COLOR = vec4(mix(shade_col, src, lit), 1.0);
}
