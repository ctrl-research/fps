extends Node3D
class_name Arena
"""
Shared combat map for the game modes (medium-large, symmetrical).

Built procedurally so it's CI-validatable and reusable. The whole layout has
180° point symmetry about the origin: every feature placed for team 0's side
(+Z) gets an identical 180°-rotated counterpart on team 1's side (-Z), so neither
team has a positional advantage. Team-coloured banners (blue / red) mark each
end for orientation — appearance only, geometry stays symmetric.

Layout: a large flat ground with a raised central platform (contested high
ground), a raised flank platform on each side, an open building near each spawn,
and KayKit dungeon props (barrels / boxes / crates / columns) for cover.

API:
    var arena := Arena.new(); add_child(arena)
    arena.team_spawns(0) -> Array[Vector3]   # +Z end
    arena.team_spawns(1) -> Array[Vector3]   # -Z end
    arena.all_spawns()   -> Array[Vector3]   # both ends (FFA)
"""

const PROPS := "res://assets/environments/kaykit_dungeon/"

# Ground footprint (metres) and the spawn-end distance from centre.
const GROUND := Vector2(64.0, 92.0)
const SPAWN_Z := 40.0

const STRUCTURE_COLOR := Color(0.32, 0.30, 0.34)

func _ready() -> void:
	_build_ground()
	_build_center()
	_build_flanks()
	_build_buildings()
	_build_cover()
	_build_decoration()

# === Spawns ===

## Spawn points for a team (team 0 = +Z end, team 1 = -Z end), mirrored so each
## team's layout is identical.
func team_spawns(team: int) -> Array:
	var z := SPAWN_Z if team == 0 else -SPAWN_Z
	var spawns: Array = []
	for x in [-9.0, -3.0, 3.0, 9.0]:
		spawns.append(Vector3(x, 1.5, z))
	return spawns

func all_spawns() -> Array:
	return team_spawns(0) + team_spawns(1)

# === Geometry ===

func _build_ground() -> void:
	_box(Vector3(0.0, -0.5, 0.0), Vector3(GROUND.x, 1.0, GROUND.y), Color(0.22, 0.23, 0.27))
	# Perimeter walls so players can't leave the play space.
	var t := 1.0
	var h := 4.0
	_box(Vector3(0.0, h * 0.5, GROUND.y * 0.5), Vector3(GROUND.x, h, t), STRUCTURE_COLOR)
	_box(Vector3(0.0, h * 0.5, -GROUND.y * 0.5), Vector3(GROUND.x, h, t), STRUCTURE_COLOR)
	_box(Vector3(GROUND.x * 0.5, h * 0.5, 0.0), Vector3(t, h, GROUND.y), STRUCTURE_COLOR)
	_box(Vector3(-GROUND.x * 0.5, h * 0.5, 0.0), Vector3(t, h, GROUND.y), STRUCTURE_COLOR)

## Central raised platform (contested high ground) with a ramp up each end.
func _build_center() -> void:
	_box(Vector3(0.0, 1.0, 0.0), Vector3(16.0, 2.0, 16.0), STRUCTURE_COLOR)
	# Ramps on the +Z and -Z faces (mirrored) so both teams reach it equally.
	_sym_ramp(Vector3(0.0, 1.0, 11.0), Vector3(8.0, 0.6, 8.0), -14.0)
	# Low cover lip on the side faces.
	_sym_box(Vector3(7.0, 2.4, 4.0), Vector3(2.0, 0.8, 4.0), STRUCTURE_COLOR)

## A raised flank platform on each side (left/right), point-mirrored.
func _build_flanks() -> void:
	_sym_box(Vector3(22.0, 0.75, 0.0), Vector3(10.0, 1.5, 12.0), STRUCTURE_COLOR)
	_sym_box(Vector3(22.0, 1.6, 7.0), Vector3(10.0, 0.6, 2.0), STRUCTURE_COLOR)  # step up

## An open, roofless building near each spawn for cover and sightline breaks.
func _build_buildings() -> void:
	var c := STRUCTURE_COLOR
	var wall_h := 3.0
	# Building centred near (14, 22): three walls opening toward mid-field.
	_sym_box(Vector3(14.0, wall_h * 0.5, 26.0), Vector3(10.0, wall_h, 0.6), c)  # back wall
	_sym_box(Vector3(9.0, wall_h * 0.5, 23.0), Vector3(0.6, wall_h, 6.0), c)    # side wall
	_sym_box(Vector3(19.0, wall_h * 0.5, 23.0), Vector3(0.6, wall_h, 6.0), c)   # side wall

# === Props ===

func _build_cover() -> void:
	# Mid-field and lane cover (one half; each is point-mirrored for the other).
	_sym_prop("barrel_large", Vector3(-6.0, 0.0, 18.0), 0.0, Vector3(1.0, 1.3, 1.0))
	_sym_prop("box_large", Vector3(6.0, 0.0, 16.0), 25.0, Vector3(1.2, 1.2, 1.2))
	_sym_prop("crates_stacked", Vector3(-14.0, 0.0, 12.0), 0.0, Vector3(1.6, 1.8, 1.6))
	_sym_prop("barrel_large", Vector3(11.0, 0.0, 30.0), 0.0, Vector3(1.0, 1.3, 1.0))
	_sym_prop("box_large", Vector3(-2.0, 0.0, 8.0), 0.0, Vector3(1.2, 1.2, 1.2))
	_sym_prop("column", Vector3(18.0, 0.0, 6.0), 0.0, Vector3(1.0, 3.0, 1.0))
	_sym_prop("crates_stacked", Vector3(24.0, 1.5, 2.0), 0.0, Vector3(1.6, 1.8, 1.6))  # on flank

func _build_decoration() -> void:
	# Team-coloured banners flank each spawn (blue = team 0 / +Z, red = team 1).
	_prop("banner_blue", Vector3(-10.0, 0.0, SPAWN_Z + 4.0), 0.0, Vector3.ZERO)
	_prop("banner_blue", Vector3(10.0, 0.0, SPAWN_Z + 4.0), 0.0, Vector3.ZERO)
	_prop("banner_red", Vector3(10.0, 0.0, -SPAWN_Z - 4.0), 180.0, Vector3.ZERO)
	_prop("banner_red", Vector3(-10.0, 0.0, -SPAWN_Z - 4.0), 180.0, Vector3.ZERO)
	# Torches up on the central platform; a chest at dead centre.
	_sym_prop("torch", Vector3(7.0, 2.0, 7.0), 0.0, Vector3.ZERO)
	_prop("chest", Vector3(0.0, 2.0, 0.0), 0.0, Vector3(1.2, 1.0, 0.8))

# === Builders ===

## A static box (mesh + collision); map geometry reads grey under the comic shader.
func _box(pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CategoryColors.to_map_grey(color)
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)

## A sloped box (ramp), pitched about X.
func _ramp(pos: Vector3, size: Vector3, pitch_deg: float) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.x = deg_to_rad(pitch_deg)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CategoryColors.to_map_grey(STRUCTURE_COLOR)
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)

## Instance a KayKit dungeon prop (visual glTF) with an optional box collider.
func _prop(name: String, pos: Vector3, yaw_deg: float, collider: Vector3) -> void:
	var scene: PackedScene = load(PROPS + name + ".gltf")
	if scene == null:
		return
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = deg_to_rad(yaw_deg)
	if collider != Vector3.ZERO:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = collider
		cs.shape = shape
		cs.position = Vector3(0.0, collider.y * 0.5, 0.0)
		body.add_child(cs)
	body.add_child(scene.instantiate())
	add_child(body)

# === Symmetry (place a feature and its 180° point-mirror) ===

func _mirror(pos: Vector3) -> Vector3:
	return Vector3(-pos.x, pos.y, -pos.z)

func _sym_box(pos: Vector3, size: Vector3, color: Color = STRUCTURE_COLOR) -> void:
	_box(pos, size, color)
	_box(_mirror(pos), size, color)

func _sym_ramp(pos: Vector3, size: Vector3, pitch_deg: float) -> void:
	_ramp(pos, size, pitch_deg)
	_ramp(_mirror(pos), size, -pitch_deg)

func _sym_prop(name: String, pos: Vector3, yaw_deg: float, collider: Vector3) -> void:
	_prop(name, pos, yaw_deg, collider)
	_prop(name, _mirror(pos), yaw_deg + 180.0, collider)
