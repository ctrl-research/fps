extends CanvasLayer
class_name SpecSelect
"""
Per-round spec pick: shows the player's current build and the node each path
would unlock next, and emits `node_picked(path)` for the chosen path. The mode
owns the timer and applies the pick.
"""

signal node_picked(path: int)

const PATH_COLORS: Array[Color] = [Color(0.5, 0.8, 1.0), Color(1.0, 0.7, 0.4)]

var _header: Label = null

func show_choices(spec: SpecTree, header_text: String) -> void:
	layer = 45

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	_header = Label.new()
	_header.text = header_text
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_theme_font_size_override("font_size", 28)
	vbox.add_child(_header)

	# Current build summary (depth into each path).
	var paths: Array = spec.class_def().get("paths", [])
	var summary := Label.new()
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	var parts: Array = []
	for p in paths.size():
		parts.append("%s %d/%d" % [paths[p].get("name", "Path"), spec.depths[p], SpecTree.PATH_DEPTH])
	summary.text = "Build: " + "   ·   ".join(parts)
	vbox.add_child(summary)

	vbox.add_child(HSeparator.new())

	for choice in spec.selectable():
		var path: int = choice["path"]
		var node: Dictionary = choice["node"]
		var capstone: bool = int(spec.depths[path]) == SpecTree.PATH_DEPTH - 1
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 60)
		var path_name: String = paths[path].get("name", "Path")
		var tag := "  ★ CAPSTONE" if capstone else ""
		button.text = "%s → %s%s\n%s" % [path_name, node.get("name", "?"), tag, node.get("desc", "")]
		button.add_theme_color_override("font_color", PATH_COLORS[path % PATH_COLORS.size()])
		button.pressed.connect(func() -> void:
			node_picked.emit(path)
			queue_free())
		vbox.add_child(button)

	if spec.selectable().is_empty():
		var maxed := Label.new()
		maxed.text = "Fully evolved — no points left to spend."
		maxed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(maxed)

func set_header(text: String) -> void:
	if _header:
		_header.text = text
