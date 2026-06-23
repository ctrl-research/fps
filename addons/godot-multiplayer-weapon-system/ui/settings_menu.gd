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
	panel.custom_minimum_size = Vector2(620, 600)
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

	# Tabbed categories; each tab scrolls so the menu can grow.
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(tabs)

	# --- Graphics ---
	var gfx := _make_tab(tabs, "Graphics")
	gfx.add_child(_make_toggle_row("Dither shading", Settings.stylize_enabled, Settings.set_stylize_enabled))
	gfx.add_child(_make_slider_row("Shadow brightness", 0.0, 1.0, 0.02, Settings.dither_shade, Settings.set_dither_shade))
	gfx.add_child(_make_slider_row("Lit brightness", 0.3, 1.2, 0.02, Settings.dither_lit, Settings.set_dither_lit))
	gfx.add_child(_make_slider_row("Shadow band start", 0.0, 1.0, 0.02, Settings.dither_low, Settings.set_dither_low))
	gfx.add_child(_make_slider_row("Shadow band end", 0.0, 1.0, 0.02, Settings.dither_high, Settings.set_dither_high))
	gfx.add_child(_make_slider_row("Grain size", 1.0, 6.0, 0.5, Settings.dither_grain, Settings.set_dither_grain))
	gfx.add_child(_make_slider_row("Light contrast", 0.5, Settings.MAX_DITHER_CONTRAST, 0.1, Settings.dither_contrast, Settings.set_dither_contrast))
	gfx.add_child(_make_slider_row("Light radius", 5.0, Settings.MAX_POV_RANGE, 5.0, Settings.pov_range, Settings.set_pov_range))
	gfx.add_child(_make_slider_row("Light brightness", 0.0, Settings.MAX_POV_ENERGY, 0.25, Settings.pov_energy, Settings.set_pov_energy))
	gfx.add_child(_make_slider_row("Ambient light", 0.0, Settings.MAX_AMBIENT, 0.05, Settings.ambient_light, Settings.set_ambient_light))
	gfx.add_child(_make_slider_row("Viewmodel light", 0.0, Settings.MAX_VM_ENERGY, 0.1, Settings.vm_energy, Settings.set_vm_energy))
	gfx.add_child(_make_slider_row("Viewmodel light angle", -90.0, 0.0, 5.0, Settings.vm_pitch, Settings.set_vm_pitch))

	# --- Audio ---
	var audio := _make_tab(tabs, "Audio")
	audio.add_child(_make_slider_row("Master volume", 0.0, 1.0, 0.05, Settings.master_volume, Settings.set_master_volume, 100.0, "%d%%"))

	# --- Gameplay ---
	var gp := _make_tab(tabs, "Gameplay")
	gp.add_child(_make_toggle_row("Rotate minimap with view", Settings.minimap_rotates, Settings.set_minimap_rotates))
	gp.add_child(_make_toggle_row("Auto-run (sprint by default)", Settings.auto_run, Settings.set_auto_run))
	gp.add_child(_make_option_row("Crosshair", Settings.CROSSHAIR_STYLES, Settings.crosshair_style, Settings.set_crosshair_style))

	# --- Controls ---
	var ctrl := _make_tab(tabs, "Controls")
	ctrl.add_child(_make_slider_row("Mouse sensitivity", Settings.MIN_MOUSE_SENSITIVITY,
		Settings.MAX_MOUSE_SENSITIVITY, 0.0001, Settings.mouse_sensitivity, Settings.set_mouse_sensitivity, 1000.0, "%.1f"))
	var hint := Label.new()
	hint.text = "Click a binding, then press a key or mouse button (Esc to cancel)."
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(0.7, 0.75, 0.8)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctrl.add_child(hint)
	for action in Settings.BINDABLE_ACTIONS:
		ctrl.add_child(_make_bind_row(action))

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

## A scrollable tab in the TabContainer; returns the VBox to add rows to.
func _make_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)
	return v

## A labelled slider row with a live value readout (disp_mult/disp_fmt format it).
func _make_slider_row(text: String, min_v: float, max_v: float, step: float, value: float,
		setter: Callable, disp_mult: float = 1.0, disp_fmt: String = "%.2f") -> HBoxContainer:
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
	value_label.text = disp_fmt % (value * disp_mult)
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		value_label.text = disp_fmt % (v * disp_mult))
	return row

## A labelled toggle (CheckButton) row wired to `setter`.
func _make_toggle_row(text: String, value: bool, setter: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(200, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var check := CheckButton.new()
	check.button_pressed = value
	check.toggled.connect(setter)
	row.add_child(check)
	return row

## A labelled dropdown row wired to `setter` (item index).
func _make_option_row(text: String, items: Array, selected: int, setter: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(200, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var opt := OptionButton.new()
	for item_name: String in items:
		opt.add_item(item_name)
	opt.selected = selected
	opt.item_selected.connect(setter)
	row.add_child(opt)
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
