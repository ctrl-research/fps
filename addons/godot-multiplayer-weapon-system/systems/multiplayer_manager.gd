extends Node
class_name MultiplayerManager
"""
Autoload singleton for WebSocket multiplayer peer management.
Handles host/server creation, client connections, and peer lifecycle.

WebSocket transport is used (rather than ENet/UDP) so that browser clients can
connect: browsers cannot open raw UDP sockets, but they can open WebSockets.
"""

## Emitted when connection state changes
signal connection_state_changed(state: ConnectionState)

## Emitted when a peer connects (includes self for host)
signal peer_connected(peer_id: int)

## Emitted when a peer disconnects
signal peer_disconnected(peer_id: int)

## Default server port
const DEFAULT_PORT: int = 42069

## Maximum players supported
const MAX_PLAYERS: int = 10

enum ConnectionState {
	DISCONNECTED,
	HOSTING,
	CONNECTING,
	CONNECTED
}

var current_state: ConnectionState = ConnectionState.DISCONNECTED:
	set(value):
		if value != current_state:
			current_state = value
			connection_state_changed.emit(value)

var server_peer: WebSocketMultiplayerPeer = null
var ui_peer: WebSocketMultiplayerPeer = null

func _ready() -> void:
	# Ensure multiplayer singleton exists
	multiplayer.peer_connected.connect(_on_mp_peer_connected)
	multiplayer.peer_disconnected.connect(_on_mp_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_mp_connected_to_server)
	multiplayer.connection_failed.connect(_on_mp_connection_failed)
	multiplayer.server_disconnected.connect(_on_mp_server_disconnected)


## Start hosting a game (listen server)
func start_host(port: int = DEFAULT_PORT) -> Error:
	if current_state != ConnectionState.DISCONNECTED:
		return ERR_ALREADY_EXISTS

	server_peer = WebSocketMultiplayerPeer.new()
	# WebSocketMultiplayerPeer has no max-player argument; the cap is enforced
	# on connect in _on_mp_peer_connected.
	var create_result = server_peer.create_server(port)
	if create_result != OK:
		server_peer = null
		return create_result

	multiplayer.multiplayer_peer = server_peer
	current_state = ConnectionState.HOSTING

	# Host is always peer_id 1
	peer_connected.emit(1)
	return OK


## Connect to a hosting server
func join_server(ip: String, port: int = DEFAULT_PORT) -> Error:
	if current_state != ConnectionState.DISCONNECTED:
		return ERR_ALREADY_EXISTS

	ui_peer = WebSocketMultiplayerPeer.new()
	# WebSocket clients connect to a URL. Accept either a bare host/IP or a
	# pre-formed ws:// URL.
	var url := ip if ip.begins_with("ws://") or ip.begins_with("wss://") else "ws://%s:%d" % [ip, port]
	var create_result = ui_peer.create_client(url)
	if create_result != OK:
		ui_peer = null
		return create_result

	current_state = ConnectionState.CONNECTING
	multiplayer.multiplayer_peer = ui_peer
	return OK


## Disconnect from current session
func disconnect_session() -> void:
	var was_hosting := current_state == ConnectionState.HOSTING

	if server_peer != null:
		server_peer.close()
		server_peer = null
	if ui_peer != null:
		ui_peer.close()
		ui_peer = null

	multiplayer.multiplayer_peer = null
	current_state = ConnectionState.DISCONNECTED

	# Notify game state cleanup
	GameState.clear_all_players()


## Check if currently hosting
func is_hosting() -> bool:
	return current_state == ConnectionState.HOSTING


## Check if currently connected (as client or host)
func is_connected() -> bool:
	return current_state == ConnectionState.CONNECTED or current_state == ConnectionState.HOSTING


## Get list of all connected peer IDs (excludes self)
func get_connected_peers() -> Array[int]:
	# High-level API: transport-agnostic and already excludes our own id.
	var peers: Array[int] = []
	if multiplayer.multiplayer_peer != null:
		for p in multiplayer.get_peers():
			peers.append(p)
	return peers


## Get peer info dict for a given peer ID
func get_peer_info(peer_id: int) -> Dictionary:
	if not multiplayer.has_peer(peer_id):
		return {}
	return {
		"peer_id": peer_id,
		"connected": true,
	}


# === Private callbacks ===

func _on_mp_peer_connected(peer_id: int) -> void:
	# Enforce the player cap on the host, since WebSocket can't pre-limit at
	# create_server time. get_peers() already includes the new peer.
	if is_hosting() and multiplayer.get_peers().size() > MAX_PLAYERS:
		server_peer.disconnect_peer(peer_id)
		return

	peer_connected.emit(peer_id)
	# Initialize player in game state
	GameState.on_peer_joined(peer_id)

func _on_mp_peer_disconnected(peer_id: int) -> void:
	peer_disconnected.emit(peer_id)
	GameState.on_peer_left(peer_id)

func _on_mp_connected_to_server() -> void:
	current_state = ConnectionState.CONNECTED

func _on_mp_connection_failed() -> void:
	current_state = ConnectionState.DISCONNECTED
	if ui_peer != null:
		ui_peer.close()
		ui_peer = null
	multiplayer.multiplayer_peer = null

func _on_mp_server_disconnected() -> void:
	disconnect_session()