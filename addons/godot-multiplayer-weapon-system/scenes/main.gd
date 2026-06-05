extends Node2D
"""
Main entry point. Loads the lobby UI on startup.
When the host starts a round, the lobby replaces itself with the game scene.
"""

func _ready() -> void:
	var lobby_scene = load("res://addons/godot-multiplayer-weapon-system/scenes/lobby.tscn")
	var lobby = lobby_scene.instantiate()
	add_child(lobby)