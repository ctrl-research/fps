// Stipple post-process — shades SHADOWS ONLY with black ink dots.
//
// Lit surfaces keep their normal rendered colour. As a pixel falls below
// shadow_cutoff luminance, black halftone dots grow denser. No posterise, no
// outline — pure stippling.
//
// Sky exclusion (no depth buffer on gl_compatibility): DayNightSky clears the 3D
// background to a magenta SENTINEL while the effect is on; those pixels are drawn
// as a smooth sky gradient (un-stippled). Mounted below the HUD by PostProcess.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float dot_size : hint_range(2.0, 12.0) = 4.0;          // pixels per dot cell
uniform float shadow_cutoff : hint_range(0.1, 1.0) = 0.55;    // only shade below this luminance
uniform float dot_gain : hint_range(0.5, 2.0) = 1.1;          // max dot size in deep shadow

// Sky exclusion (driven by PostProcess / DayNightSky).
uniform bool sky_enabled = false;
uniform float sky_day = 1.0;       // 1 = day, 0 = night
uniform float sky_sunset = 0.0;    // peaks at sunset

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Black halftone dots sized by how deep in shadow the pixel is. Lit pixels
// (luma >= shadow_cutoff) get no dots and keep their colour.
vec3 stipple(vec3 c, vec2 px) {
	float l = luma(c);
	float shadow = 1.0 - smoothstep(shadow_cutoff * 0.5, shadow_cutoff, l);
	vec2 f = fract(px / dot_size) - 0.5;
	float dist = length(f) * 2.0;             // 0 at cell centre
	float radius = shadow * dot_gain;
	float dots = 1.0 - smoothstep(radius - 0.15, radius + 0.15, dist);
	return mix(c, vec3(0.0), dots);           // black dots over the colour
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
	// Sentinel background = sky: draw a smooth gradient, un-stippled.
	bool is_sky = src.r > 0.25 && src.b > 0.25 && src.g < 0.2 && abs(src.r - src.b) < 0.25;
	if (sky_enabled && is_sky) {
		COLOR = vec4(sky_gradient(SCREEN_UV), 1.0);
		return;
	}
	COLOR = vec4(stipple(src, SCREEN_UV / SCREEN_PIXEL_SIZE), 1.0);
}
