extends Node
"""
Autoload: app-wide text legibility.

Builds one shared Theme that gives every Label / RichTextLabel a soft drop
shadow and every Button-family control a dark outline, then installs it on the
root window so it applies to ALL controls — whether built in code or in a
.tscn — without any per-widget setup. New UI gets contrast for free.

Buttons (and other BaseButton controls) don't render a font shadow in Godot,
so they get an equivalent dark outline instead; the goal is contrast either way.

For text drawn directly on a CanvasItem (e.g. the HUD cooldown numbers), themes
don't apply — use draw_string_shadow() for the same effect.
"""

const SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.7)
const SHADOW_OFFSET: Vector2 = Vector2(1, 1)
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.7)
const OUTLINE_SIZE: int = 4

## Types that render a font shadow (color + offset constants).
const SHADOW_TYPES: Array[String] = ["Label", "RichTextLabel"]
## Types that render a font outline instead (no shadow support).
const OUTLINE_TYPES: Array[String] = [
	"Button", "CheckButton", "CheckBox", "OptionButton", "MenuButton",
	"LinkButton", "PopupMenu",
]

var theme: Theme = null

func _ready() -> void:
	theme = _build_theme()
	# The root window's theme is the fallback for every Control in the tree, so
	# this one assignment styles the whole app.
	get_tree().root.theme = theme

func _build_theme() -> Theme:
	var t := Theme.new()
	for type in SHADOW_TYPES:
		t.set_color("font_shadow_color", type, SHADOW_COLOR)
		t.set_constant("shadow_offset_x", type, int(SHADOW_OFFSET.x))
		t.set_constant("shadow_offset_y", type, int(SHADOW_OFFSET.y))
		t.set_constant("shadow_outline_size", type, 1)
	for type in OUTLINE_TYPES:
		t.set_color("font_outline_color", type, OUTLINE_COLOR)
		t.set_constant("outline_size", type, OUTLINE_SIZE)
	return t

## Draw `text` with a dark drop shadow then the bright fill, for text drawn
## directly on a CanvasItem (where the app theme can't reach).
func draw_string_shadow(ci: CanvasItem, font: Font, pos: Vector2, text: String,
		alignment: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0,
		font_size: int = 16, color: Color = Color.WHITE) -> void:
	ci.draw_string(font, pos + SHADOW_OFFSET, text, alignment, width, font_size, SHADOW_COLOR)
	ci.draw_string(font, pos, text, alignment, width, font_size, color)
