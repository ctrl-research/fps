extends Node
# No `class_name`: registered as the `MultiplayerManager` autoload; a matching
# global class would shadow the singleton and break clean compiles.
"""
Autoload singleton for multiplayer peer management.
Handles host/server creation, client connections, and peer lifecycle.

Two transports are supported:
- WebSocket (LAN / direct IP): start_host() / join_server(). Simple, no broker.
- WebRTC (online, true P2P, browser-capable): host_online() / join_online(code).
  Uses a signaling broker only for the handshake; game traffic is peer-to-peer.

The host is always peer id 1; clients get ids >= 2.
"""

## Emitted when connection state changes
signal connection_state_changed(state: ConnectionState)

## Emitted when a peer connects (includes self for host)
signal peer_connected(peer_id: int)

## Emitted when a peer disconnects
signal peer_disconnected(peer_id: int)

## Emitted (online host) when the broker assigns this session a room code to share
signal room_code_assigned(room_code: String)

## Emitted when the online/signaling path fails (reason is a short code)
signal online_error(reason: String)

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

# === WebRTC (online) transport ===
# WebRTC classes come from the webrtc-native GDExtension on desktop and are built
# into the web export. They are NOT core, so we never reference them statically
# (that would break compilation where the extension is absent) — we instantiate
# via ClassDB and gate the online path on _webrtc_available().
var rtc_peer = null
var _signaling: WebRTCSignalingClient = null
## Room code for the current online session (host shares this); empty otherwise.
var current_room_code: String = ""

func _ready() -> void:
	# Ensure multiplayer singleton exists
	multiplayer.peer_connected.connect(_on_mp_peer_connected)
	multiplayer.peer_disconnected.connect(_on_mp_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_mp_connected_to_server)
	multiplayer.connection_failed.connect(_on_mp_connection_failed)
	multiplayer.server_disconnected.connect(_on_mp_server_disconnected)

	# Signaling client (only used for the WebRTC/online path).
	_signaling = WebRTCSignalingClient.new()
	_signaling.name = "WebRTCSignalingClient"
	add_child(_signaling)
	_signaling.id_assigned.connect(_on_signaling_id_assigned)
	_signaling.peer_connect.connect(_on_signaling_peer_connect)
	_signaling.peer_disconnect.connect(_on_signaling_peer_disconnect)
	_signaling.offer_received.connect(_on_signaling_offer)
	_signaling.answer_received.connect(_on_signaling_answer)
	_signaling.candidate_received.connect(_on_signaling_candidate)
	_signaling.error_received.connect(_on_signaling_error)
	_signaling.closed.connect(_on_signaling_closed)


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


# === WebRTC (online) transport ===

## Whether WebRTC is available on this build (extension present, or web export).
func is_online_available() -> bool:
	return ClassDB.class_exists("WebRTCPeerConnection") and ClassDB.class_exists("WebRTCMultiplayerPeer")


## Host an online game: connect to the signaling broker, which creates a room and
## assigns this peer id 1. The room code arrives via room_code_assigned.
func host_online() -> Error:
	if current_state != ConnectionState.DISCONNECTED:
		return ERR_ALREADY_EXISTS
	if not is_online_available():
		online_error.emit("webrtc_unavailable")
		return ERR_UNAVAILABLE
	current_state = ConnectionState.CONNECTING
	return _signaling.start(ProjectSettingsWrapper.get_signaling_url(), "")


## Join an online game by room code via the signaling broker.
func join_online(room_code: String) -> Error:
	if current_state != ConnectionState.DISCONNECTED:
		return ERR_ALREADY_EXISTS
	if not is_online_available():
		online_error.emit("webrtc_unavailable")
		return ERR_UNAVAILABLE
	current_state = ConnectionState.CONNECTING
	return _signaling.start(ProjectSettingsWrapper.get_signaling_url(), room_code.strip_edges().to_upper())


## Lock the room so no more players can join (host only).
func seal_room() -> void:
	if _signaling != null and _signaling.is_active():
		_signaling.seal()


func _on_signaling_id_assigned(peer_id: int, room: String, is_host: bool) -> void:
	current_room_code = room
	rtc_peer = ClassDB.instantiate("WebRTCMultiplayerPeer")
	var err: int
	if is_host:
		err = rtc_peer.create_server()
	else:
		err = rtc_peer.create_client(peer_id)
	if err != OK:
		online_error.emit("rtc_create_failed")
		disconnect_session()
		return

	multiplayer.multiplayer_peer = rtc_peer
	if is_host:
		current_state = ConnectionState.HOSTING
		peer_connected.emit(1)
		room_code_assigned.emit(room)
	else:
		# A WebRTC client is "connected" once its data channel to the host opens;
		# that surfaces via multiplayer.connected_to_server. Stay CONNECTING here.
		pass


func _on_signaling_peer_connect(peer_id: int) -> void:
	_create_rtc_connection(peer_id)


func _on_signaling_peer_disconnect(peer_id: int) -> void:
	if rtc_peer != null and rtc_peer.has_peer(peer_id):
		rtc_peer.remove_peer(peer_id)


## Create a WebRTCPeerConnection for a remote peer and wire signaling. The peer
## with the higher id creates the offer (avoids both sides offering at once).
func _create_rtc_connection(peer_id: int) -> void:
	if rtc_peer == null or rtc_peer.has_peer(peer_id):
		return
	var connection = ClassDB.instantiate("WebRTCPeerConnection")
	connection.initialize({"iceServers": ProjectSettingsWrapper.get_ice_servers()})
	connection.session_description_created.connect(_on_session_description_created.bind(peer_id))
	connection.ice_candidate_created.connect(_on_ice_candidate_created.bind(peer_id))
	rtc_peer.add_peer(connection, peer_id)
	if peer_id < rtc_peer.get_unique_id():
		connection.create_offer()


func _on_session_description_created(type: String, sdp: String, peer_id: int) -> void:
	if rtc_peer == null or not rtc_peer.has_peer(peer_id):
		return
	rtc_peer.get_peer(peer_id)["connection"].set_local_description(type, sdp)
	if type == "offer":
		_signaling.send_offer(peer_id, sdp)
	else:
		_signaling.send_answer(peer_id, sdp)


func _on_ice_candidate_created(mid: String, index: int, name: String, peer_id: int) -> void:
	_signaling.send_candidate(peer_id, mid, index, name)


func _on_signaling_offer(peer_id: int, sdp: String) -> void:
	if rtc_peer != null and rtc_peer.has_peer(peer_id):
		rtc_peer.get_peer(peer_id)["connection"].set_remote_description("offer", sdp)


func _on_signaling_answer(peer_id: int, sdp: String) -> void:
	if rtc_peer != null and rtc_peer.has_peer(peer_id):
		rtc_peer.get_peer(peer_id)["connection"].set_remote_description("answer", sdp)


func _on_signaling_candidate(peer_id: int, mid: String, index: int, name: String) -> void:
	if rtc_peer != null and rtc_peer.has_peer(peer_id):
		rtc_peer.get_peer(peer_id)["connection"].add_ice_candidate(mid, index, name)


func _on_signaling_error(reason: String) -> void:
	online_error.emit(reason)
	disconnect_session()


func _on_signaling_closed() -> void:
	# If the broker drops before we ever connected to a host, treat as a failure.
	if current_state == ConnectionState.CONNECTING:
		disconnect_session()


## Disconnect from current session
func disconnect_session() -> void:
	if server_peer != null:
		server_peer.close()
		server_peer = null
	if ui_peer != null:
		ui_peer.close()
		ui_peer = null
	if rtc_peer != null:
		rtc_peer.close()
		rtc_peer = null
	if _signaling != null:
		_signaling.stop()
	current_room_code = ""

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
	# Enforce the player cap on the host. Neither transport pre-limits at create
	# time (the broker also caps, but defend here too). get_peers() includes the
	# new peer already.
	if is_hosting() and multiplayer.get_peers().size() > MAX_PLAYERS:
		if server_peer != null:
			server_peer.disconnect_peer(peer_id)
		elif rtc_peer != null:
			rtc_peer.remove_peer(peer_id)
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