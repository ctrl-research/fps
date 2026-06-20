extends Node3D
"""
Gun Game — offline FFA vs bots.

Every kill advances you up a weapon ladder; finish past the last weapon to win.
Bots advance too (each time one downs you it climbs a rung), so there's pressure
not to die. Runs entirely offline (no networking / broker) for easy testing.

GameState is parked (match_over + LIVE) so its round machine doesn't interfere
and the buy-phase HUD hint stays hidden.
"""

const PLAYER_SCENE: String = "res://addons/godot-multiplayer-weapon-system/player/player.tscn"
const BOT_SCENE: String = "res://addons/godot-multiplayer-weapon-system/player/bot.tscn"
const MAIN_SCENE: String = "res://addons/godot-multiplayer-weapon-system/scenes/main.tscn"

## Weapon progression (WeaponDatabase ids). Advancing past the last one wins.
const LADDER: Array[String] = [
	"pistol_basic", "smg_fast", "smg_high_cap", "ar_basic", "ar_heavy",
	"shotgun_pump", "sniper_auto", "pistol_deagle",
]

const PLAYER_PEER: int = 1
const RESPAWN_DELAY: float = 2.0

# Spawns pulled from the shared Arena (FFA: player + bots spread across both ends).
var _player_spawn: Vector3 = Vector3(0.0, 1.5, 40.0)
var _bot_spawns: Array = []

var _player: PlayerController = null
var _player_level: int = 0
var _bots: Dictionary = {}        # peer_id -> Bot
var _bot_levels: Dictionary = {}  # peer_id -> int
var _over: bool = false

var _level_label: Label = null

func _ready() -> void:
	# Neutralise the round machine so it doesn't tick / show the buy hint.
	GameState.match_over = true
	GameState.current_round_state = GameState.RoundState.LIVE

	_build_environment()
	# Shared battle map. FFA: player at one end, bots at the far end + spares.
	var arena := Arena.new()
	add_child(arena)
	var spawns := arena.all_spawns()
	_player_spawn = spawns[0]
	_bot_spawns = spawns.slice(1)
	_spawn_bots()
	_spawn_player()
	_build_hud()
	_update_level_label()

	# Esc opens the in-game menu (Resume / Settings / Leave).
	add_child(PauseController.new())

func _exit_tree() -> void:
	GameState.match_over = false

# === Setup ===

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

const BOT_COUNT: int = 3

func _spawn_bots() -> void:
	var scene: PackedScene = load(BOT_SCENE)
	for index in mini(BOT_COUNT, _bot_spawns.size()):
		var bot: Bot = scene.instantiate()
		var peer_id := 1001 + index * 2
		bot.authority_peer_id = peer_id
		bot.position = _bot_spawns[index]
		add_child(bot)
		bot.defeated.connect(_on_bot_defeated.bind(peer_id))
		_bots[peer_id] = bot
		_bot_levels[peer_id] = 0

func _spawn_player() -> void:
	PlayerLoadout.primary_weapon = LADDER[0]
	PlayerLoadout.secondary_weapon = ""
	_player = load(PLAYER_SCENE).instantiate()
	_player.name = "Player_%d" % PLAYER_PEER
	_player.authority_peer_id = PLAYER_PEER
	_player.position = _player_spawn
	add_child(_player)
	_player.downed.connect(_on_player_downed)

# === Gun Game rules ===

func _on_bot_defeated(by_peer_id: int, _bot_peer_id: int) -> void:
	if by_peer_id == PLAYER_PEER:
		_player_scored()

func _on_player_downed() -> void:
	if not _over:
		var attacker: int = _player._last_attacker_id
		if _bots.has(attacker):
			_bot_scored(attacker)
	# Quick respawn (keeps the player's level).
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if is_instance_valid(_player) and not _over:
		_player.respawn(_player_spawn)

func _player_scored() -> void:
	if _over:
		return
	_player_level += 1
	if _player_level >= LADDER.size():
		_declare_winner("VICTORY", true)
	else:
		_equip_for_level()

func _bot_scored(peer_id: int) -> void:
	if _over or not _bot_levels.has(peer_id):
		return
	_bot_levels[peer_id] += 1
	if _bot_levels[peer_id] >= LADDER.size():
		_declare_winner("DEFEAT", false)

func _equip_for_level() -> void:
	PlayerLoadout.primary_weapon = LADDER[_player_level]
	PlayerLoadout.secondary_weapon = ""
	PlayerLoadout.loadout_changed.emit()
	_update_level_label()

func _declare_winner(title: String, player_won: bool) -> void:
	_over = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var screen := MatchEndScreen.new()
	add_child(screen)
	var subtitle := "Gun Game — first to clear the ladder (%d kills)" % LADDER.size()
	screen.show_custom(title, player_won, subtitle, ["Player", "Kills", "Weapon"], _scoreboard_rows())

## FFA scoreboard rows (player + bots), sorted by kills (= ladder level) desc.
func _scoreboard_rows() -> Array:
	var entries: Array = [{"name": "You", "kills": _player_level}]
	var index := 1
	for peer_id in _bot_levels:
		entries.append({"name": "Bot %d" % index, "kills": _bot_levels[peer_id]})
		index += 1
	entries.sort_custom(func(a, b): return a["kills"] > b["kills"])

	var rows: Array = []
	for entry in entries:
		var kills: int = entry["kills"]
		var weapon := "— finished —" if kills >= LADDER.size() else \
			WeaponDatabase.get_weapon(LADDER[kills]).get("name", LADDER[kills])
		rows.append([entry["name"], str(kills), weapon])
	return rows

# === HUD ===

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	_level_label = Label.new()
	_level_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_level_label.offset_top = 44.0
	_level_label.offset_left = -260.0
	_level_label.offset_right = 260.0
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 20)
	_level_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	layer.add_child(_level_label)

func _update_level_label() -> void:
	var weapon_name: String = WeaponDatabase.get_weapon(LADDER[_player_level]).get("name", LADDER[_player_level])
	_level_label.text = "GUN GAME   Level %d / %d   ·   %s" % [_player_level + 1, LADDER.size(), weapon_name]
