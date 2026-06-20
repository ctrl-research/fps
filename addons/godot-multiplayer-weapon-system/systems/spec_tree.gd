extends RefCounted
class_name SpecTree
"""
A player's spec allocation in their class's two skill paths.

Each path is a linear ladder, so allocation is just a depth per path (points
spent in order). Each round a point can advance either path by one node, capped
at ClassDatabase.MAX_POINTS total. Reaching a path's 8th node is its capstone
(specialist); splitting points is a hybrid that never reaches a capstone.

Resolves the net effects of the root passive + all taken nodes:
  aggregate_stats()    -> {stat: multiplier}   (feed to PlayerController.apply_stats)
  granted_abilities()  -> [ability_id, ...]    (base kit + taken grants)
  tags()               -> {tag: values_dict}   (named passives + their tunables)
"""

const PATH_DEPTH: int = 8  # nodes per path (beyond the free root)

var class_id: String
var depths: Array = [0, 0]  # points spent in path 0 / path 1

func _init(class_id_: String) -> void:
	class_id = class_id_

func class_def() -> Dictionary:
	return ClassDatabase.get_def(class_id)

func points_spent() -> int:
	return depths[0] + depths[1]

## Whether more points can still be allocated (capped at MAX_POINTS).
func can_spend(earned_points: int) -> bool:
	return points_spent() < mini(earned_points, ClassDatabase.MAX_POINTS)

## True once a path's full ladder is taken (the capstone is unlocked).
func is_capstone(path: int) -> bool:
	return depths[path] >= PATH_DEPTH

## The node a point would unlock next in `path`, or {} if that path is maxed.
func next_node(path: int) -> Dictionary:
	var nodes: Array = _path_nodes(path)
	if depths[path] >= nodes.size():
		return {}
	return nodes[depths[path]]

## The choices available to spend this round: [{path, node}] for each path with
## room left. (Linear paths → "pick a node" = pick which path to advance.)
func selectable() -> Array:
	var out: Array = []
	for path in [0, 1]:
		var node := next_node(path)
		if not node.is_empty():
			out.append({"path": path, "node": node})
	return out

## Spend a point into `path` (no-op if that path is maxed). Returns success.
func advance(path: int) -> bool:
	if next_node(path).is_empty():
		return false
	depths[path] += 1
	return true

## Clear all allocation (for the respec lobby option).
func reset() -> void:
	depths = [0, 0]

## Net stat multipliers from the root passive + every taken node.
func aggregate_stats() -> Dictionary:
	var stats := {}
	_fold_stats(stats, class_def().get("passive", {}).get("stats", {}))
	for path in [0, 1]:
		var nodes: Array = _path_nodes(path)
		for i in depths[path]:
			_fold_stats(stats, nodes[i].get("stats", {}))
	return stats

## Base-kit abilities plus any granted by taken nodes.
func granted_abilities() -> Array:
	var out: Array = class_def().get("base_abilities", []).duplicate()
	for path in [0, 1]:
		var nodes: Array = _path_nodes(path)
		for i in depths[path]:
			for a in nodes[i].get("grants", []):
				if not out.has(a):
					out.append(a)
	return out

## Active passive tags -> their values dict (root passive + taken nodes).
func tags() -> Dictionary:
	var out := {}
	_fold_tags(out, class_def().get("passive", {}))
	for path in [0, 1]:
		var nodes: Array = _path_nodes(path)
		for i in depths[path]:
			_fold_tags(out, nodes[i])
	return out

# === internals ===

func _path_nodes(path: int) -> Array:
	var paths: Array = class_def().get("paths", [])
	if path < 0 or path >= paths.size():
		return []
	return paths[path].get("nodes", [])

func _fold_stats(into: Dictionary, stats: Dictionary) -> void:
	for key in stats:
		into[key] = float(into.get(key, 1.0)) * float(stats[key])

func _fold_tags(into: Dictionary, node: Dictionary) -> void:
	for tag in node.get("tags", []):
		into[tag] = node.get("values", {})
