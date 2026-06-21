// Global comic-book stylise post-process (replaces the old dither + outline).
//
// Two effects over the rendered 3D frame:
//   1. Dynamic colour remapping — keeps each object's own hue (so category base
//        colours read: grey map, blue allies, red enemies, yellow interactables)
//        and shades it by lighting.
//        Classic  : posterised into a few hard luminance bands (stark, comic).
//        Realistic: a saturation + contrast grade over the natural colours.
//   2. Sobel edge outline — a luminance edge-detect that inks thick black lines
//        around silhouettes and shading boundaries for a heavy comic look.
//
// gl_compatibility note: the WebGL2 / Compatibility renderer doesn't expose a
// depth / normal buffer to screen-space shaders, so the Sobel runs on screen
// luminance rather than a true depth+geometry buffer. With the posterised
// palette this still reads as inked geometry edges. Mounted below the HUD by
// PostProcess so only the 3D world is stylised, not the UI.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// World-coverage mask (alpha 1 = geometry, 0 = sky). Sky pixels skip the effect.
uniform sampler2D mask_tex : filter_nearest;

// 0 = Classic posterise, 1 = Realistic grade.
uniform int color_mode = 0;
// Classic-mode luminance bands (lower = starker).
uniform float classic_bands : hint_range(2.0, 8.0) = 4.0;

uniform bool outline_enabled = true;
// Edge sampling distance (screen pixels) — higher = thicker lines.
uniform float outline_thickness : hint_range(0.5, 4.0) = 1.6;
// Luminance gradient above which a pixel is inked.
uniform float outline_threshold : hint_range(0.02, 1.0) = 0.30;
uniform vec3 outline_color : source_color = vec3(0.0);

// Realistic-mode grade.
uniform float contrast : hint_range(0.5, 2.5) = 1.18;
uniform float saturation : hint_range(0.0, 2.5) = 1.4;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Keep the pixel's hue, snap its brightness to a few hard bands (cel/comic).
vec3 classic_posterize(vec3 c) {
	float l = luma(c);
	float ql = (floor(l * classic_bands) + 0.5) / classic_bands;
	return clamp(c * (ql / max(l, 0.001)), 0.0, 1.0);
}

// Keep the natural hue, push saturation and contrast.
vec3 realistic_grade(vec3 c) {
	vec3 sat = mix(vec3(luma(c)), c, saturation);
	return clamp((sat - 0.5) * contrast + 0.5, 0.0, 1.0);
}

// 3x3 Sobel magnitude on screen luminance.
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

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	// Leave the sky (no world geometry) untouched.
	if (texture(mask_tex, SCREEN_UV).a < 0.5) {
		COLOR = vec4(src, 1.0);
		return;
	}
	vec3 col = (color_mode == 0) ? classic_posterize(src) : realistic_grade(src);
	if (outline_enabled) {
		float e = sobel(SCREEN_UV, SCREEN_PIXEL_SIZE * outline_thickness);
		col = mix(col, outline_color, step(outline_threshold, e));
	}
	COLOR = vec4(col, 1.0);
}
