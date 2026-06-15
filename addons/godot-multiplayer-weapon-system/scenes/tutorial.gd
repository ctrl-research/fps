extends Node3D
"""
Offline practice range.

Lets a single local player test movement, weapon switching, firing,
spread/recoil, reload, and damage against dummy targets without starting a
multiplayer session. With no network peer active, the player body is its own
authority, so everything runs locally. Reached from the lobby's Tutorial button;
press ESC to return to the main menu.
"""

const PLAYER_SCENE: String = "res://addons/godot-multiplayer-weapon-system/player/player.tscn"
const DUMMY_SCENE: String = "res://addons/godot-multiplayer-weapon-system/player/target_dummy.tscn"
const MAIN_SCENE: String = "res://addons/godot-multiplayer-weapon-system/scenes/main.tscn"

## Where dummy targets are placed (in front of the player, who faces -Z).
const DUMMY_POSITIONS: Array[Vector3] = [
	Vector3(-4.0, 1.0, -9.0),
	Vector3(0.0, 1.0, -11.0),
	Vector3(4.0, 1.0, -9.0),
	Vector3(-2.0, 1.0, -16.0),
	Vector3(2.5, 1.0, -16.0),
]

func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_cover()
	_spawn_dummies()
	_spawn_player()
	_build_instructions()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("disconnect_network"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_tree().change_scene_to_file(MAIN_SCENE)

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
	var floor_color := Color(0.2, 0.22, 0.26)
	_add_static_box(Vector3(0.0, -0.5, -6.0), Vector3(60.0, 1.0, 60.0), floor_color)

func _build_cover() -> void:
	var cover_color := Color(0.3, 0.26, 0.22)
	_add_static_box(Vector3(-3.0, 0.75, -5.0), Vector3(1.5, 1.5, 1.5), cover_color)
	_add_static_box(Vector3(3.5, 1.0, -7.0), Vector3(1.5, 2.0, 1.5), cover_color)
	_add_static_box(Vector3(0.0, 0.5, -13.0), Vector3(3.0, 1.0, 1.0), cover_color)

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
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)

	add_child(body)

func _spawn_dummies() -> void:
	var scene: PackedScene = load(DUMMY_SCENE)
	for pos in DUMMY_POSITIONS:
		var dummy := scene.instantiate()
		add_child(dummy)
		dummy.global_position = pos

func _spawn_player() -> void:
	# Equip a primary so weapon switching (1/2) is testable; the pistol fills the
	# secondary slot by default.
	PlayerLoadout.primary_weapon = "ar_basic"
	PlayerLoadout.secondary_weapon = "pistol_basic"

	var player: PlayerController = load(PLAYER_SCENE).instantiate()
	player.name = "Player_1"
	player.authority_peer_id = 1
	add_child(player)
	player.global_position = Vector3(0.0, 1.5, 5.0)

func _build_instructions() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var label := Label.new()
	label.position = Vector2(16.0, 12.0)
	label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	label.text = "PRACTICE RANGE\n" \
		+ "WASD move · Mouse look · Space jump · Shift sprint · Ctrl crouch\n" \
		+ "LMB fire · R reload · 1 primary (AR) · 2 secondary (pistol)\n" \
		+ "Shoot the dummies — they respawn. ESC: back to menu"
	layer.add_child(label)
