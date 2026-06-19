extends Node3D
"""
Offline practice range / tutorial.

A single local player (its own authority, since no network peer is active) can
learn the controls and try every loadout without setting up multiplayer. The
scene is laid out in three zones:

  1. Movement — signage plus a small obstacle course (steps, a gap, a low
     overhang) to practise walking, jumping, sprinting, crouching and sliding.
  2. Combat — signage for firing, reloading, and switching weapons.
  3. Firing range — a free loadout station (the buy menu with effectively
     infinite credits) and dummy targets at marked distances.

Press B to open the loadout station, ESC to return to the main menu.
"""

const PLAYER_SCENE: String = "res://addons/godot-multiplayer-weapon-system/player/player.tscn"
const DUMMY_SCENE: String = "res://addons/godot-multiplayer-weapon-system/player/target_dummy.tscn"
const BUY_MENU_SCENE: String = "res://addons/godot-multiplayer-weapon-system/ui/buy_menu.tscn"
const BOT_SCENE: String = "res://addons/godot-multiplayer-weapon-system/player/bot.tscn"
const MAIN_SCENE: String = "res://addons/godot-multiplayer-weapon-system/scenes/main.tscn"

## Bot positions: inside the enclosed arena (walls block sight until you enter).
const BOT_POSITIONS: Array[Vector3] = [
	Vector3(-22.0, 1.0, -14.0),
	Vector3(-24.0, 1.0, -16.5),
	Vector3(-20.0, 1.0, -12.0),
]

## Effectively unlimited credits for the loadout station.
const SANDBOX_CREDITS: int = 10_000_000

## Player spawn (faces -Z, toward the range).
const SPAWN: Vector3 = Vector3(0.0, 1.5, 8.0)

var _player: PlayerController = null
var _pause_menu: PauseMenu = null
var _buy_menu = null
var _was_captured: bool = false

func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_movement_course()
	_build_range()
	_build_signs()
	_build_bots()
	_spawn_player()
	_build_mirror()
	_setup_loadout_station()
	_build_hud_overlay()

func _process(_delta: float) -> void:
	# Browsers reserve Esc to exit pointer lock and don't deliver the keypress, so
	# the Esc action never reaches us on web. Detect the lock loss instead: if the
	# cursor was captured and is suddenly free with no menu open, the player hit
	# Esc — open the pause menu. (Godot only reports CAPTURED->VISIBLE on a real
	# unlock, so requesting capture while still unlocked won't false-trigger.)
	var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if _was_captured and not captured and not _any_menu_open():
		_toggle_pause()
	_was_captured = captured

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("disconnect_network"):
		return
	# Esc priority: close the buy menu first if it's open, otherwise toggle the
	# in-game (pause) menu. (On desktop Esc arrives here; on web the _process
	# lock-loss check above handles opening the pause menu.)
	if is_instance_valid(_buy_menu) and _buy_menu.is_open():
		_buy_menu.close_menu()
	else:
		_toggle_pause()

func _any_menu_open() -> bool:
	if is_instance_valid(_pause_menu):
		return true
	return is_instance_valid(_buy_menu) and _buy_menu.is_open()

## Esc opens the in-game menu (Resume / Settings / Leave); pressing it again
## while open resumes.
func _toggle_pause() -> void:
	if is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return
	_pause_menu = PauseMenu.new()
	add_child(_pause_menu)
	_pause_menu.resumed.connect(func() -> void: Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED))
	_pause_menu.leave_requested.connect(_on_leave_to_menu)

func _on_leave_to_menu() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file(MAIN_SCENE)

# === World ===

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.15, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.45)
	env.ambient_light_energy = 1.0

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)

func _build_floor() -> void:
	# Spans the spawn (z≈8) through the 30 m range (z≈-22).
	_add_static_box(Vector3(0.0, -0.5, -7.0), Vector3(70.0, 1.0, 70.0), Color(0.2, 0.22, 0.26))

## A small obstacle course off to the right of spawn.
func _build_movement_course() -> void:
	var step_color := Color(0.28, 0.3, 0.34)
	# Ascending steps to walk/jump up.
	_add_static_box(Vector3(7.0, 0.25, 6.0), Vector3(2.0, 0.5, 2.0), step_color)
	_add_static_box(Vector3(9.0, 0.6, 6.0), Vector3(2.0, 1.2, 2.0), step_color)
	_add_static_box(Vector3(11.0, 1.0, 6.0), Vector3(2.0, 2.0, 2.0), step_color)

	# A raised platform with a gap to jump across.
	_add_static_box(Vector3(9.0, 0.75, 1.5), Vector3(4.0, 1.5, 2.0), step_color)
	_add_static_box(Vector3(9.0, 0.75, -3.0), Vector3(4.0, 1.5, 2.0), step_color)

	# A low overhang to crouch/slide under (underside at y≈1.3).
	var overhang_color := Color(0.34, 0.28, 0.24)
	_add_static_box(Vector3(4.5, 0.6, 2.0), Vector3(0.4, 1.2, 0.4), overhang_color)
	_add_static_box(Vector3(6.5, 0.6, 2.0), Vector3(0.4, 1.2, 0.4), overhang_color)
	_add_static_box(Vector3(5.5, 1.45, 2.0), Vector3(2.4, 0.3, 1.2), overhang_color)

## The firing range: distance markers and dummy targets straight ahead.
func _build_range() -> void:
	# Distance is measured from the spawn point (z = 8).
	_add_distance_row(10.0, [Vector3(-2.0, 1.0, -2.0), Vector3(2.0, 1.0, -2.0)])
	_add_distance_row(20.0, [Vector3(-3.0, 1.0, -12.0), Vector3(0.0, 1.0, -12.0), Vector3(3.0, 1.0, -12.0)])
	_add_distance_row(30.0, [Vector3(-2.0, 1.0, -22.0), Vector3(2.0, 1.0, -22.0)])

	# Side cover to practise peeking.
	_add_static_box(Vector3(-6.0, 1.0, -8.0), Vector3(1.0, 2.0, 4.0), Color(0.3, 0.26, 0.22))
	_add_static_box(Vector3(6.0, 1.0, -8.0), Vector3(1.0, 2.0, 4.0), Color(0.3, 0.26, 0.22))

func _add_distance_row(meters: float, positions: Array) -> void:
	for pos in positions:
		_spawn_dummy(pos)
	# A marker post at the left edge of the row.
	var marker_z: float = positions[0].z
	_add_sign(Vector3(-7.0, 1.5, marker_z), "%dm" % int(meters), 96, Color(1.0, 0.85, 0.4))

func _build_signs() -> void:
	var movement := "MOVEMENT\nMove WASD · Look Mouse\nJump %s · Sprint %s\nCrouch %s (slides while moving)" % [
		_key_for("jump"), _key_for("sprint"), _key_for("crouch")]
	_add_sign(Vector3(8.0, 3.2, 7.5), movement, 56, Color(0.7, 0.9, 1.0))

	var combat := "COMBAT\nFire %s · Reload %s · Grenade %s (hold to cook)\nPrimary %s · Secondary %s · Loadout %s" % [
		_key_for("shoot"), _key_for("reload"), _key_for("grenade"),
		_key_for("weapon_primary"), _key_for("weapon_secondary"), _key_for("buy")]
	_add_sign(Vector3(0.0, 3.2, 4.0), combat, 52, Color(1.0, 0.8, 0.7))

	_add_sign(Vector3(0.0, 3.2, -26.0),
		"FIRING RANGE\nTargets respawn · Free loadout (%s)" % _key_for("buy"),
		56, Color(0.8, 1.0, 0.8))

## The display label for an action's first bound key/mouse button, read from the
## live InputMap so signage matches the actual bindings.
func _key_for(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var keycode: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			return OS.get_keycode_string(keycode)
		if event is InputEventMouseButton:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					return "LMB"
				MOUSE_BUTTON_RIGHT:
					return "RMB"
				_:
					return "Mouse %d" % event.button_index
	return "?"

# === Builders ===

## Build a StaticBody3D box (collision + mesh) on the default collision layer so
## the player and projectiles interact with it.
func _add_static_box(pos: Vector3, box_size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos

	var shape := CollisionShape3D.new()
	var collision_box := BoxShape3D.new()
	collision_box.size = box_size
	shape.shape = collision_box
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	# Map geometry reads as grey (keeps light/dark contrast) for category clarity.
	material.albedo_color = CategoryColors.to_map_grey(color)
	mesh.material_override = material
	body.add_child(mesh)

	add_child(body)

func _add_sign(pos: Vector3, text: String, font_size: int, color: Color) -> void:
	var label := Label3D.new()
	label.position = pos
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.008
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.double_sided = true
	label.no_depth_test = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Keep signage text out of the mirror reflection.
	label.layers = Mirror.NO_REFLECTION_VISUAL_LAYER
	add_child(label)

func _spawn_dummy(pos: Vector3) -> void:
	var scene: PackedScene = load(DUMMY_SCENE)
	var dummy := scene.instantiate()
	add_child(dummy)
	dummy.global_position = pos

func _spawn_player() -> void:
	# Start with an AR primary and pistol secondary so 1/2 switching is testable;
	# any weapon can be swapped in at the loadout station.
	PlayerLoadout.primary_weapon = "ar_basic"
	PlayerLoadout.secondary_weapon = "pistol_basic"

	_player = load(PLAYER_SCENE).instantiate()
	_player.name = "Player_1"
	_player.authority_peer_id = 1
	add_child(_player)
	_player.global_position = SPAWN
	_player.died.connect(_on_player_died)
	_player.downed.connect(_on_player_downed)

## Practice range: respawn quickly when downed (no long bleedout while training).
func _on_player_downed() -> void:
	await get_tree().create_timer(2.5).timeout
	if is_instance_valid(_player) and _player.is_downed:
		_player.respawn(SPAWN)

## Fallback respawn if the player somehow dies outright.
func _on_player_died() -> void:
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(_player) and _player.is_dead:
		_player.respawn(SPAWN)

## An enclosed bot arena off to the left. Walls block line of sight from the
## range, so the bots only engage once you step through the doorway. Bots always
## respawn at their fixed positions inside.
func _build_bots() -> void:
	var wall := Color(0.24, 0.23, 0.27)
	# Walls around x[-26,-16], z[-19,-9], with a doorway gap in the east wall.
	_add_static_box(Vector3(-26.0, 1.5, -14.0), Vector3(0.5, 3.0, 10.5), wall)   # west
	_add_static_box(Vector3(-21.0, 1.5, -19.0), Vector3(10.5, 3.0, 0.5), wall)   # north
	_add_static_box(Vector3(-21.0, 1.5, -9.0), Vector3(10.5, 3.0, 0.5), wall)    # south
	_add_static_box(Vector3(-16.0, 1.5, -17.5), Vector3(0.5, 3.0, 3.5), wall)    # east (lower)
	_add_static_box(Vector3(-16.0, 1.5, -10.5), Vector3(0.5, 3.0, 3.5), wall)    # east (upper)
	# Doorway gap spans z ≈ -15.5 .. -12.5 in the east wall.

	var scene: PackedScene = load(BOT_SCENE)
	var index := 0
	for pos in BOT_POSITIONS:
		var bot: Bot = scene.instantiate()
		bot.authority_peer_id = 1001 + index * 2  # distinct odd ids = enemy team
		# Set position BEFORE add_child so the bot's _ready captures the correct
		# spawn point (it respawns there after being defeated).
		bot.position = pos
		add_child(bot)
		index += 1

	_add_sign(Vector3(-13.0, 2.6, -14.0), "BOT ARENA\nEnter the doorway to engage · respawn 5s", 44, Color(1.0, 0.7, 0.6))

## A mirror just behind the spawn — turn around to see yourself and your weapon.
func _build_mirror() -> void:
	var mirror := Mirror.new()
	add_child(mirror)
	mirror.global_position = Vector3(0.0, 1.6, 11.0)
	mirror.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	_add_sign(Vector3(0.0, 3.3, 11.0), "MIRROR — turn around", 48, Color(0.8, 0.9, 1.0))

# === Loadout station (free economy) ===

func _setup_loadout_station() -> void:
	# Park GameState in a never-ending buy phase with effectively infinite
	# credits so the buy menu acts as a free loadout station. Offline, GameState
	# is its own authority, so purchases resolve locally.
	GameState.current_round_state = GameState.RoundState.BUY_PHASE
	GameState.round_timer = 1.0e9
	GameState.player_credits[GameState._local_peer_id()] = SANDBOX_CREDITS

	_buy_menu = load(BUY_MENU_SCENE).instantiate()
	add_child(_buy_menu)
	_buy_menu.enable_sandbox_mode()

func _build_hud_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var label := Label.new()
	label.position = Vector2(16.0, 12.0)
	label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	label.text = "PRACTICE RANGE — free loadout, targets respawn\n" \
		+ "Move WASD · Look Mouse · Jump %s · Sprint %s · Crouch/Slide %s\n" % [
			_key_for("jump"), _key_for("sprint"), _key_for("crouch")] \
		+ "Fire %s · Reload %s · Switch %s/%s · Loadout %s · Menu %s" % [
			_key_for("shoot"), _key_for("reload"), _key_for("weapon_primary"),
			_key_for("weapon_secondary"), _key_for("buy"), _key_for("disconnect_network")]
	layer.add_child(label)
