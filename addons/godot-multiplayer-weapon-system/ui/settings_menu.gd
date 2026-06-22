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
var _volume_value_label: Label = null

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
	panel.custom_minimum_size = Vector2(580, 680)
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

	# Rotate minimap toggle.
	var minimap_row := HBoxContainer.new()
	minimap_row.add_theme_constant_override("separation", 12)
	vbox.add_child(minimap_row)
	var minimap_label := Label.new()
	minimap_label.text = "Rotate minimap with view"
	minimap_label.custom_minimum_size = Vector2(200, 0)
	minimap_row.add_child(minimap_label)
	var minimap_check := CheckButton.new()
	minimap_check.button_pressed = Settings.minimap_rotates
	minimap_check.toggled.connect(Settings.set_minimap_rotates)
	minimap_row.add_child(minimap_check)

	# Auto-run toggle (sprint by default; sprint key walks).
	var autorun_row := HBoxContainer.new()
	autorun_row.add_theme_constant_override("separation", 12)
	vbox.add_child(autorun_row)
	var autorun_label := Label.new()
	autorun_label.text = "Auto-run (sprint by default)"
	autorun_label.custom_minimum_size = Vector2(200, 0)
	autorun_row.add_child(autorun_label)
	var autorun_check := CheckButton.new()
	autorun_check.button_pressed = Settings.auto_run
	autorun_check.toggled.connect(Settings.set_auto_run)
	autorun_row.add_child(autorun_check)

	# Dither shading: master toggle + live-tunable params.
	var stylize_row := HBoxContainer.new()
	stylize_row.add_theme_constant_override("separation", 12)
	vbox.add_child(stylize_row)
	var stylize_label := Label.new()
	stylize_label.text = "Dither shading"
	stylize_label.custom_minimum_size = Vector2(200, 0)
	stylize_row.add_child(stylize_label)
	var stylize_check := CheckButton.new()
	stylize_check.button_pressed = Settings.stylize_enabled
	stylize_check.toggled.connect(Settings.set_stylize_enabled)
	stylize_row.add_child(stylize_check)

	vbox.add_child(_make_slider_row("Shade darkness", 0.0, 1.0, 0.02,
		Settings.dither_shade, Settings.set_dither_shade))
	vbox.add_child(_make_slider_row("Shadow band start", 0.0, 1.0, 0.02,
		Settings.dither_low, Settings.set_dither_low))
	vbox.add_child(_make_slider_row("Shadow band end", 0.0, 1.0, 0.02,
		Settings.dither_high, Settings.set_dither_high))
	vbox.add_child(_make_slider_row("Grain size", 1.0, 6.0, 0.5,
		Settings.dither_grain, Settings.set_dither_grain))
	vbox.add_child(_make_slider_row("Light contrast", 0.5, Settings.MAX_DITHER_CONTRAST, 0.1,
		Settings.dither_contrast, Settings.set_dither_contrast))

	# Master volume.
	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	vbox.add_child(volume_row)
	var volume_label := Label.new()
	volume_label.text = "Master Volume"
	volume_label.custom_minimum_size = Vector2(200, 0)
	volume_row.add_child(volume_label)
	var volume_slider := HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = Settings.master_volume
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_row.add_child(volume_slider)
	_volume_value_label = Label.new()
	_volume_value_label.custom_minimum_size = Vector2(56, 0)
	_volume_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_row.add_child(_volume_value_label)
	volume_slider.value_changed.connect(_on_volume_changed)

	# Crosshair shape.
	var crosshair_row := HBoxContainer.new()
	crosshair_row.add_theme_constant_override("separation", 12)
	vbox.add_child(crosshair_row)
	var crosshair_label := Label.new()
	crosshair_label.text = "Crosshair"
	crosshair_label.custom_minimum_size = Vector2(200, 0)
	crosshair_row.add_child(crosshair_label)
	var crosshair_option := OptionButton.new()
	for style_name in Settings.CROSSHAIR_STYLES:
		crosshair_option.add_item(style_name)
	crosshair_option.selected = Settings.crosshair_style
	crosshair_option.item_selected.connect(Settings.set_crosshair_style)
	crosshair_row.add_child(crosshair_option)

	var hint := Label.new()
	hint.text = "Click a binding, then press a key or mouse button (Esc to cancel)."
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(0.7, 0.75, 0.8)
	vbox.add_child(hint)

	# Keybind list.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 300)
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

## A labelled slider row with a live value readout, wired to `setter`.
func _make_slider_row(text: String, min_v: float, max_v: float, step: float, value: float, setter: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(200, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(56, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = "%.2f" % value
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		value_label.text = "%.2f" % v)
	return row

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
		# Esc closes the menu. Works on web too: the cursor is already unlocked
		# while a menu is open, so the browser delivers the keypress here.
		if _is_cancel(event):
			get_viewport().set_input_as_handled()
			_on_close_pressed()
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

func _on_volume_changed(value: float) -> void:
	Settings.set_master_volume(value)
	_update_volume_label()

func _on_reset_pressed() -> void:
	Settings.reset_to_defaults()
	_refresh()

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()

## True for an Esc / ui_cancel press (used to dismiss the menu).
func _is_cancel(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		return true
	return event is InputEventKey and event.pressed and not event.echo \
		and event.keycode == KEY_ESCAPE

func _refresh() -> void:
	for action in _rebind_buttons:
		_rebind_buttons[action].text = Settings.binding_label(action)
	_update_sensitivity_label()
	_update_volume_label()

func _update_sensitivity_label() -> void:
	if _sensitivity_value_label:
		_sensitivity_value_label.text = "%.1f" % (Settings.mouse_sensitivity * 1000.0)

func _update_volume_label() -> void:
	if _volume_value_label:
		_volume_value_label.text = "%d%%" % int(round(Settings.master_volume * 100.0))
