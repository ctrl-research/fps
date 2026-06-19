extends Node
# No `class_name`: registered as the `PostProcess` autoload. A matching global
# class would shadow the singleton and break clean compiles.
"""
Global screen-space post-processing.

Owns a screen-filling ColorRect on a top CanvasLayer that survives scene changes
(it's a child of this autoload), running the ordered-dithering shader over the
whole composited frame. Toggled via Settings.dither_enabled.
"""

const SHADER_PATH: String = "res://addons/godot-multiplayer-weapon-system/shaders/dither_post.gdshader"
## Above all gameplay/menu layers so the filter is truly global.
const OVERLAY_LAYER: int = 128

var _rect: ColorRect = null

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = OVERLAY_LAYER
	add_child(layer)

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Never intercept clicks — the filter must not block buttons underneath.
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	_rect.material = material
	layer.add_child(_rect)

	_refresh()
	Settings.settings_changed.connect(_refresh)

func _refresh() -> void:
	if _rect != null:
		_rect.visible = Settings.dither_enabled
