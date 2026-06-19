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

# Grenade cooking (hold to cook, release to throw).
var _cooking: bool = false
var _cook_time: float = 0.0
var _cook_grenade_id: String = ""

var _muzzle: Node3D = null
var _flash_mesh: MeshInstance3D = null
var _flash_light: OmniLight3D = null
var _audio: AudioStreamPlayer3D = null
var _flash_timer: float = 0.0
var _viewmodel: Node3D = null

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

	if _cooking:
		_cook_time += delta
		if _cook_time >= Grenade.FUSE_TIME:
			_release_grenade()  # held too long — cooks off on throw

	_recover_recoil(delta)
	_handle_input()

# === Input ===

func _handle_input() -> void:
	# Weapons are inert unless the player is in control of the view. The buy
	# menu (and any overlay) releases the mouse, which suppresses combat.
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if _player and (_player.is_dead or _player.is_downed):
		return

	if Input.is_action_just_pressed("weapon_primary"):
		_switch_to("primary")
	elif Input.is_action_just_pressed("weapon_secondary"):
		_switch_to("secondary")
	elif Input.is_action_just_pressed("weapon_melee"):
		_switch_to("melee")

	if Input.is_action_just_pressed("reload"):
		_start_reload()

	if Input.is_action_just_pressed("grenade"):
		_begin_cook()
	if Input.is_action_just_released("grenade"):
		_release_grenade()

	var weapon := _active()
	if weapon == null:
		return
	if weapon.type() in AUTOMATIC_TYPES:
		if Input.is_action_pressed("shoot"):
			_try_fire()
	elif Input.is_action_just_pressed("shoot"):
		_try_fire()

# === Grenades ===

## Press starts cooking the first grenade carried; release throws it with the
## fuse already counted down. Holding past the full fuse cooks it off.
func _begin_cook() -> void:
	if _cooking:
		return
	var grenade_id := _first_available_grenade()
	if grenade_id == "":
		return
	_cooking = true
	_cook_time = 0.0
	_cook_grenade_id = grenade_id

func _release_grenade() -> void:
	if not _cooking:
		return
	_cooking = false
	var grenade_id := _cook_grenade_id
	_cook_grenade_id = ""
	if _camera == null or PlayerLoadout.grenades.get(grenade_id, 0) <= 0:
		return
	var data := WeaponDatabase.get_grenade(grenade_id)
	PlayerLoadout.use_grenade(grenade_id)

	var scene: PackedScene = load(GRENADE_SCENE)
	var grenade: Grenade = scene.instantiate()
	var forward := -_camera.global_transform.basis.z
	# Set the spawn position before add_child (it's a physics body).
	grenade.position = _camera.global_position + forward * 0.6
	var world := _player.get_parent() if _player else get_tree().current_scene
	world.add_child(grenade)
	grenade.throw_from(data, _peer_id(), forward, maxf(Grenade.FUSE_TIME - _cook_time, 0.05))

func _first_available_grenade() -> String:
	for grenade_id in PlayerLoadout.grenades:
		if PlayerLoadout.grenades[grenade_id] > 0:
			return grenade_id
	return ""

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
	_cooldown = weapon.fire_rate()
	_time_since_fire = 0.0

	if weapon.fire_mode() == "projectile":
		_fire_projectile(weapon)
	else:
		_fire_hitscan(weapon)

	_apply_recoil(weapon)
	_spray_index += 1

	_play_fire_effects()
	_broadcast_fire_effects()
	ammo_changed.emit(weapon.mag, weapon.reserve)

	# Auto-reload as soon as the magazine runs dry (melee has no ammo).
	if not weapon.is_melee() and weapon.mag == 0:
		_start_reload()

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
			collider.request_damage(weapon.damage(), _peer_id())

func _fire_projectile(weapon: Weapon) -> void:
	if _camera == null:
		return
	var scene: PackedScene = load(PROJECTILE_SCENE)
	var projectile: Projectile = scene.instantiate()
	projectile.speed = weapon.projectile_speed()
	projectile.damage = weapon.damage()
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

	_audio = AudioStreamPlayer3D.new()
	_audio.stream = _build_gunshot_stream()
	_audio.unit_size = 8.0
	_muzzle.add_child(_audio)

# === Weapon view model ===

## Container for the held-weapon mesh, sitting in front of the camera.
func _build_viewmodel() -> void:
	_viewmodel = Node3D.new()
	_viewmodel.name = "ViewModel"
	# Lowered to sit around the character model's hand level.
	_viewmodel.position = Vector3(0.25, -0.35, -0.45)
	if _camera:
		_camera.add_child(_viewmodel)
	else:
		add_child(_viewmodel)

## Rebuild a simple blocky gun model sized to the active weapon's class.
func _update_viewmodel(weapon: Weapon) -> void:
	if _viewmodel == null:
		return
	for child in _viewmodel.get_children():
		child.queue_free()

	if weapon.is_melee():
		# Knife: a short blade and a dark handle.
		_add_gun_part(Vector3(0.02, 0.05, 0.26), Vector3(0.0, 0.0, -0.13), Color(0.75, 0.78, 0.82))
		_add_gun_part(Vector3(0.04, 0.05, 0.1), Vector3(0.0, -0.01, 0.05), Color(0.12, 0.12, 0.14))
		return

	var color := _viewmodel_color(weapon.type())
	var barrel_len := _barrel_length(weapon.type())

	# Receiver (main body), barrel, and grip — a recognisable gun silhouette.
	_add_gun_part(Vector3(0.07, 0.1, 0.32), Vector3(0.0, 0.0, 0.0), color)
	_add_gun_part(Vector3(0.035, 0.035, barrel_len), Vector3(0.0, 0.015, -0.16 - barrel_len * 0.5), color)
	_add_gun_part(Vector3(0.06, 0.14, 0.06), Vector3(0.0, -0.11, 0.1), color)

	match weapon.type():
		"sniper":
			# Scope on top.
			_add_gun_part(Vector3(0.04, 0.04, 0.18), Vector3(0.0, 0.09, 0.0), Color(0.05, 0.05, 0.06))
		"smg", "assault_rifle", "shotgun":
			# Magazine below the receiver.
			_add_gun_part(Vector3(0.05, 0.16, 0.07), Vector3(0.0, -0.13, -0.05), color)

func _add_gun_part(part_size: Vector3, offset: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = part_size
	part.mesh = box
	part.position = offset
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.6
	material.roughness = 0.4
	part.material_override = material
	_viewmodel.add_child(part)

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

func _play_fire_effects() -> void:
	_set_flash_visible(true)
	_flash_timer = FLASH_TIME
	if _audio:
		_audio.pitch_scale = randf_range(0.95, 1.05)
		_audio.play()

func _set_flash_visible(value: bool) -> void:
	if _flash_mesh:
		_flash_mesh.visible = value
	if _flash_light:
		_flash_light.visible = value

func _broadcast_fire_effects() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_remote_fire_effects.rpc()

## Cosmetic-only: replay the firing peer's muzzle flash/audio on other clients.
@rpc("any_peer", "call_remote", "unreliable")
func _remote_fire_effects() -> void:
	_play_fire_effects()

## Build a short procedural gunshot (noise burst + low thump) so the system has
## audible feedback without shipping binary audio assets.
func _build_gunshot_stream() -> AudioStreamWAV:
	var rate := 22050
	var sample_count := int(rate * 0.18)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / float(rate)
		var envelope: float = exp(-t * 28.0)
		var noise := randf_range(-1.0, 1.0) * envelope
		var thump: float = sin(t * TAU * 90.0) * exp(-t * 18.0) * 0.6
		var sample: float = clamp(noise + thump, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	return wav

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
