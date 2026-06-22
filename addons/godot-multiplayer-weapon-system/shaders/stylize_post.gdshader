// Stipple post-process — shades SHADOWS only with black ink dots.
//
// Lit surfaces keep their normal rendered colour; as a surface falls into
// shadow, black halftone dots grow denser. Keeps full colour so team
// red/blue/yellow stay readable. Optional Sobel ink outline.
//
// Sky exclusion (no depth buffer on gl_compatibility): DayNightSky clears the
// 3D background to a magenta SENTINEL while the effect is on. Sentinel pixels
// are drawn as a smooth sky gradient (un-stippled) instead of being shaded.
// Mounted below the HUD by PostProcess.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// 0 = keep surface colour, 1 = greyscale under the dots.
uniform int color_mode = 0;
uniform float dot_size : hint_range(2.0, 12.0) = 4.0;          // pixels per dot cell
uniform float shadow_cutoff : hint_range(0.1, 1.0) = 0.55;    // only shade below this luminance
uniform float dot_gain : hint_range(0.5, 2.0) = 1.1;          // max dot size in deep shadow

uniform bool outline_enabled = true;
uniform float outline_thickness : hint_range(0.5, 4.0) = 1.6;
uniform float outline_threshold : hint_range(0.02, 1.0) = 0.30;
uniform vec3 outline_color : source_color = vec3(0.0);

// Sky exclusion (driven by PostProcess / DayNightSky).
uniform bool sky_enabled = false;
uniform float sky_day = 1.0;       // 1 = day, 0 = night
uniform float sky_sunset = 0.0;    // peaks at sunset

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Black halftone dots, sized by how deep in shadow the pixel is. Lit pixels
// (luma >= shadow_cutoff) get no dots and keep their colour.
vec3 stipple(vec3 c, vec2 px) {
	float l = luma(c);
	float shadow = 1.0 - smoothstep(shadow_cutoff * 0.5, shadow_cutoff, l);
	vec2 f = fract(px / dot_size) - 0.5;
	float dist = length(f) * 2.0;             // 0 at cell centre
	float radius = shadow * dot_gain;
	float dots = 1.0 - smoothstep(radius - 0.15, radius + 0.15, dist);
	vec3 base = (color_mode == 0) ? c : vec3(l);
	return mix(base, vec3(0.0), dots);        // black dots over the base
}

// Smooth vertical sky gradient (screen-space; no camera matrix or noise).
vec3 sky_gradient(vec2 uv) {
	float h = clamp(uv.y, 0.0, 1.0);          // 0 = screen top, 1 = bottom
	vec3 top = mix(vec3(0.01, 0.02, 0.06), vec3(0.20, 0.42, 0.82), sky_day);
	vec3 hor = mix(vec3(0.04, 0.06, 0.13), vec3(0.70, 0.80, 0.95), sky_day);
	hor = mix(hor, vec3(0.95, 0.45, 0.20), sky_sunset);
	return mix(top, hor, smoothstep(0.0, 0.55, h));
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
	// Sentinel background = sky: draw a smooth gradient, un-stippled. Detect the
	// magenta by hue (high R + high B, ~zero G), robust to tonemapping.
	bool is_sky = src.r > 0.25 && src.b > 0.25 && src.g < 0.2 && abs(src.r - src.b) < 0.25;
	if (sky_enabled && is_sky) {
		COLOR = vec4(sky_gradient(SCREEN_UV), 1.0);
		return;
	}
	vec2 px = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec3 col = stipple(src, px);
	if (outline_enabled) {
		float e = sobel(SCREEN_UV, SCREEN_PIXEL_SIZE * outline_thickness);
		col = mix(col, outline_color, step(outline_threshold, e));
	}
	COLOR = vec4(col, 1.0);
}
