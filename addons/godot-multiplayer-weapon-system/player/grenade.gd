extends RigidBody3D
class_name Grenade
"""
A thrown grenade. Arcs under physics (UP impulse + gravity), then detonates on a
fuse with a per-type effect read from its WeaponDatabase entry:

- frag:  falloff blast damage in radius
- flash: blinds nearby players (white screen overlay) for `duration`
- smoke: a CPUParticles3D cloud that lasts `duration` and obscures vision
- emp:   disables nearby players' utility for `duration`
- push:  knockback impulse to nearby players

Smoke uses CPUParticles3D (not GPUParticles3D) because the project renders in
gl_compatibility, where GPU particles aren't reliably supported. Lives on its own
collision layer so weapon raycasts ignore it.
"""

const THROW_SPEED: float = 15.0
const THROW_LIFT: float = 3.0
const FUSE_TIME: float = 2.2

var type: String = "frag"
var blast_damage: float = 0.0
var blast_radius: float = 5.0
var duration: float = 2.0
var force: float = 0.0
var attacker_id: int = 0

var _fuse: float = FUSE_TIME
var _detonated: bool = false

## Configure from a WeaponDatabase grenade entry and throw along `direction`.
## `fuse_remaining` lets the thrower pass a cooked-down fuse. `speed`/`lift` set
## the throw arc (mid-range throw vs short lob). Call after add_child (its
## position should be set before add_child, since it's a physics body).
func throw_from(data: Dictionary, shooter_id: int, direction: Vector3, fuse_remaining: float = FUSE_TIME,
		speed: float = THROW_SPEED, lift: float = THROW_LIFT) -> void:
	type = data.get("type", "frag")
	blast_damage = float(data.get("damage", 0.0))
	blast_radius = float(data.get("radius", 5.0))
	duration = float(data.get("duration", 2.0))
	force = float(data.get("force", 0.0))
	attacker_id = shooter_id
	_fuse = maxf(fuse_remaining, 0.05)
	linear_velocity = direction.normalized() * speed + Vector3.UP * lift

func _physics_process(delta: float) -> void:
	if _detonated:
		return
	_fuse -= delta
	if _fuse <= 0.0:
		_detonate()

func _detonate() -> void:
	_detonated = true
	# Spatial blast (played at the world so it survives this node freeing).
	GameAudio.play_at(global_position, "grenade_explode", "grenade")
	match type:
		"flash":
			_apply_to_players("apply_flash", duration)
			_spawn_light(Color(1.0, 1.0, 1.0))
		"emp":
			_apply_to_players("apply_emp", duration)
			_spawn_light(Color(0.4, 0.6, 1.0))
		"push":
			_apply_push()
			_spawn_light(Color(0.6, 1.0, 0.7))
		"smoke":
			_spawn_smoke()
		_:  # frag (and any unknown type)
			_apply_blast_damage()
			_spawn_light(Color(1.0, 0.7, 0.35))
	queue_free()

# === Effects ===

func _bodies_in_radius() -> Array:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = blast_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), global_position)
	params.collision_mask = 1
	var bodies: Array = []
	for result in space.intersect_shape(params, 32):
		var collider = result.get("collider")
		if collider != null and not bodies.has(collider):
			bodies.append(collider)
	return bodies

func _apply_blast_damage() -> void:
	for collider in _bodies_in_radius():
		if not collider.has_method("request_damage"):
			continue
		var dist: float = global_position.distance_to(collider.global_position)
		var damage: float = blast_damage * (1.0 - clampf(dist / blast_radius, 0.0, 1.0))
		if damage > 0.0:
			collider.request_damage(damage, attacker_id)

## Call a player effect method (apply_flash / apply_emp) on every player in range.
func _apply_to_players(method: String, seconds: float) -> void:
	for collider in _bodies_in_radius():
		if collider.has_method(method):
			collider.call(method, seconds)

func _apply_push() -> void:
	for collider in _bodies_in_radius():
		if not collider.has_method("apply_knockback"):
			continue
		var offset: Vector3 = collider.global_position - global_position
		var dist: float = offset.length()
		var dir: Vector3 = offset.normalized() if dist > 0.05 else Vector3.UP
		var strength: float = force * 0.02 * (1.0 - clampf(dist / blast_radius, 0.0, 1.0))
		collider.apply_knockback(dir * strength + Vector3.UP * strength * 0.5)

func _spawn_light(color: Color) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 8.0
	light.omni_range = blast_radius * 1.5
	parent.add_child(light)
	light.global_position = global_position
	light.get_tree().create_timer(0.25).timeout.connect(light.queue_free)

func _spawn_smoke() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var smoke := _build_smoke()
	parent.add_child(smoke)
	smoke.global_position = global_position + Vector3(0.0, 0.4, 0.0)
	smoke.emitting = true
	var tree := smoke.get_tree()
	# Stop emitting after `duration`, then free once the last puffs fade. Callables
	# on a freed node are skipped automatically, so no validity check is needed.
	tree.create_timer(duration).timeout.connect(smoke.set.bind("emitting", false))
	tree.create_timer(duration + smoke.lifetime).timeout.connect(smoke.queue_free)

func _build_smoke() -> CPUParticles3D:
	var smoke := CPUParticles3D.new()
	smoke.amount = 48
	smoke.lifetime = 4.0
	smoke.preprocess = 0.6
	smoke.randomness = 0.5
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = blast_radius * 0.4
	smoke.direction = Vector3(0.0, 1.0, 0.0)
	smoke.spread = 90.0
	smoke.gravity = Vector3(0.0, 0.25, 0.0)
	smoke.initial_velocity_min = 0.3
	smoke.initial_velocity_max = 1.0
	smoke.scale_amount_min = 2.5
	smoke.scale_amount_max = 4.5

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.72, 0.75, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = material
	smoke.mesh = quad
	return smoke
