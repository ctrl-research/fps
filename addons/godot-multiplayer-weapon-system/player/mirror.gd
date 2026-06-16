extends Node3D
class_name Mirror
"""
A real-time planar mirror.

A SubViewport renders the shared world from a camera placed at the reflection of
the active camera across the mirror plane; that render is shown on a quad. The
mirror surface lives on its own visual layer so the reflection camera ignores it
(no feedback loop). The mirror plane is the local XY plane, facing local +Z.
"""

## Visual layer 19: the mirror surface, culled by the reflection camera.
const SURFACE_VISUAL_LAYER: int = 1 << 18

@export var surface_size: Vector2 = Vector2(2.0, 2.4)
@export var resolution: Vector2i = Vector2i(512, 614)

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
	_viewport.size = resolution
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.world_3d = get_world_3d()
	add_child(_viewport)

	_mirror_cam = Camera3D.new()
	# See everything except the mirror surface, so the reflection never includes
	# the mirror itself.
	_mirror_cam.cull_mask = 0xFFFFF & ~SURFACE_VISUAL_LAYER
	_mirror_cam.current = true
	_viewport.add_child(_mirror_cam)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = _viewport.get_texture()
	# No UV flip: the reflection camera's basis is already laterally inverted
	# relative to the viewer (its right vector is the viewer's left), which is the
	# lateral inversion a mirror shows. Flipping here would double-invert and
	# break horizontal parallax.
	_surface.material_override = material

func _process(_delta: float) -> void:
	var main := get_viewport().get_camera_3d()
	if main == null or _mirror_cam == null:
		return

	# Mirror plane normal is the mirror's local +Z in world space.
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
