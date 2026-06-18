extends CanvasLayer
class_name MatchEndScreen
"""
Post-match results overlay.

Shows a VICTORY/DEFEAT banner and a scoreboard, then auto-returns to the main
menu after a countdown. The button shows the live countdown and lets the player
skip straight back.

Two entry points:
  show_result(local_team)  — team round mode; reads the result from GameState.
  show_custom(...)         — any mode (e.g. FFA Gun Game) supplies its own
                             title / win flag / subtitle / scoreboard.
"""

const MAIN_SCENE: String = "res://addons/godot-multiplayer-weapon-system/scenes/main.tscn"
const COUNTDOWN: float = 8.0
const TEAM_NAMES: Array[String] = ["Team A", "Team B"]

var _remaining: float = COUNTDOWN
var _button: Button = null
var _leaving: bool = false

## Team round mode: build the result from GameState for the given local team.
func show_result(local_team: int) -> void:
	var won := GameState.match_winner == local_team
	var subtitle := "%s   %d  —  %d   %s" % [
		TEAM_NAMES[0], GameState.team_scores.get(0, 0), GameState.team_scores.get(1, 0), TEAM_NAMES[1]]

	var columns: Array[String] = ["Player", "Team", "Kills", "Credits"]
	var peers: Array = GameState.player_credits.keys()
	peers.sort_custom(func(a, b): return GameState.player_kills.get(a, 0) > GameState.player_kills.get(b, 0))
	var rows: Array = []
	for peer_id in peers:
		rows.append([
			"Player %d" % peer_id,
			TEAM_NAMES[GameState._get_player_team(peer_id) % 2],
			str(GameState.player_kills.get(peer_id, 0)),
			"$%d" % GameState.get_player_credits(peer_id),
		])

	show_custom("VICTORY" if won else "DEFEAT", won, subtitle, columns, rows)

## Generic entry: any mode supplies its own banner text and scoreboard.
## rows is an Array of Array[String], one entry per column.
func show_custom(title: String, won: bool, subtitle: String, columns: Array, rows: Array) -> void:
	layer = 40
	_build_ui(title, won, subtitle, columns, rows)

func _process(delta: float) -> void:
	if _leaving:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_return_to_menu()
	elif _button != null:
		_button.text = "Back to Menu (%d)" % int(ceil(_remaining))

func _build_ui(title: String, won: bool, subtitle: String, columns: Array, rows: Array) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 56)
	title_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5) if won else Color(1.0, 0.4, 0.4))
	vbox.add_child(title_label)

	if subtitle != "":
		var subtitle_label := Label.new()
		subtitle_label.text = subtitle
		subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		subtitle_label.add_theme_font_size_override("font_size", 24)
		vbox.add_child(subtitle_label)

	vbox.add_child(HSeparator.new())
	vbox.add_child(_scoreboard(columns, rows))
	vbox.add_child(HSeparator.new())

	_button = Button.new()
	_button.text = "Back to Menu (%d)" % int(ceil(_remaining))
	_button.pressed.connect(_return_to_menu)
	vbox.add_child(_button)

## A column-aligned table from headers + rows.
func _scoreboard(columns: Array, rows: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns.size()
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)

	for header in columns:
		var cell := Label.new()
		cell.text = str(header)
		cell.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		grid.add_child(cell)

	for row in rows:
		for value in row:
			grid.add_child(_cell(str(value)))
	return grid

func _cell(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _return_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	# Leave any active session before returning to the menu (no-op offline).
	if MultiplayerManager.current_state != MultiplayerManager.ConnectionState.DISCONNECTED:
		MultiplayerManager.disconnect_session()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file(MAIN_SCENE)
