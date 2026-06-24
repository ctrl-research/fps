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
const TEAM_LABELS: Array[String] = ["Team A", "Team B"]

var _player: PlayerController = null

var _health_bar: ProgressBar = null
var _health_fill: StyleBoxFlat = null
var _health_label: Label = null
var _grenades_box: HBoxContainer = null
var _equipment_label: Label = null
var _scores_label: Label = null
var _buy_hint: Label = null
var _minimap: Control = null
var _status_label: Label = null
var _showing_revive: bool = false
var _crosshair: Control = null
var _ability_bar: Control = null

# Hold-Tab scoreboard overlay.
var _scoreboard_root: Control = null
var _scoreboard_vbox: VBoxContainer = null
var _scoreboard_shown: bool = false

## Connect the HUD to its player and build the UI.
func bind(player: PlayerController) -> void:
	_player = player
	_build_ui()
	_build_scoreboard()

	player.health_changed.connect(_on_health_changed)
	player.downed.connect(_on_downed)
	player.died.connect(_on_died)
	player.revived.connect(_on_revived)
	PlayerLoadout.loadout_changed.connect(_refresh_loadout)
	GameState.team_score_updated.connect(_on_score_updated)
	GameState.round_state_changed.connect(_on_round_state_changed)
	Settings.settings_changed.connect(func() -> void:
		if _crosshair:
			_crosshair.queue_redraw())

	_on_health_changed(player.health, player.max_health)
	_refresh_loadout()
	_refresh_scores()
	_update_buy_hint(GameState.current_round_state)
	_status_label.text = ""

func _process(_delta: float) -> void:
	if _minimap:
		_minimap.queue_redraw()
	if _ability_bar:
		_ability_bar.queue_redraw()
	if _player and is_instance_valid(_player):
		if _player.is_downed:
			_status_label.text = "DOWNED — %ds" % int(ceil(maxf(_player.bleedout_timer, 0.0)))
		elif not _player.is_dead and _player.revive_target != null:
			if _player.revive_progress > 0.0:
				_status_label.text = "Reviving… %d%%" % int(_player.revive_progress * 100.0)
			else:
				_status_label.text = "Hold [F] to revive a teammate"
			_showing_revive = true
		elif _showing_revive and not _player.is_dead:
			_status_label.text = ""
			_showing_revive = false
	_update_scoreboard()

## Show the scoreboard while Tab is held (rebuilt on press for live values).
func _update_scoreboard() -> void:
	var held := Input.is_key_pressed(KEY_TAB)
	if held == _scoreboard_shown:
		return
	_scoreboard_shown = held
	if held:
		_refresh_scoreboard()
	if _scoreboard_root:
		_scoreboard_root.visible = held

# === Build ===

func _build_ui() -> void:
	# Bottom-left stack: grenades, equipment, health.
	var bottom_left := VBoxContainer.new()
	add_child(bottom_left)
	# Fixed region in the bottom-left corner.
	_set_rect(bottom_left, 0.0, 1.0, 0.0, 1.0, 16.0, -120.0, 320.0, -16.0)
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
	# Opaque styleboxes (the default ProgressBar theme is semi-transparent).
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.09, 0.10, 0.13)
	hp_bg.set_corner_radius_all(3)
	_health_bar.add_theme_stylebox_override("background", hp_bg)
	_health_fill = StyleBoxFlat.new()
	_health_fill.bg_color = Color(0.3, 0.85, 0.4)
	_health_fill.set_corner_radius_all(3)
	_health_bar.add_theme_stylebox_override("fill", _health_fill)
	health_row.add_child(_health_bar)
	_health_label = Label.new()
	_health_label.custom_minimum_size = Vector2(48, 0)
	health_row.add_child(_health_label)

	# Top-center: team scores + buy hint.
	var top_center := VBoxContainer.new()
	top_center.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(top_center)
	_set_rect(top_center, 0.5, 0.0, 0.5, 0.0, -240.0, 12.0, 240.0, 84.0)
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
	_set_rect(_minimap, 1.0, 0.0, 1.0, 0.0, -(MINIMAP_SIZE + 16.0), 16.0, -16.0, MINIMAP_SIZE + 16.0)

	# Aiming crosshair, centred; shape from Settings.crosshair_style.
	_crosshair = Control.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	add_child(_crosshair)
	_set_rect(_crosshair, 0.5, 0.5, 0.5, 0.5, -32.0, -32.0, 32.0, 32.0)

	# Ability cooldown bar, bottom-centre.
	_ability_bar = Control.new()
	_ability_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_bar.draw.connect(_draw_ability_bar)
	add_child(_ability_bar)
	_set_rect(_ability_bar, 0.5, 1.0, 0.5, 1.0, -220.0, -88.0, 220.0, -20.0)

	# Center: downed / eliminated status.
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 40)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	add_child(_status_label)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_set_rect(_status_label, 0.5, 0.5, 0.5, 0.5, -260.0, -40.0, 260.0, 40.0)

## Anchor a control to an explicit rect (anchors + pixel offsets), matching the
## proven pattern in the weapon HUD. Avoids the zero-size + grow approach, which
## left widgets collapsed off-screen.
func _set_rect(c: Control, al: float, at: float, ar: float, ab: float,
		ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob

# === Ability cooldown bar ===

## Draw a box per cooldown ability with its icon, keybind, and cooldown sweep.
func _draw_ability_bar() -> void:
	if not is_instance_valid(_player):
		return
	var ctrl: AbilityController = _player.ability_controller()
	if ctrl == null:
		return
	var slots := ctrl.cooldown_slots()
	if slots.is_empty():
		return
	var font := ThemeDB.fallback_font
	var box := 52.0
	var gap := 10.0
	var total := slots.size() * box + (slots.size() - 1) * gap
	var size := _ability_bar.size
	var y := (size.y - box) * 0.5
	var x0 := (size.x - total) * 0.5
	for i in slots.size():
		var s: Dictionary = slots[i]
		var x := x0 + i * (box + gap)
		var rect := Rect2(x, y, box, box)
		var rem := float(s["remaining"])
		_ability_bar.draw_rect(rect, Color(0.1, 0.12, 0.16, 0.7))
		_ability_bar.draw_string(font, Vector2(x, y + box * 0.6), str(s["icon"]),
			HORIZONTAL_ALIGNMENT_CENTER, box, 18, Color.WHITE)
		_ability_bar.draw_string(font, Vector2(x + 4, y + 14), str(s["key"]),
			HORIZONTAL_ALIGNMENT_LEFT, box - 8, 11, Color(0.75, 0.8, 0.95))
		var cd := float(s["cooldown"])
		if rem > 0.0 and cd > 0.0:
			# Dark sweep that shrinks from the top as the cooldown elapses.
			var frac := clampf(rem / cd, 0.0, 1.0)
			_ability_bar.draw_rect(Rect2(x, y, box, box * frac), Color(0, 0, 0, 0.6))
			_ability_bar.draw_string(font, Vector2(x, y + box * 0.62), "%d" % int(ceil(rem)),
				HORIZONTAL_ALIGNMENT_CENTER, box, 20, Color(1.0, 0.9, 0.6))
		var border := Color(0.5, 0.6, 0.7, 0.6) if rem > 0.0 else Color(0.6, 0.85, 1.0, 0.8)
		_ability_bar.draw_rect(rect, border, false, 2.0)

# === Crosshair ===

## Draw the aiming reticle (shape from Settings.crosshair_style), centred.
func _draw_crosshair() -> void:
	var c := _crosshair.size * 0.5
	var col := Color(0.95, 0.95, 0.95, 0.9)
	var t := 2.0
	var gap := 4.0
	var length := 8.0
	match Settings.crosshair_style:
		1:  # Dot
			_crosshair.draw_circle(c, 2.5, col)
		2:  # Circle
			_crosshair.draw_arc(c, 7.0, 0.0, TAU, 32, col, t)
		3:  # X
			for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var dir := d.normalized()
				_crosshair.draw_line(c + dir * gap, c + dir * (gap + length), col, t)
		4:  # Star (cross + diagonal spokes)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT,
					Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var dir := d.normalized()
				_crosshair.draw_line(c + dir * gap, c + dir * (gap + length * 0.8), col, t)
		_:  # Cross (default)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				_crosshair.draw_line(c + d * gap, c + d * (gap + length), col, t)

# === Minimap ===

func _draw_minimap() -> void:
	# Static square border (does not rotate, even when the map does).
	var rect := Rect2(Vector2.ZERO, _minimap.size)
	_minimap.draw_rect(rect, Color(0.05, 0.07, 0.1, 0.6))
	_minimap.draw_rect(rect, Color(0.5, 0.6, 0.7, 0.5), false, 2.0)
	if not is_instance_valid(_player):
		return

	var center := _minimap.size * 0.5
	var origin := _player.global_position
	# Rotate so the player's forward points up; 0 keeps it north-up.
	var rot: float = _player.rotation.y if Settings.minimap_rotates else 0.0

	for node in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(node):
			continue
		var body := node as Node3D
		var rel: Vector3 = body.global_position - origin
		var planar := Vector2(rel.x, rel.z).rotated(rot)
		var dot := center + planar * MINIMAP_PIXELS_PER_METRE
		if dot.x < 4.0 or dot.x > _minimap.size.x - 4.0 or dot.y < 4.0 or dot.y > _minimap.size.y - 4.0:
			continue
		var color := LOCAL_COLOR if node == _player else _team_color(node)
		# Downed (revivable) = +, dead (gone) = X.
		var downed := false
		var dead := false
		if node is PlayerController:
			downed = (node as PlayerController).is_downed
			dead = (node as PlayerController).is_dead
		elif node is Bot:
			downed = (node as Bot).is_downed()
			dead = not (node as Bot).is_alive()
		if downed:
			_draw_minimap_plus(dot, color)
			continue
		if dead:
			_draw_minimap_x(dot, color)
			continue
		var facing3 := -body.global_transform.basis.z
		var facing := Vector2(facing3.x, facing3.z)
		if facing.length() < 0.01:
			facing = Vector2(0.0, -1.0)
		facing = facing.rotated(rot).normalized()
		_draw_pointer(dot, facing, color)

## A + marker at `pos` (downed but revivable).
func _draw_minimap_plus(pos: Vector2, color: Color) -> void:
	var s := 5.0
	_minimap.draw_line(pos + Vector2(-s, 0.0), pos + Vector2(s, 0.0), color, 2.0)
	_minimap.draw_line(pos + Vector2(0.0, -s), pos + Vector2(0.0, s), color, 2.0)

## An X marker at `pos` (dead / gone).
func _draw_minimap_x(pos: Vector2, color: Color) -> void:
	var s := 5.0
	_minimap.draw_line(pos + Vector2(-s, -s), pos + Vector2(s, s), color, 2.0)
	_minimap.draw_line(pos + Vector2(-s, s), pos + Vector2(s, -s), color, 2.0)

## A small arrowhead at `pos` pointing along `facing` (a directional dot).
func _draw_pointer(pos: Vector2, facing: Vector2, color: Color) -> void:
	var side := Vector2(-facing.y, facing.x)
	var tip := pos + facing * 7.0
	var base_a := pos - facing * 5.0 + side * 4.5
	var base_b := pos - facing * 5.0 - side * 4.5
	_minimap.draw_colored_polygon(PackedVector2Array([tip, base_a, base_b]), color)

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
	# Tint the (opaque) fill from green (full) to red (low).
	if _health_fill:
		_health_fill.bg_color = Color(1.0 - ratio * 0.7, 0.3 + ratio * 0.7, 0.3, 1.0)

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

# === Scoreboard (hold Tab) ===

## Build the (hidden) scoreboard overlay container. Populated on show.
func _build_scoreboard() -> void:
	_scoreboard_root = CenterContainer.new()
	_scoreboard_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scoreboard_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard_root.visible = false
	add_child(_scoreboard_root)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	_scoreboard_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	_scoreboard_vbox = VBoxContainer.new()
	_scoreboard_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(_scoreboard_vbox)

## Repopulate the scoreboard from live GameState: team score + per-player rows
## (player, team, kills, credits), sorted by kills.
func _refresh_scoreboard() -> void:
	if _scoreboard_vbox == null:
		return
	for child in _scoreboard_vbox.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "SCOREBOARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	_scoreboard_vbox.add_child(title)

	var score := Label.new()
	score.text = "%s   %d  —  %d   %s" % [TEAM_LABELS[0],
		GameState.team_scores.get(0, 0), GameState.team_scores.get(1, 0), TEAM_LABELS[1]]
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scoreboard_vbox.add_child(score)

	_scoreboard_vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	_scoreboard_vbox.add_child(grid)

	for header in ["Player", "Team", "Kills", "Credits"]:
		var cell := Label.new()
		cell.text = header
		cell.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		grid.add_child(cell)

	var peers: Array = GameState.player_credits.keys()
	peers.sort_custom(func(a, b): return GameState.player_kills.get(a, 0) > GameState.player_kills.get(b, 0))
	for peer_id in peers:
		var team: int = GameState._get_player_team(peer_id)
		_add_cell(grid, "Player %d" % peer_id)
		_add_cell(grid, TEAM_LABELS[team % 2])
		_add_cell(grid, str(GameState.player_kills.get(peer_id, 0)))
		_add_cell(grid, "$%d" % GameState.get_player_credits(peer_id))

	if Modifiers.has_active():
		_add_evolutions_section()

## Evolution mode: list the local player's accumulated buffs (+) and debuffs (-).
func _add_evolutions_section() -> void:
	_scoreboard_vbox.add_child(HSeparator.new())
	var header := Label.new()
	header.text = "YOUR EVOLUTIONS"
	header.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	_scoreboard_vbox.add_child(header)

	var buffs := Modifiers.local_buffs()
	var debuffs := Modifiers.local_debuffs()
	if buffs.is_empty() and debuffs.is_empty():
		var none := Label.new()
		none.text = "(none yet)"
		_scoreboard_vbox.add_child(none)
		return
	for id in buffs:
		_add_modifier_row(id, "+ ", Color(0.4, 1.0, 0.55))
	for id in debuffs:
		_add_modifier_row(id, "- ", Color(1.0, 0.5, 0.45))

func _add_modifier_row(id: String, prefix: String, color: Color) -> void:
	var m := Modifiers.get_mod(id)
	var label := Label.new()
	label.text = "%s%s  (%s)" % [prefix, m.get("name", id), m.get("desc", "")]
	label.add_theme_color_override("font_color", color)
	_scoreboard_vbox.add_child(label)

func _add_cell(grid: GridContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)

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
