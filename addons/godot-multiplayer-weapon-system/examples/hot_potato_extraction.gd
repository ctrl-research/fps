extends Node2D
class_name HotPotatoExtraction

"""
Hot Potato Extraction game mode implementation.
Teams fight to capture and extract a strategic objective.
"""

## Signal emitted when objective is picked up
signal objective_picked_up(carrier_peer_id: int)

## Signal emitted when objective is dropped
signal objective_dropped(position: Vector3)

## Signal emitted when objective is extracted
signal objective_extracted(team_id: int)

## Signal emitted when objective is secured by defenders
signal objective_secured(defender_team_id: int)

## Hot Potato objective states
enum ObjectiveState {
	IDLE,           # Not yet picked up
	CARRIED,        # Being carried by a player
	DROPPED,        # On the ground, can be picked up
	SECURED,        # Defenders have secured it
	EXTRACTED       # Successfully extracted by attackers
}

## Current objective state
var objective_state: ObjectiveState = ObjectiveState.IDLE

## The player currently carrying the objective (-1 if none)
var carrier_peer_id: int = -1

## Last known position of the objective
var objective_position: Vector3 = Vector3.ZERO

## Pickup channel time in seconds
const PICKUP_TIME: float = 1.5

## Secure channel time in seconds
const SECURE_TIME: float = 2.0

## Movement speed penalty when carrying
const CARRY_SPEED_PENALTY: float = 0.7

## Extraction zone position
var extraction_zone_position: Vector3 = Vector3(100, 0, 100)

## Extraction zone radius
var extraction_zone_radius: float = 10.0

## Objective zone positions (array of possible spawns)
var objective_zone_spawns: Array[Vector3] = []

## Current objective spawn index
var current_spawn_index: int = 0

## Extraction window timer (seconds)
var extraction_window: float = 30.0

## Is extraction window active
var extraction_window_active: bool = false

## Attacking team ID
const ATTACKING_TEAM: int = 0

## Defending team ID
const DEFENDING_TEAM: int = 1

func _ready() -> void:
	_setup_objective_zones()

## Setup objective zone spawn points
func _setup_objective_zones() -> void:
	# In a real implementation, these would be loaded from map data
	objective_zone_spawns = [
		Vector3(50, 0, 50),
		Vector3(50, 0, -50),
		Vector3(-50, 0, 50),
		Vector3(-50, 0, -50),
		Vector3(0, 0, 0)
	]

## Start the game mode (called when round begins)
func start_mode() -> void:
	objective_state = ObjectiveState.IDLE
	carrier_peer_id = -1
	extraction_window_active = false
	_spawn_objective()

## Spawn the objective at a random zone position
func _spawn_objective() -> void:
	current_spawn_index = randi() % objective_zone_spawns.size()
	objective_position = objective_zone_spawns[current_spawn_index]
	objective_state = ObjectiveState.IDLE

## Attempt to pick up the objective
func try_pickup_objective(peer_id: int, player_position: Vector3) -> bool:
	# Check if player is close enough
	var distance = player_position.distance_to(objective_position)
	if distance > 2.0:
		return false
	
	# Can only pick up if dropped or idle
	if objective_state != ObjectiveState.IDLE and objective_state != ObjectiveState.DROPPED:
		return false
	
	carrier_peer_id = peer_id
	objective_state = ObjectiveState.CARRIED
	objective_picked_up.emit(peer_id)
	return true

## Drop the objective (called when carrier dies)
func drop_objective(position: Vector3) -> void:
	objective_position = position
	carrier_peer_id = -1
	objective_state = ObjectiveState.DROPPED
	objective_dropped.emit(position)

## Cancel pickup/interrupt revive (interrupt mechanic)
func interrupt_pickup(peer_id: int) -> void:
	# If this player was attempting pickup, cancel it
	# This would be called when a downed player is shot
	pass

## Attempt to secure a dropped objective (defender action)
func try_secure_objective(peer_id: int, player_position: Vector3) -> bool:
	var distance = player_position.distance_to(objective_position)
	if distance > 2.0:
		return false
	
	if objective_state != ObjectiveState.DROPPED:
		return false
	
	# Check if player is on defending team
	var player_team = _get_player_team(peer_id)
	if player_team != DEFENDING_TEAM:
		return false
	
	objective_state = ObjectiveState.SECURED
	objective_secured.emit(DEFENDING_TEAM)
	return true

## Check if the carrier has reached extraction zone
func check_extraction() -> bool:
	if objective_state != ObjectiveState.CARRIED:
		return false
	
	var carrier_team = _get_player_team(carrier_peer_id)
	if carrier_team != ATTACKING_TEAM:
		return false
	
	var distance = objective_position.distance_to(extraction_zone_position)
	if distance <= extraction_zone_radius:
		_trigger_extraction(carrier_team)
		return true
	
	return false

## Trigger extraction sequence
func _trigger_extraction(team_id: int) -> void:
	objective_state = ObjectiveState.EXTRACTED
	extraction_window_active = false
	objective_extracted.emit(team_id)

## Start extraction window (30 seconds to extract)
func start_extraction_window() -> void:
	extraction_window_active = true
	extraction_window = 30.0

## Process extraction window timer
func _process(delta: float) -> void:
	if extraction_window_active:
		extraction_window -= delta
		if extraction_window <= 0:
			# Extraction window expired - defenders win
			extraction_window_active = false

## Get the objective state as a string for debugging/UI
func get_state_string() -> String:
	match objective_state:
		ObjectiveState.IDLE:
			return "Objective Idle"
		ObjectiveState.CARRIED:
			return "Objective Carried"
		ObjectiveState.DROPPED:
			return "Objective Dropped"
		ObjectiveState.SECURED:
			return "Objective Secured"
		ObjectiveState.EXTRACTED:
			return "Objective Extracted"
	return "Unknown"

## Get objective carrier's team (-1 if none)
func get_carrier_team() -> int:
	if carrier_peer_id == -1:
		return -1
	return _get_player_team(carrier_peer_id)

## Get player team (placeholder - would use GameState)
func _get_player_team(peer_id: int) -> int:
	return peer_id % 2

## Reset mode for new round
func reset_mode() -> void:
	objective_state = ObjectiveState.IDLE
	carrier_peer_id = -1
	extraction_window_active = false
	extraction_window = 30.0
	_spawn_objective()

## Get remaining extraction time
func get_extraction_time_remaining() -> float:
	return extraction_window

## Check if extraction window is active
func is_extraction_window_active() -> bool:
	return extraction_window_active