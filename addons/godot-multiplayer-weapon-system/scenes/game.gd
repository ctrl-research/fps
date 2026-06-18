extends Node3D
"""
Game scene root. Manages the game world and round lifecycle.
Instantiated when the host starts a round.
"""

@onready var player_spawner: Node = $PlayerSpawner

func _ready() -> void:
	# Ensure environment is set up
	_setup_environment()
	GameState.match_ended.connect(_on_match_ended)

func _on_match_ended(_winning_team: int) -> void:
	# Show the results overlay for whichever team the local player is on.
	var local_team := GameState._get_player_team(GameState._local_peer_id())
	var screen := MatchEndScreen.new()
	add_child(screen)
	screen.show_result(local_team)

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
