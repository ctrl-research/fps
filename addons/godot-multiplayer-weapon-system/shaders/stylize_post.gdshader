// Stipple post-process — shades SHADOWS ONLY with black ink dots.
//
// Lit surfaces keep their normal rendered colour; as a pixel falls below
// shadow_cutoff luminance, black halftone dots grow denser. No posterise, no
// outline — pure stippling. Mounted below the HUD by PostProcess; shown only
// while a 3D camera is active.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float dot_size : hint_range(2.0, 12.0) = 4.0;          // pixels per dot cell
uniform float shadow_cutoff : hint_range(0.1, 1.0) = 0.5;     // only shade below this luminance
uniform float dot_gain : hint_range(0.5, 2.0) = 1.1;          // max dot size in deep shadow

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Black halftone dots sized by how deep in shadow the pixel is. Lit pixels
// (luma >= shadow_cutoff) get no dots and keep their colour — this also leaves
// the bright sky untouched.
vec3 stipple(vec3 c, vec2 px) {
	float l = luma(c);
	float shadow = 1.0 - smoothstep(shadow_cutoff * 0.5, shadow_cutoff, l);
	vec2 f = fract(px / dot_size) - 0.5;
	float dist = length(f) * 2.0;             // 0 at cell centre
	float radius = shadow * dot_gain;
	float dots = 1.0 - smoothstep(radius - 0.15, radius + 0.15, dist);
	return mix(c, vec3(0.0), dots);           // black dots over the colour
}

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	COLOR = vec4(stipple(src, SCREEN_UV / SCREEN_PIXEL_SIZE), 1.0);
}
