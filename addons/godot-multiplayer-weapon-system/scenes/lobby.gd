extends CanvasLayer
"""
Lobby screen UI for hosting/joining multiplayer sessions.
Shown at startup and when disconnected. Manages connection state display.
"""

@onready var status_label: Label = $MenuPanel/Margin/VBox/StatusLabel
@onready var host_button: Button = $MenuPanel/Margin/VBox/HostButton
@onready var join_section: HBoxContainer = $MenuPanel/Margin/VBox/JoinSection
@onready var ip_input: LineEdit = $MenuPanel/Margin/VBox/JoinSection/IPInput
@onready var join_button: Button = $MenuPanel/Margin/VBox/JoinSection/JoinButton
@onready var tutorial_button: Button = $MenuPanel/Margin/VBox/TutorialButton
var _evolution_button: Button = null
var _class_arena_button: Button = null
@onready var settings_button: Button = $MenuPanel/Margin/VBox/SettingsButton
@onready var round_test_button: Button = $MenuPanel/Margin/VBox/RoundTestButton
@onready var disconnect_button: Button = $MenuPanel/Margin/VBox/DisconnectButton
@onready var player_list_label: Label = $MenuPanel/Margin/VBox/PlayerListLabel
@onready var player_list: VBoxContainer = $MenuPanel/Margin/VBox/PlayerList
@onready var start_button: Button = $MenuPanel/Margin/VBox/StartButton
@onready var online_separator: HSeparator = $MenuPanel/Margin/VBox/OnlineSeparator
@onready var host_online_button: Button = $MenuPanel/Margin/VBox/HostOnlineButton
@onready var join_online_section: HBoxContainer = $MenuPanel/Margin/VBox/JoinOnlineSection
@onready var room_code_input: LineEdit = $MenuPanel/Margin/VBox/JoinOnlineSection/RoomCodeInput
@onready var join_online_button: Button = $MenuPanel/Margin/VBox/JoinOnlineSection/JoinOnlineButton
@onready var room_code_label: Label = $MenuPanel/Margin/VBox/RoomCodeLabel

var _port: int = 42069

func _ready() -> void:
	# Connect button signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	tutorial_button.pressed.connect(_on_tutorial_pressed)

	# Class Arena — the core mode of the pivot (offline vs bots for now).
	_class_arena_button = Button.new()
	_class_arena_button.text = "Class Arena (vs bots)"
	tutorial_button.get_parent().add_child(_class_arena_button)
	tutorial_button.get_parent().move_child(_class_arena_button, tutorial_button.get_index() + 1)
	_class_arena_button.pressed.connect(_on_class_arena_pressed)

	# Evolution (old modifier-vote mode) kept as reference, after Class Arena.
	_evolution_button = Button.new()
	_evolution_button.text = "Evolution (vs bots)"
	tutorial_button.get_parent().add_child(_evolution_button)
	tutorial_button.get_parent().move_child(_evolution_button, _class_arena_button.get_index() + 1)
	_evolution_button.pressed.connect(_on_evolution_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	round_test_button.pressed.connect(_on_round_test_pressed)
	host_online_button.pressed.connect(_on_host_online_pressed)
	join_online_button.pressed.connect(_on_join_online_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	start_button.pressed.connect(_on_start_pressed)

	# Connect MultiplayerManager signals
	MultiplayerManager.connection_state_changed.connect(_on_connection_state_changed)
	MultiplayerManager.peer_connected.connect(_on_peer_connected)
	MultiplayerManager.peer_disconnected.connect(_on_peer_disconnected)
	MultiplayerManager.room_code_assigned.connect(_on_room_code_assigned)
	MultiplayerManager.online_error.connect(_on_online_error)

	# Initial state
	_update_ui(MultiplayerManager.current_state)

	# On web, a shared link like ".../#room=ABCDE" auto-joins that room.
	_try_auto_join_from_url()

func _input(event: InputEvent) -> void:
	# ESC to disconnect when connected
	if event.is_action_pressed("disconnect_network"):
		if MultiplayerManager.current_state != MultiplayerManager.ConnectionState.DISCONNECTED:
			MultiplayerManager.disconnect_session()

func _on_host_pressed() -> void:
	var err = MultiplayerManager.start_host(_port)
	if err != OK:
		status_label.text = "Failed to host: port may be in use"
		return
	status_label.text = "Hosting on port %d..." % _port
	_set_buttons_connected(true)

func _on_join_pressed() -> void:
	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		status_label.text = "Enter a server IP address"
		return
	var err = MultiplayerManager.join_server(ip, _port)
	if err != OK:
		status_label.text = "Failed to connect"
		return
	status_label.text = "Connecting to %s..." % ip
	_set_buttons_connected(true)

func _on_tutorial_pressed() -> void:
	# Offline practice range — no multiplayer session required.
	var err := get_tree().change_scene_to_file("res://addons/godot-multiplayer-weapon-system/scenes/tutorial.tscn")
	if err != OK:
		status_label.text = "Tutorial failed to load (error %d)" % err
		push_error("Tutorial scene failed to load: %d" % err)


func _on_class_arena_pressed() -> void:
	get_tree().change_scene_to_file("res://addons/godot-multiplayer-weapon-system/scenes/class_arena.tscn")

func _on_evolution_pressed() -> void:
	# Offline team-vs-bots round mode with the modifier draft — no networking.
	get_tree().change_scene_to_file("res://addons/godot-multiplayer-weapon-system/scenes/evolution.tscn")

func _on_settings_pressed() -> void:
	add_child(SettingsMenu.new())

func _on_round_test_pressed() -> void:
	# Offline harness for the round state machine (no networking needed).
	get_tree().change_scene_to_file("res://addons/godot-multiplayer-weapon-system/scenes/round_test.tscn")

func _on_host_online_pressed() -> void:
	var err = MultiplayerManager.host_online()
	if err != OK:
		status_label.text = "Failed to reach signaling server"
		return
	status_label.text = "Creating room..."
	_set_buttons_connected(true)

func _on_join_online_pressed() -> void:
	_join_online_with_code(room_code_input.text)

func _join_online_with_code(code: String) -> void:
	var room = code.strip_edges().to_upper()
	if room.is_empty():
		status_label.text = "Enter a room code"
		return
	var err = MultiplayerManager.join_online(room)
	if err != OK:
		status_label.text = "Failed to reach signaling server"
		return
	status_label.text = "Joining room %s..." % room
	_set_buttons_connected(true)

func _on_room_code_assigned(room_code: String) -> void:
	room_code_label.text = "Room code: %s\n%s" % [room_code, _get_share_url(room_code)]
	room_code_label.visible = true

func _on_online_error(reason: String) -> void:
	status_label.text = "Online error: %s" % reason

## On web, read location.hash for "#room=CODE" and auto-join it.
func _try_auto_join_from_url() -> void:
	if not OS.has_feature("web"):
		return
	var hash_value = JavaScriptBridge.eval("location.hash", true)
	if typeof(hash_value) != TYPE_STRING:
		return
	var prefix := "#room="
	if (hash_value as String).begins_with(prefix):
		var code := (hash_value as String).substr(prefix.length())
		if not code.strip_edges().is_empty():
			_join_online_with_code(code)

## Build a shareable URL with the room code embedded (web only); otherwise just
## return the code so it can be shared manually.
func _get_share_url(room_code: String) -> String:
	if OS.has_feature("web"):
		var base = JavaScriptBridge.eval("location.origin + location.pathname", true)
		if typeof(base) == TYPE_STRING:
			return "%s#room=%s" % [base, room_code]
	return "(desktop: share the code above)"

func _on_disconnect_pressed() -> void:
	MultiplayerManager.disconnect_session()
	# Remove game scene and return to lobby
	if has_node("/root/Game"):
		get_node("/root/Game").queue_free()

func _on_start_pressed() -> void:
	# Only host transitions to game
	if not MultiplayerManager.is_hosting():
		return
	# Lock the online room so no one joins mid-match (no-op for LAN).
	MultiplayerManager.seal_room()
	GameState.start_buy_phase()
	_load_game_scene()

func _load_game_scene() -> void:
	var game_scene = load("res://addons/godot-multiplayer-weapon-system/scenes/game.tscn")
	var game = game_scene.instantiate()
	get_tree().root.add_child(game)
	queue_free()  # Remove lobby

func _on_connection_state_changed(state: int) -> void:
	_update_ui(state)

func _on_peer_connected(peer_id: int) -> void:
	_refresh_player_list()

func _on_peer_disconnected(peer_id: int) -> void:
	_refresh_player_list()

func _update_ui(state: int) -> void:
	# Offline practice is only offered when not in a session.
	tutorial_button.visible = state == MultiplayerManager.ConnectionState.DISCONNECTED
	if _evolution_button:
		_evolution_button.visible = state == MultiplayerManager.ConnectionState.DISCONNECTED
	if _class_arena_button:
		_class_arena_button.visible = state == MultiplayerManager.ConnectionState.DISCONNECTED
	match state:
		MultiplayerManager.ConnectionState.DISCONNECTED:
			status_label.text = "Disconnected"
			_show_connect_controls(true)
			ip_input.text = ""
			ip_input.editable = true
			join_button.disabled = false
			host_button.disabled = false
			# Online buttons require WebRTC (web build, or desktop with the
			# webrtc-native extension installed).
			var online_ok := MultiplayerManager.is_online_available()
			room_code_input.editable = online_ok
			join_online_button.disabled = not online_ok
			host_online_button.disabled = not online_ok
			if not online_ok:
				var tip := "Online play requires WebRTC (web build or the webrtc-native extension)."
				host_online_button.tooltip_text = tip
				join_online_button.tooltip_text = tip
			disconnect_button.visible = false
			player_list_label.visible = false
			player_list.visible = false
			start_button.visible = false
			room_code_label.visible = false
		MultiplayerManager.ConnectionState.HOSTING:
			if MultiplayerManager.current_room_code != "":
				status_label.text = "Hosting online"
				room_code_label.visible = true
			else:
				status_label.text = "Hosting on port %d" % _port
				room_code_label.visible = false
			_show_connect_controls(false)
			disconnect_button.visible = true
			player_list_label.visible = true
			player_list.visible = true
			start_button.visible = true
			_refresh_player_list()
		MultiplayerManager.ConnectionState.CONNECTING:
			status_label.text = "Connecting..."
			_set_buttons_connected(true)
		MultiplayerManager.ConnectionState.CONNECTED:
			status_label.text = "Connected"
			_show_connect_controls(false)
			room_code_label.visible = false
			disconnect_button.visible = true
			player_list_label.visible = true
			player_list.visible = true
			start_button.visible = false
			_refresh_player_list()

## Show or hide all the "start a session" controls (LAN + online) at once.
func _show_connect_controls(show_controls: bool) -> void:
	host_button.visible = show_controls
	join_section.visible = show_controls
	online_separator.visible = show_controls
	host_online_button.visible = show_controls
	join_online_section.visible = show_controls

func _set_buttons_connected(connected: bool) -> void:
	host_button.disabled = connected
	join_button.disabled = connected
	ip_input.editable = not connected
	host_online_button.disabled = connected
	join_online_button.disabled = connected
	room_code_input.editable = not connected

func _refresh_player_list() -> void:
	# Clear existing entries
	for child in player_list.get_children():
		child.queue_free()

	# Add self
	var self_entry = _make_player_entry(multiplayer.get_unique_id(), true)
	player_list.add_child(self_entry)

	# Add other peers
	for peer_id in MultiplayerManager.get_connected_peers():
		player_list.add_child(_make_player_entry(peer_id, false))

func _make_player_entry(peer_id: int, is_self: bool) -> Label:
	var label = Label.new()
	label.text = "Player %d%s" % [peer_id, " (You)" if is_self else ""]
	if is_self:
		label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	return label