extends RefCounted
class_name Weapon
"""
Runtime state for a single equipped weapon.

Wraps a weapon definition from the WeaponDatabase and tracks the mutable
per-life state (current magazine and reserve ammo) that the WeaponController
mutates as the player fires and reloads. All static stats are read straight
from the database dictionary so the database remains the single source of truth.
"""

## Default reload time per weapon type, in seconds. A weapon definition may
## override this with a "reload_time" key in the database.
const RELOAD_TIMES: Dictionary = {
	"pistol": 1.5,
	"smg": 2.0,
	"assault_rifle": 2.5,
	"shotgun": 3.0,
	"sniper": 3.5,
}

## Number of pellets fired per shot for shotgun-type weapons.
const SHOTGUN_PELLETS: int = 8

var id: String
var data: Dictionary
var mag: int = 0
var reserve: int = 0

func _init(weapon_id: String) -> void:
	id = weapon_id
	data = WeaponDatabase.get_weapon(weapon_id)
	mag = mag_size()
	reserve = int(data.get("reserve_ammo", 0))

## Whether this weapon resolved to a real database entry.
func is_valid() -> bool:
	return not data.is_empty()

func display_name() -> String:
	return data.get("name", id)

func type() -> String:
	return data.get("type", "")

## Melee weapons have no ammo and a short hit range.
func is_melee() -> bool:
	return type() == "melee"

## Maximum hitscan distance in metres (short for melee, effectively unlimited else).
func range_m() -> float:
	return float(data.get("range", 1000.0))

func damage() -> float:
	return float(data.get("damage", 0.0))

## Seconds between consecutive shots.
func fire_rate() -> float:
	return float(data.get("fire_rate", 0.1))

func mag_size() -> int:
	return int(data.get("mag_size", 0))

## Base spread (cone half-angle, radians) when standing still and not spraying.
func base_spread() -> float:
	return float(data.get("spread", 0.0))

func recoil() -> float:
	return float(data.get("recoil", 0.0))

func reload_time() -> float:
	if data.has("reload_time"):
		return float(data["reload_time"])
	return RELOAD_TIMES.get(type(), 2.5)

## Firing mode: "hitscan" (raycast) or "projectile" (Area3D travel).
func fire_mode() -> String:
	return data.get("fire_mode", "hitscan")

func projectile_speed() -> float:
	return float(data.get("projectile_speed", 60.0))

## Pellets emitted per trigger pull (shotguns fire a spread of pellets).
func pellets() -> int:
	if type() == "shotgun":
		return int(data.get("pellets", SHOTGUN_PELLETS))
	return 1

func can_fire() -> bool:
	return is_melee() or mag > 0

func consume() -> void:
	if is_melee():
		return  # melee has no ammo
	mag = max(mag - 1, 0)

func can_reload() -> bool:
	return reserve > 0 and mag < mag_size()

## Refill the magazine from reserve ammo, up to the magazine capacity.
func reload() -> void:
	var needed := mag_size() - mag
	var taken := min(needed, reserve)
	mag += taken
	reserve -= taken
