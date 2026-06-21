extends CanvasLayer
class_name SpecSelect
"""
Skill-tree spec UI: a horizontal tree with two paths. Each node is a square with
an icon; hover shows its bonuses (tooltip). Specced nodes are coloured, the next
available node is bright/clickable, and locked nodes are greyed — a node can only
be taken once the previous node in its path is taken.

Two modes (unchanged API):
- Normal (allow_respec off): click the next node to advance — emits
  node_picked(path) and closes. Specs are permanent.
- Respec (allow_respec on): the tree resets; spend all earned points freely
  (Reset / Change class / Confirm) — emits allocation_done().
"""

signal node_picked(path: int)
signal allocation_done()
signal change_class_requested()

const PATH_COLORS: Array[Color] = [Color(0.45, 0.75, 1.0), Color(1.0, 0.65, 0.4)]
const ROOT_COLOR: Color = Color(1.0, 0.9, 0.5)
const LOCKED_COLOR: Color = Color(0.35, 0.35, 0.4)
const NODE_SIZE: Vector2 = Vector2(66, 66)
const LABEL_WIDTH: float = 120.0

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
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 14)
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

	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	if _respec:
		status.text = "Points to spend: %d / %d" % [_points_left(), _earned]
	else:
		status.text = "Spend 1 point — hover a node for details"
	_body.add_child(status)
	_body.add_child(HSeparator.new())

	# Free root passive (always owned).
	var passive: Dictionary = _spec.class_def().get("passive", {})
	var root_row := HBoxContainer.new()
	root_row.add_theme_constant_override("separation", 8)
	_body.add_child(root_row)
	root_row.add_child(_row_label("Passive"))
	var root := _make_node(passive.get("icon", "P"), passive.get("name", ""), passive.get("desc", ""),
		ROOT_COLOR, true, Callable())
	root_row.add_child(root)

	# Two horizontal paths of square nodes.
	var paths: Array = _spec.class_def().get("paths", [])
	for p in paths.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_body.add_child(row)
		row.add_child(_row_label(paths[p].get("name", "Path")))
		var nodes: Array = paths[p].get("nodes", [])
		for i in nodes.size():
			row.add_child(_make_path_node(p, i, nodes[i]))

	if _respec:
		_body.add_child(HSeparator.new())
		var controls := HBoxContainer.new()
		controls.alignment = BoxContainer.ALIGNMENT_CENTER
		controls.add_theme_constant_override("separation", 12)
		_body.add_child(controls)
		_add_button(controls, "Reset", func() -> void: _spec.reset(); _render())
		if _allow_class_change:
			_add_button(controls, "Change class", func() -> void: change_class_requested.emit(); queue_free())
		_add_button(controls, "Confirm", func() -> void: allocation_done.emit(); queue_free())

## A square node in a path, with its specced/available/locked state + action.
func _make_path_node(path: int, i: int, node: Dictionary) -> Button:
	var depth: int = int(_spec.depths[path])
	var taken := depth > i
	var is_next := depth == i
	var available := is_next and (_points_left() > 0 if _respec else true)
	var color: Color
	var action := Callable()
	if taken:
		color = PATH_COLORS[path % PATH_COLORS.size()]
	elif available:
		color = Color.WHITE
		action = _on_take.bind(path)
	else:
		color = LOCKED_COLOR  # locked: previous node not taken yet
	return _make_node(node.get("icon", _abbrev(node.get("name", "?"))),
		node.get("name", ""), node.get("desc", ""), color, taken, action)

func _make_node(icon: String, title: String, desc: String, color: Color, taken: bool, action: Callable) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = NODE_SIZE
	btn.clip_text = true
	btn.text = icon
	btn.add_theme_font_size_override("font_size", 18)
	btn.tooltip_text = "%s\n%s" % [title, desc] if desc != "" else title
	btn.modulate = color
	if taken:
		btn.add_theme_color_override("font_color", Color.WHITE)
	if action.is_valid():
		btn.pressed.connect(action)
	else:
		btn.focus_mode = Control.FOCUS_NONE
	return btn

func _on_take(path: int) -> void:
	if _respec:
		if _points_left() > 0:
			_spec.advance(path)
			_render()
	else:
		node_picked.emit(path)
		queue_free()

func _row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _add_button(row: HBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 0)
	b.pressed.connect(cb)
	row.add_child(b)

func _points_left() -> int:
	return _earned - _spec.points_spent()

func _abbrev(name: String) -> String:
	return name.substr(0, 3).to_upper()
