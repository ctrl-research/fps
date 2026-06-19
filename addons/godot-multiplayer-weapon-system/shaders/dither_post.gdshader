// Global ordered-dithering post-process.
//
// A full-screen canvas_item shader: reads the composited frame and applies a 4x4
// Bayer ordered dither while quantising each RGB channel to a few levels. This
// keeps every pixel's colour but adds a grainy, reduced-depth texture (a retro
// dithered look) instead of converting to greyscale.
//
// Mounted on a screen-filling ColorRect on a top CanvasLayer by PostProcess, so
// it covers the whole screen. gl_compatibility-safe (2D screen-texture read).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
// Quantisation steps per colour channel. Lower = stronger dither texture.
uniform float color_levels : hint_range(2.0, 16.0) = 3.0;
// Larger = chunkier dither cells (pattern scaled down in screen space).
uniform float dither_scale : hint_range(1.0, 8.0) = 3.0;

// Centred 4x4 Bayer threshold (0..1) for a screen-space fragment.
float bayer(vec2 frag) {
	float pattern[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0);
	int x = int(mod(frag.x, 4.0));
	int y = int(mod(frag.y, 4.0));
	return (pattern[x + y * 4] + 0.5) / 16.0;
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	// Per-channel ordered dithering: nudge by the Bayer offset, then snap to the
	// nearest level. Hue is preserved; the pattern shows up as texture/grain.
	float offset = bayer(FRAGCOORD.xy / dither_scale) - 0.5;
	float steps = color_levels - 1.0;
	vec3 dithered = round(c * steps + offset) / steps;
	COLOR = vec4(clamp(dithered, 0.0, 1.0), 1.0);
}
