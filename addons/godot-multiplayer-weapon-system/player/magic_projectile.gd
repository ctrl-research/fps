extends Area3D
class_name MagicProjectile
"""
A travelling spell projectile (Mage bolt / fireball). Moves forward, damages the
first body it touches, then frees itself. With aoe_radius > 0 it instead bursts,
damaging everything in range. Self-builds its collision + a glowing mesh, so no
scene file is needed.
"""

var speed: float = 42.0
var damage: float = 0.0
var attacker_id: int = 0
var shooter: Node = null
var lifetime: float = 3.0
var aoe_radius: float = 0.0   # 0 = single target
var color: Color = Color(0.5, 0.7, 1.0)
# On-hit passives carried from the caster's spec.
var lifesteal: float = 0.0    # fraction of damage healed back to the shooter
var slow_factor: float = 1.0  # >1 = slower (Frostbite); applied for slow_time
var slow_time: float = 0.0

var _dir: Vector3 = Vector3.FORWARD
var _age: float = 0.0
var _spent: bool = false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1  # world + characters
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	shape.shape = sphere
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.18
	sphere_mesh.height = 0.36
	mesh.mesh = sphere_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mesh.material_override = mat
	add_child(mesh)

	body_entered.connect(_on_body_entered)

## Configure direction/position before (or right after) adding to the scene.
func launch(from: Vector3, direction: Vector3) -> void:
	global_position = from
	_dir = direction.normalized()

func _physics_process(delta: float) -> void:
	global_position += _dir * speed * delta
	_age += delta
	if _age >= lifetime:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if _spent or body == shooter:
		return
	_spent = true
	if aoe_radius > 0.0:
		_burst()
	elif body.has_method("request_damage"):
		body.request_damage(damage, attacker_id)
		_apply_on_hit(body)
	queue_free()

## Damage every damageable body within aoe_radius of the impact.
func _burst() -> void:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = aoe_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), global_position)
	params.collision_mask = 1
	for result in space.intersect_shape(params, 24):
		var collider = result.get("collider")
		if collider and collider != shooter and collider.has_method("request_damage"):
			collider.request_damage(damage, attacker_id)
			_apply_on_hit(collider)

## Caster on-hit passives: lifesteal heals the shooter; slow chills the target.
func _apply_on_hit(target: Node) -> void:
	if lifesteal > 0.0 and is_instance_valid(shooter) and shooter.has_method("heal"):
		shooter.heal(damage * lifesteal)
	if slow_time > 0.0 and target.has_method("apply_slow"):
		target.apply_slow(slow_factor, slow_time)
