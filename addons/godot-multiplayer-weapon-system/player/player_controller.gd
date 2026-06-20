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

## Emitted when the player is downed (health hit 0, bleedout begins)
signal downed()

## Emitted when the player is restored to full (respawn / revive)
signal revived()

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

# Visual layer 17: the local first-person weapon viewmodel. Rendered by the
# owner's camera but culled by mirrors (so the gun isn't seen at head height in
# reflections — the in-hand weapon shows there instead).
const VIEWMODEL_VISUAL_LAYER: int = 1 << 16

## Player character model (KayKit Mage). Character selection will swap this later.
const PLAYER_MODEL: String = "res://assets/characters/kaykit_adventurers/Mage.glb"

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
# Most recent non-zero movement input (local space). Slides launch in this
# direction rather than the current velocity.
var _last_input_dir: Vector3 = Vector3.ZERO
var _velocity_y: float = 0.0
var _mouse_captured: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0

# === Combat ===
## Seconds in the downed state before bleeding out.
const DOWNED_DURATION: float = 10.0
## How quickly grenade knockback decays (m/s per second).
const KNOCKBACK_DECAY: float = 18.0

var health: float = 100.0
var is_dead: bool = false
var is_downed: bool = false
var bleedout_timer: float = 0.0
var emp_timer: float = 0.0
var _knockback: Vector3 = Vector3.ZERO
var _last_attacker_id: int = 0
var _weapon_controller: WeaponController = null
var _model: CharacterModel = null
# Previous position, for deriving planar speed to pick the locomotion animation.
var _prev_anim_pos: Vector3 = Vector3.ZERO

# Footsteps: only running is audible (walking is silent). Computed per-body on
# every client from movement, so footsteps are spatial for all players.
const FOOTSTEP_RUN_SPEED: float = 7.0
const FOOTSTEP_INTERVAL: float = 0.32
var _footstep_timer: float = 0.0

# Evolution stat multipliers (1.0 = unmodified). Read by movement / weapon.
const BASE_MAX_HEALTH: float = 100.0
var stat_speed_mult: float = 1.0
var stat_damage_mult: float = 1.0
var stat_fire_rate_mult: float = 1.0

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

	# Joined so the minimap and other systems can enumerate all player bodies.
	add_to_group("players")

	# Re-tint allies/enemies when sides swap mid-match.
	GameState.teams_swapped.connect(_apply_team_tint)

	if is_local:
		var hud = load("res://addons/godot-multiplayer-weapon-system/ui/game_hud.gd").new()
		add_child(hud)
		hud.bind(self)

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

## Build the visible character model so the player is seen by mirrors and other
## players. For the local player it is moved to a dedicated visual layer that its
## own camera culls, so it never obstructs the first-person view.
func _build_body_mesh(is_local: bool) -> void:
	var body := Node3D.new()
	body.name = "BodyModel"
	add_child(body)

	_model = CharacterModel.new()
	body.add_child(_model)
	_model.setup(PLAYER_MODEL)

	if is_local:
		# Own body on its own visual layer, culled from the first-person camera.
		_model.set_visual_layer(OWN_BODY_VISUAL_LAYER)
		_camera.cull_mask &= ~OWN_BODY_VISUAL_LAYER

	# Comic outline + posterise is a global post-process; the body's base colour
	# encodes team (blue ally / red enemy) for readability.
	_apply_team_tint()

	# Put the held weapon in the model's hand (for mirrors / other players); the
	# local first-person viewmodel is separate and camera-mounted.
	if _weapon_controller:
		_weapon_controller.attach_world_weapon()

	_prev_anim_pos = global_position

## The player's character model (for the weapon controller's hand attachment).
func character_model() -> CharacterModel:
	return _model

## Apply Evolution stat multipliers ({health, speed, damage, fire_rate}) and
## refill to the new max. Called at the start of each round.
func apply_stats(stats: Dictionary) -> void:
	stat_speed_mult = stats.get("speed", 1.0)
	stat_damage_mult = stats.get("damage", 1.0)
	stat_fire_rate_mult = stats.get("fire_rate", 1.0)
	max_health = BASE_MAX_HEALTH * float(stats.get("health", 1.0))
	health = max_health
	health_changed.emit(health, max_health)

## Colour the body relative to the local viewer's team: allies blue, enemies
## red. Recomputed on team swap.
func _apply_team_tint() -> void:
	if _model == null:
		return
	var local_team := GameState._get_player_team(GameState._local_peer_id())
	var my_team := GameState._get_player_team(authority_peer_id)
	_model.set_tint(CategoryColors.ALLY if my_team == local_team else CategoryColors.ENEMY)

func _input(event: InputEvent) -> void:
	# Only look around while the cursor is captured. Overlays such as the buy menu
	# release the cursor, which must suppress camera look without spinning the view.
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var sensitivity: float = Settings.mouse_sensitivity
		_yaw -= event.relative.x * sensitivity
		_pitch -= event.relative.y * sensitivity
		# MOUSE_VERTICAL_LIMIT is in degrees; _pitch is radians.
		var pitch_limit := deg_to_rad(MOUSE_VERTICAL_LIMIT)
		_pitch = clamp(_pitch, -pitch_limit, pitch_limit)

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
		_update_animation(delta)
		return

	if emp_timer > 0.0:
		emp_timer -= delta

	if is_dead:
		_update_animation(delta)
		return

	if is_downed:
		_process_downed(delta)
		_update_animation(delta)
		return

	_handle_movement(delta)
	_update_animation(delta)

## Drive the character model: death pose while down/dead, otherwise pick
## idle / walk / run / jump from the planar speed derived from position change.
func _update_animation(delta: float) -> void:
	if _model == null:
		return
	if is_dead or is_downed:
		_model.play_death()
		return
	var moved := global_position - _prev_anim_pos
	_prev_anim_pos = global_position
	var planar := Vector2(moved.x, moved.z).length() / maxf(delta, 0.0001)
	var on_floor: bool = is_on_floor() if is_multiplayer_authority() else true
	_model.set_locomotion(planar, on_floor)
	_update_footsteps(delta, planar, on_floor)

## Play spatial footsteps while running (walking is silent). Runs for every body.
func _update_footsteps(delta: float, planar: float, on_floor: bool) -> void:
	if not on_floor or planar < FOOTSTEP_RUN_SPEED:
		_footstep_timer = 0.0
		return
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_footstep_timer = FOOTSTEP_INTERVAL
		GameAudio.play_at(global_position, "footstep", "footstep")

## Downed players can't move or act; they just bleed out (gravity keeps them
## grounded). The HUD shows the countdown.
func _process_downed(delta: float) -> void:
	bleedout_timer -= delta
	if bleedout_timer <= 0.0:
		_bleed_out()
		return
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		_velocity_y -= GRAVITY * delta
	else:
		_velocity_y = 0.0
	velocity.y = _velocity_y
	move_and_slide()

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

	if input_dir.length() > 0.1:
		_last_input_dir = input_dir.normalized()

	# Crouch initiates a slide while moving; otherwise it just crouches.
	if Input.is_action_just_pressed("crouch") and _slide_cooldown_timer <= 0:
		var horizontal_speed := Vector2(velocity.x, velocity.z).length()
		if horizontal_speed > 1.0 and _last_input_dir.length() > 0.1:
			_begin_slide(_last_input_dir)
			return

	# Crouch
	_update_crouch(delta, input_dir)

	# Sprint
	_is_sprinting = Input.is_action_pressed("sprint") and input_dir.z < 0 and not _is_crouching

	# Determine speed (scaled by any Evolution speed modifier)
	if _is_crouching:
		_current_speed = CROUCH_SPEED
	elif _is_sprinting:
		_current_speed = SPRINT_SPEED
	else:
		_current_speed = WALK_SPEED
	_current_speed *= stat_speed_mult

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
	# Add (decaying) grenade knockback on top of input movement.
	velocity.x = direction.x * _current_speed + _knockback.x
	velocity.z = direction.z * _current_speed + _knockback.z
	velocity.y = _velocity_y
	_knockback = _knockback.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)

	# Apply movement
	move_and_slide()

	# Camera rotation follows body yaw. Wrap (don't clamp) so horizontal turning
	# is unlimited — wrapping from PI to -PI is the same orientation, so it's
	# seamless, whereas clamping would hard-stop the view at +/-180 degrees.
	_yaw = wrapf(_yaw, -PI, PI)
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
func _apply_damage(amount: float, attacker_id: int) -> void:
	if is_dead or is_downed or amount <= 0.0:
		return
	_last_attacker_id = attacker_id
	health = max(health - amount, 0.0)
	health_changed.emit(health, max_health)
	_broadcast_health()
	if health <= 0.0:
		_enter_downed()

func _enter_downed() -> void:
	is_downed = true
	bleedout_timer = DOWNED_DURATION
	downed.emit()
	# The downed player hears their own heartbeat (local only).
	if is_multiplayer_authority():
		GameAudio.start_heartbeat()
	# Report to the round machine (host-authoritative; no-op outside a live round).
	GameState.report_death(authority_peer_id, _last_attacker_id)

func _bleed_out() -> void:
	is_downed = false
	is_dead = true
	health = 0.0
	if is_multiplayer_authority():
		GameAudio.stop_heartbeat()
	health_changed.emit(0.0, max_health)
	_broadcast_health()
	died.emit()

## Restore the player to full health at a position (respawn / revive).
func respawn(pos: Vector3) -> void:
	is_dead = false
	is_downed = false
	bleedout_timer = 0.0
	health = max_health
	velocity = Vector3.ZERO
	_velocity_y = 0.0
	global_position = pos
	sync_position = pos
	_prev_anim_pos = pos
	if _model != null:
		_model.play_idle()
	if is_multiplayer_authority():
		GameAudio.stop_heartbeat()
	health_changed.emit(health, max_health)
	revived.emit()
	_broadcast_health()

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

# === Grenade effects ===
# These guard on multiplayer authority so they only affect the player on their
# own machine (avoids, e.g., flashing the thrower's screen). Cross-peer routing
# for online play is a follow-up; offline/tutorial applies directly.

## Knockback impulse (push grenade). Decays via _knockback in movement.
func apply_knockback(impulse: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	_knockback += Vector3(impulse.x, 0.0, impulse.z)
	_velocity_y += maxf(impulse.y, 0.0)

## Whether utility (scope/mobility) is currently EMP-disabled.
func is_emp_disabled() -> bool:
	return emp_timer > 0.0

## EMP: disable utility for `seconds` and show a brief screen tint.
func apply_emp(seconds: float) -> void:
	if not is_multiplayer_authority():
		return
	emp_timer = maxf(emp_timer, seconds)
	_show_screen_overlay(Color(0.4, 0.6, 1.0, 0.35), seconds, 50)

## Flashbang: full white screen overlay that fades over `seconds`.
func apply_flash(seconds: float) -> void:
	if not is_multiplayer_authority():
		return
	_show_screen_overlay(Color(1.0, 1.0, 1.0, 1.0), maxf(seconds, 0.1), 60)

## Build a fading fullscreen ColorRect overlay (used by flash and EMP).
func _show_screen_overlay(color: Color, seconds: float, layer_index: int) -> void:
	var layer := CanvasLayer.new()
	layer.layer = layer_index
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	add_child(layer)
	var tween := create_tween()
	tween.tween_property(rect, "color:a", 0.0, seconds)
	tween.tween_callback(layer.queue_free)
