extends CharacterBody3D
class_name Bot
"""
Practice-range combat bot.

Takes damage like a player (exposes request_damage), is defeated at 0 HP and
respawns after 5 seconds. A melee chaser: it advances on the nearest living
player it can see and strikes when in range (no pathfinding — it moves in a
straight line, so it only pursues with line of sight).
"""

## Emitted when the bot is defeated; carries the attacker's peer id (for kill
## attribution, e.g. Gun Game progression).
signal defeated(by_peer_id: int)

@export var max_health: float = 100.0
## Odd id so the minimap colours the bot as the enemy team (peer_id % 2 == 1).
@export var authority_peer_id: int = 1001
## Optional class identity (warrior / mage / archer) — picks the matching model.
@export var class_id: String = ""

const GRAVITY: float = 20.0
const RESPAWN_DELAY: float = 5.0
const HIT_FLASH_TIME: float = 0.05
# Melee chaser tuning.
const MOVE_SPEED: float = 4.5
const MELEE_RANGE: float = 2.6
const MELEE_DAMAGE: float = 14.0
const ATTACK_INTERVAL: float = 1.1

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _head: MeshInstance3D = $Head
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _eye: Node3D = $Eye
@onready var _muzzle_flash: MeshInstance3D = $Eye/MuzzleFlash
@onready var _label: Label3D = $HealthLabel

## When false, the bot stays down after dying (round-based modes reset it).
@export var auto_respawn: bool = true

# Evolution stat multipliers (1.0 = unmodified).
var stat_health_mult: float = 1.0
var stat_damage_mult: float = 1.0
var stat_fire_rate_mult: float = 1.0

var health: float = 0.0
var _dead: bool = false
var _respawn_timer: float = 0.0
var _attack_timer: float = 0.0
var _hit_flash_timer: float = 0.0
var _material: StandardMaterial3D = null
var _spawn_position: Vector3 = Vector3.ZERO
var _last_attacker_id: int = 0
var _model: CharacterModel = null
var _prev_anim_pos: Vector3 = Vector3.ZERO
var _stun_time: float = 0.0
var _slow_factor: float = 1.0
var _slow_time: float = 0.0

## Bot character model (KayKit Skeleton Warrior).
const BOT_MODEL: String = "res://assets/characters/kaykit_skeletons/Skeleton_Warrior.glb"

func _ready() -> void:
	_spawn_position = global_position
	# Enemy dot on the minimap (which reads the 'players' group + authority_peer_id).
	add_to_group("players")

	_material = StandardMaterial3D.new()
	_mesh.material_override = _material
	_head.material_override = _material
	# The KayKit model replaces the placeholder capsule/sphere visuals.
	_mesh.visible = false
	_head.visible = false
	_muzzle_flash.visible = false

	_model = CharacterModel.new()
	add_child(_model)
	var model_path := BOT_MODEL
	if class_id != "":
		model_path = String(ClassDatabase.get_def(class_id).get("model", BOT_MODEL))
	_model.setup(model_path)
	_model.set_tint(CategoryColors.ENEMY)

	_reset()

func _physics_process(delta: float) -> void:
	if _dead:
		if not auto_respawn:
			return
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_reset()
		return

	var grav := 0.0 if is_on_floor() else -GRAVITY * delta
	velocity.y += grav

	if _slow_time > 0.0:
		_slow_time -= delta
		if _slow_time <= 0.0:
			_slow_factor = 1.0
	if _stun_time > 0.0:
		# Stunned (e.g. Shield Bash): frozen, no chasing or striking.
		_stun_time -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	# Chase the nearest visible player; strike when in melee range.
	var target := _find_target()
	var move := Vector3.ZERO
	if target != null:
		_face(target)
		var to := target.global_position - global_position
		to.y = 0.0
		if to.length() > MELEE_RANGE:
			move = to.normalized() * MOVE_SPEED / maxf(_slow_factor, 0.01)
		else:
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				_attack_timer = ATTACK_INTERVAL * stat_fire_rate_mult * _slow_factor
				_melee_attack(target)
	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()

	if _model != null:
		var moved := global_position - _prev_anim_pos
		_prev_anim_pos = global_position
		_model.set_locomotion(Vector2(moved.x, moved.z).length() / maxf(delta, 0.0001), is_on_floor())

	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0.0:
			_update_color()

## Weapon hit entry point (same signature as PlayerController.request_damage).
func request_damage(amount: float, attacker_id: int) -> void:
	if _dead or amount <= 0.0:
		return
	_last_attacker_id = attacker_id
	health = max(health - amount, 0.0)
	_label.text = "%d" % int(health)
	_material.albedo_color = Color(1.0, 1.0, 1.0)
	_hit_flash_timer = HIT_FLASH_TIME
	if health <= 0.0:
		_die()

func _die() -> void:
	_dead = true
	_respawn_timer = RESPAWN_DELAY
	_muzzle_flash.visible = false
	if _model != null:
		_model.play_death()
	_label.text = "respawning…"
	_collision.set_deferred("disabled", true)
	defeated.emit(_last_attacker_id)

func _reset() -> void:
	_dead = false
	health = max_health * stat_health_mult
	if _model != null:
		_model.play_idle()
	_collision.set_deferred("disabled", false)
	global_position = _spawn_position
	_prev_anim_pos = _spawn_position
	velocity = Vector3.ZERO
	# Stagger so a group of bots doesn't strike in unison.
	_attack_timer = ATTACK_INTERVAL * randf_range(0.4, 1.2)
	_label.text = "%d" % int(health)
	_update_color()

## Apply Evolution stat multipliers and revive at full (new) health.
func apply_stats(stats: Dictionary) -> void:
	stat_health_mult = float(stats.get("health", 1.0))
	stat_damage_mult = float(stats.get("damage", 1.0))
	stat_fire_rate_mult = float(stats.get("fire_rate", 1.0))
	_reset()

## Revive for a new round (round-based modes that disable auto_respawn).
func reset_for_round() -> void:
	_reset()

func is_alive() -> bool:
	return not _dead

## Stunned: no aiming/firing for `seconds` (Warrior Shield Bash).
func apply_stun(seconds: float) -> void:
	_stun_time = maxf(_stun_time, seconds)

## Slowed: fire interval scaled by `factor` (>1 = slower) for `seconds` (Stagger).
func apply_slow(factor: float, seconds: float) -> void:
	_slow_factor = factor
	_slow_time = maxf(_slow_time, seconds)

## Nearest living player with a clear line of sight, at any range (bots ignore
## downed/dead targets and each other).
func _find_target() -> PlayerController:
	var best: PlayerController = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("players"):
		if not (node is PlayerController) or not is_instance_valid(node):
			continue
		var player := node as PlayerController
		if player.is_dead or player.is_downed:
			continue
		var dist := global_position.distance_to(player.global_position)
		if dist <= best_dist and _has_line_of_sight(player):
			best = player
			best_dist = dist
	return best

## True if nothing solid sits between the bot's eye and the player (so bots
## behind walls don't fire until you reach the doorway).
func _has_line_of_sight(player: PlayerController) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		_eye.global_position, player.global_position + Vector3(0.0, 1.0, 0.0))
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player

func _face(target: PlayerController) -> void:
	var flat := target.global_position
	flat.y = global_position.y
	if global_position.distance_to(flat) > 0.05:
		look_at(flat, Vector3.UP)

## Melee strike: damage the target if it's still within reach when the swing lands.
func _melee_attack(target: PlayerController) -> void:
	GameAudio.play_at(global_position, "swing", "movement")
	if is_instance_valid(target) and global_position.distance_to(target.global_position) <= MELEE_RANGE + 0.6:
		target.request_damage(MELEE_DAMAGE * stat_damage_mult, authority_peer_id)

func _update_color() -> void:
	_material.albedo_color = Color(0.8, 0.3, 0.3)
