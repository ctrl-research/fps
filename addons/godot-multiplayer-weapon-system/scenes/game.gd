extends Node3D
"""
Game scene root. Manages the game world and round lifecycle.
Instantiated when the host starts a round.
"""

@onready var player_spawner: Node = $PlayerSpawner

func _ready() -> void:
	# Ensure environment is set up
	_setup_environment()

func _setup_environment() -> void:
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.1, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.4)

	var world_env = $WorldEnvironment
	world_env.environment = env

func get_spawn_point() -> Vector3:
	return Vector3(0, 1, 0)
