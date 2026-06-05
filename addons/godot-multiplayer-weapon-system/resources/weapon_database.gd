extends Resource
class_name WeaponDatabase

"""
Resource database for weapons, attachments, and equipment.
Serves as a central registry for all game items.
"""

## Signal emitted when the database is modified
signal database_updated()

## Internal weapon registry
var _weapons: Dictionary = {}

## Internal grenade registry
var _grenades: Dictionary = {}

## Internal equipment registry
var _equipment: Dictionary = {}

## Internal attachment registry
var _attachments: Dictionary = {}

func _init() -> void:
	_setup_default_weapons()
	_setup_default_grenades()
	_setup_default_equipment()

## Get a weapon by its ID
func get_weapon(weapon_id: String) -> Dictionary:
	return _weapons.get(weapon_id, {})

## Get all registered weapons
func get_all_weapons() -> Array:
	return _weapons.values()

## Register a new weapon
func register_weapon(weapon_id: String, weapon_data: Dictionary) -> void:
	_weapons[weapon_id] = weapon_data
	database_updated.emit()

## Remove a weapon from the database
func unregister_weapon(weapon_id: String) -> void:
	_weapons.erase(weapon_id)
	database_updated.emit()

## Get a grenade by its ID
func get_grenade(grenade_id: String) -> Dictionary:
	return _grenades.get(grenade_id, {})

## Get all registered grenades
func get_all_grenades() -> Array:
	return _grenades.values()

## Register a new grenade type
func register_grenade(grenade_id: String, grenade_data: Dictionary) -> void:
	_grenades[grenade_id] = grenade_data
	database_updated.emit()

## Get equipment by its ID
func get_equipment(equipment_id: String) -> Dictionary:
	return _equipment.get(equipment_id, {})

## Get all registered equipment
func get_all_equipment() -> Array:
	return _equipment.values()

## Register a new equipment type
func register_equipment(equipment_id: String, equipment_data: Dictionary) -> void:
	_equipment[equipment_id] = equipment_data
	database_updated.emit()

## Get an attachment by its ID
func get_attachment(attachment_id: String) -> Dictionary:
	return _attachments.get(attachment_id, {})

## Register a new attachment
func register_attachment(attachment_id: String, attachment_data: Dictionary) -> void:
	_attachments[attachment_id] = attachment_data
	database_updated.emit()

## Setup default weapons
func _setup_default_weapons() -> void:
	# Assault Rifles
	register_weapon("ar_basic", {
		"name": "AR-15",
		"type": "assault_rifle",
		"damage": 30,
		"fire_rate": 0.1,
		"mag_size": 30,
		"reserve_ammo": 90,
		"recoil": 0.15,
		"spread": 0.03,
		"price": 1500,
		"mobility_penalty": 0.05
	})
	
	register_weapon("ar_heavy", {
		"name": "AK-74",
		"type": "assault_rifle",
		"damage": 35,
		"fire_rate": 0.12,
		"mag_size": 30,
		"reserve_ammo": 75,
		"recoil": 0.2,
		"spread": 0.04,
		"price": 1800,
		"mobility_penalty": 0.08
	})
	
	# SMGs
	register_weapon("smg_fast", {
		"name": "MP5",
		"type": "smg",
		"damage": 22,
		"fire_rate": 0.06,
		"mag_size": 30,
		"reserve_ammo": 120,
		"recoil": 0.08,
		"spread": 0.04,
		"price": 1200,
		"mobility_penalty": 0.0
	})
	
	register_weapon("smg_high_cap", {
		"name": "Vector",
		"type": "smg",
		"damage": 20,
		"fire_rate": 0.05,
		"mag_size": 50,
		"reserve_ammo": 150,
		"recoil": 0.1,
		"spread": 0.05,
		"price": 1400,
		"mobility_penalty": 0.03
	})
	
	# Shotguns
	register_weapon("shotgun_pump", {
		"name": "M870",
		"type": "shotgun",
		"damage": 80,
		"fire_rate": 0.8,
		"mag_size": 8,
		"reserve_ammo": 24,
		"recoil": 0.4,
		"spread": 0.15,
		"price": 1100,
		"mobility_penalty": 0.1
	})
	
	register_weapon("shotgun_auto", {
		"name": "AA-12",
		"type": "shotgun",
		"damage": 50,
		"fire_rate": 0.3,
		"mag_size": 20,
		"reserve_ammo": 60,
		"recoil": 0.35,
		"spread": 0.18,
		"price": 2000,
		"mobility_penalty": 0.12
	})
	
	# Sniper Rifles
	register_weapon("sniper_light", {
		"name": "AWP",
		"type": "sniper",
		"damage": 115,
		"fire_rate": 1.2,
		"mag_size": 10,
		"reserve_ammo": 30,
		"recoil": 0.6,
		"spread": 0.01,
		"price": 2500,
		"mobility_penalty": 0.15
	})
	
	register_weapon("sniper_auto", {
		"name": "MSG90",
		"type": "sniper",
		"damage": 85,
		"fire_rate": 0.5,
		"mag_size": 10,
		"reserve_ammo": 40,
		"recoil": 0.35,
		"spread": 0.02,
		"price": 2200,
		"mobility_penalty": 0.12
	})
	
	# Pistols
	register_weapon("pistol_basic", {
		"name": "Glock 17",
		"type": "pistol",
		"damage": 18,
		"fire_rate": 0.15,
		"mag_size": 17,
		"reserve_ammo": 51,
		"recoil": 0.03,
		"spread": 0.02,
		"price": 0,  # Starting weapon
		"mobility_penalty": 0.0
	})
	
	register_weapon("pistol_deagle", {
		"name": "Desert Eagle",
		"type": "pistol",
		"damage": 35,
		"fire_rate": 0.4,
		"mag_size": 7,
		"reserve_ammo": 28,
		"recoil": 0.12,
		"spread": 0.03,
		"price": 600,
		"mobility_penalty": 0.02
	})

## Setup default grenades
func _setup_default_grenades() -> void:
	register_grenade("frag", {
		"name": "Frag Grenade",
		"type": "frag",
		"damage": 100,
		"radius": 5.0,
		"price": 300,
		"max_inventory": 2
	})
	
	register_grenade("flash", {
		"name": "Flashbang",
		"type": "flash",
		"duration": 2.0,
		"radius": 5.0,
		"price": 200,
		"max_inventory": 2
	})
	
	register_grenade("smoke", {
		"name": "Smoke Grenade",
		"type": "smoke",
		"duration": 8.0,
		"radius": 6.0,
		"price": 150,
		"max_inventory": 2
	})
	
	register_grenade("emp", {
		"name": "EMP Grenade",
		"type": "emp",
		"duration": 4.0,
		"radius": 4.0,
		"price": 250,
		"max_inventory": 2,
		"disables_electronics": true
	})
	
	register_grenade("push", {
		"name": "Push Grenade",
		"type": "push",
		"force": 500.0,
		"radius": 3.0,
		"price": 200,
		"max_inventory": 2
	})

## Setup default equipment
func _setup_default_equipment() -> void:
	register_equipment("armor_light", {
		"name": "Light Armor",
		"type": "armor",
		"damage_reduction": 0.2,
		"price": 400,
		"mobility_penalty": 0.0
	})
	
	register_equipment("armor_heavy", {
		"name": "Heavy Armor",
		"type": "armor",
		"damage_reduction": 0.4,
		"price": 800,
		"mobility_penalty": 0.05
	})
	
	register_equipment("mobility_grapple", {
		"name": "Grapple Hook",
		"type": "mobility",
		"uses": 1,
		"price": 600
	})
	
	register_equipment("mobility_dash", {
		"name": "Combat Dash",
		"type": "mobility",
		"uses": 2,
		"price": 500
	})
	
	register_equipment("medical_kit", {
		"name": "Medical Kit",
		"type": "consumable",
		"heal_amount": 100,
		"uses": 1,
		"price": 150
	})
	
	register_equipment("ammo_pack", {
		"name": "Ammo Pack",
		"type": "consumable",
		"uses": 1,
		"price": 100
	})