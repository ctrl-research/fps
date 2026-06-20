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

func setup(player: PlayerController, camera: Camera3D, is_local: bool) -> void:
	_player = player
	_camera = camera
	_is_local = is_local

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
	if _is_local:
		_handle_input()

# === Input ===

func _handle_input() -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if _player and (_player.is_dead or _player.is_downed):
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
			_attack_cd = MELEE_INTERVAL * _fire_rate_mult()
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
	if _player:
		GameAudio.play_at(_player.global_position, "swing", "movement")
	var collider := _hitscan(MELEE_RANGE)
	if collider == null or not collider.has_method("request_damage"):
		return
	var was_alive := _is_alive(collider)
	collider.request_damage(MELEE_DAMAGE * _damage_mult(), _peer_id())
	_play_hitmarker(collider)
	if _tags.has("lifesteal") and _player:
		_player.heal(MELEE_DAMAGE * _damage_mult() * float(_tags["lifesteal"].get("lifesteal", 0.0)))
	if _tags.has("rampage") and was_alive and not _is_alive(collider):
		reduce_cooldowns(float(_tags["rampage"].get("cdr", 0.0)) * 4.0)

func _do_dash() -> void:
	if _player == null or _camera == null:
		return
	var forward := -_camera.global_transform.basis.z
	forward.y = 0.0
	_player.apply_knockback(forward.normalized() * DASH_SPEED)

# Warrior actives — registered + dispatched here; full effects land in #80.
func _do_shield_bash() -> void:
	# Placeholder: a melee hit that also knocks the target back.
	var collider := _hitscan(MELEE_RANGE)
	if collider and collider.has_method("request_damage"):
		collider.request_damage(MELEE_DAMAGE * _damage_mult(), _peer_id())
		if collider.has_method("apply_knockback") and _camera:
			collider.apply_knockback(-_camera.global_transform.basis.z * 12.0)

func _do_leap_strike() -> void:
	# Placeholder: leap forward and up (AoE on land comes in #80).
	if _player and _camera:
		var dir := -_camera.global_transform.basis.z
		_player.apply_knockback(dir * DASH_SPEED + Vector3.UP * 6.0)

func _do_immovable() -> void:
	pass  # #80: timed damage-reduction + knockback immunity + taunt aura

func _do_berserk() -> void:
	pass  # #80: timed attack-speed + lifesteal + spinning AoE

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
