extends CanvasLayer
class_name ClassSelect
"""
Pre-match class picker: one button per class in the ClassDatabase. Emits
`class_picked(class_id)`.
"""

signal class_picked(class_id: String)

func show_classes() -> void:
	layer = 46

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "CHOOSE YOUR CLASS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	for id in ClassDatabase.class_ids():
		var def := ClassDatabase.get_def(id)
		var paths: Array = def.get("paths", [])
		var path_names: Array = []
		for p in paths:
			path_names.append(p.get("name", "Path"))
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 72)
		button.text = "%s\n%s\nPaths: %s" % [
			def.get("name", id), def.get("description", ""), " / ".join(path_names)]
		button.pressed.connect(func() -> void:
			class_picked.emit(id)
			queue_free())
		vbox.add_child(button)
