extends CanvasLayer
class_name EvolutionDraft
"""
Evolution draft overlay: presents a few rolled modifiers (buffs for your team /
debuffs for the enemy) and emits `picked` with the chosen id. The opener
releases the mouse before showing this and re-captures it after.
"""

signal picked(modifier_id: String)

const BUFF_COLOR: Color = Color(0.4, 1.0, 0.55)
const DEBUFF_COLOR: Color = Color(1.0, 0.5, 0.45)

## Build the draft from a list of modifier ids and a header (e.g. "Round 2").
func show_options(option_ids: Array, header_text: String) -> void:
	layer = 45

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var header := Label.new()
	header.text = header_text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 28)
	vbox.add_child(header)

	var sub := Label.new()
	sub.text = "Evolve — pick a buff for your team or a debuff for the enemy"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	for id in option_ids:
		var mod := Modifiers.get_mod(id)
		if mod.is_empty():
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 56)
		var is_buff: bool = mod.get("kind") == "buff"
		button.text = "%s  —  %s" % [mod.get("name", id), mod.get("desc", "")]
		button.add_theme_color_override("font_color", BUFF_COLOR if is_buff else DEBUFF_COLOR)
		button.pressed.connect(_on_pick.bind(id))
		vbox.add_child(button)

func _on_pick(id: String) -> void:
	picked.emit(id)
	queue_free()
