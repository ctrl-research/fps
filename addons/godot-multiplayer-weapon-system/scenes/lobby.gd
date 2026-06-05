extends CanvasLayer
"""
Lobby screen UI for hosting/joining multiplayer sessions.
Shown at startup and when disconnected. Manages connection state display.
"""

@onready var status_label: Label = $MenuPanel/Margin/VBox/StatusLabel
@onready var host_button: Button = $MenuPanel/Margin/VBox/HostButton
@onready var ip_input: LineEdit = $MenuPanel/Margin/VBox/JoinSection/IPInput
@onready var join_button: Button = $MenuPanel/Margin/VBox/JoinSection/JoinButton
@onready var disconnect_button: Button = $MenuPanel/Margin/VBox/DisconnectButton
@onready var player_list_label: Label = $MenuPanel/Margin/VBox/PlayerListLabel
@onready var player_list: VBoxContainer = $MenuPanel/Margin/VBox/PlayerList
@onready var start_button: Button = $MenuPanel/Margin/VBox/StartButton

var _port: int = 42069

func _ready() -> void:
	# Connect button signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	start_button.pressed.connect(_on_start_pressed)

	# Connect MultiplayerManager signals
	MultiplayerManager.connection_state_changed.connect(_on_connection_state_changed)
	MultiplayerManager.peer_connected.connect(_on_peer_connected)
	MultiplayerManager.peer_disconnected.connect(_on_peer_disconnected)

	# Initial state
	_update_ui(MultiplayerManager.current_state)

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

func _on_disconnect_pressed() -> void:
	MultiplayerManager.disconnect_session()
	# Remove game scene and return to lobby
	if has_node("/root/Game"):
		get_node("/root/Game").queue_free()

func _on_start_pressed() -> void:
	# Only host transitions to game
	if not MultiplayerManager.is_hosting():
		return
	GameState.start_buy_phase()
	_load_game_scene()

func _load_game_scene() -> void:
	var game_scene = load("res://addons/godot-multiplayer-weapon-system/scenes/game.tscn")
	var game = game_scene.instantiate()
	get_tree().root.add_child(game)
	queue_free()  # Remove lobby

func _on_connection_state_changed(state: MultiplayerManager.ConnectionState) -> void:
	_update_ui(state)

func _on_peer_connected(peer_id: int) -> void:
	_refresh_player_list()

func _on_peer_disconnected(peer_id: int) -> void:
	_refresh_player_list()

func _update_ui(state: MultiplayerManager.ConnectionState) -> void:
	match state:
		case MultiplayerManager.ConnectionState.DISCONNECTED:
			status_label.text = "Disconnected"
			host_button.visible = true
			ip_input.text = ""
			ip_input.editable = true
			join_button.disabled = false
			disconnect_button.visible = false
			player_list_label.visible = false
			player_list.visible = false
			start_button.visible = false
		case MultiplayerManager.ConnectionState.HOSTING:
			status_label.text = "Hosting on port %d" % _port
			host_button.visible = false
			ip_input.editable = false
			join_button.disabled = true
			disconnect_button.visible = true
			player_list_label.visible = true
			player_list.visible = true
			start_button.visible = true
			_refresh_player_list()
		case MultiplayerManager.ConnectionState.CONNECTING:
			status_label.text = "Connecting..."
			_set_buttons_connected(true)
		case MultiplayerManager.ConnectionState.CONNECTED:
			status_label.text = "Connected to server"
			host_button.visible = false
			ip_input.editable = false
			join_button.disabled = true
			disconnect_button.visible = true
			player_list_label.visible = true
			player_list.visible = true
			start_button.visible = false
			_refresh_player_list()

func _set_buttons_connected(connected: bool) -> void:
	host_button.disabled = connected
	join_button.disabled = connected
	ip_input.editable = not connected

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