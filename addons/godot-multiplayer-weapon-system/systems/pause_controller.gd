extends Node
class_name PauseController
"""
Reusable in-game pause handling, shared by every gameplay scene.

Opens the PauseMenu (Resume / Settings / Leave) when the player presses Esc, and
toggles it off again. Handles the web pointer-lock quirk: browsers reserve Esc to
exit pointer lock and never deliver the keypress, so we also detect the
CAPTURED->VISIBLE lock loss and treat it as Esc.

Usage — add as a child of the scene and (optionally) configure hooks:
    var pause := PauseController.new()
    add_child(pause)
    pause.is_blocked = func() -> bool: return _draft_open      # suppress while busy
    pause.on_escape = func() -> bool: return _close_buy_menu() # consume Esc first
    pause.leave_action = func() -> void: _disconnect_and_quit() # custom Leave

Defaults: Leave returns to the main menu.
"""

const MAIN_SCENE: String = "res://addons/godot-multiplayer-weapon-system/scenes/main.tscn"

## Returns true to suppress opening the menu (e.g. another overlay is up).
var is_blocked: Callable = Callable()
## Called first on Esc; return true if it consumed the press (e.g. closed a menu).
var on_escape: Callable = Callable()
## What "Leave to Menu" does; defaults to changing to the main scene.
var leave_action: Callable = Callable()

## How long to keep re-requesting pointer lock after a resume (web browsers
## enforce a ~1s cooldown after Esc, so an immediate request silently fails).
const CAPTURE_RETRY_TIME: float = 2.0

var _pause_menu: PauseMenu = null
var _was_captured: bool = false
var _capture_retry: float = 0.0

func _process(delta: float) -> void:
	var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if _capture_retry > 0.0 and not is_paused():
		# Resuming: keep asking for pointer lock until it engages (web cooldown).
		if captured:
			_capture_retry = 0.0
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			_capture_retry -= delta
	elif _was_captured and not captured and not is_paused() and not _blocked():
		# A CAPTURED->VISIBLE transition with no menu open means Esc was pressed
		# (the browser ate the key). Treat it as a pause request.
		_open()
	_was_captured = captured

func _unhandled_input(event: InputEvent) -> void:
	# Desktop path (Esc is delivered). The PauseMenu/SettingsMenu consume Esc via
	# _input while open, so this only fires to OPEN the menu.
	if not event.is_action_pressed("disconnect_network"):
		return
	if on_escape.is_valid() and bool(on_escape.call()):
		return
	if _blocked():
		return
	toggle()

func is_paused() -> bool:
	return is_instance_valid(_pause_menu)

func toggle() -> void:
	if is_paused():
		_pause_menu.queue_free()
		_request_capture()
	else:
		_open()

## Re-acquire pointer lock, retrying past the browser's post-Esc cooldown.
func _request_capture() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_capture_retry = CAPTURE_RETRY_TIME

func _blocked() -> bool:
	return is_blocked.is_valid() and bool(is_blocked.call())

func _open() -> void:
	_pause_menu = PauseMenu.new()
	add_child(_pause_menu)
	_pause_menu.resumed.connect(_request_capture)
	_pause_menu.leave_requested.connect(_leave)

func _leave() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if leave_action.is_valid():
		leave_action.call()
	else:
		get_tree().change_scene_to_file(MAIN_SCENE)
