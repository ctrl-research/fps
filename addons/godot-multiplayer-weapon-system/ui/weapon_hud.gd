extends CanvasLayer
class_name WeaponHud
"""
Minimal in-combat weapon HUD: a dynamic crosshair plus weapon/ammo readout.

Built entirely in code and attached to the local player's WeaponController. The
crosshair gap grows with the active weapon's current spread so the player gets
direct feedback on movement and spray inaccuracy.
"""

const CROSSHAIR_BASE_GAP: float = 2.0
const CROSSHAIR_LENGTH: float = 6.0
const CROSSHAIR_THICKNESS: float = 2.0
const CROSSHAIR_MAX_GAP: float = 18.0
const CROSSHAIR_COLOR: Color = Color(0.2, 1.0, 0.4, 0.9)

## Radians of spread mapped to crosshair-gap pixels. Kept small so the reticle
## stays tight near the centre and only opens up modestly while moving/spraying.
const SPREAD_TO_PIXELS: float = 500.0

var _controller: WeaponController = null
var _crosshair: Control = null
var _weapon_label: Label = null
var _ammo_label: Label = null
var _reload_label: Label = null

## Connect the HUD to its controller and build the UI.
func bind(controller: WeaponController) -> void:
	_controller = controller
	controller.weapon_changed.connect(_on_weapon_changed)
	controller.ammo_changed.connect(_on_ammo_changed)
	controller.reload_started.connect(_on_reload_started)
	controller.reload_finished.connect(_on_reload_finished)

func _ready() -> void:
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	add_child(_crosshair)

	_weapon_label = _make_label(Vector2(-220.0, -70.0))
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label = _make_label(Vector2(-220.0, -48.0))
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.add_theme_font_size_override("font_size", 28)
	_reload_label = _make_label(Vector2(-220.0, -16.0))
	_reload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reload_label.modulate = Color(1.0, 0.8, 0.3)

func _process(_delta: float) -> void:
	# Redraw so the crosshair tracks live spread changes.
	if _crosshair:
		_crosshair.queue_redraw()

func _make_label(offset: Vector2) -> Label:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.offset_left = offset.x
	label.offset_top = offset.y
	label.offset_right = -20.0
	add_child(label)
	return label

func _draw_crosshair() -> void:
	var center := _crosshair.size * 0.5
	var gap := CROSSHAIR_BASE_GAP
	if _controller:
		gap += _controller.current_spread() * SPREAD_TO_PIXELS
	gap = minf(gap, CROSSHAIR_MAX_GAP)

	match Settings.crosshair_style:
		1:  # Dot
			_crosshair.draw_circle(center, 2.5, CROSSHAIR_COLOR)
		2:  # Circle
			_crosshair.draw_arc(center, gap + 4.0, 0.0, TAU, 32, CROSSHAIR_COLOR, CROSSHAIR_THICKNESS, true)
			_crosshair.draw_circle(center, 1.5, CROSSHAIR_COLOR)
		3:  # X
			_draw_x(center, gap)
		4:  # Star (cross + X)
			_draw_cross(center, gap)
			_draw_x(center, gap)
		_:  # Cross (default)
			_draw_cross(center, gap)

func _draw_cross(center: Vector2, gap: float) -> void:
	var half := CROSSHAIR_THICKNESS * 0.5
	_crosshair.draw_rect(Rect2(center.x - gap - CROSSHAIR_LENGTH, center.y - half, CROSSHAIR_LENGTH, CROSSHAIR_THICKNESS), CROSSHAIR_COLOR)
	_crosshair.draw_rect(Rect2(center.x + gap, center.y - half, CROSSHAIR_LENGTH, CROSSHAIR_THICKNESS), CROSSHAIR_COLOR)
	_crosshair.draw_rect(Rect2(center.x - half, center.y - gap - CROSSHAIR_LENGTH, CROSSHAIR_THICKNESS, CROSSHAIR_LENGTH), CROSSHAIR_COLOR)
	_crosshair.draw_rect(Rect2(center.x - half, center.y + gap, CROSSHAIR_THICKNESS, CROSSHAIR_LENGTH), CROSSHAIR_COLOR)

func _draw_x(center: Vector2, gap: float) -> void:
	for d in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var dir: Vector2 = d.normalized()
		_crosshair.draw_line(center + dir * gap, center + dir * (gap + CROSSHAIR_LENGTH), CROSSHAIR_COLOR, CROSSHAIR_THICKNESS)

func _on_weapon_changed(weapon: Weapon) -> void:
	_weapon_label.text = weapon.display_name()
	_reload_label.text = ""

func _on_ammo_changed(mag: int, reserve: int) -> void:
	_ammo_label.text = "%d / %d" % [mag, reserve]

func _on_reload_started(_duration: float) -> void:
	_reload_label.text = "Reloading…"

func _on_reload_finished() -> void:
	_reload_label.text = ""
