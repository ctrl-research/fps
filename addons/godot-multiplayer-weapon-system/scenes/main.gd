extends Node2D
"""
Branded splash + first-load screen (themed for MEDIEVAL-UTION).

The project's main scene, so it's the first thing shown once the engine is up.
Displays the game emblem over a dark backdrop with a loading bar while the lobby
streams in on a background thread, then transitions to it. Keeps a minimum
on-screen time so the brand moment never just flashes by.
"""

const LOBBY_PATH: String = "res://addons/godot-multiplayer-weapon-system/scenes/lobby.tscn"
const LOGO_PATH: String = "res://assets/branding/logo.svg"
const BG_COLOR: Color = Color(0.055, 0.06, 0.08)
const GOLD: Color = Color(0.9, 0.7, 0.23)
const MIN_DISPLAY_SECS: float = 1.3

var _bar: ProgressBar = null
var _status: Label = null
var _elapsed: float = 0.0
var _done: bool = false

func _ready() -> void:
	_build_ui()
	ResourceLoader.load_threaded_request(LOBBY_PATH)

func _process(delta: float) -> void:
	_elapsed += delta
	if _done:
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(LOBBY_PATH, progress)
	var ratio: float = progress[0] if not progress.is_empty() else 0.0
	if _bar:
		# Only ever move forward, so the bar reads as steady progress.
		_bar.value = maxf(_bar.value, ratio * 100.0)
	match status:
		ResourceLoader.THREAD_LOAD_FAILED:
			_status.text = "Failed to load"
			_done = true
		ResourceLoader.THREAD_LOAD_LOADED:
			if _elapsed >= MIN_DISPLAY_SECS:
				_bar.value = 100.0
				_done = true
				_go_to_lobby()

func _go_to_lobby() -> void:
	var packed: PackedScene = ResourceLoader.load_threaded_get(LOBBY_PATH)
	if packed:
		get_tree().change_scene_to_packed(packed)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	center.add_child(vbox)

	var logo := TextureRect.new()
	var tex := load(LOGO_PATH) as Texture2D
	if tex:
		logo.texture = tex
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(380, 380)
	vbox.add_child(logo)

	_status = Label.new()
	_status.text = "Loading…"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
	vbox.add_child(_status)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(380, 14)
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.show_percentage = false
	var bg_box := StyleBoxFlat.new()
	bg_box.bg_color = Color(0.13, 0.14, 0.18)
	bg_box.set_corner_radius_all(7)
	bg_box.set_border_width_all(1)
	bg_box.border_color = Color(0.0, 0.0, 0.0, 0.6)
	_bar.add_theme_stylebox_override("background", bg_box)
	var fill_box := StyleBoxFlat.new()
	fill_box.bg_color = GOLD
	fill_box.set_corner_radius_all(7)
	_bar.add_theme_stylebox_override("fill", fill_box)
	vbox.add_child(_bar)
