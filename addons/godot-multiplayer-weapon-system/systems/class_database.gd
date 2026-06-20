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
	return {"warrior": _warrior()}

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
			"stats": {"health": 1.25},
			"tags": ["knockback_resist"],
		},
		"paths": [
			{
				"name": "Juggernaut",
				"nodes": [
					{"id": "thick_skin", "name": "Thick Skin", "desc": "+12% max health", "stats": {"health": 1.12}},
					{"id": "bracing", "name": "Bracing", "desc": "-15% damage taken while stationary", "tags": ["bracing"], "values": {"reduction": 0.15}},
					{"id": "second_wind", "name": "Second Wind", "desc": "Regenerate health out of combat", "tags": ["regen"], "values": {"per_sec": 5.0}},
					{"id": "stagger", "name": "Stagger", "desc": "Your hits briefly slow enemies", "tags": ["stagger"], "values": {"slow": 0.3, "time": 0.8}},
					{"id": "fortified", "name": "Fortified", "desc": "+20% max health", "stats": {"health": 1.20}},
					{"id": "shield_bash", "name": "Shield Bash", "desc": "Ability: knockback + short stun", "grants": ["shield_bash"]},
					{"id": "unbreakable", "name": "Unbreakable", "desc": "-20% damage taken", "stats": {"damage_taken": 0.80}},
					{"id": "immovable", "name": "Immovable", "desc": "CAPSTONE: ~5s of 70% damage reduction, knockback immunity, taunt aura", "grants": ["immovable"]},
				],
			},
			{
				"name": "Berserker",
				"nodes": [
					{"id": "honed_edge", "name": "Honed Edge", "desc": "+12% melee damage", "stats": {"damage": 1.12}},
					{"id": "frenzy", "name": "Frenzy", "desc": "+15% attack speed", "stats": {"fire_rate": 0.85}},
					{"id": "bloodthirst", "name": "Bloodthirst", "desc": "Melee hits heal you (lifesteal)", "tags": ["lifesteal"], "values": {"lifesteal": 0.15}},
					{"id": "momentum", "name": "Momentum", "desc": "Move-speed burst after a kill", "tags": ["momentum"], "values": {"speed": 1.15, "time": 3.0}},
					{"id": "brutality", "name": "Brutality", "desc": "+20% melee damage", "stats": {"damage": 1.20}},
					{"id": "leap_strike", "name": "Leap Strike", "desc": "Ability: leap gap-closer + AoE", "grants": ["leap_strike"]},
					{"id": "rampage", "name": "Rampage", "desc": "Kills reduce ability cooldowns", "tags": ["rampage"], "values": {"cdr": 0.5}},
					{"id": "berserk", "name": "Berserk", "desc": "CAPSTONE: ~6s of huge attack speed, lifesteal, spinning AoE", "grants": ["berserk"]},
				],
			},
		],
	}
