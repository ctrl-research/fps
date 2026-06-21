extends Node
# No `class_name`: registered as the `PostProcess` autoload. A matching global
# class would shadow the singleton and break clean compiles.
"""
Global comic-book stylise post-process.

Owns a screen-filling ColorRect running the stylise shader (gradient colour
remap + Sobel edge outline) over the rendered 3D frame. The overlay sits on a
low CanvasLayer — below the HUD/menus (layer >= 1) — so only the 3D world is
stylised, and is shown only while a 3D camera is active (i.e. in gameplay, not
the 2D main menu). Driven by Settings (stylize_enabled / color_mode /
outline_enabled).
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
	if _rect != null:
		_rect.visible = Settings.stylize_enabled and get_viewport().get_camera_3d() != null

func _refresh() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("color_mode", Settings.color_mode)
	_material.set_shader_parameter("outline_enabled", Settings.outline_enabled)
