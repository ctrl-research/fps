extends CanvasLayer
class_name SettingsMenu
"""
Settings / keybinds overlay.

Reusable overlay (from the main menu or in-game pause). Lists rebindable actions
with their current key, captures a new key/mouse button on click, adjusts mouse
sensitivity, and can reset to defaults. Persists via the Settings autoload.
Emits `closed` when dismissed so the opener can restore state.
"""

signal closed()

var _rebind_buttons: Dictionary = {}  # action -> Button
var _listening_action: String = ""
var _sensitivity_value_label: Label = null

func _ready() -> void:
	layer = 20
	_build_ui()
	_refresh()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 620)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	# Mouse sensitivity.
	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 12)
	vbox.add_child(sens_row)
	var sens_label := Label.new()
	sens_label.text = "Mouse Sensitivity"
	sens_label.custom_minimum_size = Vector2(200, 0)
	sens_row.add_child(sens_label)
	var slider := HSlider.new()
	slider.min_value = Settings.MIN_MOUSE_SENSITIVITY
	slider.max_value = Settings.MAX_MOUSE_SENSITIVITY
	slider.step = 0.0001
	slider.value = Settings.mouse_sensitivity
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_sensitivity_changed)
	sens_row.add_child(slider)
	_sensitivity_value_label = Label.new()
	_sensitivity_value_label.custom_minimum_size = Vector2(56, 0)
	_sensitivity_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sens_row.add_child(_sensitivity_value_label)

	var hint := Label.new()
	hint.text = "Click a binding, then press a key or mouse button (Esc to cancel)."
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(0.7, 0.75, 0.8)
	vbox.add_child(hint)

	# Keybind list.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 380)
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for action in Settings.BINDABLE_ACTIONS:
		list.add_child(_make_bind_row(action))

	# Footer.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	footer.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(footer)
	var reset_button := Button.new()
	reset_button.text = "Reset to Defaults"
	reset_button.pressed.connect(_on_reset_pressed)
	footer.add_child(reset_button)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(_on_close_pressed)
	footer.add_child(close_button)

func _make_bind_row(action: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = Settings.ACTION_LABELS.get(action, action)
	label.custom_minimum_size = Vector2(220, 0)
	row.add_child(label)
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_rebind_pressed.bind(action))
	row.add_child(button)
	_rebind_buttons[action] = button
	return row

func _input(event: InputEvent) -> void:
	if _listening_action == "":
		return
	# Capture the first key or mouse button as the new binding.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_cancel_listen()
		else:
			Settings.rebind_action(_listening_action, event)
			_stop_listen()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		Settings.rebind_action(_listening_action, event)
		_stop_listen()
		get_viewport().set_input_as_handled()

func _on_rebind_pressed(action: String) -> void:
	if _listening_action != "":
		_refresh()  # cancel any in-progress listen
	_listening_action = action
	_rebind_buttons[action].text = "Press a key…"

func _stop_listen() -> void:
	_listening_action = ""
	_refresh()

func _cancel_listen() -> void:
	_listening_action = ""
	_refresh()

func _on_sensitivity_changed(value: float) -> void:
	Settings.set_mouse_sensitivity(value)
	_update_sensitivity_label()

func _on_reset_pressed() -> void:
	Settings.reset_to_defaults()
	_refresh()

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()

func _refresh() -> void:
	for action in _rebind_buttons:
		_rebind_buttons[action].text = Settings.binding_label(action)
	_update_sensitivity_label()

func _update_sensitivity_label() -> void:
	if _sensitivity_value_label:
		_sensitivity_value_label.text = "%.1f" % (Settings.mouse_sensitivity * 1000.0)
