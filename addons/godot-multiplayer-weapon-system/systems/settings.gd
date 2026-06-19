extends Node
# No `class_name`: registered as the `Settings` autoload. A matching global class
# would shadow the singleton and break clean compiles.
"""
User settings: rebindable input actions and mouse sensitivity, persisted to
user://settings.cfg. Saved keybinds are applied to the InputMap on startup so
they take effect game-wide.
"""

## Emitted whenever a binding or option changes.
signal settings_changed()

const CONFIG_PATH: String = "user://settings.cfg"
const DEFAULT_MOUSE_SENSITIVITY: float = 0.003
const MIN_MOUSE_SENSITIVITY: float = 0.0005
const MAX_MOUSE_SENSITIVITY: float = 0.02
const DEFAULT_MASTER_VOLUME: float = 0.75

## Crosshair shapes, in dropdown order (index stored as crosshair_style).
const CROSSHAIR_STYLES: Array[String] = ["Cross", "Dot", "Circle", "X", "Star"]

## Actions exposed in the rebinding UI, in display order.
const BINDABLE_ACTIONS: Array[String] = [
	"move_forward", "move_backward", "move_left", "move_right",
	"jump", "sprint", "crouch", "shoot", "reload",
	"weapon_primary", "weapon_secondary", "grenade", "buy",
]

## Friendly labels for the actions above.
const ACTION_LABELS: Dictionary = {
	"move_forward": "Move Forward",
	"move_backward": "Move Backward",
	"move_left": "Move Left",
	"move_right": "Move Right",
	"jump": "Jump",
	"sprint": "Sprint",
	"crouch": "Crouch / Slide",
	"shoot": "Fire",
	"reload": "Reload",
	"weapon_primary": "Primary Weapon",
	"weapon_secondary": "Secondary Weapon",
	"grenade": "Throw Grenade",
	"buy": "Buy Menu",
}

var mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY
## When true, the minimap rotates with the player's view (border stays fixed).
var minimap_rotates: bool = true
## Master output volume, 0..1 (applied to the Master audio bus).
var master_volume: float = DEFAULT_MASTER_VOLUME
## Index into CROSSHAIR_STYLES.
var crosshair_style: int = 0
## Per-entity view-angle outline shader.
var entity_outline_enabled: bool = true
## Global ordered-dithering post-process.
var dither_enabled: bool = true

# Default events captured from the project InputMap at boot, used by reset.
var _default_events: Dictionary = {}

func _ready() -> void:
	_capture_defaults()
	_load()
	_apply_volume()

func _capture_defaults() -> void:
	for action in BINDABLE_ACTIONS:
		if InputMap.has_action(action):
			_default_events[action] = InputMap.action_get_events(action).duplicate()

## Replace an action's binding with a single event, then persist.
func rebind_action(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	save()
	settings_changed.emit()

func reset_to_defaults() -> void:
	for action in _default_events:
		InputMap.action_erase_events(action)
		for event in _default_events[action]:
			InputMap.action_add_event(action, event)
	mouse_sensitivity = DEFAULT_MOUSE_SENSITIVITY
	save()
	settings_changed.emit()

func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	save()
	settings_changed.emit()

func set_minimap_rotates(value: bool) -> void:
	minimap_rotates = value
	save()
	settings_changed.emit()

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	save()
	settings_changed.emit()

func set_crosshair_style(index: int) -> void:
	crosshair_style = clampi(index, 0, CROSSHAIR_STYLES.size() - 1)
	save()
	settings_changed.emit()

func set_entity_outline_enabled(value: bool) -> void:
	entity_outline_enabled = value
	save()
	settings_changed.emit()

func set_dither_enabled(value: bool) -> void:
	dither_enabled = value
	save()
	settings_changed.emit()

## Apply the master volume to the Master audio bus (mute at zero to avoid -inf dB).
func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		bus = 0
	AudioServer.set_bus_mute(bus, master_volume <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.001)))

## Human-readable label for an action's first bound key / mouse button.
func binding_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var keycode: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			return OS.get_keycode_string(keycode)
		if event is InputEventMouseButton:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					return "Mouse Left"
				MOUSE_BUTTON_RIGHT:
					return "Mouse Right"
				MOUSE_BUTTON_MIDDLE:
					return "Mouse Middle"
				_:
					return "Mouse %d" % event.button_index
	return "—"

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("options", "minimap_rotates", minimap_rotates)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("options", "crosshair_style", crosshair_style)
	cfg.set_value("options", "entity_outline_enabled", entity_outline_enabled)
	cfg.set_value("options", "dither_enabled", dither_enabled)
	for action in BINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var events := InputMap.action_get_events(action)
		if events.is_empty():
			continue
		var event: InputEvent = events[0]
		if event is InputEventKey:
			var keycode: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			cfg.set_value("keys", action, {"type": "key", "keycode": keycode})
		elif event is InputEventMouseButton:
			cfg.set_value("keys", action, {"type": "mouse", "button": event.button_index})
	cfg.save(CONFIG_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", DEFAULT_MOUSE_SENSITIVITY)
	minimap_rotates = cfg.get_value("options", "minimap_rotates", true)
	master_volume = cfg.get_value("audio", "master_volume", DEFAULT_MASTER_VOLUME)
	crosshair_style = cfg.get_value("options", "crosshair_style", 0)
	entity_outline_enabled = cfg.get_value("options", "entity_outline_enabled", true)
	dither_enabled = cfg.get_value("options", "dither_enabled", true)
	if not cfg.has_section("keys"):
		return
	for action in cfg.get_section_keys("keys"):
		if not InputMap.has_action(action):
			continue
		var event := _event_from_data(cfg.get_value("keys", action, {}))
		if event != null:
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, event)

func _event_from_data(data: Dictionary) -> InputEvent:
	match data.get("type", ""):
		"key":
			var key_event := InputEventKey.new()
			key_event.physical_keycode = int(data.get("keycode", 0))
			return key_event
		"mouse":
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = int(data.get("button", MOUSE_BUTTON_LEFT))
			return mouse_event
	return null
