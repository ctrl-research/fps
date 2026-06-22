// Stipple / halftone post-process.
//
// Screen-space halftone: per-pixel luminance drives the size of BLACK ink dots
// over the surface colour (colours kept so team red/blue/yellow stay readable;
// color_mode 1 = white paper for a pure ink look). Optional Sobel ink outline.
// Mounted below the HUD by PostProcess.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// 0 = keep surface colour under the dots, 1 = white paper (pure black/white ink).
uniform int color_mode = 0;
uniform float dot_size : hint_range(2.0, 12.0) = 4.0;       // pixels per dot cell
uniform float dot_gain : hint_range(0.5, 2.0) = 1.15;      // how fast dots grow as it darkens

uniform bool outline_enabled = true;
uniform float outline_thickness : hint_range(0.5, 4.0) = 1.6;
uniform float outline_threshold : hint_range(0.02, 1.0) = 0.30;
uniform vec3 outline_color : source_color = vec3(0.0);

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Halftone: darker tone => larger black dot within each screen-space cell.
vec3 stipple(vec3 c, vec2 px) {
	float l = luma(c);
	vec2 f = fract(px / dot_size) - 0.5;
	float dist = length(f) * 2.0;              // 0 at cell centre
	float radius = (1.0 - l) * dot_gain;       // bright => ~0 (no dot), dark => big
	float dots = 1.0 - smoothstep(radius - 0.15, radius + 0.15, dist);
	vec3 base = (color_mode == 0) ? c : vec3(1.0);
	return mix(base, vec3(0.0), dots);         // black dots over the base
}

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
	vec2 px = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec3 col = stipple(src, px);
	if (outline_enabled) {
		float e = sobel(SCREEN_UV, SCREEN_PIXEL_SIZE * outline_thickness);
		col = mix(col, outline_color, step(outline_threshold, e));
	}
	COLOR = vec4(col, 1.0);
}
