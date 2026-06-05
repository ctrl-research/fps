extends Node
"""
Manages spawning and despawning PlayerController instances for each connected peer.
Spawns one player body per peer when they connect, removes on disconnect.
"""
class_name PlayerSpawner

## Where to spawn players by default
@export var spawn_point: Vector3 = Vector3(0, 1, 0)

## Scene to instantiate for player bodies
var _player_scene: PackedScene

# [peer_id] = PlayerController instance
var _players: Dictionary = {}

func _ready() -> void:
	_player_scene = load("res://addons/godot-multiplayer-weapon-system/player/player.tscn")

	MultiplayerManager.peer_connected.connect(_on_peer_connected)
	MultiplayerManager.peer_disconnected.connect(_on_peer_disconnected)

	# Spawn for already-connected peers (e.g., host who just started hosting)
	for peer_id in _get_active_peers():
		_spawn_player(peer_id)

func _get_active_peers() -> Array[int]:
	var peers: Array[int] = []
	# Host is always peer_id 1
	if multiplayer.is_server():
		peers.append(1)
		for p in MultiplayerManager.get_connected_peers():
			peers.append(p)
	elif multiplayer.has_multiplayer_authority():
		peers.append(multiplayer.get_unique_id())
	return peers

func _on_peer_connected(peer_id: int) -> void:
	_spawn_player(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	_despawn_player(peer_id)

func _spawn_player(peer_id: int) -> void:
	if _players.has(peer_id):
		return  # Already spawned

	var player: PlayerController = _player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.authority_peer_id = peer_id

	# Set this peer's own node to be authority over their body
	if peer_id == multiplayer.get_unique_id():
		player.set_multiplayer_authority(peer_id)

	player.global_position = _get_spawn_position(peer_id)
	add_child(player)
	_players[peer_id] = player

func _despawn_player(peer_id: int) -> void:
	if not _players.has(peer_id):
		return
	var player = _players[peer_id]
	_players.erase(peer_id)
	player.queue_free()

func _get_spawn_position(peer_id: int) -> Vector3:
	# Simple: stagger spawn positions by team
	# Team 0 offset, Team 1 offset
	var team := GameState._get_player_team(peer_id)
	var offset := Vector3.ZERO
	if team == 0:
		offset = Vector3(-2.0 * peer_id, 0, 0)
	else:
		offset = Vector3(2.0 * peer_id, 0, 0)
	return spawn_point + offset
