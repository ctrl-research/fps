extends Node
class_name ProjectSettingsWrapper

"""
Autoload singleton providing typed access to project settings with defaults.
Wraps ProjectSettings for cleaner access throughout the codebase.
"""

## Default values for quick access
const DEFAULT_NETWORK_PORT: int = 10567
const DEFAULT_MAX_PLAYERS: int = 10
const DEFAULT_TICK_RATE: int = 64
const DEFAULT子弹_SPEED: float = 800.0
const DEFAULT_GRAVITY: float = 980.0

static func get_setting(p_path: String, default: Variant) -> Variant:
	"""
	Get a project setting value with a default fallback.
	"""
	if ProjectSettings.has_setting(p_path):
		return ProjectSettings.get_setting(p_path)
	return default

static func set_setting(p_path: String, value: Variant) -> void:
	"""
	Set a project setting value, creating the setting if it doesn't exist.
	"""
	ProjectSettings.set_setting(p_path, value)

static func get_network_port() -> int:
	return get_setting("network/lobby/port", DEFAULT_NETWORK_PORT)

static func get_max_players() -> int:
	return get_setting("network/lobby/max_players", DEFAULT_MAX_PLAYERS)

static func get_tick_rate() -> int:
	return get_setting("gameplay/tick_rate", DEFAULT_TICK_RATE)

static func get_bullet_speed() -> float:
	return get_setting("gameplay/bullet_speed", DEFAULT子弹_SPEED)

static func get_gravity() -> float:
	return get_setting("physics/common/default_gravity", DEFAULT_GRAVITY)

static func get_buy_phase_duration() -> float:
	return get_setting("gameplay/round/buy_phase_duration", 15.0)

static func get_round_duration() -> float:
	return get_setting("gameplay/round/round_duration", 240.0)

static func get_starting_credits() -> int:
	return get_setting("gameplay/economy/starting_credits", 800)

static func get_max_carry_credits() -> int:
	return get_setting("gameplay/economy/max_carry_credits", 3200)

static func get_downed_duration() -> float:
	return get_setting("gameplay/player/down_state_duration", 10.0)

static func get_revive_time() -> float:
	return get_setting("gameplay/player/revive_time", 3.0)

static func get_rounds_to_win() -> int:
	return get_setting("gameplay/match/rounds_to_win", 8)

## WebRTC signaling broker URL (wss:// in production, behind a TLS proxy).
## Override per build via the project setting network/signaling/url.
static func get_signaling_url() -> String:
	return get_setting("network/signaling/url", "ws://localhost:9080")

## ICE servers for WebRTC connections. STUN is free/public; add a TURN entry here
## (with credentials) if friends on strict/symmetric NATs can't connect.
static func get_ice_servers() -> Array:
	return get_setting("network/signaling/ice_servers", [
		{"urls": ["stun:stun.l.google.com:19302"]},
	])

static func setup_gameplay_settings() -> void:
	"""
	Initialize default gameplay settings if not already present.
	Call this from _ready() of an autoload.
	"""
	if not ProjectSettings.has_setting("gameplay/tick_rate"):
		ProjectSettings.set_setting("gameplay/tick_rate", DEFAULT_TICK_RATE)
		ProjectSettings.set_setting("gameplay/bullet_speed", DEFAULT子弹_SPEED)
		ProjectSettings.set_setting("gameplay/round/buy_phase_duration", 15.0)
		ProjectSettings.set_setting("gameplay/round/round_duration", 240.0)
		ProjectSettings.set_setting("gameplay/economy/starting_credits", 800)
		ProjectSettings.set_setting("gameplay/economy/max_carry_credits", 3200)
		ProjectSettings.set_setting("gameplay/player/down_state_duration", 10.0)
		ProjectSettings.set_setting("gameplay/player/revive_time", 3.0)
		ProjectSettings.set_setting("gameplay/match/rounds_to_win", 8)
		ProjectSettings.set_setting("gameplay/grenade/flash_duration", 2.0)
		ProjectSettings.set_setting("gameplay/grenade/smoke_duration", 8.0)
		ProjectSettings.set_setting("gameplay/grenade/emp_duration", 4.0)
		ProjectSettings.set_setting("gameplay/grenade/push_radius", 3.0)
		ProjectSettings.set_setting("network/lobby/port", DEFAULT_NETWORK_PORT)
		ProjectSettings.set_setting("network/lobby/max_players", DEFAULT_MAX_PLAYERS)
		ProjectSettings.set_setting("network/signaling/url", "ws://localhost:9080")
		ProjectSettings.set_setting("network/signaling/ice_servers", [
			{"urls": ["stun:stun.l.google.com:19302"]},
		])

		ProjectSettings.save()