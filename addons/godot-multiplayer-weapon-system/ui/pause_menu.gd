extends CanvasLayer
class_name PauseMenu
"""
In-game menu overlay (opened with Esc).

Offers Resume, Settings, and Leave. Does not pause the scene tree (so it is safe
in multiplayer); it just releases the cursor and dims the view. The opener
connects `resumed` (re-capture the mouse) and `leave_requested` (return to menu).
"""

signal resumed()
signal leave_requested()

const SETTINGS_MENU := "res://addons/godot-multiplayer-weapon-system/ui/settings_menu.gd"

func _ready() -> void:
	layer = 15
	_build_ui()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(title)

	var resume_button := Button.new()
	resume_button.text = "Resume"
	resume_button.pressed.connect(_on_resume_pressed)
	vbox.add_child(resume_button)

	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.pressed.connect(_on_settings_pressed)
	vbox.add_child(settings_button)

	var leave_button := Button.new()
	leave_button.text = "Leave to Menu"
	leave_button.pressed.connect(_on_leave_pressed)
	vbox.add_child(leave_button)

func _on_resume_pressed() -> void:
	resumed.emit()
	queue_free()

func _on_settings_pressed() -> void:
	var settings = load(SETTINGS_MENU).new()
	add_child(settings)

func _on_leave_pressed() -> void:
	leave_requested.emit()
