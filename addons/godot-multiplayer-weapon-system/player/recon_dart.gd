extends Area3D
class_name ReconDart
"""
Marksman recon dart. Flies like a normal arrow but deals no damage: it sticks to
the first thing it touches, then for `reveal_time` seconds it outlines every
enemy player within `reveal_radius` of where it landed — through walls, and only
while they remain in range (leaving the radius drops the outline).
"""

var speed: float = 60.0
var attacker_id: int = 0
var shooter: Node = null
var shooter_team: int = -1
var reveal_radius: float = 14.0
var reveal_time: float = 3.0
var color: Color = Color(0.4, 1.0, 0.6)
var max_flight: float = 4.0   # seconds before a whiffed dart sticks in mid-air

var _dir: Vector3 = Vector3.FORWARD
var _stuck: bool = false
var _age: float = 0.0
var _revealed: Array = []     # enemies this dart is currently outlining

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.18
	shape.shape = sphere
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.14
	m.height = 0.28
	mesh.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mesh.material_override = mat
	add_child(mesh)

	body_entered.connect(_on_body_entered)

func launch(from: Vector3, direction: Vector3) -> void:
	global_position = from
	_dir = direction.normalized()

func _physics_process(delta: float) -> void:
	if not _stuck:
		global_position += _dir * speed * delta
		_age += delta
		if _age >= max_flight:
			_stick()
		return
	_age += delta
	_update_reveal()
	if _age >= reveal_time:
		_clear_reveal()
		queue_free()

func _on_body_entered(body: Node) -> void:
	if _stuck or body == shooter:
		return
	_stick()

func _stick() -> void:
	_stuck = true
	_age = 0.0
	monitoring = false

## Outline enemies currently within range; un-outline any that have left.
func _update_reveal() -> void:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = reveal_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), global_position)
	params.collision_mask = 1
	var current: Array = []
	for result in space.intersect_shape(params, 32):
		var col = result.get("collider")
		if col == null or col == shooter or not col.has_method("set_revealed"):
			continue
		if "team" in col and col.team == shooter_team:
			continue
		current.append(col)
		if not (col in _revealed):
			col.set_revealed(true)
			_revealed.append(col)
	for node in _revealed.duplicate():
		if not is_instance_valid(node) or not (node in current):
			if is_instance_valid(node):
				node.set_revealed(false)
			_revealed.erase(node)

func _clear_reveal() -> void:
	for node in _revealed:
		if is_instance_valid(node):
			node.set_revealed(false)
	_revealed.clear()

func _exit_tree() -> void:
	_clear_reveal()
