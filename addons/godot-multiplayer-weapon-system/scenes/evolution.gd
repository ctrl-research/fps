extends Node3D
"""
Evolution — offline team-vs-bots round mode.

Each round opens with a DRAFT: you pick a modifier (a buff for your team or a
debuff for the enemy). Picks accumulate across the match (the "evolution") and
are applied to you and the enemy bots at the start of every round. Clear the
bots to win a round; get downed to lose it. First to ROUNDS_TO_WIN wins.

Offline slice: you are team 0 (solo for now); the bots are team 1 and auto-pick
their own modifier each round. GameState is parked (like Gun Game) so its round
machine doesn't interfere. Full team play with ally bots + networking are later
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
const WINNER_BONUS_OPTION: int = 1  # round winner drafts from one extra option

var _player: PlayerController = null
var _bots: Array = []
var _team_mods: Dictionary = {0: [], 1: []}  # team -> [modifier id, ...]
var _scores: Dictionary = {0: 0, 1: 0}
var _round: int = 1
var _last_winner: int = -1
var _resolving: bool = false

var _info_label: Label = null
var _announce_label: Label = null
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
	_start_draft()

func _exit_tree() -> void:
	GameState.match_over = false
	Modifiers.clear_active()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("disconnect_network") and not is_instance_valid(_draft):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_tree().change_scene_to_file(MAIN_SCENE)

# === Round flow ===

func _start_draft() -> void:
	_resolving = true
	_set_combat_active(false)  # freeze bots/player while drafting
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var count := DRAFT_OPTIONS + (WINNER_BONUS_OPTION if _last_winner == 0 else 0)
	_draft = EvolutionDraft.new()
	add_child(_draft)
	_draft.picked.connect(_on_player_pick)
	_draft.show_options(Modifiers.roll(count), "Round %d — Draft" % _round)
	_update_info()

func _on_player_pick(modifier_id: String) -> void:
	_team_mods[0].append(modifier_id)
	# Enemy team auto-picks (one random modifier).
	var enemy_roll := Modifiers.roll(1)
	if not enemy_roll.is_empty():
		_team_mods[1].append(enemy_roll[0])
	_apply_all_stats()
	_begin_live()

func _apply_all_stats() -> void:
	# Publish the stacks so the scoreboard (Tab) can show them.
	Modifiers.set_active(_team_mods, 0)
	if is_instance_valid(_player):
		_player.apply_stats(Modifiers.stats_for(_team_mods, 0))
	var bot_stats := Modifiers.stats_for(_team_mods, 1)
	for bot in _bots:
		if is_instance_valid(bot):
			bot.apply_stats(bot_stats)

func _begin_live() -> void:
	_resolving = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if is_instance_valid(_player):
		_player.respawn(PLAYER_SPAWN)
	for bot in _bots:
		if is_instance_valid(bot):
			bot.reset_for_round()
	_set_combat_active(true)
	_announce_evolutions()
	_update_info()

## Briefly announce what each team drafted this round.
func _announce_evolutions() -> void:
	if _announce_label == null:
		return
	var player_pick: String = _team_mods[0].back() if not _team_mods[0].is_empty() else ""
	var enemy_pick: String = _team_mods[1].back() if not _team_mods[1].is_empty() else ""
	_announce_label.text = "EVOLUTION   —   You: %s      Enemy: %s" % [_signed(player_pick), _signed(enemy_pick)]
	_announce_label.visible = true
	var tween := create_tween()
	tween.tween_interval(3.5)
	tween.tween_callback(func() -> void: _announce_label.visible = false)

## "+Name" for a buff, "-Name" for a debuff.
func _signed(modifier_id: String) -> String:
	if modifier_id == "":
		return "—"
	var m := Modifiers.get_mod(modifier_id)
	var prefix := "+" if m.get("kind") == "buff" else "-"
	return "%s%s" % [prefix, m.get("name", modifier_id)]

## Freeze/unfreeze the player and bots (so combat pauses during the draft).
func _set_combat_active(active: bool) -> void:
	if is_instance_valid(_player):
		_player.set_physics_process(active)
	for bot in _bots:
		if is_instance_valid(bot):
			bot.set_physics_process(active)

func _on_bot_defeated(_by_peer_id: int) -> void:
	if _resolving:
		return
	for bot in _bots:
		if is_instance_valid(bot) and bot.is_alive():
			return  # at least one enemy still up
	_end_round(0)  # all enemies down — player wins the round

func _on_player_downed() -> void:
	if _resolving:
		return
	_end_round(1)  # player downed — enemy wins the round

func _end_round(winner: int) -> void:
	_resolving = true
	_scores[winner] += 1
	_last_winner = winner
	GameAudio.play_ui("round_win" if winner == 0 else "round_lose", -2.0)
	if _scores[winner] >= ROUNDS_TO_WIN:
		_finish_match(winner)
		return
	_round += 1
	_start_draft()

func _finish_match(winner: int) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var screen := MatchEndScreen.new()
	add_child(screen)
	var rows := [
		["You", _modifier_summary(0), str(_scores[0])],
		["Enemy", _modifier_summary(1), str(_scores[1])],
	]
	screen.show_custom("VICTORY" if winner == 0 else "DEFEAT", winner == 0,
		"Evolution — first to %d rounds" % ROUNDS_TO_WIN,
		["Team", "Evolutions", "Rounds"], rows)

## Human-readable list of a team's drafted modifiers.
func _modifier_summary(team: int) -> String:
	var names: Array = []
	for id in _team_mods[team]:
		names.append(Modifiers.get_mod(id).get("name", id))
	return ", ".join(names) if not names.is_empty() else "—"

# === Setup ===

func _spawn_player() -> void:
	PlayerLoadout.primary_weapon = "ar_basic"
	PlayerLoadout.secondary_weapon = "pistol_basic"
	_player = load(PLAYER_SCENE).instantiate()
	_player.name = "Player_%d" % PLAYER_PEER
	_player.authority_peer_id = PLAYER_PEER
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

	# Round-start announcement of each team's drafted evolution (auto-hides).
	_announce_label = Label.new()
	_announce_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_announce_label.offset_top = 84.0
	_announce_label.offset_left = -400.0
	_announce_label.offset_right = 400.0
	_announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_label.add_theme_font_size_override("font_size", 26)
	_announce_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	_announce_label.visible = false
	layer.add_child(_announce_label)

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
