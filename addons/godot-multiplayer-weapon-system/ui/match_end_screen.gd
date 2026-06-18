extends CanvasLayer
class_name MatchEndScreen
"""
Post-match results overlay.

Shows VICTORY/DEFEAT (relative to the local team) and a scoreboard, then auto-
returns to the main menu after a countdown. The button shows the live countdown
and lets the player skip straight back.
"""

const MAIN_SCENE: String = "res://addons/godot-multiplayer-weapon-system/scenes/main.tscn"
const COUNTDOWN: float = 8.0
const TEAM_NAMES: Array[String] = ["Team A", "Team B"]

var _remaining: float = COUNTDOWN
var _button: Button = null
var _leaving: bool = false

## Build and show the results for the given local team (0 or 1).
func show_result(local_team: int) -> void:
	layer = 40
	_build_ui(local_team)

func _process(delta: float) -> void:
	if _leaving:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_return_to_menu()
	elif _button != null:
		_button.text = "Back to Menu (%d)" % int(ceil(_remaining))

func _build_ui(local_team: int) -> void:
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

	var won := GameState.match_winner == local_team
	var title := Label.new()
	title.text = "VICTORY" if won else "DEFEAT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5) if won else Color(1.0, 0.4, 0.4))
	vbox.add_child(title)

	var score := Label.new()
	score.text = "%s   %d  —  %d   %s" % [
		TEAM_NAMES[0], GameState.team_scores.get(0, 0), GameState.team_scores.get(1, 0), TEAM_NAMES[1]]
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.add_theme_font_size_override("font_size", 24)
	vbox.add_child(score)

	vbox.add_child(HSeparator.new())
	vbox.add_child(_scoreboard())
	vbox.add_child(HSeparator.new())

	_button = Button.new()
	_button.text = "Back to Menu (%d)" % int(ceil(_remaining))
	_button.pressed.connect(_return_to_menu)
	vbox.add_child(_button)

## A per-player table (player, team, kills, credits), sorted by kills.
func _scoreboard() -> VBoxContainer:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = "Player        Team      Kills      Credits"
	header.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	list.add_child(header)

	var peers: Array = GameState.player_credits.keys()
	peers.sort_custom(func(a, b): return GameState.player_kills.get(a, 0) > GameState.player_kills.get(b, 0))
	for peer_id in peers:
		var team: int = GameState._get_player_team(peer_id)
		var kills: int = GameState.player_kills.get(peer_id, 0)
		var credits: int = GameState.get_player_credits(peer_id)
		var row := Label.new()
		row.text = "Player %-4d   %-8s   %-6d   $%d" % [peer_id, TEAM_NAMES[team % 2], kills, credits]
		list.add_child(row)
	return list

func _return_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	# Leave any active session before returning to the menu (no-op offline).
	if MultiplayerManager.current_state != MultiplayerManager.ConnectionState.DISCONNECTED:
		MultiplayerManager.disconnect_session()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file(MAIN_SCENE)
