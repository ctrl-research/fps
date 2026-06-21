extends Node3D
class_name AbilityController
"""
Class-arena combat: a melee base attack plus cooldown-gated class abilities.
Replaces the gun WeaponController for the pivot (issue #79).

Driven by a SpecTree: configure() takes the granted ability ids and active
passive tags, so the kit grows as the player specs down their tree. Abilities
are bound to input slots (attack / dash / ability1 / ult). Stat multipliers
(damage, attack speed, etc.) live on the PlayerController via apply_stats; this
reads them at hit/cast time. Passive tags (lifesteal, …) are applied here.

Foundation scope: melee + dash are implemented; the Warrior actives
(shield_bash / leap_strike / immovable / berserk) are registered with cooldowns
and dispatched, with full effects landing in the Warrior issue (#80).
"""

signal ability_state_changed(slot: String, id: String, cooldown: float, remaining: float)

const MELEE_RANGE: float = 2.6
const MELEE_DAMAGE: float = 34.0
const MELEE_INTERVAL: float = 0.55
const DASH_SPEED: float = 16.0

## ability id -> {slot, cooldown}. slot maps to an input action below.
const ABILITY_DEFS: Dictionary = {
	"melee": {"slot": "attack", "cooldown": 0.0},
	"dash": {"slot": "dash", "cooldown": 4.0},
	"shield_bash": {"slot": "ability1", "cooldown": 8.0},
	"leap_strike": {"slot": "ability1", "cooldown": 7.0},
	"immovable": {"slot": "ult", "cooldown": 40.0},
	"berserk": {"slot": "ult", "cooldown": 45.0},
}
## Which input action triggers each slot.
const SLOT_ACTION: Dictionary = {
	"attack": "shoot",
	"dash": "mobility",
	"ability1": "utility",
	"ult": "grenade",
}

var _player: PlayerController = null
var _camera: Camera3D = null
var _is_local: bool = false

var _abilities: Array = ["melee", "dash"]
var _tags: Dictionary = {}
var _cooldowns: Dictionary = {}  # ability id -> remaining seconds
var _attack_cd: float = 0.0

# Berserk capstone window (seconds remaining) + AoE tick accumulator.
var _berserk_time: float = 0.0
var _berserk_tick: float = 0.0

# First-person viewmodel (local player): a two-handed longsword that swings.
var _sword: Node3D = null
var _sword_rest: Transform3D = Transform3D.IDENTITY
var _swing_tween: Tween = null

func setup(player: PlayerController, camera: Camera3D, is_local: bool) -> void:
	_player = player
	_camera = camera
	_is_local = is_local
	if _is_local:
		_build_viewmodel()

## Apply a SpecTree's resolved kit: available abilities + active passive tags.
func configure(abilities: Array, tags: Dictionary) -> void:
	_abilities = abilities.duplicate()
	_tags = tags.duplicate()

func _process(delta: float) -> void:
	if _attack_cd > 0.0:
		_attack_cd -= delta
	for id in _cooldowns:
		if _cooldowns[id] > 0.0:
			_cooldowns[id] = maxf(0.0, _cooldowns[id] - delta)
	if _berserk_time > 0.0:
		_berserk_time -= delta
		_berserk_tick -= delta
		if _berserk_tick <= 0.0 and _player:
			_berserk_tick = 0.5
			_aoe_damage(_player.global_position, 3.0, MELEE_DAMAGE * 0.4 * _damage_mult())
			_player.heal(6.0)
	if _is_local:
		_handle_input()

# === Input ===

func _handle_input() -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if _player and (_player.is_dead or _player.is_downed or _player.is_stunned()):
		return
	for id in _abilities:
		var def: Dictionary = ABILITY_DEFS.get(id, {})
		var action: String = SLOT_ACTION.get(def.get("slot", ""), "")
		if action == "" or not Input.is_action_just_pressed(action):
			continue
		_try_cast(id, def)

func _try_cast(id: String, def: Dictionary) -> void:
	if id == "melee":
		if _attack_cd <= 0.0:
			_do_melee()
			# Berserk roughly halves the swing interval.
			_attack_cd = MELEE_INTERVAL * _fire_rate_mult() * (0.5 if _berserk_time > 0.0 else 1.0)
		return
	if _cooldowns.get(id, 0.0) > 0.0:
		return
	var cd: float = float(def.get("cooldown", 0.0))
	_cooldowns[id] = cd
	ability_state_changed.emit(def.get("slot", ""), id, cd, cd)
	_cast(id)

## Reduce all ability cooldowns (Rampage tag: kills cut cooldowns).
func reduce_cooldowns(seconds: float) -> void:
	for id in _cooldowns:
		_cooldowns[id] = maxf(0.0, _cooldowns[id] - seconds)

# === Abilities ===

func _cast(id: String) -> void:
	match id:
		"dash": _do_dash()
		"shield_bash": _do_shield_bash()
		"leap_strike": _do_leap_strike()
		"immovable": _do_immovable()
		"berserk": _do_berserk()

## Short-range melee swing: damages the first body in front, with lifesteal /
## cooldown-on-kill passives applied.
func _do_melee() -> void:
	_swing()
	if _player:
		GameAudio.play_at(_player.global_position, "swing", "movement")
	var collider := _hitscan(MELEE_RANGE)
	if collider == null or not collider.has_method("request_damage"):
		return
	_apply_hit(collider, MELEE_DAMAGE * _damage_mult())

## Resolve a single melee hit: damage, hitmarker, and the lifesteal / rampage /
## stagger / momentum passives.
func _apply_hit(collider: Node, damage: float) -> void:
	var was_alive := _is_alive(collider)
	collider.request_damage(damage, _peer_id())
	_play_hitmarker(collider)
	if _tags.has("lifesteal") and _player:
		_player.heal(damage * float(_tags["lifesteal"].get("lifesteal", 0.0)))
	if _tags.has("stagger") and collider.has_method("apply_slow"):
		var s: Dictionary = _tags["stagger"]
		collider.apply_slow(1.0 + float(s.get("slow", 0.0)), float(s.get("time", 0.0)))
	var killed := was_alive and not _is_alive(collider)
	if killed and _tags.has("rampage"):
		reduce_cooldowns(float(_tags["rampage"].get("cdr", 0.0)) * 4.0)
	if killed and _tags.has("momentum") and _player:
		var m: Dictionary = _tags["momentum"]
		_player.apply_speed_burst(float(m.get("speed", 1.0)), float(m.get("time", 0.0)))

func _do_dash() -> void:
	if _player == null or _camera == null:
		return
	var forward := -_camera.global_transform.basis.z
	forward.y = 0.0
	_player.apply_knockback(forward.normalized() * DASH_SPEED)

## Shield Bash (Juggernaut 6): a sword hit that knocks back and stuns.
func _do_shield_bash() -> void:
	_swing()
	var collider := _hitscan(MELEE_RANGE)
	if collider == null or not collider.has_method("request_damage"):
		return
	_apply_hit(collider, MELEE_DAMAGE * _damage_mult())
	if collider.has_method("apply_knockback") and _camera:
		collider.apply_knockback(-_camera.global_transform.basis.z * 12.0)
	if collider.has_method("apply_stun"):
		collider.apply_stun(1.2)

## Leap Strike (Berserker 6): leap forward, then an AoE slam on landing.
func _do_leap_strike() -> void:
	if _player and _camera:
		var dir := -_camera.global_transform.basis.z
		_player.apply_knockback(dir * DASH_SPEED + Vector3.UP * 6.0)
	await get_tree().create_timer(0.45).timeout
	if is_instance_valid(_player):
		_swing()
		_aoe_damage(_player.global_position, 4.0, MELEE_DAMAGE * 1.5 * _damage_mult())

## Immovable (Juggernaut capstone): ~5s of 70% damage reduction.
func _do_immovable() -> void:
	if _player:
		_player.apply_defensive_window(0.3, 5.0)

## Berserk (Berserker capstone): ~6s of fast attacks, lifesteal, spin AoE.
func _do_berserk() -> void:
	_berserk_time = 6.0
	_berserk_tick = 0.0

# === First-person viewmodel (two-handed longsword) ===

## Build the sword in front of the camera, on the viewmodel visual layer.
func _build_viewmodel() -> void:
	if _camera == null:
		return
	_sword = Node3D.new()
	_sword.name = "SwordViewModel"
	# Held two-handed, centred-low, blade up and angled across the view.
	_sword.position = Vector3(0.12, -0.32, -0.55)
	_sword.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(8.0), deg_to_rad(10.0))
	_camera.add_child(_sword)
	_sword_rest = _sword.transform

	var steel := Color(0.74, 0.77, 0.82)
	var dark := Color(0.13, 0.12, 0.14)
	# Parts laid along local +Y (grip → guard → blade), origin at the hands.
	_add_part(Vector3(0.05, 0.05, 0.05), Vector3(0.0, -0.16, 0.0), dark)        # pommel
	_add_part(Vector3(0.045, 0.22, 0.045), Vector3(0.0, -0.02, 0.0), dark)       # grip
	_add_part(Vector3(0.24, 0.045, 0.05), Vector3(0.0, 0.10, 0.0), steel)        # crossguard
	_add_part(Vector3(0.05, 0.95, 0.018), Vector3(0.0, 0.60, 0.0), steel)        # blade
	# Two hands gripping the hilt (two-handed hold).
	var skin := Color(0.85, 0.68, 0.55)
	_add_part(Vector3(0.07, 0.08, 0.07), Vector3(0.0, 0.02, 0.02), skin)
	_add_part(Vector3(0.07, 0.08, 0.07), Vector3(0.0, -0.08, 0.02), skin)

func _add_part(part_size: Vector3, offset: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = part_size
	mesh.mesh = box
	mesh.position = offset
	mesh.layers = PlayerController.VIEWMODEL_VISUAL_LAYER
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.3
	mat.roughness = 0.5
	mesh.material_override = mat
	_sword.add_child(mesh)

## A quick diagonal slash of the sword, returning to rest.
func _swing() -> void:
	if _sword == null:
		return
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	_sword.transform = _sword_rest
	# Wind up slightly, slash down-and-across, then ease back to rest.
	var windup := _sword_rest.rotated_local(Vector3.RIGHT, deg_to_rad(25.0)).rotated_local(Vector3.FORWARD, deg_to_rad(-20.0))
	var slash := _sword_rest.rotated_local(Vector3.RIGHT, deg_to_rad(-55.0)).rotated_local(Vector3.FORWARD, deg_to_rad(40.0))
	_swing_tween = create_tween()
	_swing_tween.tween_property(_sword, "transform", windup, 0.06)
	_swing_tween.tween_property(_sword, "transform", slash, 0.08)
	_swing_tween.tween_property(_sword, "transform", _sword_rest, 0.16)

# === Helpers ===

## First damageable/world body along the camera forward within `range_m`.
func _hitscan(range_m: float) -> Node:
	if _camera == null:
		return null
	var space := _camera.get_world_3d().direct_space_state
	var origin := _camera.global_position
	var to := origin + (-_camera.global_transform.basis.z) * range_m
	var query := PhysicsRayQueryParameters3D.create(origin, to)
	query.collision_mask = 1
	if _player:
		query.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(query)
	return hit.get("collider") if not hit.is_empty() else null

## Damage every damageable body within `radius` of `center` (excludes self).
func _aoe_damage(center: Vector3, radius: float, damage: float) -> void:
	if _player == null:
		return
	var space := _player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = 1
	params.exclude = [_player.get_rid()]
	for result in space.intersect_shape(params, 16):
		var collider = result.get("collider")
		if collider and collider.has_method("request_damage"):
			collider.request_damage(damage, _peer_id())

func _is_alive(node: Node) -> bool:
	if node is PlayerController:
		return not (node.is_dead or node.is_downed)
	if node.has_method("is_alive"):
		return node.is_alive()
	return true

func _play_hitmarker(collider: Node) -> void:
	var teammate := false
	if collider is PlayerController:
		teammate = GameState._get_player_team(collider.authority_peer_id) == GameState._get_player_team(_peer_id())
	GameAudio.play_ui("hit_teammate" if teammate else "hit_enemy", -4.0)

func _damage_mult() -> float:
	return _player.stat_damage_mult if _player else 1.0

func _fire_rate_mult() -> float:
	return _player.stat_fire_rate_mult if _player else 1.0

func _peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()
