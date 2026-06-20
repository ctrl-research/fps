extends RefCounted
class_name Modifiers
"""
Evolution-mode modifier catalog + helpers.

Each round a team drafts one modifier — a buff for itself or a debuff for the
enemy — and they accumulate across the match (the "evolution"). A modifier is a
multiplier on one stat:

  health     max health
  speed      move speed
  damage     weapon damage dealt
  fire_rate  time between shots (lower = faster, so buffs are < 1.0)

Picks are stored per team as `team_mods[team] = [id, id, ...]`. effective()/
stats_for() resolve a player's net multipliers: their own team's `self` buffs
plus the enemy team's `enemy` debuffs.
"""

const STATS: Array[String] = ["health", "speed", "damage", "fire_rate"]

const CATALOG: Array[Dictionary] = [
	{"id": "vitality", "name": "Vitality", "kind": "buff", "target": "self", "stat": "health", "value": 1.25, "desc": "+25% max health"},
	{"id": "swift", "name": "Swift", "kind": "buff", "target": "self", "stat": "speed", "value": 1.15, "desc": "+15% move speed"},
	{"id": "sharpshooter", "name": "Sharpshooter", "kind": "buff", "target": "self", "stat": "damage", "value": 1.20, "desc": "+20% weapon damage"},
	{"id": "rapid_fire", "name": "Rapid Fire", "kind": "buff", "target": "self", "stat": "fire_rate", "value": 0.85, "desc": "+15% fire rate"},
	{"id": "cripple", "name": "Cripple", "kind": "debuff", "target": "enemy", "stat": "speed", "value": 0.80, "desc": "Enemies -20% move speed"},
	{"id": "frailty", "name": "Frailty", "kind": "debuff", "target": "enemy", "stat": "health", "value": 0.82, "desc": "Enemies -18% max health"},
	{"id": "weaken", "name": "Weaken", "kind": "debuff", "target": "enemy", "stat": "damage", "value": 0.82, "desc": "Enemies -18% damage"},
	{"id": "jam", "name": "Jam", "kind": "debuff", "target": "enemy", "stat": "fire_rate", "value": 1.25, "desc": "Enemies -20% fire rate"},
]

# Active stacks for the current Evolution run, so the HUD scoreboard can show
# the local player's buffs/debuffs. Set by the mode; cleared on exit.
static var active_team_mods: Dictionary = {}
static var active_local_team: int = 0

static func set_active(team_mods: Dictionary, local_team: int) -> void:
	active_team_mods = team_mods
	active_local_team = local_team

static func clear_active() -> void:
	active_team_mods = {}

static func has_active() -> bool:
	return not active_team_mods.is_empty()

## Buffs the local player benefits from (own team's self-buffs).
static func local_buffs() -> Array:
	var out: Array = []
	for id in active_team_mods.get(active_local_team, []):
		if get_mod(id).get("target") == "self":
			out.append(id)
	return out

## Debuffs afflicting the local player (enemy team's enemy-debuffs).
static func local_debuffs() -> Array:
	var out: Array = []
	var enemy := 1 - active_local_team
	for id in active_team_mods.get(enemy, []):
		if get_mod(id).get("target") == "enemy":
			out.append(id)
	return out

static func get_mod(id: String) -> Dictionary:
	for m in CATALOG:
		if m["id"] == id:
			return m
	return {}

## `count` distinct random modifier ids to offer in a draft.
static func roll(count: int) -> Array:
	var ids: Array = []
	for m in CATALOG:
		ids.append(m["id"])
	ids.shuffle()
	return ids.slice(0, mini(count, ids.size()))

## Net multiplier for `stat` on a player of `team`: own-team self-buffs times the
## enemy team's enemy-debuffs.
static func effective(team_mods: Dictionary, team: int, stat: String) -> float:
	var mult := 1.0
	var enemy := 1 - team
	for id in team_mods.get(team, []):
		var m := get_mod(id)
		if m.get("target") == "self" and m.get("stat") == stat:
			mult *= float(m.get("value", 1.0))
	for id in team_mods.get(enemy, []):
		var m := get_mod(id)
		if m.get("target") == "enemy" and m.get("stat") == stat:
			mult *= float(m.get("value", 1.0))
	return mult

## All four stat multipliers for a team, as {stat: mult}.
static func stats_for(team_mods: Dictionary, team: int) -> Dictionary:
	var d := {}
	for s in STATS:
		d[s] = effective(team_mods, team, s)
	return d
