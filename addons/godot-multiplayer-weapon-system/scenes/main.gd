extends Node2D
"""
Main entry point. Loads the lobby UI on startup.
"""

func _ready() -> void:
	# Show lobby as the entry point
	var lobby_scene = load("res://addons/godot-multiplayer-weapon-system/scenes/lobby.tscn")
	var lobby = lobby_scene.instantiate()
	add_child(lobby)