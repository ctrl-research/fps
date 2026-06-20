extends Node3D
class_name WeaponController
"""
Drives weapon handling for a single player body.

Responsibilities:
- Owns the two equipped weapon slots (primary / secondary) and switching.
- Fires hitscan raycasts or projectiles from the camera centre.
- Applies movement/spray inaccuracy and a CS-style climbing recoil pattern.
- Plays muzzle flash + gunshot audio locally and broadcasts them to peers.
- Tracks ammo and reload timing, emitting signals for the HUD.

Only the body's local authority reads input and resolves hits; remote bodies
keep a controller solely to replay fire effects received over RPC.
"""

## Emitted when the active weapon changes (switch / loadout refresh).
signal weapon_changed(weapon: Weapon)

## Emitted whenever the active weapon's ammo counts change.
signal ammo_changed(mag: int, reserve: int)

## Emitted when a reload begins; carries the reload duration in seconds.
signal reload_started(duration: float)

## Emitted when a reload completes.
signal reload_finished()

const PROJECTILE_SCENE: String = "res://addons/godot-multiplayer-weapon-system/player/projectile.tscn"
const GRENADE_SCENE: String = "res://addons/godot-multiplayer-weapon-system/player/grenade.tscn"
const HUD_SCRIPT: String = "res://addons/godot-multiplayer-weapon-system/ui/weapon_hud.gd"

## Maximum hitscan range in metres.
const MAX_DISTANCE: float = 1000.0

## Weapon types that fire full-auto while the trigger is held.
const AUTOMATIC_TYPES: Array[String] = ["assault_rifle", "smg"]

## Time without firing before the spray pattern resets, in seconds.
const SPRAY_RESET_TIME: float = 0.35

## How quickly accumulated recoil pitch is recovered (radians/second).
const RECOIL_RECOVER_SPEED: float = 1.2

## How long the muzzle flash stays visible, in seconds.
const FLASH_TIME: float = 0.05

# Throwable arcs: left-click mid-range throw vs right-click short lob.
const THROW_MID_SPEED: float = 18.0
const THROW_MID_LIFT: float = 3.5
const THROW_LOB_SPEED: float = 8.0
const THROW_LOB_LIFT: float = 6.0
const THROW_MID_COLOR: Color = Color(0.4, 0.85, 1.0)
const THROW_LOB_COLOR: Color = Color(1.0, 0.82, 0.3)
## Grenade falls under the project's default 3D gravity (not the player's).
const GRENADE_GRAVITY: float = 9.8
const TRAJ_STEPS: int = 40
const TRAJ_DT: float = 0.05

var _player: PlayerController = null
var _camera: Camera3D = null
var _is_local: bool = false

# [slot] = Weapon, where slot is "primary" or "secondary"
var _slots: Dictionary = {}
var _active_slot: String = "primary"

var _cooldown: float = 0.0
var _spray_index: int = 0
var _time_since_fire: float = 999.0
var _reloading: bool = false
var _reload_timer: float = 0.0
var _recoil_accum: float = 0.0

# Throwable mode: G pulls out a grenade (and cycles types); left-click throws
# mid-range, right-click lobs short. Holding either previews the trajectory.
var _throwable_active: bool = false
var _throwable_types: Array = []   # carried grenade ids with count > 0
var _throwable_index: int = 0
var _throw_aim: int = 0            # 0 none, 1 mid (LMB), 2 lob (RMB)
var _trajectory: ThrowTrajectory = null

var _muzzle: Node3D = null
var _flash_mesh: MeshInstance3D = null
var _flash_light: OmniLight3D = null
var _flash_timer: float = 0.0
var _viewmodel: Node3D = null
# Third-person weapon parented to the model's hand bone (mirror / other players).
var _hand_weapon: Node3D = null

## Wire the controller to its body and camera. Builds effect nodes, the local
## HUD, and the initial loadout. Called by PlayerController after add_child.
func setup(player: PlayerController, camera: Camera3D, is_local: bool) -> void:
	_player = player
	_camera = camera
	_is_local = is_local

	_build_effects()

	if _is_local:
		_build_hud()
		PlayerLoadout.loadout_changed.connect(refresh_loadout)
		refresh_loadout()

func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_set_flash_visible(false)

	if not _is_local:
		return

	_time_since_fire += delta
	if _time_since_fire > SPRAY_RESET_TIME:
		_spray_index = 0

	if _cooldown > 0.0:
		_cooldown -= delta

	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_complete_reload()

	_recover_recoil(delta)
	_handle_input()

	# Preview the throw arc while a throw button is held in throwable mode.
	if _throwable_active and _throw_aim != 0:
		_show_trajectory(_throw_aim == 2)
	elif _trajectory != null:
		_trajectory.hide_arc()

# === Input ===

func _handle_input() -> void:
	# Weapons are inert unless the player is in control of the view. The buy
	# menu (and any overlay) releases the mouse, which suppresses combat.
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		_throw_aim = 0
		return
	if _player and (_player.is_dead or _player.is_downed):
		_throw_aim = 0
		return

	# Switching to a weapon puts the throwable away.
	if Input.is_action_just_pressed("weapon_primary"):
		_exit_throwable()
		_switch_to("primary")
	elif Input.is_action_just_pressed("weapon_secondary"):
		_exit_throwable()
		_switch_to("secondary")
	elif Input.is_action_just_pressed("weapon_melee"):
		_exit_throwable()
		_switch_to("melee")

	# G pulls out a throwable; pressing it again cycles between carried types.
	if Input.is_action_just_pressed("grenade"):
		_toggle_throwable()

	# In throwable mode, left-click throws mid-range and right-click lobs short;
	# the gun's fire/reload are suppressed.
	if _throwable_active:
		_handle_throw_input()
		return

	if Input.is_action_just_pressed("reload"):
		_start_reload()

	var weapon := _active()
	if weapon == null:
		return
	if weapon.type() in AUTOMATIC_TYPES:
		if Input.is_action_pressed("shoot"):
			_try_fire()
	elif Input.is_action_just_pressed("shoot"):
		_try_fire()

# === Grenades ===

## Enter throwable mode (or cycle to the next carried type if already in it).
func _toggle_throwable() -> void:
	_refresh_throwable_types()
	if _throwable_types.is_empty():
		return
	if not _throwable_active:
		_throwable_active = true
		_throwable_index = 0
	else:
		_throwable_index = (_throwable_index + 1) % _throwable_types.size()
	_throw_aim = 0
	if _player:
		GameAudio.play_at(_player.global_position, "grenade_pull", "movement")

## Leave throwable mode (back to the held weapon).
func _exit_throwable() -> void:
	if not _throwable_active:
		return
	_throwable_active = false
	_throw_aim = 0
	if _trajectory != null:
		_trajectory.hide_arc()

## Left-click aims/throws mid-range; right-click aims/lobs short. The aim is set
## on press (so _process previews the arc) and the grenade flies on release.
func _handle_throw_input() -> void:
	if Input.is_action_just_pressed("shoot"):
		_throw_aim = 1
	if Input.is_action_just_pressed("throw_lob"):
		_throw_aim = 2
	if Input.is_action_just_released("shoot") and _throw_aim == 1:
		_do_throw(false)
	if Input.is_action_just_released("throw_lob") and _throw_aim == 2:
		_do_throw(true)

func _do_throw(is_lob: bool) -> void:
	_throw_aim = 0
	if _trajectory != null:
		_trajectory.hide_arc()
	var grenade_id := _current_throwable_id()
	if grenade_id == "" or _camera == null or PlayerLoadout.grenades.get(grenade_id, 0) <= 0:
		return
	var data := WeaponDatabase.get_grenade(grenade_id)
	PlayerLoadout.use_grenade(grenade_id)

	var speed: float = THROW_LOB_SPEED if is_lob else THROW_MID_SPEED
	var lift: float = THROW_LOB_LIFT if is_lob else THROW_MID_LIFT
	var forward := -_camera.global_transform.basis.z
	var scene: PackedScene = load(GRENADE_SCENE)
	var grenade: Grenade = scene.instantiate()
	# Set the spawn position before add_child (it's a physics body).
	grenade.position = _camera.global_position + forward * 0.6
	var world := _player.get_parent() if _player else get_tree().current_scene
	world.add_child(grenade)
	grenade.throw_from(data, _peer_id(), forward, Grenade.FUSE_TIME, speed, lift)
	GameAudio.play_at(grenade.global_position, "grenade_throw", "grenade")

	# Drop empty types from the cycle; leave throwable mode if nothing's left.
	_refresh_throwable_types()
	if _throwable_types.is_empty():
		_exit_throwable()
	else:
		_throwable_index = clampi(_throwable_index, 0, _throwable_types.size() - 1)

## Carried grenade ids that still have ammo, in a stable order.
func _refresh_throwable_types() -> void:
	_throwable_types.clear()
	for grenade_id in PlayerLoadout.grenades:
		if PlayerLoadout.grenades[grenade_id] > 0:
			_throwable_types.append(grenade_id)
	if _throwable_index >= _throwable_types.size():
		_throwable_index = 0

func _current_throwable_id() -> String:
	if _throwable_index < _throwable_types.size():
		return _throwable_types[_throwable_index]
	return ""

## Show the dotted arc for the current throw type, simulating the grenade's
## flight (same gravity) until it hits geometry or runs out of steps.
func _show_trajectory(is_lob: bool) -> void:
	if _camera == null:
		return
	if _trajectory == null:
		_trajectory = ThrowTrajectory.new()
		# Parented to the controller (freed with the player); top_level keeps it
		# in world space regardless.
		add_child(_trajectory)
	var speed: float = THROW_LOB_SPEED if is_lob else THROW_MID_SPEED
	var lift: float = THROW_LOB_LIFT if is_lob else THROW_MID_LIFT
	var color: Color = THROW_LOB_COLOR if is_lob else THROW_MID_COLOR
	_trajectory.show_arc(_simulate_arc(speed, lift), color)

func _simulate_arc(speed: float, lift: float) -> Array:
	var points: Array = []
	var forward := -_camera.global_transform.basis.z
	var pos := _camera.global_position + forward * 0.6
	var vel := forward * speed + Vector3.UP * lift
	var space := _camera.get_world_3d().direct_space_state
	for _i in TRAJ_STEPS:
		points.append(pos)
		var next := pos + vel * TRAJ_DT
		vel.y -= GRENADE_GRAVITY * TRAJ_DT
		var query := PhysicsRayQueryParameters3D.create(pos, next)
		query.collision_mask = 1
		if _player:
			query.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			points.append(hit.get("position"))
			break
		pos = next
	return points

# === Loadout / switching ===

## Rebuild the weapon slots from the local PlayerLoadout, preserving ammo for
## weapons that are unchanged. Local-authority only.
func refresh_loadout() -> void:
	_sync_slot("primary", PlayerLoadout.primary_weapon)
	_sync_slot("secondary", PlayerLoadout.secondary_weapon)
	_sync_slot("melee", PlayerLoadout.melee_weapon)

	if not _slots.has(_active_slot):
		if _slots.has("primary"):
			_active_slot = "primary"
		elif _slots.has("secondary"):
			_active_slot = "secondary"

	var weapon := _active()
	if weapon:
		weapon_changed.emit(weapon)
		ammo_changed.emit(weapon.mag, weapon.reserve)
		_update_viewmodel(weapon)

func _sync_slot(slot: String, weapon_id: String) -> void:
	if weapon_id == "":
		_slots.erase(slot)
		return
	var current: Weapon = _slots.get(slot)
	if current and current.id == weapon_id:
		return
	var weapon := Weapon.new(weapon_id)
	if weapon.is_valid():
		_slots[slot] = weapon

func _switch_to(slot: String) -> void:
	if slot == _active_slot:
		return
	var weapon: Weapon = _slots.get(slot)
	if weapon == null:
		return
	_active_slot = slot
	_reloading = false
	_spray_index = 0
	weapon_changed.emit(weapon)
	ammo_changed.emit(weapon.mag, weapon.reserve)
	_update_viewmodel(weapon)

func _active() -> Weapon:
	return _slots.get(_active_slot)

# === Firing ===

func _try_fire() -> void:
	var weapon := _active()
	if weapon == null or _reloading or _cooldown > 0.0:
		return
	if not weapon.can_fire():
		# Out of ammo — auto-reload instead of dry-firing.
		_start_reload()
		return

	weapon.consume()
	_cooldown = weapon.fire_rate() * _fire_rate_mult()
	_time_since_fire = 0.0

	# Melee is a swing, not a shot: short-range hit, no muzzle flash / gunshot /
	# recoil — just the viewmodel lunge.
	if weapon.is_melee():
		_fire_hitscan(weapon)
		_swing_viewmodel()
		if _player:
			GameAudio.play_at(_player.global_position, "swing", "movement")
		return

	if weapon.fire_mode() == "projectile":
		_fire_projectile(weapon)
	else:
		_fire_hitscan(weapon)

	_apply_recoil(weapon)
	_spray_index += 1

	_play_fire_effects(weapon.type())
	_broadcast_fire_effects(weapon.type())
	ammo_changed.emit(weapon.mag, weapon.reserve)

	# Auto-reload as soon as the magazine runs dry.
	if weapon.mag == 0:
		_start_reload()

## A quick forward stab of the viewmodel — the knife swing feedback.
func _swing_viewmodel() -> void:
	if _viewmodel == null:
		return
	var tween := create_tween()
	tween.tween_property(_viewmodel, "rotation:x", deg_to_rad(-50.0), 0.05)
	tween.tween_property(_viewmodel, "rotation:x", 0.0, 0.12)

func _fire_hitscan(weapon: Weapon) -> void:
	if _camera == null:
		return
	var space := _camera.get_world_3d().direct_space_state
	var origin := _camera.global_position
	var spread := _current_spread(weapon)
	for _i in weapon.pellets():
		var dir := _aim_direction(spread)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * weapon.range_m())
		query.collide_with_bodies = true
		query.collision_mask = 1  # layer 1 = world + characters; ignores thrown grenades
		if _player:
			query.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var collider = hit.get("collider")
		# Any body exposing request_damage is damageable (players, dummies, …).
		if collider and collider.has_method("request_damage"):
			collider.request_damage(weapon.damage() * _damage_mult(), _peer_id())
			_play_hitmarker(collider)

## Local hit feedback: a distinct tone for hitting a teammate vs an enemy.
func _play_hitmarker(collider: Node) -> void:
	var teammate := false
	if collider is PlayerController:
		teammate = GameState._get_player_team(collider.authority_peer_id) == GameState._get_player_team(_peer_id())
	GameAudio.play_ui("hit_teammate" if teammate else "hit_enemy", -4.0)

func _fire_projectile(weapon: Weapon) -> void:
	if _camera == null:
		return
	var scene: PackedScene = load(PROJECTILE_SCENE)
	var projectile: Projectile = scene.instantiate()
	projectile.speed = weapon.projectile_speed()
	projectile.damage = weapon.damage() * _damage_mult()
	projectile.attacker_id = _peer_id()
	projectile.shooter = _player

	var world := _player.get_parent() if _player else get_tree().current_scene
	world.add_child(projectile)

	var dir := _aim_direction(_current_spread(weapon))
	var muzzle_pos := _camera.global_position + (-_camera.global_transform.basis.z) * 0.5
	projectile.launch(muzzle_pos, dir)

## Current cone half-angle (radians) combining base spread, movement
## inaccuracy, and accumulated spray.
func _current_spread(weapon: Weapon) -> float:
	var spread := weapon.base_spread()
	if _player:
		var horizontal := Vector3(_player.velocity.x, 0.0, _player.velocity.z).length()
		var move_factor: float = clamp(horizontal / PlayerController.WALK_SPEED, 0.0, 1.0)
		spread += weapon.base_spread() * move_factor * 1.5
	spread += float(_spray_index) * weapon.recoil() * 0.01
	return spread

## A randomised direction within the spread cone around the camera forward axis.
func _aim_direction(spread: float) -> Vector3:
	var basis := _camera.global_transform.basis
	var forward := -basis.z
	var yaw := randf_range(-1.0, 1.0) * spread
	var pitch := randf_range(-1.0, 1.0) * spread
	forward = forward.rotated(basis.x.normalized(), pitch)
	forward = forward.rotated(basis.y.normalized(), yaw)
	return forward.normalized()

## Kick the view following a CS-style pattern: a vertical climb that decelerates
## as the spray lengthens, with a small alternating horizontal sway.
func _apply_recoil(weapon: Weapon) -> void:
	if _player == null:
		return
	var climb: float = 1.0 - clamp(float(_spray_index) / 12.0, 0.0, 0.7)
	var pitch_kick := weapon.recoil() * 0.02 * climb
	var yaw_kick := sin(float(_spray_index) * 1.3) * weapon.recoil() * 0.006
	_player.add_look_recoil(pitch_kick, yaw_kick)
	_recoil_accum += pitch_kick

func _recover_recoil(delta: float) -> void:
	if _recoil_accum <= 0.0 or _time_since_fire < 0.1 or _player == null:
		return
	var recovered: float = min(_recoil_accum, delta * RECOIL_RECOVER_SPEED)
	_player.add_look_recoil(-recovered, 0.0)
	_recoil_accum -= recovered

# === Reload ===

func _start_reload() -> void:
	var weapon := _active()
	if weapon == null or _reloading or not weapon.can_reload():
		return
	_reloading = true
	_reload_timer = weapon.reload_time()
	reload_started.emit(weapon.reload_time())
	if _player:
		GameAudio.play_at(_player.global_position, "reload", "weapon")

func _complete_reload() -> void:
	_reloading = false
	var weapon := _active()
	if weapon:
		weapon.reload()
		ammo_changed.emit(weapon.mag, weapon.reserve)
	reload_finished.emit()

# === Effects ===

func _build_effects() -> void:
	_muzzle = Node3D.new()
	_muzzle.name = "Muzzle"
	# Sit the muzzle in front of and below the camera, roughly at gun height.
	_muzzle.position = Vector3(0.25, -0.33, -0.7)
	if _camera:
		_camera.add_child(_muzzle)
	else:
		add_child(_muzzle)

	# The first-person viewmodel only exists for the local player (so remote
	# bodies don't carry a gun at head height); they get the hand weapon instead.
	if _is_local:
		_build_viewmodel()

	var flash_material := StandardMaterial3D.new()
	flash_material.emission_enabled = true
	flash_material.emission = Color(1.0, 0.85, 0.4)
	flash_material.albedo_color = Color(1.0, 0.9, 0.5)
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.06
	flash_mesh.height = 0.12
	_flash_mesh = MeshInstance3D.new()
	_flash_mesh.mesh = flash_mesh
	_flash_mesh.material_override = flash_material
	_flash_mesh.visible = false
	_muzzle.add_child(_flash_mesh)

	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.85, 0.5)
	_flash_light.light_energy = 4.0
	_flash_light.omni_range = 4.0
	_flash_light.visible = false
	_muzzle.add_child(_flash_light)

# === Weapon view model ===

## First-person viewmodel, in front of the camera, on the viewmodel layer (the
## mirror camera culls that layer so it never shows in reflections).
func _build_viewmodel() -> void:
	_viewmodel = Node3D.new()
	_viewmodel.name = "ViewModel"
	_viewmodel.position = Vector3(0.25, -0.25, -0.45)
	if _camera:
		_camera.add_child(_viewmodel)
	else:
		add_child(_viewmodel)

## Parent a third-person weapon to the model's hand bone so the mirror and other
## players see the gun in-hand. Called by the player once its model exists.
func attach_world_weapon() -> void:
	if _player == null:
		return
	var model: CharacterModel = _player.character_model()
	if model == null:
		return
	var socket := model.get_hand_socket()
	if socket == null:
		return
	_hand_weapon = Node3D.new()
	_hand_weapon.name = "HandWeapon"
	socket.add_child(_hand_weapon)
	var weapon := _active()
	if weapon:
		_update_viewmodel(weapon)

## Rebuild both the FP viewmodel (if any) and the hand weapon (if any).
func _update_viewmodel(weapon: Weapon) -> void:
	if _viewmodel != null:
		_rebuild_weapon(_viewmodel, weapon, PlayerController.VIEWMODEL_VISUAL_LAYER)
	if _hand_weapon != null:
		_rebuild_weapon(_hand_weapon, weapon, _body_layer())

## The layer the body renders on, so the hand weapon shows wherever the body does
## (local player: own-body layer → mirror only; everyone else: default).
func _body_layer() -> int:
	if _player and _player.is_multiplayer_authority():
		return PlayerController.OWN_BODY_VISUAL_LAYER
	return 1

## Build a simple blocky weapon (sized to the class) under `parent` on `layer`.
func _rebuild_weapon(parent: Node3D, weapon: Weapon, layer: int) -> void:
	for child in parent.get_children():
		child.queue_free()

	if weapon.is_melee():
		# Knife: a short blade and a dark handle.
		_add_gun_part(parent, Vector3(0.02, 0.05, 0.26), Vector3(0.0, 0.0, -0.13), Color(0.75, 0.78, 0.82), layer)
		_add_gun_part(parent, Vector3(0.04, 0.05, 0.1), Vector3(0.0, -0.01, 0.05), Color(0.12, 0.12, 0.14), layer)
		return

	var color := _viewmodel_color(weapon.type())
	var barrel_len := _barrel_length(weapon.type())

	# Receiver (main body), barrel, and grip — a recognisable gun silhouette.
	_add_gun_part(parent, Vector3(0.07, 0.1, 0.32), Vector3(0.0, 0.0, 0.0), color, layer)
	_add_gun_part(parent, Vector3(0.035, 0.035, barrel_len), Vector3(0.0, 0.015, -0.16 - barrel_len * 0.5), color, layer)
	_add_gun_part(parent, Vector3(0.06, 0.14, 0.06), Vector3(0.0, -0.11, 0.1), color, layer)

	match weapon.type():
		"sniper":
			_add_gun_part(parent, Vector3(0.04, 0.04, 0.18), Vector3(0.0, 0.09, 0.0), Color(0.05, 0.05, 0.06), layer)
		"smg", "assault_rifle", "shotgun":
			_add_gun_part(parent, Vector3(0.05, 0.16, 0.07), Vector3(0.0, -0.13, -0.05), color, layer)

func _add_gun_part(parent: Node3D, part_size: Vector3, offset: Vector3, color: Color, layer: int) -> void:
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = part_size
	part.mesh = box
	part.position = offset
	part.layers = layer
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.6
	material.roughness = 0.4
	part.material_override = material
	parent.add_child(part)

func _viewmodel_color(weapon_type: String) -> Color:
	match weapon_type:
		"pistol":
			return Color(0.18, 0.18, 0.2)
		"smg":
			return Color(0.2, 0.2, 0.16)
		"assault_rifle":
			return Color(0.22, 0.16, 0.12)
		"shotgun":
			return Color(0.26, 0.18, 0.1)
		"sniper":
			return Color(0.12, 0.14, 0.16)
		_:
			return Color(0.18, 0.18, 0.2)

func _barrel_length(weapon_type: String) -> float:
	match weapon_type:
		"pistol":
			return 0.12
		"smg":
			return 0.2
		"assault_rifle":
			return 0.34
		"shotgun":
			return 0.36
		"sniper":
			return 0.5
		_:
			return 0.28

## Muzzle flash + a category-specific gunshot at the muzzle (spatial, so other
## players hear it falling off with distance).
func _play_fire_effects(weapon_type: String) -> void:
	_set_flash_visible(true)
	_flash_timer = FLASH_TIME
	if _muzzle:
		GameAudio.play_at(_muzzle.global_position, "gunshot_" + weapon_type, "weapon")

func _set_flash_visible(value: bool) -> void:
	if _flash_mesh:
		_flash_mesh.visible = value
	if _flash_light:
		_flash_light.visible = value

func _broadcast_fire_effects(weapon_type: String) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_remote_fire_effects.rpc(weapon_type)

## Cosmetic-only: replay the firing peer's muzzle flash/gunshot on other clients.
@rpc("any_peer", "call_remote", "unreliable")
func _remote_fire_effects(weapon_type: String) -> void:
	_play_fire_effects(weapon_type)

# === HUD ===

func _build_hud() -> void:
	# Untyped so the dynamically-attached HUD script's bind() resolves at runtime.
	var hud = CanvasLayer.new()
	hud.name = "WeaponHud"
	hud.set_script(load(HUD_SCRIPT))
	add_child(hud)
	hud.bind(self)

# === Helpers exposed to the HUD ===

## Current spread in radians for the active weapon, for crosshair sizing.
func current_spread() -> float:
	var weapon := _active()
	if weapon == null:
		return 0.0
	return _current_spread(weapon)

func is_reloading() -> bool:
	return _reloading

func _peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()

## Evolution stat multipliers from the owning player (1.0 if unset).
func _damage_mult() -> float:
	return _player.stat_damage_mult if _player else 1.0

func _fire_rate_mult() -> float:
	return _player.stat_fire_rate_mult if _player else 1.0
