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
## Team id (0 = player's team / ally, 1 = enemy). Drives targeting, revive, tint.
@export var team: int = 1

const GRAVITY: float = 20.0
const RESPAWN_DELAY: float = 5.0
const HIT_FLASH_TIME: float = 0.05
# Melee chaser tuning.
const MOVE_SPEED: float = 4.5
const MELEE_RANGE: float = 2.6
const MELEE_DAMAGE: float = 14.0
const ATTACK_INTERVAL: float = 1.1

# Downed / revive tuning.
const DOWNED_DURATION: float = 30.0     # bleedout time while downed (revivable)
const DOWNED_CRAWL_SPEED: float = 1.6   # slow retreat while downed
const REVIVE_RANGE: float = 2.4         # ally must reach this to revive
const REVIVE_TIME: float = 3.0          # seconds an ally channels to revive

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
var _downed: bool = false
var _bleedout: float = 0.0
var _revive_channel: float = 0.0    # progress while THIS bot revives a downed ally
# Class-derived combat behaviour (set from class_id in _configure_class).
var _ranged: bool = false
var _attack_range: float = MELEE_RANGE
var _keep_dist: float = 0.0
var _attack_interval: float = ATTACK_INTERVAL
var _proj_damage: float = 0.0
var _proj_speed: float = 40.0
var _proj_aoe: float = 0.0
var _proj_color: Color = Color(1.0, 0.6, 0.3)
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
	_model.set_tint(CategoryColors.ALLY if team == 0 else CategoryColors.ENEMY)

	_configure_class()
	_reset()

## Set combat behaviour from the bot's class: warriors melee, mage/archer kite
## and fire projectiles.
func _configure_class() -> void:
	match class_id:
		"mage":
			_ranged = true
			_attack_range = 22.0
			_keep_dist = 11.0
			_attack_interval = 1.4
			_proj_damage = 12.0
			_proj_speed = 30.0
			_proj_aoe = 1.8
			_proj_color = Color(1.0, 0.5, 0.2)
		"archer":
			_ranged = true
			_attack_range = 28.0
			_keep_dist = 13.0
			_attack_interval = 1.1
			_proj_damage = 14.0
			_proj_speed = 60.0
			_proj_aoe = 0.0
			_proj_color = Color(0.85, 0.78, 0.55)
		_:
			_ranged = false
			_attack_range = MELEE_RANGE
			_attack_interval = ATTACK_INTERVAL

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

	# Downed: bleed out unless an ally revives in time; crawl slowly toward safety.
	if _downed:
		_process_downed(delta)
		return

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

	# A living bot prioritises reviving a downed ally; otherwise it fights.
	var move := Vector3.ZERO
	var ally := _find_downed_ally()
	if ally != null:
		move = _revive_ally(ally, delta)
		velocity.x = move.x
		velocity.z = move.z
		move_and_slide()
		if _model != null:
			var m := global_position - _prev_anim_pos
			_prev_anim_pos = global_position
			_model.set_locomotion(Vector2(m.x, m.z).length() / maxf(delta, 0.0001), is_on_floor())
		return
	_revive_channel = 0.0

	# Engage the nearest visible player. Melee bots close in; ranged bots hold at
	# their attack range, back off if crowded, and fire projectiles.
	var target := _find_target()
	if target != null:
		_face(target)
		var to := target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		var speed := MOVE_SPEED / maxf(_slow_factor, 0.01)
		if dist > _attack_range:
			move = to.normalized() * speed                      # close in
		elif _ranged and dist < _keep_dist:
			move = -to.normalized() * speed                     # kite away
		if dist <= _attack_range:
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				_attack_timer = _attack_interval * stat_fire_rate_mult * _slow_factor
				if _ranged:
					_ranged_attack(target)
				else:
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
	# A hit on a downed bot finishes it off (true death).
	if _downed:
		_die()
		return
	health = max(health - amount, 0.0)
	_label.text = "%d" % int(health)
	_material.albedo_color = Color(1.0, 1.0, 1.0)
	_hit_flash_timer = HIT_FLASH_TIME
	if health <= 0.0:
		_enter_downed()

## Knocked down (revivable) rather than killed outright. An allied bot can revive
## it; another hit, or the bleedout timer, finishes it.
func _enter_downed() -> void:
	_downed = true
	_bleedout = DOWNED_DURATION
	_muzzle_flash.visible = false
	if _model != null:
		_model.play_death()
	_label.text = "DOWNED"

## Tick bleedout and crawl slowly away from threats while downed.
func _process_downed(delta: float) -> void:
	_bleedout -= delta
	_label.text = "DOWNED %d" % int(ceil(maxf(_bleedout, 0.0)))
	if _bleedout <= 0.0:
		_die()
		return
	var threat := _find_target()
	var move := Vector3.ZERO
	if threat != null:
		var away := global_position - threat.global_position
		away.y = 0.0
		if away.length() > 0.1:
			move = away.normalized() * DOWNED_CRAWL_SPEED
	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()

func _die() -> void:
	_dead = true
	_downed = false
	_respawn_timer = RESPAWN_DELAY
	_muzzle_flash.visible = false
	if _model != null:
		_model.play_death()
	_label.text = "respawning…"
	_collision.set_deferred("disabled", true)
	defeated.emit(_last_attacker_id)

## Bring a downed bot back into the fight (called by an allied bot).
func revive() -> void:
	if not _downed or _dead:
		return
	_downed = false
	_bleedout = 0.0
	health = max_health * stat_health_mult * 0.5
	if _model != null:
		_model.play_idle()
	_label.text = "%d" % int(health)
	_update_color()

func is_downed() -> bool:
	return _downed

## Put a living bot straight into the downed state (e.g. ally bots that start a
## round downed, waiting to be revived).
func knock_down() -> void:
	if not _dead and not _downed:
		_enter_downed()

## Nearest downed allied bot within reach (all bots share the enemy team).
## Nearest downed same-team ally (bot OR player) within reach.
func _find_downed_ally() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("players"):
		if node == self or not is_instance_valid(node):
			continue
		var downed := false
		var ally := false
		if node is PlayerController:
			downed = (node as PlayerController).is_downed
			ally = (node as PlayerController).team == team
		elif node is Bot:
			downed = (node as Bot).is_downed()
			ally = (node as Bot).team == team
		if not downed or not ally:
			continue
		var d := global_position.distance_to((node as Node3D).global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best

## Move toward a downed ally (bot or player) and channel a revive when in range.
## Returns the desired planar move for this frame.
func _revive_ally(ally: Node3D, delta: float) -> Vector3:
	_face(ally)
	var to := ally.global_position - global_position
	to.y = 0.0
	if to.length() > REVIVE_RANGE:
		_revive_channel = 0.0
		return to.normalized() * (MOVE_SPEED / maxf(_slow_factor, 0.01))
	_revive_channel += delta
	if _revive_channel >= REVIVE_TIME:
		_revive_channel = 0.0
		if ally is PlayerController:
			(ally as PlayerController).request_revive()
		elif ally.has_method("revive"):
			ally.revive()
	return Vector3.ZERO

func _reset() -> void:
	_dead = false
	_downed = false
	_bleedout = 0.0
	_revive_channel = 0.0
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

## Nearest living enemy (opposing team) with a clear line of sight — a player or
## an enemy bot. Ignores downed/dead and same-team units.
func _find_target() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("players"):
		if node == self or not is_instance_valid(node):
			continue
		var other_team := 99
		var alive := false
		if node is PlayerController:
			var p := node as PlayerController
			other_team = p.team
			alive = not (p.is_dead or p.is_downed)
		elif node is Bot:
			var b := node as Bot
			other_team = b.team
			alive = b.is_alive() and not b.is_downed()
		else:
			continue
		if other_team == team or not alive:
			continue
		var t := node as Node3D
		var dist := global_position.distance_to(t.global_position)
		if dist <= best_dist and _has_line_of_sight(t):
			best = t
			best_dist = dist
	return best

## True if nothing solid sits between the bot's eye and the target.
func _has_line_of_sight(target: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		_eye.global_position, target.global_position + Vector3(0.0, 1.0, 0.0))
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == target

func _face(target: Node3D) -> void:
	var flat := target.global_position
	flat.y = global_position.y
	if global_position.distance_to(flat) > 0.05:
		look_at(flat, Vector3.UP)

## Melee strike: damage the target if it's still within reach when the swing lands.
func _melee_attack(target: Node3D) -> void:
	GameAudio.play_at(global_position, "swing", "movement")
	if is_instance_valid(target) and global_position.distance_to(target.global_position) <= MELEE_RANGE + 0.6:
		target.request_damage(MELEE_DAMAGE * stat_damage_mult, authority_peer_id)

## Ranged strike (mage/archer): fire a projectile at the target.
func _ranged_attack(target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	GameAudio.play_at(global_position, "swing", "movement")
	var origin := _eye.global_position if _eye else global_position + Vector3.UP * 1.4
	var aim := target.global_position + Vector3.UP * 1.0
	var proj := MagicProjectile.new()
	proj.damage = _proj_damage * stat_damage_mult
	proj.aoe_radius = _proj_aoe
	proj.color = _proj_color
	proj.speed = _proj_speed
	proj.attacker_id = authority_peer_id
	proj.shooter = self
	get_parent().add_child(proj)
	proj.launch(origin, (aim - origin).normalized())

func _update_color() -> void:
	_material.albedo_color = Color(0.8, 0.3, 0.3)
