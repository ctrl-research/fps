extends Node3D
"""
Evolution — offline team-vs-bots round mode.

Round loop:
  POST-ROUND countdown (5s)  → VOTE (≤30s)  → PRE-ROUND countdown (5s)  → LIVE
The first round skips the post-round countdown (nothing precedes it).

Each round the team votes on a modifier — a buff for itself or a debuff for the
enemy. Votes show as ally-blue dots; the most-voted option wins (ties broken
randomly; no votes → random). Voting ends at 30s, or shortly after everyone has
voted. Picks accumulate across the match and reapply each round. Clear the bots
to win a round; get downed to lose it. First to ROUNDS_TO_WIN wins.

Offline slice: you are team 0 (solo for now); the bots are team 1 and auto-pick.
GameState is parked (like Gun Game). Full team play + networking are later
milestones (see issue #64).
"""

const PLAYER_SCENE: String = "res://addons/godot-multiplayer-weapon-system/player/player.tscn"
const BOT_SCENE: String = "res://addons/godot-multiplayer-weapon-system/player/bot.tscn"
const MAIN_SCENE: String = "res://addons/godot-multiplayer-weapon-system/scenes/main.tscn"

const PLAYER_PEER: int = 1
const PLAYER_SPAWN: Vector3 = Vector3(0.0, 1.5, 14.0)
const BOT_SPAWNS: Array[Vector3] = [
	Vector3(-6.0, 1.0, -12.0),
	Vector3(6.0, 1.0, -12.0),
	Vector3(0.0, 1.0, -15.0),
]
const ROUNDS_TO_WIN: int = 4
const DRAFT_OPTIONS: int = 3
const WINNER_BONUS_OPTION: int = 1  # round winner votes from one extra option

const POST_SECS: float = 5.0       # pacing buffer after a round, before voting
const PRE_SECS: float = 5.0        # "get ready" countdown before the fight
const VOTE_SECS: float = 30.0      # max voting time
const VOTE_LOCKIN_SECS: float = 3.0  # grace once everyone has voted

enum Phase { POST, VOTE, PRE, LIVE }

var _player: PlayerController = null
var _bots: Array = []
var _team_mods: Dictionary = {0: [], 1: []}  # team -> [modifier id, ...]
var _scores: Dictionary = {0: 0, 1: 0}
var _round: int = 1
var _last_winner: int = -1

var _phase: int = Phase.POST
var _timer: float = 0.0
var _options: Array = []
var _votes: Dictionary = {}        # voter peer id -> option id
var _voters: Array = [PLAYER_PEER]  # team-0 members able to vote
var _lockin_applied: bool = false

var _info_label: Label = null
var _countdown_label: Label = null
var _draft: EvolutionDraft = null

func _ready() -> void:
	# Park GameState so its round machine / buy hint / buy music stay out.
	GameState.match_over = true
	GameState.current_round_state = GameState.RoundState.LIVE

	_build_environment()
	_build_arena()
	_spawn_bots()
	_spawn_player()
	_build_hud()

	# Esc opens the in-game menu, but only during LIVE (not the draft/countdowns).
	var pause := PauseController.new()
	pause.is_blocked = func() -> bool: return _phase != Phase.LIVE
	add_child(pause)

	_enter_vote()  # round 1: straight to voting (no preceding round)

func _exit_tree() -> void:
	GameState.match_over = false
	Modifiers.clear_active()

func _process(delta: float) -> void:
	# Keep the cursor free through every pre-fight phase. This also defeats the
	# web pointer-lock grant that can arrive a frame after the player spawns
	# (the round-1 "mouse stuck" bug): we re-assert VISIBLE until the fight.
	if _phase != Phase.LIVE and Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	match _phase:
		Phase.POST:
			_timer -= delta
			_countdown_label.text = "Round %d won by %s\nNext round in %d" % [
				_round - 1, _team_name(_last_winner), int(ceil(_timer))]
			if _timer <= 0.0:
				_enter_vote()
		Phase.VOTE:
			_timer -= delta
			if not _lockin_applied and _all_voted():
				_timer = minf(_timer, VOTE_LOCKIN_SECS)
				_lockin_applied = true
			if is_instance_valid(_draft):
				_draft.set_header("Round %d — Vote  (%ds)" % [_round, int(ceil(_timer))])
			if _timer <= 0.0:
				_resolve_vote()
		Phase.PRE:
			_timer -= delta
			_countdown_label.text = "Round %d starting in %d\nYou: %s    Enemy: %s" % [
				_round, int(ceil(_timer)), _signed(_last_pick(0)), _signed(_last_pick(1))]
			if _timer <= 0.0:
				_begin_live()

# === Phases ===

func _enter_post() -> void:
	_phase = Phase.POST
	_timer = POST_SECS
	_set_combat_active(false)
	_countdown_label.visible = true

func _enter_vote() -> void:
	_phase = Phase.VOTE
	_timer = VOTE_SECS
	_lockin_applied = false
	_votes.clear()
	_set_combat_active(false)
	_countdown_label.visible = false

	var count := DRAFT_OPTIONS + (WINNER_BONUS_OPTION if _last_winner == 0 else 0)
	_options = Modifiers.roll(count)
	_draft = EvolutionDraft.new()
	add_child(_draft)
	_draft.vote_changed.connect(_on_vote)
	_draft.show_options(_options, "Round %d — Vote  (%ds)" % [_round, int(VOTE_SECS)])
	_draft.set_votes(_tally())
	_update_info()

func _enter_pre() -> void:
	_phase = Phase.PRE
	_timer = PRE_SECS
	_countdown_label.visible = true

func _begin_live() -> void:
	_phase = Phase.LIVE
	_countdown_label.visible = false
	if is_instance_valid(_player):
		_player.respawn(PLAYER_SPAWN)
	for bot in _bots:
		if is_instance_valid(bot):
			bot.reset_for_round()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_set_combat_active(true)
	_update_info()

# === Voting ===

func _on_vote(option_id: String) -> void:
	_votes[PLAYER_PEER] = option_id
	if is_instance_valid(_draft):
		_draft.set_votes(_tally())

func _all_voted() -> bool:
	for voter in _voters:
		if not _votes.has(voter):
			return false
	return true

## {option_id: vote count} for the current options.
func _tally() -> Dictionary:
	var counts := {}
	for id in _options:
		counts[id] = 0
	for voter in _votes:
		var id: String = _votes[voter]
		counts[id] = int(counts.get(id, 0)) + 1
	return counts

## The voted-in modifier: most votes, ties broken randomly, no votes → random.
func _winning_option() -> String:
	if _votes.is_empty():
		return _options[randi() % _options.size()] if not _options.is_empty() else ""
	var counts := _tally()
	var best := 0
	for id in counts:
		best = maxi(best, counts[id])
	var top: Array = []
	for id in counts:
		if counts[id] == best:
			top.append(id)
	return top[randi() % top.size()]

func _resolve_vote() -> void:
	var pick := _winning_option()
	if pick != "":
		_team_mods[0].append(pick)
	# Enemy team auto-picks one random modifier.
	var enemy_roll := Modifiers.roll(1)
	if not enemy_roll.is_empty():
		_team_mods[1].append(enemy_roll[0])

	if is_instance_valid(_draft):
		_draft.queue_free()
		_draft = null
	_apply_all_stats()
	_enter_pre()

func _apply_all_stats() -> void:
	# Publish the stacks so the scoreboard (Tab) can show them.
	Modifiers.set_active(_team_mods, 0)
	if is_instance_valid(_player):
		_player.apply_stats(Modifiers.stats_for(_team_mods, 0))
	var bot_stats := Modifiers.stats_for(_team_mods, 1)
	for bot in _bots:
		if is_instance_valid(bot):
			bot.apply_stats(bot_stats)

# === Round resolution ===

func _on_bot_defeated(_by_peer_id: int) -> void:
	if _phase != Phase.LIVE:
		return
	for bot in _bots:
		if is_instance_valid(bot) and bot.is_alive():
			return  # at least one enemy still up
	_end_round(0)  # all enemies down — player wins the round

func _on_player_downed() -> void:
	if _phase != Phase.LIVE:
		return
	_end_round(1)  # player downed — enemy wins the round

func _end_round(winner: int) -> void:
	_set_combat_active(false)
	_scores[winner] += 1
	_last_winner = winner
	GameAudio.play_ui("round_win" if winner == 0 else "round_lose", -2.0)
	if _scores[winner] >= ROUNDS_TO_WIN:
		_finish_match(winner)
		return
	_round += 1
	_enter_post()

func _finish_match(winner: int) -> void:
	_phase = Phase.POST  # not LIVE → pause stays blocked, cursor freed
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_countdown_label.visible = false
	var screen := MatchEndScreen.new()
	add_child(screen)
	var rows := [
		["You", _modifier_summary(0), str(_scores[0])],
		["Enemy", _modifier_summary(1), str(_scores[1])],
	]
	screen.show_custom("VICTORY" if winner == 0 else "DEFEAT", winner == 0,
		"Evolution — first to %d rounds" % ROUNDS_TO_WIN,
		["Team", "Evolutions", "Rounds"], rows)

# === Helpers ===

func _last_pick(team: int) -> String:
	return _team_mods[team].back() if not _team_mods[team].is_empty() else ""

## "+Name" for a buff, "-Name" for a debuff.
func _signed(modifier_id: String) -> String:
	if modifier_id == "":
		return "—"
	var m := Modifiers.get_mod(modifier_id)
	var prefix := "+" if m.get("kind") == "buff" else "-"
	return "%s%s" % [prefix, m.get("name", modifier_id)]

func _team_name(team: int) -> String:
	return "You" if team == 0 else "Enemy"

## Human-readable list of a team's drafted modifiers.
func _modifier_summary(team: int) -> String:
	var names: Array = []
	for id in _team_mods[team]:
		names.append(Modifiers.get_mod(id).get("name", id))
	return ", ".join(names) if not names.is_empty() else "—"

## Freeze/unfreeze the player and bots (combat only runs during LIVE).
func _set_combat_active(active: bool) -> void:
	if is_instance_valid(_player):
		_player.set_physics_process(active)
		_player.set_process_input(active)
		_player.set_process_unhandled_input(active)
	for bot in _bots:
		if is_instance_valid(bot):
			bot.set_physics_process(active)

# === Setup ===

func _spawn_player() -> void:
	PlayerLoadout.primary_weapon = "ar_basic"
	PlayerLoadout.secondary_weapon = "pistol_basic"
	_player = load(PLAYER_SCENE).instantiate()
	_player.name = "Player_%d" % PLAYER_PEER
	_player.authority_peer_id = PLAYER_PEER
	# The mode drives the cursor (voting/countdowns are mouse-free); don't let the
	# player grab pointer lock on spawn (the round-1 "mouse stuck" cause).
	_player.capture_mouse_on_ready = false
	_player.position = PLAYER_SPAWN
	add_child(_player)
	_player.downed.connect(_on_player_downed)

func _spawn_bots() -> void:
	var scene: PackedScene = load(BOT_SCENE)
	var index := 0
	for pos in BOT_SPAWNS:
		var bot: Bot = scene.instantiate()
		bot.authority_peer_id = 1001 + index * 2
		bot.auto_respawn = false
		bot.position = pos
		add_child(bot)
		bot.defeated.connect(_on_bot_defeated)
		_bots.append(bot)
		index += 1

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_info_label = Label.new()
	_info_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_info_label.offset_top = 44.0
	_info_label.offset_left = -300.0
	_info_label.offset_right = 300.0
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.add_theme_font_size_override("font_size", 20)
	_info_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	layer.add_child(_info_label)

	# Big centred countdown for the POST / PRE phases.
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
		_info_label.text = "EVOLUTION   Round %d   ·   You %d — %d Enemy   (first to %d)" % [
			_round, _scores[0], _scores[1], ROUNDS_TO_WIN]

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

func _build_arena() -> void:
	_add_static_box(Vector3(0.0, -0.5, 0.0), Vector3(48.0, 1.0, 60.0), Color(0.2, 0.22, 0.26))
	var cover := Color(0.3, 0.27, 0.24)
	_add_static_box(Vector3(-5.0, 1.0, 0.0), Vector3(2.0, 2.0, 2.0), cover)
	_add_static_box(Vector3(5.0, 1.0, 0.0), Vector3(2.0, 2.0, 2.0), cover)
	_add_static_box(Vector3(0.0, 1.0, -4.0), Vector3(4.0, 2.0, 1.0), cover)
	_add_static_box(Vector3(-9.0, 1.25, 4.0), Vector3(1.0, 2.5, 5.0), cover)
	_add_static_box(Vector3(9.0, 1.25, 4.0), Vector3(1.0, 2.5, 5.0), cover)

func _add_static_box(pos: Vector3, box_size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var collision_box := BoxShape3D.new()
	collision_box.size = box_size
	shape.shape = collision_box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = CategoryColors.to_map_grey(color)
	mesh.material_override = material
	body.add_child(mesh)
	add_child(body)
