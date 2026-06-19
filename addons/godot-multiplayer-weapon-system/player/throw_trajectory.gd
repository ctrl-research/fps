extends MultiMeshInstance3D
class_name ThrowTrajectory
"""
A dotted, world-space arc preview for grenade throws.

Fed a list of simulated world-space points (see WeaponController), it places a
small unshaded sphere at each. top_level so the instance positions are world
coordinates regardless of the parent.
"""

const DOT_RADIUS: float = 0.07

func _ready() -> void:
	top_level = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sphere := SphereMesh.new()
	sphere.radius = DOT_RADIUS
	sphere.height = DOT_RADIUS * 2.0
	mm.mesh = sphere
	multimesh = mm

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	material_override = mat
	visible = false

## Place a dot at each world-space point and tint them.
func show_arc(points: Array, color: Color) -> void:
	multimesh.instance_count = points.size()
	for i in points.size():
		multimesh.set_instance_transform(i, Transform3D(Basis(), points[i]))
	(material_override as StandardMaterial3D).albedo_color = color
	visible = true

func hide_arc() -> void:
	visible = false
	multimesh.instance_count = 0
