extends CanvasLayer
"""
Offline round-state-machine test harness.

GameState is its own authority when there's no network peer, so the whole round
lifecycle runs in a single client — no host/join and no signaling broker needed.
This registers a few fake players, starts a match, and lets you drive/observe the
machine (skip phases, force wins, simulate eliminations) to validate it.
"""

const MAIN_SCENE: String = "res://addons/godot-multiplayer-weapon-system/scenes/main.tscn"
# Fake players. team = peer_id % 2  ->  team 1: {1,3}, team 0: {2,4}.
const FAKE_PEERS: Array[int] = [1, 2, 3, 4]
const PHASE_NAMES: Array[String] = ["BUY", "LIVE", "ROUND END"]

var _info: Label = null

func _ready() -> void:
	_build_ui()
	GameState.match_ended.connect(_on_match_ended)
	for peer_id in FAKE_PEERS:
		GameState.on_peer_joined(peer_id)
	GameState.start_match()

func _on_match_ended(_winning_team: int) -> void:
	# Show the same results overlay the real game uses, from peer 1's perspective.
	var screen := MatchEndScreen.new()
	add_child(screen)
	screen.show_result(GameState._get_player_team(1))

func _process(_delta: float) -> void:
	_info.text = _state_text()

func _exit_tree() -> void:
	# Don't leave the fake players in GameState for a later real match.
	GameState.clear_all_players()

func _state_text() -> String:
	var phase: String = PHASE_NAMES[GameState.current_round_state]
	var text := "Round %d / %d\n" % [GameState.current_round, GameState.TOTAL_ROUNDS]
	text += "Phase: %s     Time: %.1f\n" % [phase, maxf(GameState.round_timer, 0.0)]
	text += "Score   Team 0: %d     Team 1: %d   (first to %d)\n" % [
		GameState.team_scores[0], GameState.team_scores[1], GameState.ROUNDS_TO_WIN]
	text += "Sides swapped: %s\n" % ("YES" if GameState.sides_swapped else "no")
	text += "Credits (peer 1): %d\n" % GameState.get_player_credits(1)
	if GameState.match_over:
		text += "\nMATCH OVER — Team %d WINS" % GameState.match_winner
	return text

func _build_ui() -> void:
	layer = 5
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "ROUND STATE MACHINE — OFFLINE TEST"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	_info = Label.new()
	_info.custom_minimum_size = Vector2(0, 130)
	vbox.add_child(_info)

	_add_button(vbox, "Skip current phase", func() -> void: GameState.round_timer = 0.05)
	_add_button(vbox, "Team 0 wins round", func() -> void: GameState.end_round(0))
	_add_button(vbox, "Team 1 wins round", func() -> void: GameState.end_round(1))
	_add_button(vbox, "Eliminate Team 0 (team 1 wins)", func() -> void: _eliminate(0))
	_add_button(vbox, "Eliminate Team 1 (team 0 wins)", func() -> void: _eliminate(1))
	_add_button(vbox, "Match point (7-7)", func() -> void: _match_point())
	_add_button(vbox, "New match", func() -> void: GameState.start_match())
	_add_button(vbox, "Back to menu", func() -> void: get_tree().change_scene_to_file(MAIN_SCENE))

func _add_button(parent: VBoxContainer, text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	parent.add_child(button)

## Put both teams one round from winning, so the next round win ends the match.
func _match_point() -> void:
	var edge: int = GameState.ROUNDS_TO_WIN - 1
	GameState.team_scores[0] = edge
	GameState.team_scores[1] = edge
	GameState.emit_signal("team_score_updated", 0, edge)
	GameState.emit_signal("team_score_updated", 1, edge)

## Simulate every player on `team` being downed, which should end the round.
func _eliminate(team: int) -> void:
	var enemy: int = 1 if team == 0 else 2
	for peer_id in FAKE_PEERS:
		if peer_id % 2 == team:
			GameState.report_death(peer_id, enemy)
