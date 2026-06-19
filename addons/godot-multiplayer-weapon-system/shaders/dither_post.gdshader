// Global 1-bit ordered-dithering post-process.
//
// A full-screen canvas_item shader: reads the composited frame, reduces it to a
// single bit per pixel (two colours) using a 4x4 Bayer threshold on luminance.
// The classic Macintosh / Return-of-the-Obra-Dinn look.
//
// Mounted on a screen-filling ColorRect on a top CanvasLayer by PostProcess, so
// it covers the whole screen. gl_compatibility-safe (2D screen-texture read).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
// The two output colours (1 bit = 2 states). Default pure black / white.
uniform vec3 dark_color : source_color = vec3(0.0);
uniform vec3 light_color : source_color = vec3(1.0);
// Larger = chunkier dither cells (pattern scaled down in screen space).
uniform float dither_scale : hint_range(1.0, 8.0) = 1.0;

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
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float threshold = bayer(FRAGCOORD.xy / dither_scale);
	float bit = step(threshold, lum);
	COLOR = vec4(mix(dark_color, light_color, bit), 1.0);
}
