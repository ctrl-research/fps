extends RigidBody3D
class_name Grenade
"""
A thrown grenade. Arcs under physics, then detonates on a fuse: any body in the
blast radius with a request_damage method takes falloff damage (frag). Non-frag
types (no damage in the database) just detonate visually for now.

Lives on its own collision layer so weapon raycasts ignore it.
"""

const THROW_SPEED: float = 15.0
const THROW_LIFT: float = 3.0
const FUSE_TIME: float = 2.2

var blast_damage: float = 0.0
var blast_radius: float = 5.0
var attacker_id: int = 0

var _fuse: float = FUSE_TIME
var _detonated: bool = false

## Set the grenade's stats from a WeaponDatabase grenade entry and throw it along
## `direction`. Call after adding it to the scene (its position should already be
## set before add_child, since it's a physics body).
func throw_from(data: Dictionary, shooter_id: int, direction: Vector3) -> void:
	blast_damage = float(data.get("damage", 0.0))
	blast_radius = float(data.get("radius", 5.0))
	attacker_id = shooter_id
	linear_velocity = direction.normalized() * THROW_SPEED + Vector3.UP * THROW_LIFT

func _physics_process(delta: float) -> void:
	if _detonated:
		return
	_fuse -= delta
	if _fuse <= 0.0:
		_detonate()

func _detonate() -> void:
	_detonated = true
	if blast_damage > 0.0:
		_apply_blast_damage()
	_spawn_flash()
	queue_free()

func _apply_blast_damage() -> void:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = blast_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), global_position)
	params.collision_mask = 1  # damageable bodies live on layer 1
	for result in space.intersect_shape(params, 32):
		var collider = result.get("collider")
		if collider == null or not collider.has_method("request_damage"):
			continue
		var dist: float = global_position.distance_to((collider as Node3D).global_position)
		var damage: float = blast_damage * (1.0 - clampf(dist / blast_radius, 0.0, 1.0))
		if damage > 0.0:
			collider.request_damage(damage, attacker_id)

## A short-lived light/flash, parented to the scene so it outlives the grenade.
func _spawn_flash() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 8.0
	light.omni_range = blast_radius * 1.5
	parent.add_child(light)
	light.global_position = global_position
	light.get_tree().create_timer(0.25).timeout.connect(light.queue_free)
