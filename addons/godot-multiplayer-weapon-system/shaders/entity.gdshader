// Shared view-angle outline for entity models (players, bots, throwables, drops).
//
// Runs as a *next_pass* over each entity's own material, so the base colour/
// shading (and runtime tints, e.g. a bot flashing red) are preserved while this
// pass adds a fresnel rim that lights up where the surface turns away from the
// camera, plus a slight shell inflation so it reads as an edge.
//
// Additive (blend_add) and unshaded so it's purely decorative and never darkens
// or recolours the base. gl_compatibility-safe.
//
// (Dithering is a separate global post-process; see shaders/dither_post.gdshader.)
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;

uniform bool outline_enabled = true;
uniform vec4 outline_color : source_color = vec4(0.30, 0.85, 1.0, 1.0);
uniform float outline_power : hint_range(0.5, 8.0) = 3.0;
uniform float outline_strength : hint_range(0.0, 4.0) = 1.3;
// Outward shell inflation (metres): keeps this pass just in front of the base so
// it renders reliably, and widens the silhouette into a visible outline.
uniform float grow : hint_range(0.0, 0.05) = 0.006;

void vertex() {
	VERTEX += normalize(NORMAL) * grow;
}

void fragment() {
	vec3 col = vec3(0.0);
	if (outline_enabled) {
		float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		float rim = pow(1.0 - facing, outline_power);
		col += outline_color.rgb * rim * outline_strength;
	}
	ALBEDO = col;
}
