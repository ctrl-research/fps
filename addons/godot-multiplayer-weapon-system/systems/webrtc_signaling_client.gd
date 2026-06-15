extends Node
class_name WebRTCSignalingClient
"""
Client for the WebRTC signaling broker (see signaling/server.js).

Maintains a WebSocket connection to the broker and translates its JSON protocol
into Godot signals. It only carries the connection handshake — once peers are
connected via WebRTC, game traffic flows peer-to-peer and never comes through here.

MultiplayerManager listens to these signals to drive a WebRTCMultiplayerPeer.
"""

## Broker connection opened
signal connected()
## Broker assigned our peer id (host == true means we created the room)
signal id_assigned(peer_id: int, room: String, is_host: bool)
## A peer we should establish a WebRTC connection with appeared
signal peer_connect(peer_id: int)
## A peer left
signal peer_disconnect(peer_id: int)
## Relayed WebRTC session description from another peer
signal offer_received(peer_id: int, sdp: String)
signal answer_received(peer_id: int, sdp: String)
## Relayed ICE candidate from another peer
signal candidate_received(peer_id: int, mid: String, index: int, name: String)
## Broker reported an error (reason is a short code, e.g. "room_not_found")
signal error_received(reason: String)
## Broker connection closed
signal closed()

var _socket: WebSocketPeer = null
var _pending_room: String = ""
var _was_open: bool = false

## Connect to the broker and, once open, join (empty room => host a new room).
func start(url: String, room: String = "") -> Error:
	_pending_room = room
	_was_open = false
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(url)
	if err != OK:
		_socket = null
	return err

## Close the broker connection.
func stop() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	_was_open = false

func is_active() -> bool:
	return _socket != null

func _process(_delta: float) -> void:
	if _socket == null:
		return

	_socket.poll()
	var state := _socket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				connected.emit()
				_send({"type": "join", "room": _pending_room})
			while _socket.get_available_packet_count() > 0:
				_handle_packet(_socket.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_socket = null
			_was_open = false
			closed.emit()

# === Outgoing ===

func send_offer(peer_id: int, sdp: String) -> void:
	_send({"type": "offer", "id": peer_id, "sdp": sdp})

func send_answer(peer_id: int, sdp: String) -> void:
	_send({"type": "answer", "id": peer_id, "sdp": sdp})

func send_candidate(peer_id: int, mid: String, index: int, name: String) -> void:
	_send({"type": "candidate", "id": peer_id, "mid": mid, "index": index, "name": name})

func seal() -> void:
	_send({"type": "seal"})

func _send(msg: Dictionary) -> void:
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(msg))

# === Incoming ===

func _handle_packet(text: String) -> void:
	var msg = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match msg.get("type", ""):
		"id":
			id_assigned.emit(int(msg.get("id", 0)), str(msg.get("room", "")), bool(msg.get("host", false)))
		"peer_connect":
			peer_connect.emit(int(msg.get("id", 0)))
		"peer_disconnect":
			peer_disconnect.emit(int(msg.get("id", 0)))
		"offer":
			offer_received.emit(int(msg.get("id", 0)), str(msg.get("sdp", "")))
		"answer":
			answer_received.emit(int(msg.get("id", 0)), str(msg.get("sdp", "")))
		"candidate":
			candidate_received.emit(
				int(msg.get("id", 0)),
				str(msg.get("mid", "")),
				int(msg.get("index", 0)),
				str(msg.get("name", ""))
			)
		"seal":
			pass  # Room locked; no client action needed.
		"error":
			error_received.emit(str(msg.get("reason", "unknown")))
