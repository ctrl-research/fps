// Global comic-book stylise post-process (replaces the old dither + outline).
//
// Two effects over the rendered 3D frame:
//   1. Dynamic colour remapping — maps scene luminance onto a palette.
//        Classic  : a stark, posterised palette (black / blue / red / grey).
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

// 0 = Classic palette, 1 = Realistic grade.
uniform int color_mode = 0;

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

// Stark, posterised palette keyed by luminance (black / blue / red / grey).
vec3 classic_palette(float l) {
	if (l < 0.18) {
		return vec3(0.04, 0.04, 0.07);
	} else if (l < 0.38) {
		return vec3(0.13, 0.17, 0.45);
	} else if (l < 0.58) {
		return vec3(0.72, 0.15, 0.17);
	} else if (l < 0.80) {
		return vec3(0.53, 0.55, 0.61);
	}
	return vec3(0.93, 0.93, 0.96);
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
	vec3 col = (color_mode == 0) ? classic_palette(luma(src)) : realistic_grade(src);
	if (outline_enabled) {
		float e = sobel(SCREEN_UV, SCREEN_PIXEL_SIZE * outline_thickness);
		col = mix(col, outline_color, step(outline_threshold, e));
	}
	COLOR = vec4(col, 1.0);
}
