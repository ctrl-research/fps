extends Node3D
class_name CharacterModel
"""
A reusable animated character visual built from a KayKit glTF model.

Instances a character `.glb` (mesh + Rig_Medium skeleton, no embedded clips) and
drives it with the shared Rig_Medium animation set. Players and bots both use
this — the Mage and Skeleton Warrior share the rig, so one merged animation
library serves every character (no retargeting).

Usage:
    var model := CharacterModel.new()
    add_child(model)
    model.setup("res://assets/characters/kaykit_adventurers/Mage.glb")
    # then each frame:
    model.set_locomotion(planar_speed, on_floor)
    # on events:
    model.play_death(); model.play_idle()

Visuals are tunable up top — KayKit models are ~2.1 m tall and may face +Z, so
SCALE / YAW_OFFSET_DEG are the first things to adjust in-engine.
"""

# Shared Rig_Medium clips. Loading just these two files keeps the merge cheap
# while covering idle / locomotion / jump / death.
const ANIM_FILES: Array[String] = [
	"res://assets/animations/rig_medium/Rig_Medium_General.glb",
	"res://assets/animations/rig_medium/Rig_Medium_MovementBasic.glb",
]

# Clip names (from the KayKit Rig_Medium set).
const IDLE: String = "Idle_A"
const WALK: String = "Walking_A"
const RUN: String = "Running_A"
const JUMP: String = "Jump_Idle"
const DEATH: String = "Death_A"
# Clips that should loop (others play once and hold their last frame).
const LOOPING: Array[String] = ["Idle_A", "Idle_B", "Walking_A", "Walking_B",
	"Walking_C", "Running_A", "Running_B", "Jump_Idle"]

# --- Tunables (verify in-engine) ---
## Uniform scale applied to the model (KayKit medium ≈ 2.1 m tall at 1.0).
const SCALE: float = 0.85
## Yaw applied so the model faces the body's forward (KayKit often faces +Z).
const YAW_OFFSET_DEG: float = 180.0
## Planar speed (m/s) above which we play walk, and above which we play run.
const WALK_THRESHOLD: float = 0.3
const RUN_THRESHOLD: float = 7.0
## Crossfade between locomotion states.
const BLEND: float = 0.15

# One merged library reused across every CharacterModel instance.
static var _shared_lib: AnimationLibrary = null

var _anim: AnimationPlayer = null
var _skeleton: Skeleton3D = null
var _current: String = ""
var _dead: bool = false

## Build the visual from a character glb path. Call once after add_child.
func setup(character_glb_path: String) -> void:
	var packed: PackedScene = load(character_glb_path)
	if packed == null:
		push_warning("CharacterModel: could not load %s" % character_glb_path)
		return
	var model: Node3D = packed.instantiate()
	model.name = "Model"
	model.scale = Vector3.ONE * SCALE
	model.rotation.y = deg_to_rad(YAW_OFFSET_DEG)
	add_child(model)
	_skeleton = _find_skeleton(model)

	_anim = AnimationPlayer.new()
	add_child(_anim)
	# Track paths in the clips are relative to the model root (which holds the
	# same-named skeleton as the animation files — identical rig).
	_anim.root_node = _anim.get_path_to(model)
	_anim.add_animation_library("", _get_library())

	play_idle()

## Pick idle / walk / run / jump from movement state (ignored once dead).
func set_locomotion(planar_speed: float, on_floor: bool) -> void:
	if _dead or _anim == null:
		return
	var want: String
	if not on_floor:
		want = JUMP
	elif planar_speed >= RUN_THRESHOLD:
		want = RUN
	elif planar_speed >= WALK_THRESHOLD:
		want = WALK
	else:
		want = IDLE
	_play(want)

func play_idle() -> void:
	_dead = false
	_play(IDLE)

func play_death() -> void:
	if _anim == null:
		return
	_dead = true
	_play(DEATH)

## Move every mesh of the model onto a visual layer mask (e.g. the local
## player's own-body layer, culled from their first-person camera).
func set_visual_layer(mask: int) -> void:
	for mesh in _meshes():
		mesh.layers = mask

func meshes() -> Array:
	return _meshes()

# === internals ===

func _play(anim_name: String) -> void:
	if anim_name == _current or _anim == null:
		return
	if not _anim.has_animation(anim_name):
		return
	_current = anim_name
	_anim.play(anim_name, BLEND)

func _meshes() -> Array:
	var result: Array = []
	var stack: Array = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		if node is MeshInstance3D:
			result.append(node)
	return result

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

## Merge the clips from ANIM_FILES into one AnimationLibrary, once, shared by all
## instances. Loads each animation glb, harvests its AnimationPlayer's clips,
## and sets loop flags. The transient scenes are freed; the clips are duplicated
## so they outlive them.
static func _get_library() -> AnimationLibrary:
	if _shared_lib != null:
		return _shared_lib
	var lib := AnimationLibrary.new()
	for path in ANIM_FILES:
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var scene: Node = packed.instantiate()
		var src: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
		if src != null:
			for src_lib_name in src.get_animation_library_list():
				var src_lib := src.get_animation_library(src_lib_name)
				for clip in src_lib.get_animation_list():
					if lib.has_animation(clip):
						continue
					var anim: Animation = src_lib.get_animation(clip).duplicate()
					if LOOPING.has(clip):
						anim.loop_mode = Animation.LOOP_LINEAR
					lib.add_animation(clip, anim)
		scene.free()
	_shared_lib = lib
	return _shared_lib
