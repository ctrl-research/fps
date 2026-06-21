extends CanvasLayer
class_name SpecSelect
"""
Per-round spec UI, in two modes:

- Normal (allow_respec off): pick ONE node to advance this round — emits
  node_picked(path) and closes. Specs are permanent.
- Respec (allow_respec on): rebuild from scratch — the spec is reset and you
  allocate all your earned points freely (with Reset / Change class), then
  Confirm — emits allocation_done(). Beginner/bot-session friendly.
"""

signal node_picked(path: int)        # normal mode
signal allocation_done()             # respec mode
signal change_class_requested()      # respec mode

const PATH_COLORS: Array[Color] = [Color(0.5, 0.8, 1.0), Color(1.0, 0.7, 0.4)]

var _spec: SpecTree = null
var _earned: int = 1
var _respec: bool = false
var _allow_class_change: bool = false
var _header_text: String = ""
var _body: VBoxContainer = null

func show_choices(spec: SpecTree, header_text: String, earned: int = 1,
		respec: bool = false, allow_class_change: bool = false) -> void:
	layer = 45
	_spec = spec
	_header_text = header_text
	_earned = earned
	_respec = respec
	_allow_class_change = allow_class_change
	if _respec:
		_spec.reset()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(660, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	margin.add_child(_body)
	_render()

func set_header(text: String) -> void:
	_header_text = text
	_render()

# === Rendering (rebuilt as the build changes) ===

func _render() -> void:
	if _body == null:
		return
	for child in _body.get_children():
		child.queue_free()

	var header := Label.new()
	header.text = _header_text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 28)
	_body.add_child(header)

	var paths: Array = _spec.class_def().get("paths", [])
	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	var build_parts: Array = []
	for p in paths.size():
		build_parts.append("%s %d/%d" % [paths[p].get("name", "Path"), _spec.depths[p], SpecTree.PATH_DEPTH])
	if _respec:
		status.text = "Points left: %d / %d     ·     %s" % [_points_left(), _earned, "   ".join(build_parts)]
	else:
		status.text = "Build: " + "   ·   ".join(build_parts)
	_body.add_child(status)
	_body.add_child(HSeparator.new())

	var can_spend := (not _respec) or _points_left() > 0
	for choice in _spec.selectable():
		var path: int = choice["path"]
		var node: Dictionary = choice["node"]
		var capstone: bool = int(_spec.depths[path]) == SpecTree.PATH_DEPTH - 1
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 56)
		button.disabled = not can_spend
		var tag := "  ★ CAPSTONE" if capstone else ""
		button.text = "%s → %s%s\n%s" % [paths[path].get("name", "Path"), node.get("name", "?"), tag, node.get("desc", "")]
		button.add_theme_color_override("font_color", PATH_COLORS[path % PATH_COLORS.size()])
		button.pressed.connect(_on_advance.bind(path))
		_body.add_child(button)

	if _respec:
		_body.add_child(HSeparator.new())
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		_body.add_child(row)
		_add_action(row, "Reset", func() -> void: _spec.reset(); _render())
		if _allow_class_change:
			_add_action(row, "Change class", func() -> void: change_class_requested.emit(); queue_free())
		_add_action(row, "Confirm", func() -> void: allocation_done.emit(); queue_free())

func _add_action(row: HBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 0)
	b.pressed.connect(cb)
	row.add_child(b)

func _on_advance(path: int) -> void:
	if _respec:
		if _points_left() > 0:
			_spec.advance(path)
			_render()
	else:
		node_picked.emit(path)
		queue_free()

func _points_left() -> int:
	return _earned - _spec.points_spent()
