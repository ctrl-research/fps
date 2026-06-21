extends Node
# No `class_name`: registered as the `PostProcess` autoload. A matching global
# class would shadow the singleton and break clean compiles.
"""
Global comic-book stylise post-process.

A screen-filling ColorRect runs the stylise shader (gradient colour remap + Sobel
edge outline) over the rendered 3D frame, on a low CanvasLayer (below the HUD)
and only while a 3D camera is active.

To keep the procedural sky un-stylised, we also render a cheap world-coverage
mask: a second camera (mirroring the active one) draws the world into a
transparent SubViewport, so geometry is opaque and the sky is transparent. The
shader reads that mask and passes sky pixels straight through, stylising only the
world. (Same shared-world SubViewport trick the mirror uses.)
"""

const SHADER_PATH: String = "res://addons/godot-multiplayer-weapon-system/shaders/stylize_post.gdshader"
## Below the HUD (CanvasLayer default 1) and all menus, above the 3D world.
const OVERLAY_LAYER: int = 0

var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _mask_vp: SubViewport = null
var _mask_cam: Camera3D = null

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = OVERLAY_LAYER
	add_child(layer)

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never intercept clicks
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH)
	_rect.material = _material
	layer.add_child(_rect)

	_build_mask()
	_refresh()
	Settings.settings_changed.connect(_refresh)
	get_viewport().size_changed.connect(_resize_mask)

## World-coverage mask: a second camera renders the shared world into a
## transparent SubViewport (geometry opaque, sky transparent).
func _build_mask() -> void:
	_mask_vp = SubViewport.new()
	_mask_vp.transparent_bg = true
	_mask_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mask_vp.world_3d = get_tree().root.get_world_3d()
	add_child(_mask_vp)

	_mask_cam = Camera3D.new()
	# No sky for this camera, so empty pixels stay transparent (the mask).
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	_mask_cam.environment = env
	_mask_cam.current = true
	_mask_vp.add_child(_mask_cam)

	_resize_mask()
	_material.set_shader_parameter("mask_tex", _mask_vp.get_texture())

func _resize_mask() -> void:
	if _mask_vp:
		_mask_vp.size = Vector2i(get_viewport().get_visible_rect().size)

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var active := Settings.stylize_enabled and cam != null
	if _rect:
		_rect.visible = active
	if _mask_vp:
		_mask_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	# Mirror the active camera so the mask aligns with the screen 1:1.
	if active and _mask_cam:
		_mask_cam.global_transform = cam.global_transform
		_mask_cam.fov = cam.fov
		_mask_cam.near = cam.near
		_mask_cam.far = cam.far
		_mask_cam.cull_mask = cam.cull_mask

func _refresh() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("color_mode", Settings.color_mode)
	_material.set_shader_parameter("outline_enabled", Settings.outline_enabled)
