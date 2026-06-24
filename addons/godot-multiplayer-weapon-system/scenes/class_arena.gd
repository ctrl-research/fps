extends Node3D
class_name ClassArena
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

## When true, the player rebuilds their spec freely each round and can change
## class (beginner / bot-session friendly). Off = specs permanent, class fixed.
@export var allow_respec: bool = false
## Set by the lobby before launching this scene (carries the lobby toggle).
static var next_allow_respec: bool = false

var _player: PlayerController = null
var _bots: Array = []                # enemy team (team 1)
var _ally_bots: Array = []           # player's team (team 0), start each round downed
var _player_spawn: Vector3 = Vector3.ZERO
var _bot_spawns: Array = []
var _team0_spawns: Array = []

var _class_id: String = ""
var _spec: SpecTree = null
var _scores: Dictionary = {0: 0, 1: 0}
var _round: int = 1
var _last_winner: int = -1

var _phase: int = Phase.SELECT
var _timer: float = 0.0
var _info_label: Label = null
var _countdown_label: Label = null
var _sky: DayNightSky = null
var _overlay: CanvasLayer = null

func _ready() -> void:
	allow_respec = next_allow_respec
	GameState.match_over = true
	GameState.current_round_state = GameState.RoundState.LIVE

	_build_environment()
	var arena := Arena.new()
	add_child(arena)
	_team0_spawns = arena.team_spawns(0)
	_player_spawn = _team0_spawns[0]
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
	_spawn_ally_bots()
	_enter_spec()

func _enter_spec() -> void:
	# Normal mode with the tree capped → nothing to pick, go to the countdown.
	if not allow_respec and (_spec.points_spent() >= ClassDatabase.MAX_POINTS or _spec.selectable().is_empty()):
		_apply_spec()
		_enter_pre()
		return
	_phase = Phase.SPEC
	_set_combat_active(false)
	_countdown_label.visible = false
	var earned := mini(_round, ClassDatabase.MAX_POINTS)
	var spec_ui := SpecSelect.new()
	add_child(spec_ui)
	if allow_respec:
		spec_ui.allocation_done.connect(_on_alloc_done)
		spec_ui.change_class_requested.connect(_on_change_class)
		spec_ui.show_choices(_spec, "Round %d — Build your spec" % _round, earned, true,
			ClassDatabase.class_ids().size() > 1)
	else:
		spec_ui.node_picked.connect(_on_node_picked)
		spec_ui.show_choices(_spec, "Round %d — Spec point" % _round, 1, false, false)
	_update_info()

func _on_node_picked(path: int) -> void:
	_spec.advance(path)
	_apply_spec()
	_enter_pre()

func _on_alloc_done() -> void:
	_apply_spec()
	_enter_pre()

## Respec mode: re-pick the class, rebuilding the spec on a fresh body.
func _on_change_class() -> void:
	var select := ClassSelect.new()
	add_child(select)
	select.class_picked.connect(_on_reclass)
	select.show_classes()

func _on_reclass(class_id: String) -> void:
	if class_id != _class_id:
		_class_id = class_id
		_spec = SpecTree.new(class_id)
		if is_instance_valid(_player):
			_player.queue_free()
		_spawn_player()
	_enter_spec()

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
	# Ally bots start each round downed, waiting for the player to revive them.
	for ally in _ally_bots:
		if is_instance_valid(ally):
			ally.reset_for_round()
			ally.knock_down()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_set_combat_active(true)
	_update_day_night()
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
	_player.team = 0
	_player.class_id = _class_id
	# The mode owns the cursor during select/spec/countdowns.
	_player.capture_mouse_on_ready = false
	_player.position = _player_spawn
	add_child(_player)
	_player.downed.connect(_on_player_downed)

func _spawn_bots() -> void:
	var scene: PackedScene = load(BOT_SCENE)
	# One bot of each class on the enemy team.
	var bot_classes: Array[String] = ["warrior", "mage", "archer"]
	for index in bot_classes.size():
		var bot: Bot = scene.instantiate()
		bot.authority_peer_id = 1001 + index * 2
		bot.auto_respawn = false
		bot.class_id = bot_classes[index]
		bot.position = _bot_spawns[index]
		add_child(bot)
		bot.team = 1
		bot.defeated.connect(_on_bot_defeated)
		_bots.append(bot)

## Spawn the player's ally bots: one of each class the player didn't pick. They
## start each round downed so the player can revive them (and they fight enemy
## bots once revived). They don't count toward the round-win check.
func _spawn_ally_bots() -> void:
	var scene: PackedScene = load(BOT_SCENE)
	var index := 0
	for cid in ClassDatabase.class_ids():
		if cid == _class_id:
			continue
		var bot: Bot = scene.instantiate()
		bot.authority_peer_id = 2002 + index * 2   # even ids
		bot.auto_respawn = false
		bot.team = 0
		bot.class_id = cid
		bot.position = _team0_spawns[mini(index + 1, _team0_spawns.size() - 1)]
		add_child(bot)
		_ally_bots.append(bot)
		index += 1

func _set_combat_active(active: bool) -> void:
	if is_instance_valid(_player):
		_player.set_physics_process(active)
		_player.set_process_input(active)
		_player.set_process_unhandled_input(active)
	for bot in _bots:
		if is_instance_valid(bot):
			bot.set_physics_process(active)
	for ally in _ally_bots:
		if is_instance_valid(ally):
			ally.set_physics_process(active)

# === HUD / helpers ===

func _build_summary() -> String:
	if _spec == null:
		return "—"
	var paths: Array = _spec.class_def().get("paths", [])
	var parts: Array = []
	for p in paths.size():
		parts.append("%s %d" % [paths[p].get("name", "Path"), _spec.depths[p]])
	return ClassDatabase.get_def(_class_id).get("name", _class_id) + ": " + " / ".join(parts)

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
	# Procedural sky + sun with a day→sunset→night cycle across the match.
	_sky = DayNightSky.new()
	add_child(_sky)

## Advance the sky each round: time-of-day progress plus a "doom" redness that
## ramps from clear (round 1) to fully red by round 8.
func _update_day_night() -> void:
	if _sky:
		var progress := clampf(float(_round - 1) / float(2 * ROUNDS_TO_WIN - 2), 0.0, 1.0)
		var red := clampf(float(_round - 1) / 7.0, 0.0, 1.0)
		_sky.apply(progress, red)
