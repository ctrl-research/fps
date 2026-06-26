extends RefCounted
class_name CategoryColors
"""
Base colours per gameplay category, for readability under the comic stylise
shader (which keeps each object's hue). Set an object's material to one of these
and it reads at a glance: allies blue, enemies red, map grey, interactables
yellow.
"""

## Players / teammates (relative to the local viewer).
const ALLY: Color = Color(0.25, 0.5, 1.0)
## Bots / opponents.
const ENEMY: Color = Color(1.0, 0.3, 0.3)
## Pickups, targets, usable stations.
const INTERACTABLE: Color = Color(1.0, 0.82, 0.2)
## Static world geometry (floors, walls, cover). Neutral grey (no hue bias) so
## bricks and structure read as plain stone.
const MAP: Color = Color(0.57, 0.57, 0.57)

## Desaturate an arbitrary colour to a grey of the same brightness, lightly
## tinted toward MAP — used to make all map geometry read as grey while keeping
## its light/dark contrast.
static func to_map_grey(color: Color) -> Color:
	var l: float = color.get_luminance()
	return Color(l, l, l).lerp(MAP, 0.35)
