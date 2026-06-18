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

## Emitted when the match ends (best-of reached); carries the winning team
signal match_ended(winning_team: int)

## Emitted when teams swap sides (halfway through the match)
signal teams_swapped()

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

## Teams swap sides once after this many rounds.
const SWAP_AFTER_ROUNDS: int = 7

## How long the ROUND_END screen lingers before the next buy phase.
const ROUND_END_DURATION: float = 5.0

## Current round number (1-indexed)
var current_round: int = 1

## True after teams have swapped sides (second half of the match).
var sides_swapped: bool = false

## Alive state during a round, [peer_id] = bool (host-authoritative).
var _alive: Dictionary = {}

## Team scores [team_id] = score
var team_scores: Dictionary = {0: 0, 1: 0}

## Player credits [peer_id] = credits
var player_credits: Dictionary = {}

## Per-player eliminations this match, [peer_id] = kills (for the scoreboard).
var player_kills: Dictionary = {}

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
	if match_over:
		return

	match current_round_state:
		RoundState.BUY_PHASE:
			round_timer -= delta
			if round_timer <= 0.0:
				start_live_round()
		RoundState.LIVE:
			round_timer -= delta
			if round_timer <= 0.0:
				end_round(1)  # time ran out — defenders win
		RoundState.ROUND_END:
			round_timer -= delta
			if round_timer <= 0.0:
				_advance_after_round()

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
	_reset_alive()
	_broadcast_round_state(RoundState.LIVE, round_duration)

## Begin a fresh match from round 1 (host/offline entry point).
func start_match() -> void:
	reset_match()
	start_buy_phase()

## Mark every known player alive at the start of a round.
func _reset_alive() -> void:
	_alive.clear()
	for peer_id in player_credits.keys():
		_alive[peer_id] = true

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

## End the current round with a winner (authority-only). Awards score + credits,
## then shows the ROUND_END screen; _process advances to the next round (or the
## match-end screen) after ROUND_END_DURATION.
func end_round(winning_team: int) -> void:
	if not _is_authority() or current_round_state == RoundState.ROUND_END or match_over:
		return
	award_round_win(winning_team)
	_broadcast_round_state(RoundState.ROUND_END, ROUND_END_DURATION)

## Award round win and handle match end
func award_round_win(team_id: int) -> void:
	team_scores[team_id] += 1
	team_score_updated.emit(team_id, team_scores[team_id])

	# Award credits: winning team gets the win bonus, losers the consolation.
	for peer_id in player_credits.keys():
		if _get_player_team(peer_id) == team_id:
			add_player_credits(peer_id, CREDIT_REWARD_ROUND_WIN)
		else:
			add_player_credits(peer_id, CREDIT_REWARD_ROUND_LOSS)

	round_ended.emit(team_id)

	# Best of TOTAL_ROUNDS: first to ROUNDS_TO_WIN takes the match.
	if team_scores[team_id] >= ROUNDS_TO_WIN:
		match_over = true
		match_winner = team_id
		match_ended.emit(team_id)

## After the ROUND_END screen, advance to the next round (unless the match ended).
func _advance_after_round() -> void:
	if match_over:
		return
	reset_round()

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
	sides_swapped = false
	_alive.clear()
	player_kills.clear()
	for peer_id in player_credits.keys():
		player_credits[peer_id] = STARTING_CREDITS
		player_credits_changed.emit(peer_id, STARTING_CREDITS)
	team_score_updated.emit(0, 0)
	team_score_updated.emit(1, 0)

## Reset for a new round (advance the counter, swap sides at halftime).
func reset_round() -> void:
	current_round += 1
	_maybe_swap_sides()
	start_buy_phase()

## Swap sides once, halfway through the match.
func _maybe_swap_sides() -> void:
	var should_swap := current_round > SWAP_AFTER_ROUNDS
	if should_swap != sides_swapped:
		sides_swapped = should_swap
		teams_swapped.emit()

# === Eliminations (win condition) ===

## Report that a player went down/was killed. Routed to the host, which awards
## the killer and checks whether a team has been eliminated.
func report_death(victim_id: int, killer_id: int) -> void:
	if _is_authority():
		_resolve_death(victim_id, killer_id)
	else:
		_submit_death.rpc_id(1, victim_id, killer_id)

@rpc("any_peer", "reliable")
func _submit_death(victim_id: int, killer_id: int) -> void:
	if not _is_authority():
		return
	_resolve_death(victim_id, killer_id)

func _resolve_death(victim_id: int, killer_id: int) -> void:
	_alive[victim_id] = false
	# Reward the killer for an enemy elimination.
	if killer_id != victim_id and player_credits.has(killer_id) \
			and _get_player_team(killer_id) != _get_player_team(victim_id):
		add_player_credits(killer_id, CREDIT_REWARD_ELIMINATION)
		player_kills[killer_id] = player_kills.get(killer_id, 0) + 1
	_check_elimination()

## End the round if one team has no living players left.
func _check_elimination() -> void:
	if current_round_state != RoundState.LIVE:
		return
	var alive_by_team := {0: 0, 1: 0}
	for peer_id in _alive.keys():
		if _alive[peer_id]:
			alive_by_team[_get_player_team(peer_id)] += 1
	if alive_by_team[0] == 0 and alive_by_team[1] == 0:
		end_round(1)  # mutual wipe — defenders take it
	elif alive_by_team[0] == 0:
		end_round(1)
	elif alive_by_team[1] == 0:
		end_round(0)