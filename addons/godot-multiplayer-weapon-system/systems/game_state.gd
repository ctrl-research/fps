extends Node

class_name GameState
"""
Autoload singleton for managing round state, team scores, and economy.
Handles the core game loop state machine and credit distribution.
"""

## Emitted when round state changes
signal round_state_changed(new_state: GameState.RoundState)

## Emitted when a team's score updates
signal team_score_updated(team_id: int, new_score: int)

## Emitted when a player's credits change
signal player_credits_changed(peer_id: int, new_credits: int)

## Emitted when the round ends
signal round_ended(winning_team: int)

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

func _ready() -> void:
	# Initialize team scores
	team_scores[0] = 0
	team_scores[1] = 0
	
	# Connect signals for multiplayer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _process(delta: float) -> void:
	if current_round_state == RoundState.LIVE:
		round_timer -= delta
		if round_timer <= 0:
			# Time ran out - defenders win
			award_round_win(1)

func _on_peer_connected(peer_id: int) -> void:
	# Initialize player credits on connect
	if not player_credits.has(peer_id):
		player_credits[peer_id] = STARTING_CREDITS

func _on_peer_disconnected(peer_id: int) -> void:
	player_credits.erase(peer_id)

## Start the buy phase for a new round
func start_buy_phase() -> void:
	current_round_state = RoundState.BUY_PHASE
	round_timer = buy_phase_duration
	round_state_changed.emit(RoundState.BUY_PHASE)

## Start the live round combat
func start_live_round() -> void:
	current_round_state = RoundState.LIVE
	round_timer = round_duration
	round_state_changed.emit(RoundState.LIVE)

## End the current round with a winner
func end_round(winning_team: int) -> void:
	current_round_state = RoundState.ROUND_END
	round_state_changed.emit(RoundState.ROUND_END)
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
	round_timer = round_duration
	current_round_state = RoundState.BUY_PHASE
	round_state_changed.emit(RoundState.BUY_PHASE)