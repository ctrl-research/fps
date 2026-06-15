extends Area3D
class_name Projectile
"""
A travelling projectile for projectile-type weapons.

Spawned by the firing peer's WeaponController. Moves forward at a fixed speed
and applies damage to the first PlayerController it overlaps, then frees itself.
Hitscan weapons do not use this; see WeaponController._fire_hitscan.
"""

## Metres travelled per second.
var speed: float = 60.0

## Damage applied on contact.
var damage: float = 0.0

## Peer id of the shooter (so kills/damage can be attributed and self-hits ignored).
var attacker_id: int = 0

## The shooter's own body, excluded from hits.
var shooter: Node = null

## Seconds before the projectile despawns if it hits nothing.
var lifetime: float = 4.0

var _direction: Vector3 = Vector3.FORWARD
var _age: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	monitoring = true

## Configure the projectile before adding it to the scene.
func launch(from: Vector3, direction: Vector3) -> void:
	global_position = from
	_direction = direction.normalized()
	look_at(from + _direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta
	_age += delta
	if _age >= lifetime:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body == shooter:
		return
	# Any body exposing request_damage is damageable (players, dummies, …).
	if body.has_method("request_damage"):
		body.request_damage(damage, attacker_id)
	queue_free()
