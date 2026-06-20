extends Node3D
"""
Class Arena — the core game mode (issue #78). Offline-vs-bots slice.

Pre-match you pick a class; then each round you spend 1 spec point down your
class's tree before fighting. Round loop:
  SELECT (once) → [ SPEC → PRE countdown → LIVE → POST countdown ] per round
Clear the enemy team to win a round; get downed to lose it. First to
ROUNDS_TO_WIN wins. Points cap at ClassDatabase.MAX_POINTS.

Reuses the symmetric Arena, the spec/ability systems, the pause controller, and
the robust pre-fight cursor handling from Evolution.
"""

const PLAYER_SCENE: String = "res://addons/godot-multiplayer-weapon-system/player/player.tscn"
const BOT_SCENE: String = "res://addons/godot-multiplayer-weapon-system/player/bot.tscn"

const PLAYER_PEER: int = 1
const ROUNDS_TO_WIN: int = 6
const POST_SECS: float = 5.0
const PRE_SECS: float = 5.0

enum Phase { SELECT, SPEC, PRE, LIVE, POST }

## When true (set by lobby/bot-session), the player can re-pick their class /
## rebuild their spec; wired by a later chunk. Stored now so the option exists.
@export var allow_respec: bool = false

var _player: PlayerController = null
var _bots: Array = []
var _player_spawn: Vector3 = Vector3.ZERO
var _bot_spawns: Array = []

var _class_id: String = ""
var _spec: SpecTree = null
var _scores: Dictionary = {0: 0, 1: 0}
var _round: int = 1
var _last_winner: int = -1

var _phase: int = Phase.SELECT
var _timer: float = 0.0
var _info_label: Label = null
var _countdown_label: Label = null
var _overlay: CanvasLayer = null

func _ready() -> void:
	GameState.match_over = true
	GameState.current_round_state = GameState.RoundState.LIVE

	_build_environment()
	var arena := Arena.new()
	add_child(arena)
	_player_spawn = arena.team_spawns(0)[0]
	_bot_spawns = arena.team_spawns(1)
	_spawn_bots()
	_build_hud()

	var pause := PauseController.new()
	pause.is_blocked = func() -> bool: return _phase != Phase.LIVE
	add_child(pause)

	_enter_select()

func _exit_tree() -> void:
	GameState.match_over = false

func _process(delta: float) -> void:
	if _phase != Phase.LIVE and Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	match _phase:
		Phase.POST:
			_timer -= delta
			_countdown_label.text = "Round %d to %s\nNext round in %d" % [
				_round - 1, _team_name(_last_winner), int(ceil(_timer))]
			if _timer <= 0.0:
				_enter_spec()
		Phase.PRE:
			_timer -= delta
			_countdown_label.text = "Round %d — get ready\n%d" % [_round, int(ceil(_timer))]
			if _timer <= 0.0:
				_begin_live()

# === Phases ===

func _enter_select() -> void:
	_phase = Phase.SELECT
	_set_combat_active(false)
	var select := ClassSelect.new()
	_overlay = select
	add_child(select)
	select.class_picked.connect(_on_class_picked)
	select.show_classes()

func _on_class_picked(class_id: String) -> void:
	_class_id = class_id
	_spec = SpecTree.new(class_id)
	_spawn_player()
	_enter_spec()

func _enter_spec() -> void:
	# No point left to spend (tree capped) → skip straight to the countdown.
	if _spec.points_spent() >= ClassDatabase.MAX_POINTS or _spec.selectable().is_empty():
		_apply_spec()
		_enter_pre()
		return
	_phase = Phase.SPEC
	_set_combat_active(false)
	_countdown_label.visible = false
	var spec_ui := SpecSelect.new()
	_overlay = spec_ui
	add_child(spec_ui)
	spec_ui.node_picked.connect(_on_node_picked)
	spec_ui.show_choices(_spec, "Round %d — Spec point" % _round)
	_update_info()

func _on_node_picked(path: int) -> void:
	_spec.advance(path)
	_apply_spec()
	_enter_pre()

func _enter_pre() -> void:
	_phase = Phase.PRE
	_timer = PRE_SECS
	_countdown_label.visible = true

func _begin_live() -> void:
	_phase = Phase.LIVE
	_countdown_label.visible = false
	if is_instance_valid(_player):
		_player.respawn(_player_spawn)
	for bot in _bots:
		if is_instance_valid(bot):
			bot.reset_for_round()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_set_combat_active(true)
	_update_info()

func _apply_spec() -> void:
	if is_instance_valid(_player):
		_player.apply_spec(_spec)

# === Round resolution ===

func _on_bot_defeated(_by_peer_id: int) -> void:
	if _phase != Phase.LIVE:
		return
	for bot in _bots:
		if is_instance_valid(bot) and bot.is_alive():
			return
	_end_round(0)

func _on_player_downed() -> void:
	if _phase != Phase.LIVE:
		return
	_end_round(1)

func _end_round(winner: int) -> void:
	_set_combat_active(false)
	_scores[winner] += 1
	_last_winner = winner
	GameAudio.play_ui("round_win" if winner == 0 else "round_lose", -2.0)
	if _scores[winner] >= ROUNDS_TO_WIN:
		_finish_match(winner)
		return
	_round += 1
	_phase = Phase.POST
	_timer = POST_SECS
	_countdown_label.visible = true

func _finish_match(winner: int) -> void:
	_phase = Phase.POST
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_countdown_label.visible = false
	var screen := MatchEndScreen.new()
	add_child(screen)
	var rows := [
		["You", _build_summary(), str(_scores[0])],
		["Enemy", "—", str(_scores[1])],
	]
	screen.show_custom("VICTORY" if winner == 0 else "DEFEAT", winner == 0,
		"Class Arena — first to %d rounds" % ROUNDS_TO_WIN,
		["Team", "Build", "Rounds"], rows)

# === Setup ===

func _spawn_player() -> void:
	_player = load(PLAYER_SCENE).instantiate()
	_player.name = "Player_%d" % PLAYER_PEER
	_player.authority_peer_id = PLAYER_PEER
	_player.class_id = _class_id
	# The mode owns the cursor during select/spec/countdowns.
	_player.capture_mouse_on_ready = false
	_player.position = _player_spawn
	add_child(_player)
	_player.downed.connect(_on_player_downed)

func _spawn_bots() -> void:
	var scene: PackedScene = load(BOT_SCENE)
	for index in _bot_spawns.size():
		var bot: Bot = scene.instantiate()
		bot.authority_peer_id = 1001 + index * 2
		bot.auto_respawn = false
		bot.position = _bot_spawns[index]
		add_child(bot)
		bot.defeated.connect(_on_bot_defeated)
		_bots.append(bot)

func _set_combat_active(active: bool) -> void:
	if is_instance_valid(_player):
		_player.set_physics_process(active)
		_player.set_process_input(active)
		_player.set_process_unhandled_input(active)
	for bot in _bots:
		if is_instance_valid(bot):
			bot.set_physics_process(active)

# === HUD / helpers ===

func _build_summary() -> String:
	if _spec == null:
		return "—"
	var paths: Array = _spec.class_def().get("paths", [])
	var parts: Array = []
	for p in paths.size():
		parts.append("%s %d" % [paths[p].get("name", "Path"), _spec.depths[p]])
	return ClassDatabase.get_class(_class_id).get("name", _class_id) + ": " + " / ".join(parts)

func _team_name(team: int) -> String:
	return "You" if team == 0 else "Enemy"

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_info_label = Label.new()
	_info_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_info_label.offset_top = 44.0
	_info_label.offset_left = -320.0
	_info_label.offset_right = 320.0
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.add_theme_font_size_override("font_size", 20)
	_info_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	layer.add_child(_info_label)

	_countdown_label = Label.new()
	_countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_label.offset_left = -360.0
	_countdown_label.offset_right = 360.0
	_countdown_label.offset_top = -80.0
	_countdown_label.offset_bottom = 80.0
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 34)
	_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	_countdown_label.visible = false
	layer.add_child(_countdown_label)

func _update_info() -> void:
	if _info_label:
		_info_label.text = "CLASS ARENA   Round %d   ·   You %d — %d Enemy   (first to %d)   ·   %s" % [
			_round, _scores[0], _scores[1], ROUNDS_TO_WIN, _build_summary()]

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.45)
	env.ambient_light_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)
