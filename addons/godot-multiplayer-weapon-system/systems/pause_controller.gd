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

var _pause_menu: PauseMenu = null
var _was_captured: bool = false

func _process(_delta: float) -> void:
	# Web: a CAPTURED->VISIBLE transition with no menu open means Esc was pressed
	# (the browser ate the key). Treat it as a pause request.
	var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if _was_captured and not captured and not is_paused() and not _blocked():
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
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		_open()

func _blocked() -> bool:
	return is_blocked.is_valid() and bool(is_blocked.call())

func _open() -> void:
	_pause_menu = PauseMenu.new()
	add_child(_pause_menu)
	_pause_menu.resumed.connect(func() -> void: Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED))
	_pause_menu.leave_requested.connect(_leave)

func _leave() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if leave_action.is_valid():
		leave_action.call()
	else:
		get_tree().change_scene_to_file(MAIN_SCENE)
