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
	# Feed the camera ray basis so the shader can reconstruct the sky per pixel.
	if _material != null and cam != null:
		_material.set_shader_parameter("cam_basis", cam.global_transform.basis)
		_material.set_shader_parameter("cam_tan", tan(deg_to_rad(cam.fov) * 0.5))
		var sz := get_viewport().get_visible_rect().size
		_material.set_shader_parameter("cam_aspect", sz.x / maxf(sz.y, 1.0))

## A DayNightSky mode calls this each round to drive the reconstructed sky.
## sun_dir is the light's travel direction; day/sunset in 0..1.
func set_sky(sun_dir: Vector3, day: float, sunset: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("sky_enabled", true)
	_material.set_shader_parameter("sky_sun_dir", sun_dir)
	_material.set_shader_parameter("sky_day", day)
	_material.set_shader_parameter("sky_sunset", sunset)

## Disable sky reconstruction (modes without a procedural sky).
func clear_sky() -> void:
	if _material:
		_material.set_shader_parameter("sky_enabled", false)

func _refresh() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("color_mode", Settings.color_mode)
	_material.set_shader_parameter("outline_enabled", Settings.outline_enabled)
