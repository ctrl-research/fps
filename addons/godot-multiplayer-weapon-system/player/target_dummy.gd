extends CharacterBody3D
class_name TargetDummy
"""
Stationary practice target for the tutorial range.

Exposes request_damage(amount, attacker_id) so the weapon system damages it like
a player body — hit detection is duck-typed on that method, not the concrete
type. Displays remaining health above the target and respawns shortly after it
is destroyed so the range never runs dry.
"""

@export var max_health: float = 100.0

const GRAVITY: float = 20.0
const RESPAWN_DELAY: float = 2.5
const HIT_FLASH_TIME: float = 0.05

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _label: Label3D = $HealthLabel
@onready var _collision: CollisionShape3D = $CollisionShape3D

var health: float = 0.0
var _dead: bool = false
var _respawn_timer: float = 0.0
var _flash_timer: float = 0.0
var _material: StandardMaterial3D = null

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_mesh.material_override = _material
	_reset()
	# Stylise the dummy body (outline + dither), like other entities.
	EntityVisuals.apply(self)

func _physics_process(delta: float) -> void:
	if _dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_reset()
		return

	# Settle onto the floor.
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_update_color()

## Weapon hit entry point. Matches PlayerController.request_damage's signature so
## the same hitscan/projectile code path damages dummies and players alike.
func request_damage(amount: float, _attacker_id: int) -> void:
	if _dead or amount <= 0.0:
		return
	health = max(health - amount, 0.0)
	_label.text = "%d" % int(health)
	_material.albedo_color = Color(1.0, 1.0, 1.0)
	_flash_timer = HIT_FLASH_TIME
	if health <= 0.0:
		_die()

func _die() -> void:
	_dead = true
	_respawn_timer = RESPAWN_DELAY
	_mesh.visible = false
	_label.text = "respawning…"
	_collision.set_deferred("disabled", true)

func _reset() -> void:
	_dead = false
	health = max_health
	_mesh.visible = true
	_collision.set_deferred("disabled", false)
	_label.text = "%d" % int(health)
	_update_color()

## Tint from green (full) toward red (low) for at-a-glance health feedback.
func _update_color() -> void:
	var t: float = clamp(health / max_health, 0.0, 1.0)
	_material.albedo_color = Color(1.0 - t * 0.2, 0.2 + t * 0.6, 0.2)
