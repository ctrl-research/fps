extends Node
# No `class_name`: registered as the `PostProcess` autoload. A matching global
# class would shadow the singleton and break clean compiles.
"""
Global stipple post-process.

Owns a screen-filling ColorRect running the stipple shader (black halftone dots
in shadows only) over the rendered 3D frame. The overlay sits on a low
CanvasLayer — below the HUD/menus (layer >= 1) — so only the 3D world is
stylised, and is shown only while a 3D camera is active (i.e. in gameplay, not
the 2D main menu). Toggled by Settings.stylize_enabled.
"""

const SHADER_PATH: String = "res://addons/godot-multiplayer-weapon-system/shaders/stylize_post.gdshader"
## Below the HUD (CanvasLayer default 1) and all menus, above the 3D world.
const OVERLAY_LAYER: int = 0

var _rect: ColorRect = null
var _material: ShaderMaterial = null

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = OVERLAY_LAYER
	add_child(layer)

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Fail-safe: a ColorRect's base colour is what shows if the shader ever fails
	# to compile. Default white would paint the whole screen white; transparent
	# means a broken shader just shows the raw (un-stylised) frame instead.
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	# Never intercept clicks.
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH)
	_rect.material = _material
	layer.add_child(_rect)

	_refresh()
	Settings.settings_changed.connect(_refresh)

func _process(_delta: float) -> void:
	# Only stylise when there's a 3D world on screen (gameplay), never the menus.
	var cam := get_viewport().get_camera_3d()
	if _rect != null:
		_rect.visible = Settings.stylize_enabled and cam != null

## Push the live-tunable dither params from Settings into the shader.
func _refresh() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("shade_strength", Settings.dither_shade)
	_material.set_shader_parameter("shadow_low", Settings.dither_low)
	_material.set_shader_parameter("shadow_high", Settings.dither_high)
	_material.set_shader_parameter("grain_size", Settings.dither_grain)
	_material.set_shader_parameter("light_contrast", Settings.dither_contrast)

## DayNightSky drives sky exclusion: sentinel pixels render as a smooth gradient
## (day/sunset in 0..1) instead of being dithered.
func set_sky(day: float, sunset: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("sky_enabled", true)
	_material.set_shader_parameter("sky_day", day)
	_material.set_shader_parameter("sky_sunset", sunset)

func clear_sky() -> void:
	if _material:
		_material.set_shader_parameter("sky_enabled", false)
