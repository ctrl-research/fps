// Shared stylised overlay for entity models (players, bots, throwables, drops).
//
// Designed to run as a *next_pass* over each entity's own material, so the base
// colour/shading (and any runtime tints, e.g. a bot flashing red) are preserved
// while this pass adds:
//   - a view-angle outline: a fresnel rim that lights up where the surface turns
//     away from the camera, plus a slight shell inflation so it reads as an edge.
//   - a dithering grain: an ordered 4x4 Bayer pattern in screen space.
//
// Additive (blend_add) and unshaded so it's purely decorative and never darkens
// or recolours the base. gl_compatibility-safe (no GPU particles / compute).
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;

uniform bool outline_enabled = true;
uniform vec4 outline_color : source_color = vec4(0.30, 0.85, 1.0, 1.0);
uniform float outline_power : hint_range(0.5, 8.0) = 3.0;
uniform float outline_strength : hint_range(0.0, 4.0) = 1.3;
// Outward shell inflation (metres): keeps this pass just in front of the base so
// it renders reliably, and widens the silhouette into a visible outline.
uniform float grow : hint_range(0.0, 0.05) = 0.006;

uniform bool dither_enabled = true;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.12;
// Larger = chunkier grain (the screen-space pattern is scaled down by this).
uniform float dither_scale : hint_range(1.0, 8.0) = 2.0;

// Normalised 4x4 ordered Bayer value (0..1) for a screen-space fragment.
float bayer(vec2 frag) {
	float pattern[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0);
	int x = int(mod(frag.x, 4.0));
	int y = int(mod(frag.y, 4.0));
	return pattern[x + y * 4] / 16.0;
}

void vertex() {
	VERTEX += normalize(NORMAL) * grow;
}

void fragment() {
	vec3 col = vec3(0.0);

	if (dither_enabled) {
		float b = bayer(FRAGCOORD.xy / dither_scale);
		col += vec3(b) * dither_strength;
	}

	if (outline_enabled) {
		float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		float rim = pow(1.0 - facing, outline_power);
		col += outline_color.rgb * rim * outline_strength;
	}

	ALBEDO = col;
}
