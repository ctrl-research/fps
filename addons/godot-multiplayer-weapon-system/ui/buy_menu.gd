extends CanvasLayer
"""
Buy menu overlay shown during the buy phase.

Opens automatically while GameState is in BUY_PHASE and closes when combat begins.
Shop rows are built data-driven from the WeaponDatabase. Purchases route through
GameState (host-authoritative credits); on confirmation the item is equipped into
the local PlayerLoadout.
"""

@onready var _credits_label: Label = $Panel/Margin/VBox/Header/CreditsLabel
@onready var _timer_label: Label = $Panel/Margin/VBox/Header/TimerLabel
@onready var _weapons_list: VBoxContainer = $Panel/Margin/VBox/Shops/Weapons/Scroll/List
@onready var _grenades_list: VBoxContainer = $Panel/Margin/VBox/Shops/Grenades/Scroll/List
@onready var _equipment_list: VBoxContainer = $Panel/Margin/VBox/Shops/Equipment/Scroll/List
@onready var _primary_label: Label = $Panel/Margin/VBox/Loadout/Primary
@onready var _secondary_label: Label = $Panel/Margin/VBox/Loadout/Secondary
@onready var _grenades_slot: Label = $Panel/Margin/VBox/Loadout/Grenades
@onready var _equipment_slot: Label = $Panel/Margin/VBox/Loadout/Equipment
@onready var _ready_button: Button = $Panel/Margin/VBox/Footer/ReadyButton

# [Button] -> {"category": String, "item_id": String}
var _item_buttons: Dictionary = {}

func _ready() -> void:
	GameState.round_state_changed.connect(_on_round_state_changed)
	GameState.player_credits_changed.connect(_on_credits_changed)
	GameState.buy_confirmed.connect(_on_buy_confirmed)
	PlayerLoadout.loadout_changed.connect(_refresh)
	_ready_button.pressed.connect(_on_ready_pressed)

	_build_shops()

	if GameState.current_round_state == GameState.RoundState.BUY_PHASE:
		_open()
	else:
		_close()

func _process(_delta: float) -> void:
	if visible:
		_update_timer()

func _unhandled_input(event: InputEvent) -> void:
	# B toggles the menu, but only during the buy phase.
	var in_buy_phase := GameState.current_round_state == GameState.RoundState.BUY_PHASE
	if event.is_action_pressed("buy") and in_buy_phase:
		if visible:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()

func _on_round_state_changed(state: int) -> void:
	if state == GameState.RoundState.BUY_PHASE:
		_open()
	else:
		_close()

func _open() -> void:
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh()

func _close() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_ready_pressed() -> void:
	GameState.request_ready()

## Tutorial/sandbox: act as a free loadout station. Hides the round-flow controls
## (Ready button + countdown) so the menu never starts a round.
func enable_sandbox_mode() -> void:
	_ready_button.visible = false
	_timer_label.visible = false

func _on_credits_changed(_peer_id: int, _new_credits: int) -> void:
	_refresh()

func _on_buy_confirmed(category: String, item_id: String) -> void:
	match category:
		"weapon":
			PlayerLoadout.equip_weapon(item_id)
		"grenade":
			PlayerLoadout.add_grenade(item_id)
		"equipment":
			PlayerLoadout.equip_equipment(item_id)
	# PlayerLoadout.loadout_changed triggers _refresh.

# === Shop construction ===

func _build_shops() -> void:
	for weapon_id in WeaponDatabase.get_weapon_ids():
		var data: Dictionary = WeaponDatabase.get_weapon(weapon_id)
		_add_row(_weapons_list, "weapon", weapon_id, data, _weapon_stats(data))
	for grenade_id in WeaponDatabase.get_grenade_ids():
		var data: Dictionary = WeaponDatabase.get_grenade(grenade_id)
		_add_row(_grenades_list, "grenade", grenade_id, data, _grenade_stats(data))
	for equipment_id in WeaponDatabase.get_equipment_ids():
		var data: Dictionary = WeaponDatabase.get_equipment(equipment_id)
		_add_row(_equipment_list, "equipment", equipment_id, data, _equipment_stats(data))

func _add_row(list: VBoxContainer, category: String, item_id: String, data: Dictionary, stats: String) -> void:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_item_pressed.bind(category, item_id))
	list.add_child(button)
	_item_buttons[button] = {"category": category, "item_id": item_id, "data": data, "stats": stats}

func _on_item_pressed(category: String, item_id: String) -> void:
	GameState.request_purchase(category, item_id)

# === Refresh ===

func _refresh() -> void:
	var credits := GameState.get_player_credits(GameState._local_peer_id())
	_credits_label.text = "Credits: %d" % credits

	for button in _item_buttons:
		var info: Dictionary = _item_buttons[button]
		var data: Dictionary = info["data"]
		var price: int = data.get("price", 0)
		button.text = "%s   %s   $%d" % [data.get("name", "?"), info["stats"], price]
		button.disabled = not _can_buy(info["category"], info["item_id"], price, credits)

	_refresh_loadout()

func _can_buy(category: String, item_id: String, price: int, credits: int) -> bool:
	if price > credits:
		return false
	match category:
		"grenade":
			return PlayerLoadout.can_add_grenade(item_id)
		"weapon":
			return not _weapon_already_equipped(item_id)
		"equipment":
			return not PlayerLoadout.is_equipment_equipped(item_id)
	return true

func _weapon_already_equipped(weapon_id: String) -> bool:
	return PlayerLoadout.primary_weapon == weapon_id or PlayerLoadout.secondary_weapon == weapon_id

func _refresh_loadout() -> void:
	_primary_label.text = "Primary: %s" % _weapon_name(PlayerLoadout.primary_weapon)
	_secondary_label.text = "Secondary: %s" % _weapon_name(PlayerLoadout.secondary_weapon)
	_grenades_slot.text = "Grenades: %s" % _grenades_summary()
	_equipment_slot.text = "Equipment: %s" % _equipment_summary()

func _weapon_name(weapon_id: String) -> String:
	if weapon_id.is_empty():
		return "—"
	return WeaponDatabase.get_weapon(weapon_id).get("name", weapon_id)

func _grenades_summary() -> String:
	var parts: Array[String] = []
	for grenade_id in PlayerLoadout.grenades:
		var display_name: String = WeaponDatabase.get_grenade(grenade_id).get("name", grenade_id)
		parts.append("%s x%d" % [display_name, PlayerLoadout.grenades[grenade_id]])
	return "—" if parts.is_empty() else ", ".join(parts)

func _equipment_summary() -> String:
	var parts: Array[String] = []
	for slot in PlayerLoadout.equipment:
		var item_id: String = PlayerLoadout.equipment[slot]
		parts.append(WeaponDatabase.get_equipment(item_id).get("name", item_id))
	return "—" if parts.is_empty() else ", ".join(parts)

func _update_timer() -> void:
	var t: int = int(ceil(max(GameState.round_timer, 0.0)))
	_timer_label.text = "%d:%02d" % [t / 60, t % 60]

# === Stat formatting ===

func _weapon_stats(data: Dictionary) -> String:
	return "DMG %d · RoF %.2f · Mag %d" % [
		int(data.get("damage", 0)), data.get("fire_rate", 0.0), int(data.get("mag_size", 0))
	]

func _grenade_stats(data: Dictionary) -> String:
	if data.get("type", "") == "frag":
		return "DMG %d · R %.0fm" % [int(data.get("damage", 0)), data.get("radius", 0.0)]
	return "Dur %.0fs · R %.0fm" % [data.get("duration", 0.0), data.get("radius", 0.0)]

func _equipment_stats(data: Dictionary) -> String:
	if data.has("damage_reduction"):
		return "DR %d%%" % int(data["damage_reduction"] * 100.0)
	if data.has("heal_amount"):
		return "Heal %d" % int(data["heal_amount"])
	if data.has("uses"):
		return "Uses %d" % int(data["uses"])
	return ""
