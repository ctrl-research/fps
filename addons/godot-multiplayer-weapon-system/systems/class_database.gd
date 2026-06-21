extends RefCounted
class_name ClassDatabase
"""
Class definitions for the class-spec arena (issue #78).

Each class has a free root passive (granted at level 1) and two paths, each a
linear ladder of 8 nodes. A node carries any of:
  stats   {stat: multiplier}        — folded into PlayerController.apply_stats
  grants  [ability_id, ...]         — abilities unlocked by taking the node
  tags    [name, ...]               — named passive behaviours handled in code
  values  {name: number}            — tunables for those tags / abilities

Stat keys (multipliers, 1.0 = unchanged): health, speed, damage, fire_rate
(attack interval — <1 is faster), damage_taken (<1 is damage reduction).

Pure data + static lookups (no autoload). Access via ClassDatabase.get_def(id).
"""

## Points a player can spend over a match (tree depth beyond the free root).
const MAX_POINTS: int = 8

static func get_def(id: String) -> Dictionary:
	return _classes().get(id, {})

static func class_ids() -> Array:
	return _classes().keys()

static func _classes() -> Dictionary:
	return {"warrior": _warrior(), "mage": _mage(), "archer": _archer()}

# === Warrior (issue #80) ===

static func _warrior() -> Dictionary:
	return {
		"id": "warrior",
		"name": "Warrior",
		"description": "Durable melee bruiser. Specialise into an unbreakable Juggernaut or a frenzied Berserker.",
		"model": "res://assets/characters/kaykit_adventurers/Barbarian.glb",
		"base_abilities": ["melee", "dash"],
		"passive": {
			"name": "Bulwark",
			"desc": "+25% max health, reduced knockback",
			"icon": "BLW",
			"stats": {"health": 1.25},
			"tags": ["knockback_resist"],
		},
		"paths": [
			{
				"name": "Juggernaut",
				"nodes": [
					{"id": "thick_skin", "name": "Thick Skin", "desc": "+12% max health", "icon": "HP", "stats": {"health": 1.12}},
					{"id": "bracing", "name": "Bracing", "desc": "-15% damage taken while stationary", "icon": "DEF", "tags": ["bracing"], "values": {"reduction": 0.15}},
					{"id": "second_wind", "name": "Second Wind", "desc": "Regenerate health out of combat", "icon": "REG", "tags": ["regen"], "values": {"per_sec": 5.0}},
					{"id": "stagger", "name": "Stagger", "desc": "Your hits briefly slow enemies", "icon": "SLW", "tags": ["stagger"], "values": {"slow": 0.3, "time": 0.8}},
					{"id": "fortified", "name": "Fortified", "desc": "+20% max health", "icon": "HP+", "stats": {"health": 1.20}},
					{"id": "shield_bash", "name": "Shield Bash", "desc": "Ability: knockback + short stun", "icon": "BSH", "grants": ["shield_bash"]},
					{"id": "unbreakable", "name": "Unbreakable", "desc": "-20% damage taken", "icon": "DR", "stats": {"damage_taken": 0.80}},
					{"id": "immovable", "name": "Immovable", "desc": "CAPSTONE: ~5s of 70% damage reduction, knockback immunity, taunt aura", "icon": "★", "grants": ["immovable"]},
				],
			},
			{
				"name": "Berserker",
				"nodes": [
					{"id": "honed_edge", "name": "Honed Edge", "desc": "+12% melee damage", "icon": "DMG", "stats": {"damage": 1.12}},
					{"id": "frenzy", "name": "Frenzy", "desc": "+15% attack speed", "icon": "AS", "stats": {"fire_rate": 0.85}},
					{"id": "bloodthirst", "name": "Bloodthirst", "desc": "Melee hits heal you (lifesteal)", "icon": "LS", "tags": ["lifesteal"], "values": {"lifesteal": 0.15}},
					{"id": "momentum", "name": "Momentum", "desc": "Move-speed burst after a kill", "icon": "SPD", "tags": ["momentum"], "values": {"speed": 1.15, "time": 3.0}},
					{"id": "brutality", "name": "Brutality", "desc": "+20% melee damage", "icon": "DM+", "stats": {"damage": 1.20}},
					{"id": "leap_strike", "name": "Leap Strike", "desc": "Ability: leap gap-closer + AoE", "icon": "LEP", "grants": ["leap_strike"]},
					{"id": "rampage", "name": "Rampage", "desc": "Kills reduce ability cooldowns", "icon": "CDR", "tags": ["rampage"], "values": {"cdr": 0.5}},
					{"id": "berserk", "name": "Berserk", "desc": "CAPSTONE: ~6s of huge attack speed, lifesteal, spinning AoE", "icon": "★", "grants": ["berserk"]},
				],
			},
		],
	}

# === Mage (issue #85) ===

static func _mage() -> Dictionary:
	return {
		"id": "mage",
		"name": "Mage",
		"description": "Ranged spellcaster. A frail glass cannon — specialise into a Pyromancer or a Frost Warden.",
		"model": "res://assets/characters/kaykit_adventurers/Mage.glb",
		"viewmodel": "palm",
		"base_abilities": ["magic_bolt", "blink"],
		"passive": {
			"name": "Arcane Focus",
			"desc": "+10% spell damage and faster casts, but frail (-15% health)",
			"icon": "ARC",
			"stats": {"damage": 1.10, "fire_rate": 0.95, "health": 0.85},
		},
		"paths": [
			{
				"name": "Pyromancer",
				"nodes": [
					{"id": "kindling", "name": "Kindling", "desc": "+12% spell damage", "icon": "DMG", "stats": {"damage": 1.12}},
					{"id": "quick_cast", "name": "Quick Cast", "desc": "+15% cast speed", "icon": "CST", "stats": {"fire_rate": 0.85}},
					{"id": "spell_siphon", "name": "Spell Siphon", "desc": "Spells heal you (lifesteal)", "icon": "LS", "tags": ["lifesteal"], "values": {"lifesteal": 0.12}},
					{"id": "pyromania", "name": "Pyromania", "desc": "+20% spell damage", "icon": "DM+", "stats": {"damage": 1.20}},
					{"id": "combustion", "name": "Combustion", "desc": "Kills reduce ability cooldowns", "icon": "CDR", "tags": ["rampage"], "values": {"cdr": 0.5}},
					{"id": "fireball", "name": "Fireball", "desc": "Ability: a projectile that bursts for AoE", "icon": "FBL", "grants": ["fireball"]},
					{"id": "immolation", "name": "Immolation", "desc": "+15% spell damage", "icon": "DM2", "stats": {"damage": 1.15}},
					{"id": "meteor", "name": "Meteor", "desc": "CAPSTONE: heavy AoE at the aim point after a short delay", "icon": "★", "grants": ["meteor"]},
				],
			},
			{
				"name": "Frost Warden",
				"nodes": [
					{"id": "frostbite", "name": "Frostbite", "desc": "Your spells slow enemies", "icon": "SLW", "tags": ["stagger"], "values": {"slow": 0.35, "time": 1.5}},
					{"id": "ice_armor", "name": "Ice Armor", "desc": "-15% damage taken while stationary", "icon": "DEF", "tags": ["bracing"], "values": {"reduction": 0.15}},
					{"id": "mana_font", "name": "Mana Font", "desc": "Regenerate health out of combat", "icon": "REG", "tags": ["regen"], "values": {"per_sec": 5.0}},
					{"id": "glacial", "name": "Glacial", "desc": "+12% spell damage", "icon": "DMG", "stats": {"damage": 1.12}},
					{"id": "ward", "name": "Ward", "desc": "-20% damage taken", "icon": "DR", "stats": {"damage_taken": 0.80}},
					{"id": "frost_nova", "name": "Frost Nova", "desc": "Ability: AoE around you that damages and slows", "icon": "NVA", "grants": ["frost_nova"]},
					{"id": "hardened", "name": "Hardened", "desc": "+18% max health", "icon": "HP", "stats": {"health": 1.18}},
					{"id": "blizzard", "name": "Blizzard", "desc": "CAPSTONE: strong AoE damage and heavy slow at the aim point", "icon": "★", "grants": ["blizzard"]},
				],
			},
		],
	}

# === Archer (issue #88) ===

static func _archer() -> Dictionary:
	return {
		"id": "archer",
		"name": "Archer",
		"description": "Mobile ranged bow user. Specialise into a precise Marksman or a nimble Skirmisher.",
		"model": "res://assets/characters/kaykit_adventurers/Ranger.glb",
		"viewmodel": "bow",
		"base_abilities": ["arrow", "dash"],
		"passive": {
			"name": "Eagle Eye",
			"desc": "+10% damage and +10% attack speed",
			"icon": "EYE",
			"stats": {"damage": 1.10, "fire_rate": 0.9},
		},
		"paths": [
			{
				"name": "Marksman",
				"nodes": [
					{"id": "steady_aim", "name": "Steady Aim", "desc": "+12% damage", "icon": "DMG", "stats": {"damage": 1.12}},
					{"id": "piercing_tips", "name": "Piercing Tips", "desc": "Your arrows pierce enemies", "icon": "PRC", "tags": ["pierce"]},
					{"id": "deadeye", "name": "Deadeye", "desc": "+15% attack speed", "icon": "AS", "stats": {"fire_rate": 0.85}},
					{"id": "hunters_mark", "name": "Hunter's Mark", "desc": "Arrows heal you (lifesteal)", "icon": "LS", "tags": ["lifesteal"], "values": {"lifesteal": 0.12}},
					{"id": "lethality", "name": "Lethality", "desc": "+20% damage", "icon": "DM+", "stats": {"damage": 1.20}},
					{"id": "power_shot", "name": "Power Shot", "desc": "Ability: a high-damage piercing arrow", "icon": "PWR", "grants": ["power_shot"]},
					{"id": "focus", "name": "Focus", "desc": "+15% damage", "icon": "DM2", "stats": {"damage": 1.15}},
					{"id": "snipe", "name": "Snipe", "desc": "CAPSTONE: a massive piercing arrow", "icon": "★", "grants": ["snipe"]},
				],
			},
			{
				"name": "Skirmisher",
				"nodes": [
					{"id": "fleet_footed", "name": "Fleet Footed", "desc": "+12% move speed", "icon": "SPD", "stats": {"speed": 1.12}},
					{"id": "crippling_shots", "name": "Crippling Shots", "desc": "Your arrows slow enemies", "icon": "SLW", "tags": ["stagger"], "values": {"slow": 0.3, "time": 1.2}},
					{"id": "light_armor", "name": "Light Armor", "desc": "-15% damage taken", "icon": "DR", "stats": {"damage_taken": 0.85}},
					{"id": "second_wind", "name": "Second Wind", "desc": "Regenerate health out of combat", "icon": "REG", "tags": ["regen"], "values": {"per_sec": 5.0}},
					{"id": "swift", "name": "Swift", "desc": "+15% move speed", "icon": "SP+", "stats": {"speed": 1.15}},
					{"id": "multishot", "name": "Multishot", "desc": "Ability: fire three arrows in a spread", "icon": "MLT", "grants": ["multishot"]},
					{"id": "adrenaline", "name": "Adrenaline", "desc": "Kills reduce ability cooldowns", "icon": "CDR", "tags": ["rampage"], "values": {"cdr": 0.5}},
					{"id": "arrow_storm", "name": "Arrow Storm", "desc": "CAPSTONE: a rain of arrows at the aim point", "icon": "★", "grants": ["arrow_storm"]},
				],
			},
		],
	}
