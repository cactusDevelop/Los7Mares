extends Node2D

const DEAL_DELAY = 0.35
const DEAL_DURATION = 0.7
const FLIP_DELAY_AFTER_DEAL = 0.6
const FLIP_WAVE_DELAY = 0.12

@export var radius: float = 1340.0
@export var deck_stack_offset: Vector2 = Vector2(0, -2)

@onready var seas_container: Node2D = $Seas
@onready var deck_area: Area2D = $Seas/DeckArea
@onready var player_list: VBoxContainer = $UI/PlayerList
@onready var player_setup_popup: Control = $UI/PlayerSetupPopup

var _sea_tiles: Array = []
var _slot_order: Array = []
var _dealt_count: int = 0
var _total_seas: int = 0
var _has_started: bool = false


func _ready() -> void:
	_sea_tiles = []
	player_list.position = Vector2(20, 20)

	for child in seas_container.get_children():
		if child.is_in_group("sea_tile"):
			_sea_tiles.append(child)

	_total_seas = _sea_tiles.size()

	# 1. Empiler visuellement au niveau du deck — position GLOBALE, pas locale
	for i in range(_sea_tiles.size()):
		var tile = _sea_tiles[i]
		tile.global_position = deck_area.global_position + deck_stack_offset * i
		tile.rotation_degrees = 0.0
		tile.z_index = i
		tile.back_sprite.visible = true
		tile.front_sprite.visible = false

	# 2. Calculer les 7 emplacements finaux, centrés sur BOARD (self), en GLOBAL
	var board_center: Vector2 = global_position
	var slots: Array = []
	for i in range(_total_seas):
		var angle_degrees = 90.0 + i * (360.0 / _total_seas)
		var angle_rad = deg_to_rad(angle_degrees)
		slots.append({
			"global_position": board_center + radius * Vector2(cos(angle_rad), sin(angle_rad)),
			"rotation": angle_degrees + 90.0,
		})

	# 3. Attribution aléatoire des emplacements
	_slot_order = _sea_tiles.duplicate()
	_slot_order.shuffle()
	for i in range(_slot_order.size()):
		var tile = _slot_order[i]
		tile.set_meta("target_global_position", slots[i].global_position)
		tile.set_meta("target_rotation", slots[i].rotation)

	deck_area.deck_clicked.connect(_on_deck_clicked)

	# --- Joueurs ---
	GameFlow.players_changed.connect(_refresh_player_list)
	_refresh_player_list()

	if GameFlow.pending_setup_mode != "":
		deck_area.input_pickable = false
		player_setup_popup.player_confirmed.connect(_on_setup_player_confirmed)
		player_setup_popup.open_for_new_player(GameFlow.players.size() + 1, GameFlow.pending_setup_target_count)


func _on_setup_player_confirmed(player_name: String, color: String) -> void:
	GameFlow.add_player(player_name, color)
	if GameFlow.players.size() < GameFlow.pending_setup_target_count:
		player_setup_popup.open_for_new_player(GameFlow.players.size() + 1, GameFlow.pending_setup_target_count)
	else:
		GameFlow.pending_setup_mode = ""
		deck_area.input_pickable = true
		player_setup_popup.visible = false


func _refresh_player_list() -> void:
	for child in player_list.get_children():
		child.queue_free()
	for player in GameFlow.players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(20, 20)
		swatch.color = GameFlow.COLOR_VALUES[player["color"]]
		row.add_child(swatch)

		var label := Label.new()
		label.text = player["name"]
		row.add_child(label)

		player_list.add_child(row)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _on_deck_clicked() -> void:
	if _has_started:
		return
	_has_started = true
	deck_area.get_node("HoverPrompt").hide_prompt()
	deck_area.input_pickable = false
	deck_area.visible = false
	_deal_seas()


func _deal_seas() -> void:
	var deal_count = 0
	for i in range(_sea_tiles.size() - 1, -1, -1):
		var tile = _sea_tiles[i]
		var target_pos = tile.get_meta("target_global_position")
		var target_rot = tile.get_meta("target_rotation")

		var tween = create_tween()
		tween.tween_interval(deal_count * DEAL_DELAY)
		tween.tween_property(tile, "global_position", target_pos, DEAL_DURATION)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(tile, "rotation_degrees", target_rot, DEAL_DURATION)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_on_one_card_dealt)
		deal_count += 1


func _on_one_card_dealt() -> void:
	_dealt_count += 1
	if _dealt_count == _total_seas:
		await get_tree().create_timer(FLIP_DELAY_AFTER_DEAL).timeout
		_flip_all_as_wave()


func _flip_all_as_wave() -> void:
	for i in range(_slot_order.size()):
		var tile = _slot_order[i]
		var t = get_tree().create_timer(i * FLIP_WAVE_DELAY)
		t.timeout.connect(tile.flip_to_front)
