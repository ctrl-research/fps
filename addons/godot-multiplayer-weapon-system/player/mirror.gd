extends Node3D
class_name Mirror
"""
A real-time planar mirror.

A SubViewport renders the world from a camera placed at the reflection of the
active camera across the mirror plane. The surface samples that render by SCREEN
position (not the mesh UVs) so it stays aligned regardless of the quad's
orientation, with a horizontal flip to produce a mirror's lateral inversion.

Visual layers let the reflection camera skip the surface itself (no feedback)
and any node tagged "no reflection" (e.g. world-space signage text).
"""

## Visual layer 19: the mirror surface, skipped by the reflection camera.
const SURFACE_VISUAL_LAYER: int = 1 << 18
## Visual layer 18: nodes that should not appear in mirrors (e.g. signage text).
const NO_REFLECTION_VISUAL_LAYER: int = 1 << 17

const MIRROR_SHADER: String = """
shader_type spatial;
render_mode unshaded;
uniform sampler2D reflection : source_color, filter_linear;
void fragment() {
	// Sample the reflection render at this fragment's screen position, flipped
	// horizontally for the lateral inversion a mirror shows.
	vec2 uv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y);
	ALBEDO = texture(reflection, uv).rgb;
}
"""

@export var surface_size: Vector2 = Vector2(2.0, 2.4)

var _viewport: SubViewport = null
var _mirror_cam: Camera3D = null
var _surface: MeshInstance3D = null

func _ready() -> void:
	_build_frame()

	_surface = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = surface_size
	_surface.mesh = quad
	_surface.layers = SURFACE_VISUAL_LAYER
	add_child(_surface)

	_viewport = SubViewport.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.world_3d = get_world_3d()
	add_child(_viewport)
	_resize_viewport()

	_mirror_cam = Camera3D.new()
	# Skip the mirror surface (feedback) and any no-reflection-tagged nodes.
	_mirror_cam.cull_mask = 0xFFFFF & ~SURFACE_VISUAL_LAYER & ~NO_REFLECTION_VISUAL_LAYER
	_mirror_cam.current = true
	_viewport.add_child(_mirror_cam)

	var shader := Shader.new()
	shader.code = MIRROR_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("reflection", _viewport.get_texture())
	_surface.material_override = material

	get_viewport().size_changed.connect(_resize_viewport)

func _resize_viewport() -> void:
	# Match the screen so SCREEN_UV sampling aligns 1:1.
	_viewport.size = Vector2i(get_viewport().get_visible_rect().size)

func _process(_delta: float) -> void:
	var main := get_viewport().get_camera_3d()
	if main == null or _mirror_cam == null:
		return

	# Reflect the viewer across the mirror plane (local +Z in world space). A
	# look_at (proper, right-handed) basis keeps face culling correct; the
	# shader's horizontal flip supplies the mirror inversion.
	var normal := global_transform.basis.z.normalized()
	var distance := (main.global_position - global_position).dot(normal)
	var reflected_pos := main.global_position - 2.0 * distance * normal

	var forward := -main.global_transform.basis.z
	var up := main.global_transform.basis.y
	var reflected_forward := forward - 2.0 * forward.dot(normal) * normal
	var reflected_up := up - 2.0 * up.dot(normal) * normal

	_mirror_cam.global_position = reflected_pos
	_mirror_cam.look_at(reflected_pos + reflected_forward, reflected_up)
	_mirror_cam.fov = main.fov
	_mirror_cam.near = main.near
	_mirror_cam.far = main.far

## A simple dark border around the mirror surface (on the surface layer so the
## reflection camera ignores it too).
func _build_frame() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.08, 0.1)
	material.metallic = 0.5
	material.roughness = 0.5

	var t := 0.1
	var half := surface_size * 0.5
	var horizontal := Vector3(surface_size.x + t * 2.0, t, t)
	var vertical := Vector3(t, surface_size.y, t)
	_add_frame_bar(Vector3(0.0, half.y + t * 0.5, 0.0), horizontal, material)
	_add_frame_bar(Vector3(0.0, -half.y - t * 0.5, 0.0), horizontal, material)
	_add_frame_bar(Vector3(-half.x - t * 0.5, 0.0, 0.0), vertical, material)
	_add_frame_bar(Vector3(half.x + t * 0.5, 0.0, 0.0), vertical, material)

func _add_frame_bar(offset: Vector3, bar_size: Vector3, material: StandardMaterial3D) -> void:
	var bar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = bar_size
	bar.mesh = box
	bar.position = offset
	bar.material_override = material
	bar.layers = SURFACE_VISUAL_LAYER
	add_child(bar)
