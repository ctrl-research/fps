extends Resource
class_name GrenadeData

"""
Resource defining a grenade type for the weapon system.
Supports flash, smoke, EMP, and push grenade effects.
"""

## Grenade type enumeration
enum GrenadeType {
	FLASH,
	SMOKE,
	EMP,
	PUSH,
	FRAG
}

## The type of grenade effect
@export var type: GrenadeType = GrenadeType.FLASH

## Display name for the grenade
@export var grenade_name: String = "Grenade"

## Base damage (for frag grenades)
@export var damage: float = 0.0

## Effect radius in meters
@export var radius: float = 5.0

## Effect duration in seconds
@export var duration: float = 2.0

## Price in credits
@export var price: int = 200

## Maximum inventory count
@export var max_inventory: int = 2

## Whether this grenade can be cooked (delayed throw)
@export var can_cook: bool = true

## Push force for push grenades
@export var push_force: float = 500.0

## Whether this grenade disables electronics (EMP)
@export var disables_electronics: bool = false

## Projectile speed when thrown
@export var throw_speed: float = 15.0

## Fuse time when cooked (minimum)
@export var min_fuse_time: float = 0.5

func _init(p_type: GrenadeType = GrenadeType.FLASH) -> void:
	type = p_type
	_apply_type_defaults()

## Apply default values based on grenade type
func _apply_type_defaults() -> void:
	match type:
		GrenadeType.FLASH:
			grenade_name = "Flashbang"
			radius = 5.0
			duration = 2.0
			price = 200
			max_inventory = 2
			can_cook = true
		GrenadeType.SMOKE:
			grenade_name = "Smoke Grenade"
			radius = 6.0
			duration = 8.0
			price = 150
			max_inventory = 2
			can_cook = false
		GrenadeType.EMP:
			grenade_name = "EMP Grenade"
			radius = 4.0
			duration = 4.0
			price = 250
			max_inventory = 2
			can_cook = false
			disables_electronics = true
		GrenadeType.PUSH:
			grenade_name = "Push Grenade"
			radius = 3.0
			duration = 0.0
			price = 200
			max_inventory = 2
			can_cook = true
			push_force = 500.0
		GrenadeType.FRAG:
			grenade_name = "Frag Grenade"
			damage = 100.0
			radius = 5.0
			price = 300
			max_inventory = 2
			can_cook = true

## Get the area effect data for collision detection
func get_area_data() -> Dictionary:
	return {
		"type": type,
		"radius": radius,
		"duration": duration,
		"disables_electronics": disables_electronics
	}

## Check if this grenade affects a target at the given distance
func affects_target(target_distance: float) -> bool:
	return target_distance <= radius

## Get damage multiplier based on distance from explosion center
func get_damage_falloff(distance: float) -> float:
	if distance >= radius:
		return 0.0
	return 1.0 - (distance / radius)

## Create a flash grenade data instance
static func create_flash() -> GrenadeData:
	var data = GrenadeData.new(GrenadeType.FLASH)
	return data

## Create a smoke grenade data instance
static func create_smoke() -> GrenadeData:
	var data = GrenadeData.new(GrenadeType.SMOKE)
	return data

## Create an EMP grenade data instance
static func create_emp() -> GrenadeData:
	var data = GrenadeData.new(GrenadeType.EMP)
	return data

## Create a push grenade data instance
static func create_push() -> GrenadeData:
	var data = GrenadeData.new(GrenadeType.PUSH)
	return data

## Create a frag grenade data instance
static func create_frag() -> GrenadeData:
	var data = GrenadeData.new(GrenadeType.FRAG)
	return data