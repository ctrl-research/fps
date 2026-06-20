extends CanvasLayer
class_name EvolutionDraft
"""
Evolution voting overlay: presents the rolled modifiers and lets the team vote.

Each team member votes for one option (and can change it). The overlay only
reports votes via `vote_changed`; the mode owns the tally, the timer, and
resolution. Votes are shown as ally-blue dots next to each option.
"""

signal vote_changed(modifier_id: String)

const BUFF_COLOR: Color = Color(0.4, 1.0, 0.55)
const DEBUFF_COLOR: Color = Color(1.0, 0.5, 0.45)

var _header: Label = null
var _buttons: Dictionary = {}     # id -> Button
var _dot_labels: Dictionary = {}  # id -> Label (ally-blue vote dots)
var _local_choice: String = ""

## Build the vote panel from rolled modifier ids.
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
	panel.custom_minimum_size = Vector2(620, 0)
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

	var sub := Label.new()
	sub.text = "Vote — buff your team or debuff the enemy (click to change your vote)"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	for id in option_ids:
		var mod := Modifiers.get_mod(id)
		if mod.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vbox.add_child(row)

		var dots := Label.new()
		dots.custom_minimum_size = Vector2(90, 0)
		dots.add_theme_color_override("font_color", CategoryColors.ALLY)
		row.add_child(dots)
		_dot_labels[id] = dots

		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 56)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var is_buff: bool = mod.get("kind") == "buff"
		button.text = "%s  —  %s" % [mod.get("name", id), mod.get("desc", "")]
		button.add_theme_color_override("font_color", BUFF_COLOR if is_buff else DEBUFF_COLOR)
		button.pressed.connect(_on_button.bind(id))
		row.add_child(button)
		_buttons[id] = button

## Update the header (used for the live vote countdown).
func set_header(text: String) -> void:
	if _header:
		_header.text = text

## Render vote dots from {option_id: count}.
func set_votes(counts: Dictionary) -> void:
	for id in _dot_labels:
		_dot_labels[id].text = "●".repeat(int(counts.get(id, 0)))

func _on_button(id: String) -> void:
	_local_choice = id
	# Highlight the locally-chosen option; dim the rest.
	for other in _buttons:
		_buttons[other].modulate = Color.WHITE if other == id else Color(0.7, 0.7, 0.7)
	vote_changed.emit(id)
