extends CharacterBody3D
class_name Bot
"""
Practice-range combat bot.

Takes weapon damage like a player (exposes request_damage), is defeated at 0 HP
and respawns after 5 seconds, and periodically fires at the nearest living
player with a chance to miss. Stationary — it only turns to face its target.
"""

@export var max_health: float = 100.0
## Odd id so the minimap colours the bot as the enemy team (peer_id % 2 == 1).
@export var authority_peer_id: int = 1001

const GRAVITY: float = 20.0
const RESPAWN_DELAY: float = 5.0
const FIRE_INTERVAL: float = 1.8
const SHOT_DAMAGE: float = 6.0
## Only engage players within this distance (so bots don't snipe you at spawn).
const ENGAGE_RANGE: float = 28.0
const FIRE_RANGE: float = 70.0
const AIM_SPREAD: float = 0.06
const FLASH_TIME: float = 0.06
const HIT_FLASH_TIME: float = 0.05

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _head: MeshInstance3D = $Head
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _eye: Node3D = $Eye
@onready var _muzzle_flash: MeshInstance3D = $Eye/MuzzleFlash
@onready var _label: Label3D = $HealthLabel

var health: float = 0.0
var _dead: bool = false
var _respawn_timer: float = 0.0
var _fire_timer: float = 0.0
var _flash_timer: float = 0.0
var _hit_flash_timer: float = 0.0
var _material: StandardMaterial3D = null
var _spawn_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	_spawn_position = global_position
	# Enemy dot on the minimap (which reads the 'players' group + authority_peer_id).
	add_to_group("players")

	_material = StandardMaterial3D.new()
	_mesh.material_override = _material
	_head.material_override = _material
	_muzzle_flash.visible = false
	_reset()

func _physics_process(delta: float) -> void:
	if _dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_reset()
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()

	var target := _find_target()
	if target != null:
		_face(target)
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer = FIRE_INTERVAL
			_shoot_at(target)

	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_muzzle_flash.visible = false
	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0.0:
			_update_color()

## Weapon hit entry point (same signature as PlayerController.request_damage).
func request_damage(amount: float, _attacker_id: int) -> void:
	if _dead or amount <= 0.0:
		return
	health = max(health - amount, 0.0)
	_label.text = "%d" % int(health)
	_material.albedo_color = Color(1.0, 1.0, 1.0)
	_hit_flash_timer = HIT_FLASH_TIME
	if health <= 0.0:
		_die()

func _die() -> void:
	_dead = true
	_respawn_timer = RESPAWN_DELAY
	_mesh.visible = false
	_head.visible = false
	_muzzle_flash.visible = false
	_label.text = "respawning…"
	_collision.set_deferred("disabled", true)

func _reset() -> void:
	_dead = false
	health = max_health
	_mesh.visible = true
	_head.visible = true
	_collision.set_deferred("disabled", false)
	global_position = _spawn_position
	velocity = Vector3.ZERO
	# Stagger so a group of bots doesn't fire in unison.
	_fire_timer = FIRE_INTERVAL * randf_range(0.4, 1.2)
	_label.text = "%d" % int(health)
	_update_color()

## Nearest living player (bots ignore downed/dead targets and each other).
func _find_target() -> PlayerController:
	var best: PlayerController = null
	var best_dist := ENGAGE_RANGE
	for node in get_tree().get_nodes_in_group("players"):
		if not (node is PlayerController) or not is_instance_valid(node):
			continue
		var player := node as PlayerController
		if player.is_dead or player.is_downed:
			continue
		var dist := global_position.distance_to(player.global_position)
		if dist <= best_dist:
			best = player
			best_dist = dist
	return best

func _face(target: PlayerController) -> void:
	var flat := target.global_position
	flat.y = global_position.y
	if global_position.distance_to(flat) > 0.05:
		look_at(flat, Vector3.UP)

func _shoot_at(target: PlayerController) -> void:
	_muzzle_flash.visible = true
	_flash_timer = FLASH_TIME

	var eye_pos := _eye.global_position
	var aim_point := target.global_position + Vector3(0.0, 1.0, 0.0)
	var dir := (aim_point - eye_pos).normalized()
	dir = (dir + Vector3(
		randf_range(-AIM_SPREAD, AIM_SPREAD),
		randf_range(-AIM_SPREAD, AIM_SPREAD),
		randf_range(-AIM_SPREAD, AIM_SPREAD))).normalized()

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye_pos, eye_pos + dir * FIRE_RANGE)
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var collider = hit.get("collider")
	# Only the player takes bot fire (walls/dummies/other bots block or are ignored).
	if collider is PlayerController:
		(collider as PlayerController).request_damage(SHOT_DAMAGE, authority_peer_id)

func _update_color() -> void:
	_material.albedo_color = Color(0.8, 0.3, 0.3)
