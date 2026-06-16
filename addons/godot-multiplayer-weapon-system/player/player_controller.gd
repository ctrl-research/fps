extends CharacterBody3D
class_name PlayerController
"""
FPS player controller. Handles local movement, camera, and networking.

- Authority: each client is authoritative for their own body.
- Peer ID 1 = dedicated server host (no player body in pure server mode).
- Other peers spawn a PlayerController for each connected peer.
"""

## Emitted when health reaches 0
signal died()

## Emitted when this body's health changes (current, maximum)
signal health_changed(current: float, maximum: float)

## Multiplayer authority ID for this body (0 = server/authority)
@export var authority_peer_id: int = 1

## Maximum health
@export var max_health: float = 100.0

# === Movement constants ===
const WALK_SPEED: float = 6.0
const SPRINT_SPEED: float = 9.0
const CROUCH_SPEED: float = 3.0
const JUMP_VELOCITY: float = 5.0
const GRAVITY: float = 20.0

# === Camera ===
const MOUSE_SENSITIVITY: float = 0.003
const MOUSE_VERTICAL_LIMIT: float = 89.0

# Visual layer 20: the owner's own body. Hidden from their own first-person
# camera (so it never blocks the view) but rendered by mirrors and other players.
const OWN_BODY_VISUAL_LAYER: int = 1 << 19

# === Crouch/Stand ===
const CROUCH_TRANSITION_SPEED: float = 8.0
const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.0

# === Slide ===
const SLIDE_SPEED: float = 12.0
const SLIDE_DURATION: float = 0.5
const SLIDE_COOLDOWN: float = 1.5

# === Network sync (authoritative peer pushes these to others) ===
var sync_position: Vector3 = Vector3.ZERO
var sync_rotation: Vector3 = Vector3.ZERO

# === State ===
var _camera: Camera3D
var _current_speed: float = WALK_SPEED
var _is_crouching: bool = false
var _crouch_height_current: float = STAND_HEIGHT
var _is_sprinting: bool = false
var _is_sliding: bool = false
var _slide_timer: float = 0.0
var _slide_cooldown_timer: float = 0.0
var _slide_direction: Vector3 = Vector3.ZERO
var _velocity_y: float = 0.0
var _mouse_captured: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0

# === Combat ===
var health: float = 100.0
var is_dead: bool = false
var _weapon_controller: WeaponController = null

func _ready() -> void:
	health = max_health

	# Set up camera
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 90.0
	add_child(_camera)

	var is_local := is_multiplayer_authority()
	_camera.current = is_local

	# Weapon handling exists on every body: the local one reads input, remote
	# ones replay fire effects received over RPC.
	_weapon_controller = WeaponController.new()
	_weapon_controller.name = "WeaponController"
	add_child(_weapon_controller)
	_weapon_controller.setup(self, _camera, is_local)

	_build_body_mesh(is_local)

	# Only process locally for this player
	# Remote players are set by set_multiplayer_authority externally
	if is_local:
		set_process_input(true)
		set_process(true)
		_capture_mouse()
	else:
		set_process_input(false)
		set_process(false)

	# Sync initial position
	sync_position = global_position

## Build a simple visible body (torso + head) so the player is seen by mirrors
## and other players. For the local player it is moved to a dedicated visual
## layer that its own camera culls, so it never obstructs the first-person view.
func _build_body_mesh(is_local: bool) -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.25, 0.5, 0.85)
	skin.metallic = 0.1
	skin.roughness = 0.7

	var body := Node3D.new()
	body.name = "BodyModel"
	add_child(body)

	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.28
	torso_mesh.height = 1.4
	torso.mesh = torso_mesh
	torso.material_override = skin
	torso.position = Vector3(0.0, 0.8, 0.0)
	body.add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.2
	head_mesh.height = 0.4
	head.mesh = head_mesh
	head.material_override = skin
	head.position = Vector3(0.0, 1.65, 0.0)
	body.add_child(head)

	if is_local:
		torso.layers = OWN_BODY_VISUAL_LAYER
		head.layers = OWN_BODY_VISUAL_LAYER
		_camera.cull_mask &= ~OWN_BODY_VISUAL_LAYER

func _input(event: InputEvent) -> void:
	# Only look around while the cursor is captured. Overlays such as the buy menu
	# release the cursor, which must suppress camera look without spinning the view.
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch -= event.relative.y * MOUSE_SENSITIVITY
		_pitch = clamp(_pitch, -MOUSE_VERTICAL_LIMIT, MOUSE_VERTICAL_LIMIT)

func _unhandled_input(event: InputEvent) -> void:
	# Browsers only grant pointer lock (MOUSE_MODE_CAPTURED) from a user gesture,
	# so re-capture on click. Clicks over an open menu are consumed by the menu's
	# UI (its full-screen dimmer) and never reach here, so this won't fire while
	# shopping.
	if not is_multiplayer_authority() or is_dead:
		return
	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			_capture_mouse()

func _process(delta: float) -> void:
	if is_multiplayer_authority():
		_send_sync_data()

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		# Remote player — interpolate toward synced position
		global_position = global_position.lerp(sync_position, delta * 10.0)
		rotation = sync_rotation
		return

	_handle_movement(delta)

func _handle_movement(delta: float) -> void:
	# Slide cooldown
	if _slide_cooldown_timer > 0:
		_slide_cooldown_timer -= delta

	# Slide timer
	if _is_sliding:
		_slide_timer -= delta
		if _slide_timer <= 0:
			_end_slide()
		_move_slide(delta)
		return

	# --- Normal movement ---
	var input_dir := Vector3.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.z = Input.get_axis("move_forward", "move_backward")

	# Crouch
	_update_crouch(delta, input_dir)

	# Sprint
	_is_sprinting = Input.is_action_pressed("sprint") and input_dir.z < 0 and not _is_crouching

	# Determine speed
	if _is_crouching:
		_current_speed = CROUCH_SPEED
	elif _is_sprinting:
		_current_speed = SPRINT_SPEED
	else:
		_current_speed = WALK_SPEED

	# Slide initiation
	if Input.is_action_just_pressed("slide") and not _is_crouching and _slide_cooldown_timer <= 0:
		if input_dir.length() > 0.1:
			_begin_slide(input_dir.normalized())

	# Gravity
	if not is_on_floor():
		_velocity_y -= GRAVITY * delta
	else:
		_velocity_y = 0.0
		if Input.is_action_just_pressed("jump"):
			_velocity_y = JUMP_VELOCITY

	# Build velocity from input rotated into the body's facing direction.
	# Assigns the inherited CharacterBody3D.velocity that move_and_slide() reads.
	var direction := Basis(Vector3.UP, _yaw) * input_dir
	if direction.length() > 1.0:
		direction = direction.normalized()
	velocity.x = direction.x * _current_speed
	velocity.z = direction.z * _current_speed
	velocity.y = _velocity_y

	# Apply movement
	move_and_slide()

	# Camera rotation follows body yaw
	_yaw = clamp(_yaw, -PI, PI)
	rotation = Vector3(0, _yaw, 0)
	_camera.rotation = Vector3(_pitch, 0, 0)

func _update_crouch(delta: float, input_dir: Vector3) -> void:
	var target_height := STAND_HEIGHT
	if Input.is_action_pressed("crouch"):
		target_height = CROUCH_HEIGHT
		_is_crouching = true
	else:
		_is_crouching = false

	_crouch_height_current = lerp(_crouch_height_current, target_height, delta * CROUCH_TRANSITION_SPEED)

	# Adjust collision and camera
	if has_node("CollisionShape3D"):
		var shape = $CollisionShape3D.shape as CylinderShape3D
		if shape:
			shape.height = _crouch_height_current
			shape.height = max(_crouch_height_current, 0.1)

	_camera.position.y = _crouch_height_current * 0.9

func _begin_slide(direction: Vector3) -> void:
	_is_sliding = true
	_slide_timer = SLIDE_DURATION
	_slide_cooldown_timer = SLIDE_COOLDOWN
	# Lock the slide direction in world space so it doesn't steer with the camera.
	_slide_direction = (Basis(Vector3.UP, _yaw) * direction).normalized()
	_is_crouching = false
	_crouch_height_current = CROUCH_HEIGHT
	_current_speed = SLIDE_SPEED

func _move_slide(_delta: float) -> void:
	# _slide_direction is stored in world space at slide start.
	velocity.x = _slide_direction.x * SLIDE_SPEED
	velocity.z = _slide_direction.z * SLIDE_SPEED
	velocity.y = _velocity_y
	move_and_slide()

func _end_slide() -> void:
	_is_sliding = false
	_slide_timer = 0.0
	_crouch_height_current = STAND_HEIGHT

func _send_sync_data() -> void:
	# Push position/rotation to other peers via sync
	sync_position = global_position
	sync_rotation = rotation

func _capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_mouse_captured = true

func release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_mouse_captured = false

# --- Called by lobby or game manager to spawn player at a position ---
func spawn_at(pos: Vector3) -> void:
	global_position = pos
	if is_multiplayer_authority():
		_capture_mouse()

# === Combat ===

## Add recoil to the player's aim. Positive pitch kicks the view up. Called by
## the WeaponController so recoil moves the actual aim (CS-style), not just a
## cosmetic camera shake the movement code would overwrite each frame.
func add_look_recoil(pitch_delta: float, yaw_delta: float) -> void:
	_pitch += pitch_delta
	_yaw += yaw_delta

## Entry point for attackers (called on the attacker's own machine). Routes the
## damage to the body's owning peer, which is the single writer for its health
## per the "each client is authoritative for its own body" model. The owner
## applies the damage and broadcasts the resulting health to everyone.
func request_damage(amount: float, attacker_id: int) -> void:
	if multiplayer.multiplayer_peer == null or authority_peer_id == _local_peer():
		_apply_damage(amount, attacker_id)
	else:
		_receive_damage.rpc_id(authority_peer_id, amount, attacker_id)

@rpc("any_peer", "reliable")
func _receive_damage(amount: float, attacker_id: int) -> void:
	# Only the owning peer applies damage to this body; ignore stray routing.
	if authority_peer_id != _local_peer():
		return
	_apply_damage(amount, attacker_id)

## Owner-side damage application followed by a health broadcast.
func _apply_damage(amount: float, _attacker_id: int) -> void:
	if is_dead or amount <= 0.0:
		return
	health = max(health - amount, 0.0)
	if health <= 0.0:
		is_dead = true
	health_changed.emit(health, max_health)
	_broadcast_health()
	if is_dead:
		died.emit()

func _broadcast_health() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_sync_health.rpc(health, is_dead)

## Display-only health sync pushed by the owning peer. Permissive sender because
## node multiplayer authority is not set consistently across peers in this
## project; the owner is the sole authoritative writer by convention.
@rpc("any_peer", "call_remote", "reliable")
func _sync_health(current: float, dead: bool) -> void:
	health = current
	health_changed.emit(health, max_health)
	if dead and not is_dead:
		is_dead = true
		died.emit()

## The local peer's id (1 when running without an active network peer).
func _local_peer() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()
