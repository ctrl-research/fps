extends Node
"""
Autoload singleton for managing round state, team scores, and economy.
Handles the core game loop state machine and credit distribution.

No `class_name`: the autoload is registered as `GameState`, and a matching
global class would shadow that singleton — which makes clean compiles (CI
export, web/exported runtime) resolve `GameState.x` to the class and fail. The
autoload name alone provides global access.
"""

## Emitted when round state changes (value is a RoundState enum)
signal round_state_changed(new_state: RoundState)

## Emitted when a team's score updates
signal team_score_updated(team_id: int, new_score: int)

## Emitted when a player's credits change
signal player_credits_changed(peer_id: int, new_credits: int)

## Emitted when the round ends
signal round_ended(winning_team: int)

## Emitted locally on the buyer when a purchase is approved (host-validated)
signal buy_confirmed(category: String, item_id: String)

enum RoundState {
	BUY_PHASE,
	LIVE,
	ROUND_END
}

## Current round state
var current_round_state: RoundState = RoundState.BUY_PHASE

## Number of rounds to win the match
const ROUNDS_TO_WIN: int = 8

## Match format (best of)
const TOTAL_ROUNDS: int = 15

## Current round number (1-indexed)
var current_round: int = 1

## Team scores [team_id] = score
var team_scores: Dictionary = {0: 0, 1: 0}

## Player credits [peer_id] = credits
var player_credits: Dictionary = {}

## Starting credits for each round
const STARTING_CREDITS: int = 800

## Maximum carryable credits between rounds
const MAX_CARRY_CREDITS: int = 3200

## Credit rewards
const CREDIT_REWARD_ELIMINATION: int = 300
const CREDIT_REWARD_ASSIST: int = 150
const CREDIT_REWARD_ROUND_WIN: int = 1000
const CREDIT_REWARD_ROUND_LOSS: int = 500
const CREDIT_REWARD_EXTRACTION: int = 500
const CREDIT_REWARD_DEFEND: int = 300

## Team sizes
var team_size: int = 5

## Buy phase duration in seconds
var buy_phase_duration: float = 15.0

## Round phase duration in seconds
var round_duration: float = 240.0

## Current round timer
var round_timer: float = 0.0

## Is the match over
var match_over: bool = false

## Winning team ID (-1 if no winner yet)
var match_winner: int = -1

## Peers that have signalled ready during the current buy phase (host-tracked)
var _ready_peers: Dictionary = {}

func _ready() -> void:
	# Initialize team scores
	team_scores[0] = 0
	team_scores[1] = 0

func _process(delta: float) -> void:
	# Only the authority drives round timers; clients receive state via RPC.
	if not _is_authority():
		return

	if current_round_state == RoundState.BUY_PHASE:
		round_timer -= delta
		if round_timer <= 0:
			start_live_round()
	elif current_round_state == RoundState.LIVE:
		round_timer -= delta
		if round_timer <= 0:
			# Time ran out - defenders win
			award_round_win(1)

## Whether this peer owns authoritative game state (host, or offline/editor run).
func _is_authority() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()

## The local peer's id (1 when running without an active network peer).
func _local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()

## Called by MultiplayerManager when a peer joins
func on_peer_joined(peer_id: int) -> void:
	if not player_credits.has(peer_id):
		player_credits[peer_id] = STARTING_CREDITS

## Called by MultiplayerManager when a peer leaves
func on_peer_left(peer_id: int) -> void:
	player_credits.erase(peer_id)

## Called when disconnecting to clear all players
func clear_all_players() -> void:
	player_credits.clear()

## Start the buy phase for a new round
func start_buy_phase() -> void:
	_ready_peers.clear()
	_broadcast_round_state(RoundState.BUY_PHASE, buy_phase_duration)

## Start the live round combat
func start_live_round() -> void:
	_ready_peers.clear()
	_broadcast_round_state(RoundState.LIVE, round_duration)

## Authority-only: push a round-state change to every peer (and self).
func _broadcast_round_state(state: RoundState, timer: float) -> void:
	if not _is_authority():
		return
	if multiplayer.multiplayer_peer == null:
		_apply_round_state(state, timer)
	else:
		_apply_round_state.rpc(state, timer)

@rpc("authority", "call_local", "reliable")
func _apply_round_state(state: RoundState, timer: float) -> void:
	current_round_state = state
	round_timer = timer
	round_state_changed.emit(state)

## End the current round with a winner
func end_round(winning_team: int) -> void:
	_broadcast_round_state(RoundState.ROUND_END, 0.0)
	award_round_win(winning_team)

## Award round win and handle match end
func award_round_win(team_id: int) -> void:
	team_scores[team_id] += 1
	team_score_updated.emit(team_id, team_scores[team_id])
	
	# Award credits to winning team
	for peer_id in player_credits.keys():
		var is_winning_team = _get_player_team(peer_id) == team_id
		if is_winning_team:
			add_player_credits(peer_id, CREDIT_REWARD_ROUND_WIN)
		else:
			add_player_credits(peer_id, CREDIT_REWARD_ROUND_LOSS)
	
	# Check for match end
	if team_scores[team_id] >= ROUNDS_TO_WIN:
		match_over = true
		match_winner = team_id
		# Emit final match end signal
	
	round_ended.emit(team_id)

## Add credits to a player
func add_player_credits(peer_id: int, amount: int) -> void:
	if not player_credits.has(peer_id):
		player_credits[peer_id] = STARTING_CREDITS
	
	player_credits[peer_id] = min(player_credits[peer_id] + amount, MAX_CARRY_CREDITS)
	player_credits_changed.emit(peer_id, player_credits[peer_id])

## Spend credits on behalf of a player
func spend_credits(peer_id: int, amount: int) -> bool:
	if not player_credits.has(peer_id):
		return false
	if player_credits[peer_id] < amount:
		return false
	
	player_credits[peer_id] -= amount
	player_credits_changed.emit(peer_id, player_credits[peer_id])
	return true

## Get current credits for a player
func get_player_credits(peer_id: int) -> int:
	return player_credits.get(peer_id, 0)

# === Buy phase: purchases & ready (host-authoritative) ===
#
# Credits are validated and deducted on the host. Loadout composition (grenade
# max_inventory, equipment slot replacement) is enforced client-side in the buy
# menu, since the host does not track per-peer loadouts here. The host only
# guarantees a player cannot spend credits they do not have.

## Called by the local buy menu to purchase an item. Routes to the host.
## category is one of "weapon" / "grenade" / "equipment".
func request_purchase(category: String, item_id: String) -> void:
	if _is_authority():
		_resolve_purchase(_local_peer_id(), category, item_id)
	else:
		_submit_purchase.rpc_id(1, category, item_id)

@rpc("any_peer", "reliable")
func _submit_purchase(category: String, item_id: String) -> void:
	if not _is_authority():
		return
	_resolve_purchase(multiplayer.get_remote_sender_id(), category, item_id)

## Host-side: validate price, deduct credits, notify the buyer to equip.
func _resolve_purchase(buyer: int, category: String, item_id: String) -> void:
	var price := _price_for(category, item_id)
	if price < 0:
		return
	if not spend_credits(buyer, price):
		return
	if buyer == _local_peer_id():
		buy_confirmed.emit(category, item_id)
	else:
		_confirm_purchase.rpc_id(buyer, category, item_id, player_credits[buyer])

@rpc("authority", "reliable")
func _confirm_purchase(category: String, item_id: String, new_credits: int) -> void:
	var me := _local_peer_id()
	player_credits[me] = new_credits
	player_credits_changed.emit(me, new_credits)
	buy_confirmed.emit(category, item_id)

## Look up an item's price from the WeaponDatabase. Returns -1 if not found.
func _price_for(category: String, item_id: String) -> int:
	var data: Dictionary
	match category:
		"weapon":
			data = WeaponDatabase.get_weapon(item_id)
		"grenade":
			data = WeaponDatabase.get_grenade(item_id)
		"equipment":
			data = WeaponDatabase.get_equipment(item_id)
		_:
			return -1
	if data.is_empty():
		return -1
	return data.get("price", 0)

## Called by the local buy menu when the player presses Ready/Skip.
func request_ready() -> void:
	if _is_authority():
		# Host confirms: skipping ends the buy phase for everyone immediately.
		start_live_round()
	else:
		_submit_ready.rpc_id(1)

@rpc("any_peer", "reliable")
func _submit_ready() -> void:
	if not _is_authority():
		return
	_ready_peers[multiplayer.get_remote_sender_id()] = true
	# Start the round once every in-round peer has readied up.
	for peer_id in player_credits.keys():
		if not _ready_peers.has(peer_id):
			return
	start_live_round()

## Get the team for a player
func _get_player_team(peer_id: int) -> int:
	# In a real implementation, this would look up team assignment
	# For now, simple hash-based assignment for testing
	return peer_id % 2

## Get current round state
func get_round_state() -> RoundState:
	return current_round_state

## Check if match is over
func is_match_over() -> bool:
	return match_over

## Get the match winner
func get_match_winner() -> int:
	return match_winner

## Get winning team score
func get_winning_score() -> int:
	return maxi(team_scores[0], team_scores[1])

## Reset for a new match
func reset_match() -> void:
	current_round = 1
	team_scores[0] = 0
	team_scores[1] = 0
	match_over = false
	match_winner = -1
	for peer_id in player_credits.keys():
		player_credits[peer_id] = STARTING_CREDITS

## Reset for a new round
func reset_round() -> void:
	current_round += 1
	start_buy_phase()