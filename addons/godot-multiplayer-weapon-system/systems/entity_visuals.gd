extends Node
# No `class_name`: registered as the `EntityVisuals` autoload. A matching global
# class would shadow the singleton and break clean compiles.
"""
Applies the shared view-angle outline shader to entity models — players, bots,
throwables, drops — so they share one look. (Dithering is a separate global
post-process; see PostProcess / shaders/dither_post.gdshader.)

The shader is attached as a *next_pass* over each mesh's existing material, which
keeps the entity's own colour/shading (and runtime tints like a bot's hit-flash)
intact. A single shared overlay material is reused for every entity, so toggling
the effects in Settings updates them all live.

Reusable: an entity calls EntityVisuals.apply(self) once its meshes exist
(typically at the end of _ready / after building its body).
"""

const SHADER_PATH: String = "res://addons/godot-multiplayer-weapon-system/shaders/entity.gdshader"
## Meshes tagged with this group are skipped (e.g. muzzle flashes, tracers).
const EXCLUDE_GROUP: String = "fx_no_shader"
## Meshes we've shaded, so settings changes can re-target them.
const SHADED_GROUP: String = "entity_shaded"

var _overlay: ShaderMaterial = null

func _ready() -> void:
	var shader: Shader = load(SHADER_PATH)
	_overlay = ShaderMaterial.new()
	_overlay.shader = shader
	_refresh_toggles()
	Settings.settings_changed.connect(_refresh_toggles)

## Attach the outline overlay to every eligible mesh under `root`.
func apply(root: Node) -> void:
	if _overlay == null:
		return
	for mesh in _eligible_meshes(root):
		var base: Material = mesh.material_override
		if base == null:
			base = mesh.get_active_material(0)
		if base == null:
			# No material to chain onto — give it a plain one so the pass renders.
			base = StandardMaterial3D.new()
			mesh.material_override = base
		base.next_pass = _overlay
		mesh.add_to_group(SHADED_GROUP)

func _eligible_meshes(root: Node) -> Array:
	var result: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		if node is MeshInstance3D and _is_shadeable(node):
			result.append(node)
	return result

## Skip FX bits and surfaces the overlay shouldn't sit on (transparent / unshaded
## decorations, or meshes already carrying a custom shader like the mirror).
func _is_shadeable(mesh: MeshInstance3D) -> bool:
	if mesh.is_in_group(EXCLUDE_GROUP):
		return false
	var mat: Material = mesh.material_override
	if mat == null:
		mat = mesh.get_active_material(0)
	if mat is ShaderMaterial:
		return false
	if mat is StandardMaterial3D:
		if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return false
		if mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			return false
	return true

## Sync the shared overlay's on/off uniform from Settings (affects all entities).
func _refresh_toggles() -> void:
	if _overlay == null:
		return
	_overlay.set_shader_parameter("outline_enabled", Settings.entity_outline_enabled)
