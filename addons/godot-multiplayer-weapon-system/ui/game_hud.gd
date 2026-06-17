extends CanvasLayer
class_name GameHud
"""
In-game HUD for the local player.

Shows health, grenades, equipment, team scores, a top-down minimap with
team-coloured player dots, a buy-phase hint, and a downed/eliminated indicator.
The crosshair and ammo counter live in the weapon HUD (built by WeaponController).
Built entirely in code and bound to the local PlayerController via bind().
"""

const MINIMAP_SIZE: float = 168.0
const MINIMAP_PIXELS_PER_METRE: float = 4.0
const MINIMAP_DOT_RADIUS: float = 4.0

const GRENADE_COLORS: Dictionary = {
	"frag": Color(0.85, 0.35, 0.2),
	"flash": Color(0.95, 0.95, 0.7),
	"smoke": Color(0.6, 0.6, 0.65),
	"emp": Color(0.4, 0.6, 1.0),
	"push": Color(0.5, 0.9, 0.5),
}
const TEAM_COLORS: Array[Color] = [Color(0.4, 0.6, 1.0), Color(1.0, 0.45, 0.4)]
const LOCAL_COLOR: Color = Color(0.3, 1.0, 0.45)

var _player: PlayerController = null

var _health_bar: ProgressBar = null
var _health_label: Label = null
var _grenades_box: HBoxContainer = null
var _equipment_label: Label = null
var _scores_label: Label = null
var _buy_hint: Label = null
var _minimap: Control = null
var _status_label: Label = null

## Connect the HUD to its player and build the UI.
func bind(player: PlayerController) -> void:
	_player = player
	_build_ui()

	player.health_changed.connect(_on_health_changed)
	player.downed.connect(_on_downed)
	player.died.connect(_on_died)
	player.revived.connect(_on_revived)
	PlayerLoadout.loadout_changed.connect(_refresh_loadout)
	GameState.team_score_updated.connect(_on_score_updated)
	GameState.round_state_changed.connect(_on_round_state_changed)

	_on_health_changed(player.health, player.max_health)
	_refresh_loadout()
	_refresh_scores()
	_update_buy_hint(GameState.current_round_state)
	_status_label.text = ""

func _process(_delta: float) -> void:
	if _minimap:
		_minimap.queue_redraw()
	if _player and _player.is_downed:
		_status_label.text = "DOWNED — %ds" % int(ceil(maxf(_player.bleedout_timer, 0.0)))

# === Build ===

func _build_ui() -> void:
	# Bottom-left stack: grenades, equipment, health.
	var bottom_left := VBoxContainer.new()
	add_child(bottom_left)
	# Anchor to the bottom-left and grow up/right so it stays on screen.
	_place(bottom_left, 0.0, 1.0, 16.0, -16.0, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	bottom_left.add_theme_constant_override("separation", 6)

	_grenades_box = HBoxContainer.new()
	_grenades_box.add_theme_constant_override("separation", 10)
	bottom_left.add_child(_grenades_box)

	_equipment_label = Label.new()
	_equipment_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	bottom_left.add_child(_equipment_label)

	var health_row := HBoxContainer.new()
	health_row.add_theme_constant_override("separation", 8)
	bottom_left.add_child(health_row)
	var hp_tag := Label.new()
	hp_tag.text = "HP"
	health_row.add_child(hp_tag)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(220, 22)
	_health_bar.min_value = 0.0
	_health_bar.max_value = 100.0
	_health_bar.show_percentage = false
	health_row.add_child(_health_bar)
	_health_label = Label.new()
	_health_label.custom_minimum_size = Vector2(48, 0)
	health_row.add_child(_health_label)

	# Top-center: team scores + buy hint.
	var top_center := VBoxContainer.new()
	top_center.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(top_center)
	_place(top_center, 0.5, 0.0, 0.0, 12.0, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	_scores_label = Label.new()
	_scores_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scores_label.add_theme_font_size_override("font_size", 22)
	top_center.add_child(_scores_label)
	_buy_hint = Label.new()
	_buy_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buy_hint.add_theme_color_override("font_color", Color(0.9, 1.0, 0.6))
	top_center.add_child(_buy_hint)

	# Top-right: minimap.
	_minimap = Control.new()
	_minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.draw.connect(_draw_minimap)
	add_child(_minimap)
	_place(_minimap, 1.0, 0.0, -16.0, 16.0, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)

	# Center: downed / eliminated status.
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 40)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	add_child(_status_label)
	_place(_status_label, 0.5, 0.5, 0.0, 0.0, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)

## Anchor a control to a single point (ax, ay in 0..1) with a pixel offset, and
## set which way it grows to fit its content. Avoids the preset/MINSIZE timing
## pitfall where offsets get baked before children exist.
func _place(c: Control, ax: float, ay: float, ox: float, oy: float, grow_h: int, grow_v: int) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_right = ox
	c.offset_top = oy
	c.offset_bottom = oy
	c.grow_horizontal = grow_h
	c.grow_vertical = grow_v

# === Minimap ===

func _draw_minimap() -> void:
	var rect := Rect2(Vector2.ZERO, _minimap.size)
	_minimap.draw_rect(rect, Color(0.05, 0.07, 0.1, 0.6))
	_minimap.draw_rect(rect, Color(0.5, 0.6, 0.7, 0.5), false, 2.0)
	if not is_instance_valid(_player):
		return
	var center := _minimap.size * 0.5
	var origin := _player.global_position
	for node in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(node):
			continue
		var body := node as Node3D
		var rel: Vector3 = body.global_position - origin
		var dot := center + Vector2(rel.x, rel.z) * MINIMAP_PIXELS_PER_METRE
		if dot.x < 0.0 or dot.x > _minimap.size.x or dot.y < 0.0 or dot.y > _minimap.size.y:
			continue
		var color := LOCAL_COLOR if node == _player else _team_color(node)
		_minimap.draw_circle(dot, MINIMAP_DOT_RADIUS, color)

func _team_color(node: Node) -> Color:
	var peer_id: int = node.get("authority_peer_id") if node.get("authority_peer_id") != null else 0
	var team: int = GameState._get_player_team(peer_id)
	return TEAM_COLORS[team % TEAM_COLORS.size()]

# === Refresh handlers ===

func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "%d" % int(round(current))
	var ratio: float = current / maxf(maximum, 1.0)
	_health_bar.modulate = Color(1.0, 1.0, 1.0)
	# Tint the fill from green (full) to red (low).
	_health_bar.self_modulate = Color(1.0 - ratio * 0.7, 0.3 + ratio * 0.7, 0.3)

func _on_downed() -> void:
	_status_label.text = "DOWNED"

func _on_died() -> void:
	_status_label.text = "ELIMINATED"

func _on_revived() -> void:
	_status_label.text = ""

func _on_score_updated(_team_id: int, _new_score: int) -> void:
	_refresh_scores()

func _on_round_state_changed(state: int) -> void:
	_update_buy_hint(state)

func _refresh_scores() -> void:
	var team_a: int = GameState.team_scores.get(0, 0)
	var team_b: int = GameState.team_scores.get(1, 0)
	_scores_label.text = "TEAM A   %d : %d   TEAM B" % [team_a, team_b]

func _update_buy_hint(state: int) -> void:
	if state == GameState.RoundState.BUY_PHASE:
		_buy_hint.text = "Buy phase — press %s for the buy menu" % _buy_key()
	else:
		_buy_hint.text = ""

func _buy_key() -> String:
	if InputMap.has_action("buy"):
		for event in InputMap.action_get_events("buy"):
			if event is InputEventKey:
				var keycode: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
				return OS.get_keycode_string(keycode)
	return "B"

func _refresh_loadout() -> void:
	for child in _grenades_box.get_children():
		child.queue_free()
	for grenade_id in PlayerLoadout.grenades:
		var count: int = PlayerLoadout.grenades[grenade_id]
		if count <= 0:
			continue
		_grenades_box.add_child(_make_grenade_chip(grenade_id, count))

	var parts: Array[String] = []
	for slot in PlayerLoadout.equipment:
		var item_id: String = PlayerLoadout.equipment[slot]
		parts.append(WeaponDatabase.get_equipment(item_id).get("name", item_id))
	_equipment_label.text = "Equipment: " + ("—" if parts.is_empty() else ", ".join(parts))

func _make_grenade_chip(grenade_id: String, count: int) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 4)
	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(16, 16)
	icon.color = GRENADE_COLORS.get(grenade_id, Color(0.7, 0.7, 0.7))
	chip.add_child(icon)
	var label := Label.new()
	var display_name: String = WeaponDatabase.get_grenade(grenade_id).get("name", grenade_id)
	label.text = "%s x%d" % [display_name, count]
	chip.add_child(label)
	return chip
