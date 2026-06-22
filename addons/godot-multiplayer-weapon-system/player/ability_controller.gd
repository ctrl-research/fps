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
const BOLT_DAMAGE: float = 22.0
const BOLT_INTERVAL: float = 0.7
const BLINK_DISTANCE: float = 9.0

## ability id -> {slot, cooldown}. slot maps to an input action below; "attack"
## abilities also use "interval" (their base swing/cast time).
const ABILITY_DEFS: Dictionary = {
	"melee": {"slot": "attack", "interval": 0.55},
	"magic_bolt": {"slot": "attack", "interval": 0.7},
	"arrow": {"slot": "attack", "interval": 0.5},
	"dash": {"slot": "dash", "cooldown": 4.0},
	"blink": {"slot": "dash", "cooldown": 3.0},
	"shield_bash": {"slot": "ability1", "cooldown": 8.0},
	"leap_strike": {"slot": "ability1", "cooldown": 7.0},
	"fireball": {"slot": "ability1", "cooldown": 6.0},
	"frost_nova": {"slot": "ability1", "cooldown": 7.0},
	"power_shot": {"slot": "ability1", "cooldown": 6.0},
	"multishot": {"slot": "ability1", "cooldown": 7.0},
	"immovable": {"slot": "ult", "cooldown": 40.0},
	"berserk": {"slot": "ult", "cooldown": 45.0},
	"meteor": {"slot": "ult", "cooldown": 35.0},
	"blizzard": {"slot": "ult", "cooldown": 38.0},
	"snipe": {"slot": "ult", "cooldown": 30.0},
	"arrow_storm": {"slot": "ult", "cooldown": 35.0},
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
var _swing_dir: float = 1.0            # alternates each swing (right<->left)
var _arc: MeshInstance3D = null        # slash arc effect
var _arc_mat: StandardMaterial3D = null
var _arc_tween: Tween = null
var _orb: MeshInstance3D = null      # mage palm fireball
var _orb_tween: Tween = null

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
		if action == "":
			continue
		# The primary attack fires continuously while held (gated by the attack
		# interval); other abilities trigger on the initial press only.
		var triggered := Input.is_action_pressed(action) if def.get("slot", "") == "attack" else Input.is_action_just_pressed(action)
		if not triggered:
			continue
		_try_cast(id, def)

func _try_cast(id: String, def: Dictionary) -> void:
	# Primary attack (melee swing / magic bolt) — gated by the attack interval.
	if def.get("slot", "") == "attack":
		if _attack_cd <= 0.0:
			_cast(id)
			# Berserk roughly halves the attack interval.
			_attack_cd = float(def.get("interval", 0.55)) * _fire_rate_mult() * (0.5 if _berserk_time > 0.0 else 1.0)
		return
	if _cooldowns.get(id, 0.0) > 0.0:
		return
	var cd: float = float(def.get("cooldown", 0.0))
	_cooldowns[id] = cd
	ability_state_changed.emit(def.get("slot", ""), id, cd, cd)
	_cast(id)

## Short icons for base-kit abilities (granted ones get their node's icon).
const BASE_ICONS: Dictionary = {"dash": "DASH", "blink": "BLINK"}
## Slots shown on the cooldown HUD (the primary attack has no cooldown).
const COOLDOWN_SLOTS: Array[String] = ["dash", "ability1", "ult"]

## Cooldown HUD data: one entry per cooldown ability the player has.
func cooldown_slots() -> Array:
	var out: Array = []
	for id in _abilities:
		var def: Dictionary = ABILITY_DEFS.get(id, {})
		var slot: String = def.get("slot", "")
		if not COOLDOWN_SLOTS.has(slot):
			continue
		var icon: String = BASE_ICONS.get(id, ClassDatabase.ability_icon(id))
		out.append({
			"id": id,
			"icon": icon,
			"key": Settings.binding_label(SLOT_ACTION.get(slot, "")),
			"cooldown": float(def.get("cooldown", 0.0)),
			"remaining": float(_cooldowns.get(id, 0.0)),
		})
	return out

## Reduce all ability cooldowns (Rampage tag: kills cut cooldowns).
func reduce_cooldowns(seconds: float) -> void:
	for id in _cooldowns:
		_cooldowns[id] = maxf(0.0, _cooldowns[id] - seconds)

# === Abilities ===

func _cast(id: String) -> void:
	match id:
		"melee": _do_melee()
		"magic_bolt": _do_magic_bolt()
		"arrow": _do_arrow()
		"dash": _do_dash()
		"blink": _do_blink()
		"shield_bash": _do_shield_bash()
		"leap_strike": _do_leap_strike()
		"fireball": _do_fireball()
		"frost_nova": _do_frost_nova()
		"power_shot": _do_power_shot()
		"multishot": _do_multishot()
		"immovable": _do_immovable()
		"berserk": _do_berserk()
		"meteor": _do_meteor()
		"blizzard": _do_blizzard()
		"snipe": _do_snipe()
		"arrow_storm": _do_arrow_storm()

## Short-range melee swing: damages the first body in front, with lifesteal /
## cooldown-on-kill passives applied.
func _do_melee() -> void:
	_swing()
	if _player:
		GameAudio.play_at(_player.global_position, "swing", "movement")
	# A small-to-medium hitbox in front of the warrior — hits everything it
	# overlaps, so clumped enemies all take the hit.
	_melee_sweep(MELEE_DAMAGE * _damage_mult())

## Damage every damageable body in a sphere just in front of the player.
func _melee_sweep(damage: float) -> void:
	if _player == null or _camera == null:
		return
	var forward := -_camera.global_transform.basis.z
	var center := _player.global_position + forward * (MELEE_RANGE * 0.55)
	center.y = _player.global_position.y
	var space := _player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = MELEE_RANGE * 0.7
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = 1
	params.exclude = [_player.get_rid()]
	for result in space.intersect_shape(params, 16):
		var collider = result.get("collider")
		if collider and collider.has_method("request_damage"):
			_apply_hit(collider, damage)

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

# === Mage abilities ===

## Magic Bolt (base attack): a single-target travelling projectile.
func _do_magic_bolt() -> void:
	_thrust()
	_spawn_projectile(BOLT_DAMAGE * _damage_mult(), 0.0, Color(0.5, 0.7, 1.0), 42.0)

## Blink (mobility): teleport forward to the first clear spot, up to BLINK_DISTANCE.
func _do_blink() -> void:
	if _player == null or _camera == null:
		return
	var dir := -_camera.global_transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var from := _player.global_position
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP, from + Vector3.UP + dir * BLINK_DISTANCE)
	query.collision_mask = 1
	query.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(query)
	var dist := BLINK_DISTANCE
	if not hit.is_empty():
		dist = maxf(0.0, from.distance_to(hit.get("position") as Vector3) - 1.0)
	_player.global_position = from + dir * dist

## Fireball (Pyromancer 6): a projectile that bursts on impact for AoE.
func _do_fireball() -> void:
	_thrust()
	_spawn_projectile(MELEE_DAMAGE * 1.2 * _damage_mult(), 4.0, Color(1.0, 0.5, 0.2), 32.0)

## Frost Nova (Frost Warden 6): instant AoE around the caster that damages + slows.
func _do_frost_nova() -> void:
	if _player == null:
		return
	_aoe_damage(_player.global_position, 5.0, MELEE_DAMAGE * 0.8 * _damage_mult())
	_aoe_slow(_player.global_position, 5.0, 1.5, 2.5)

## Meteor (Pyromancer capstone): a heavy AoE at the aim point after a short delay.
func _do_meteor() -> void:
	var target := _aim_point(40.0)
	await get_tree().create_timer(1.0).timeout
	_aoe_damage(target, 6.0, MELEE_DAMAGE * 3.0 * _damage_mult())

## Blizzard (Frost Warden capstone): strong AoE damage + heavy slow at the aim point.
func _do_blizzard() -> void:
	var target := _aim_point(40.0)
	_aoe_damage(target, 6.5, MELEE_DAMAGE * 1.5 * _damage_mult())
	_aoe_slow(target, 6.5, 2.0, 4.0)

## Arrow (base attack): a fast single-target projectile; pierces with Piercing Tips.
func _do_arrow() -> void:
	_release()
	_spawn_projectile(BOLT_DAMAGE * _damage_mult(), 0.0, Color(0.85, 0.78, 0.55), 60.0, _tags.has("pierce"))

## Power Shot (Marksman 6): a high-damage piercing arrow.
func _do_power_shot() -> void:
	_release()
	_spawn_projectile(MELEE_DAMAGE * 1.6 * _damage_mult(), 0.0, Color(1.0, 0.9, 0.4), 70.0, true)

## Snipe (Marksman capstone): a massive piercing arrow.
func _do_snipe() -> void:
	_release()
	_spawn_projectile(MELEE_DAMAGE * 4.0 * _damage_mult(), 0.0, Color(1.0, 1.0, 0.6), 95.0, true)

## Multishot (Skirmisher 6): three arrows in a horizontal spread.
func _do_multishot() -> void:
	_release()
	if _camera == null:
		return
	var forward := -_camera.global_transform.basis.z
	for deg: float in [-12.0, 0.0, 12.0]:
		var d := forward.rotated(Vector3.UP, deg_to_rad(deg))
		_spawn_projectile(BOLT_DAMAGE * 0.8 * _damage_mult(), 0.0, Color(0.85, 0.78, 0.55), 60.0, _tags.has("pierce"), d)

## Arrow Storm (Skirmisher capstone): a rain of arrows (AoE) at the aim point.
func _do_arrow_storm() -> void:
	var target := _aim_point(40.0)
	await get_tree().create_timer(0.6).timeout
	_aoe_damage(target, 6.0, MELEE_DAMAGE * 2.0 * _damage_mult())
	_aoe_slow(target, 6.0, 1.5, 2.0)

## Spawn a MagicProjectile from the camera. `dir` defaults to the aim direction.
func _spawn_projectile(damage: float, aoe_radius: float, color: Color, speed: float,
		pierce: bool = false, dir: Vector3 = Vector3.ZERO) -> void:
	if _camera == null:
		return
	var forward := -_camera.global_transform.basis.z
	var fly := dir if dir != Vector3.ZERO else forward
	var proj := MagicProjectile.new()
	proj.damage = damage
	proj.aoe_radius = aoe_radius
	proj.color = color
	proj.speed = speed
	proj.pierce = pierce
	proj.attacker_id = _peer_id()
	proj.shooter = _player
	# Carry the caster's on-hit passives (lifesteal, slow).
	if _tags.has("lifesteal"):
		proj.lifesteal = float(_tags["lifesteal"].get("lifesteal", 0.0))
	if _tags.has("stagger"):
		var s: Dictionary = _tags["stagger"]
		proj.slow_factor = 1.0 + float(s.get("slow", 0.0))
		proj.slow_time = float(s.get("time", 0.0))
	var world := _player.get_parent() if _player else get_tree().current_scene
	world.add_child(proj)
	proj.launch(_camera.global_position + forward * 0.8, fly)

## Slow every damageable body within radius (for frost abilities).
func _aoe_slow(center: Vector3, radius: float, factor: float, seconds: float) -> void:
	if _player == null:
		return
	var space := _player.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = 1
	params.exclude = [_player.get_rid()]
	for result in space.intersect_shape(params, 24):
		var collider = result.get("collider")
		if collider and collider.has_method("apply_slow"):
			collider.apply_slow(factor, seconds)

## World point the camera is aimed at (raycast), or a point `dist` ahead if clear.
func _aim_point(dist: float) -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var origin := _camera.global_position
	var forward := -_camera.global_transform.basis.z
	var space := _camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * dist)
	query.collision_mask = 1
	if _player:
		query.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(query)
	return (hit.get("position") as Vector3) if not hit.is_empty() else origin + forward * dist

# === First-person viewmodel (sword / staff by class) ===

## Build the class's viewmodel in front of the camera (viewmodel visual layer).
func _build_viewmodel() -> void:
	if _camera == null:
		return
	_sword = Node3D.new()
	_sword.name = "ViewModel"
	_camera.add_child(_sword)
	var vm: String = "sword"
	if _player:
		vm = String(ClassDatabase.get_def(_player.class_id).get("viewmodel", "sword"))
	match vm:
		"palm": _build_palm()
		"bow": _build_bow()
		_: _build_sword()
	_sword_rest = _sword.transform

func _build_sword() -> void:
	# Held diagonally in the lower-right: blade axis ~60° above horizontal (30°
	# roll), with the tip tilted slightly toward the camera.
	_sword.position = Vector3(0.22, -0.46, -0.55)
	_sword.rotation = Vector3(deg_to_rad(12.0), deg_to_rad(0.0), deg_to_rad(-30.0))
	var steel := Color(0.74, 0.77, 0.82)
	var dark := Color(0.13, 0.12, 0.14)
	_add_part(Vector3(0.05, 0.05, 0.05), Vector3(0.0, -0.16, 0.0), dark)        # pommel
	_add_part(Vector3(0.045, 0.22, 0.045), Vector3(0.0, -0.02, 0.0), dark)       # grip
	_add_part(Vector3(0.24, 0.045, 0.05), Vector3(0.0, 0.10, 0.0), steel)        # crossguard
	_add_part(Vector3(0.05, 0.95, 0.018), Vector3(0.0, 0.60, 0.0), steel)        # blade
	# Both hands grip the handle: right hand on top (near the crossguard), left
	# hand below it.
	var skin := Color(0.85, 0.68, 0.55)
	_add_part(Vector3(0.09, 0.085, 0.1), Vector3(0.0, 0.05, 0.02), skin)         # right hand (top)
	_add_part(Vector3(0.09, 0.085, 0.1), Vector3(0.0, -0.06, 0.02), skin)        # left hand (bottom)
	_build_swing_arc()

## A translucent crescent that flashes along the blade's path on each swing.
func _build_swing_arc() -> void:
	_arc = MeshInstance3D.new()
	_arc.mesh = _make_arc_mesh()
	_arc.layers = PlayerController.VIEWMODEL_VISUAL_LAYER
	_arc.position = Vector3(0.05, -0.05, -0.7)
	_arc_mat = StandardMaterial3D.new()
	_arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arc_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_arc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arc_mat.no_depth_test = true
	_arc_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	_arc.material_override = _arc_mat
	_arc.visible = false
	_camera.add_child(_arc)

## A crescent ribbon in the XY plane (a thin arc), built once and reused.
func _make_arc_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 18
	var a0 := deg_to_rad(-75.0)
	var a1 := deg_to_rad(75.0)
	var r_in := 0.42
	var r_out := 0.72
	for i in segments:
		var ang0 := lerpf(a0, a1, float(i) / float(segments))
		var ang1 := lerpf(a0, a1, float(i + 1) / float(segments))
		var i0 := Vector3(cos(ang0), sin(ang0), 0.0) * r_in
		var o0 := Vector3(cos(ang0), sin(ang0), 0.0) * r_out
		var i1 := Vector3(cos(ang1), sin(ang1), 0.0) * r_in
		var o1 := Vector3(cos(ang1), sin(ang1), 0.0) * r_out
		st.add_vertex(i0)
		st.add_vertex(o0)
		st.add_vertex(o1)
		st.add_vertex(i0)
		st.add_vertex(o1)
		st.add_vertex(i1)
	return st.commit()

func _build_palm() -> void:
	# Right hand held palm-up in the lower-right, with a fireball hovering above.
	_sword.position = Vector3(0.46, -0.44, -0.6)
	_sword.rotation = Vector3(deg_to_rad(-8.0), deg_to_rad(-10.0), deg_to_rad(0.0))
	var skin := Color(0.85, 0.68, 0.55)
	_add_part(Vector3(0.14, 0.035, 0.16), Vector3(0.0, 0.0, 0.0), skin)          # palm
	_add_part(Vector3(0.05, 0.03, 0.07), Vector3(0.09, 0.01, -0.02), skin)       # thumb
	# Fingertips curled slightly up at the front edge (cupping the flame).
	for fx in [-0.045, 0.0, 0.045]:
		_add_part(Vector3(0.03, 0.05, 0.04), Vector3(fx, 0.02, -0.10), skin)

	# Hovering fireball.
	_orb = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.22
	_orb.mesh = sphere
	_orb.position = Vector3(0.0, 0.16, -0.01)
	_orb.layers = PlayerController.VIEWMODEL_VISUAL_LAYER
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.55, 0.2)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.45, 0.15)
	# On top of the world like the rest of the viewmodel.
	glow.no_depth_test = true
	glow.render_priority = 1
	_orb.material_override = glow
	_sword.add_child(_orb)
	# Gentle hover bob.
	_orb_tween = create_tween().set_loops()
	_orb_tween.tween_property(_orb, "position:y", 0.19, 0.9).set_trans(Tween.TRANS_SINE)
	_orb_tween.tween_property(_orb, "position:y", 0.13, 0.9).set_trans(Tween.TRANS_SINE)

func _build_bow() -> void:
	# A bow held in the lower-right: grip + two angled limbs, string, nocked arrow.
	_sword.position = Vector3(0.3, -0.4, -0.62)
	_sword.rotation = Vector3(deg_to_rad(0.0), deg_to_rad(-24.0), deg_to_rad(8.0))
	var wood := Color(0.42, 0.29, 0.17)
	_add_part(Vector3(0.04, 0.22, 0.04), Vector3(0.0, 0.0, 0.0), wood)                          # grip
	_add_part(Vector3(0.03, 0.45, 0.03), Vector3(0.0, 0.3, 0.05), wood, Vector3(28.0, 0.0, 0.0))   # upper limb
	_add_part(Vector3(0.03, 0.45, 0.03), Vector3(0.0, -0.3, 0.05), wood, Vector3(-28.0, 0.0, 0.0)) # lower limb
	_add_part(Vector3(0.006, 0.92, 0.006), Vector3(0.0, 0.0, 0.12), Color(0.8, 0.8, 0.8))       # string
	_add_part(Vector3(0.012, 0.012, 0.55), Vector3(0.0, 0.0, -0.16), Color(0.55, 0.4, 0.25))    # arrow shaft
	_add_part(Vector3(0.03, 0.03, 0.04), Vector3(0.0, 0.0, -0.44), Color(0.85, 0.85, 0.9))      # arrowhead

func _add_part(part_size: Vector3, offset: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = part_size
	mesh.mesh = box
	mesh.position = offset
	mesh.rotation = Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	mesh.layers = PlayerController.VIEWMODEL_VISUAL_LAYER
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.3
	mat.roughness = 0.5
	# Render the viewmodel on top of the world (never clipped by walls) while
	# keeping it in the main frame so the dither post-process still shades it.
	# no_depth_test moves it to the transparent pass, drawn after world geometry.
	mat.no_depth_test = true
	mat.render_priority = 1
	mesh.material_override = mat
	_sword.add_child(mesh)

## A diagonal slash: cock up-and-out to the right, then sweep the tip diagonally
## down toward screen centre (pitch forward + roll inward).
func _swing() -> void:
	if _sword == null:
		return
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	_sword.transform = _sword_rest
	# Alternate the sweep each swing: right->left, then left->right.
	var d := _swing_dir
	var windup := _sword_rest.rotated_local(Vector3.RIGHT, deg_to_rad(20.0)).rotated_local(Vector3.FORWARD, deg_to_rad(30.0 * d))
	var slash := _sword_rest.rotated_local(Vector3.RIGHT, deg_to_rad(-65.0)).rotated_local(Vector3.FORWARD, deg_to_rad(-50.0 * d))
	_swing_tween = create_tween()
	_swing_tween.tween_property(_sword, "transform", windup, 0.07)
	_swing_tween.tween_property(_sword, "transform", slash, 0.10)
	_swing_tween.tween_property(_sword, "transform", _sword_rest, 0.18)
	_flash_arc(d)
	_swing_dir = -_swing_dir

## Flash the slash arc, mirrored to match the swing direction, then fade it out.
func _flash_arc(d: float) -> void:
	if _arc == null:
		return
	if _arc_tween and _arc_tween.is_valid():
		_arc_tween.kill()
	# Orient the crescent diagonally along the swing, flipped per direction.
	_arc.rotation = Vector3(0.0, 0.0, deg_to_rad(-35.0 * d))
	_arc.scale = Vector3(d, 1.0, 1.0)
	_arc_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	_arc.visible = true
	_arc_tween = create_tween()
	_arc_tween.tween_property(_arc_mat, "albedo_color", Color(1.0, 1.0, 1.0, 0.0), 0.22)
	_arc_tween.tween_callback(func() -> void: _arc.visible = false)

## A forward jab (spell cast), returning to rest.
func _thrust() -> void:
	if _sword == null:
		return
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	_sword.transform = _sword_rest
	var jab := _sword_rest.translated_local(Vector3(0.0, 0.0, -0.2))
	_swing_tween = create_tween()
	_swing_tween.tween_property(_sword, "transform", jab, 0.07)
	_swing_tween.tween_property(_sword, "transform", _sword_rest, 0.14)

## A quick bow draw-back and release-snap, returning to rest.
func _release() -> void:
	if _sword == null:
		return
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	_sword.transform = _sword_rest
	var drawn := _sword_rest.translated_local(Vector3(0.0, 0.0, 0.1))
	_swing_tween = create_tween()
	_swing_tween.tween_property(_sword, "transform", drawn, 0.05)
	_swing_tween.tween_property(_sword, "transform", _sword_rest, 0.12)

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
