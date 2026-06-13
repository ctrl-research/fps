extends Node
class_name PlayerLoadout
"""
Autoload singleton tracking the local player's chosen loadout for the buy phase.

Loadout composition (which weapon fills each slot, grenade counts, equipment slots)
is local per-peer state. Credits are validated host-authoritatively by GameState;
this node only records what the local player has equipped after a purchase confirms.
"""

## Emitted whenever the loadout changes (slot equipped, grenade added, etc.)
signal loadout_changed()

## Equipment slot categories (one item each)
const SLOT_ARMOR: String = "armor"
const SLOT_MOBILITY: String = "mobility"
const SLOT_CONSUMABLE: String = "consumable"

## Primary weapon id (empty until bought)
var primary_weapon: String = ""

## Secondary weapon id (free starting pistol by default)
var secondary_weapon: String = "pistol_basic"

## Grenade inventory [grenade_id] = count
var grenades: Dictionary = {}

## Equipment by slot category [category] = equipment_id
var equipment: Dictionary = {}

## Equip a weapon into the correct slot based on its type.
## Pistols fill the secondary slot; everything else fills the primary slot.
func equip_weapon(weapon_id: String) -> void:
	var data := WeaponDatabase.get_weapon(weapon_id)
	if data.is_empty():
		return
	if data.get("type", "") == "pistol":
		secondary_weapon = weapon_id
	else:
		primary_weapon = weapon_id
	loadout_changed.emit()

## Add one grenade of the given type to the inventory.
func add_grenade(grenade_id: String) -> void:
	if WeaponDatabase.get_grenade(grenade_id).is_empty():
		return
	grenades[grenade_id] = grenade_count(grenade_id) + 1
	loadout_changed.emit()

## Current count of a grenade type.
func grenade_count(grenade_id: String) -> int:
	return grenades.get(grenade_id, 0)

## Whether another grenade of this type can be carried (below max_inventory).
func can_add_grenade(grenade_id: String) -> bool:
	var data := WeaponDatabase.get_grenade(grenade_id)
	if data.is_empty():
		return false
	var max_count: int = data.get("max_inventory", 2)
	return grenade_count(grenade_id) < max_count

## Equip an equipment item into its slot (armor / mobility / consumable), replacing any
## item currently in that slot.
func equip_equipment(equipment_id: String) -> void:
	var data := WeaponDatabase.get_equipment(equipment_id)
	if data.is_empty():
		return
	equipment[_equipment_slot(data)] = equipment_id
	loadout_changed.emit()

## Whether an equipment item is currently equipped in its slot.
func is_equipment_equipped(equipment_id: String) -> bool:
	var data := WeaponDatabase.get_equipment(equipment_id)
	if data.is_empty():
		return false
	return equipment.get(_equipment_slot(data), "") == equipment_id

## Reset for a new round: equipment and grenades reset, weapons persist
## (per game design: equipment resets each round, weapons persist).
func reset_round() -> void:
	grenades.clear()
	equipment.clear()
	loadout_changed.emit()

## Map an equipment data dict to its loadout slot category.
func _equipment_slot(data: Dictionary) -> String:
	match data.get("type", ""):
		"armor":
			return SLOT_ARMOR
		"mobility":
			return SLOT_MOBILITY
		_:
			return SLOT_CONSUMABLE
