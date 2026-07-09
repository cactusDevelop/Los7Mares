extends Node2D

const DEAL_DELAY = 0.35
const DEAL_DURATION = 0.7
const FLIP_DELAY_AFTER_DEAL = 0.6
const FLIP_WAVE_DELAY = 0.12
const SELECTION_PANEL_WIDTH := 240.0

const CAPTAIN_SCENE := preload("res://scenes/board/pieces/captain_piece.tscn")
const SECOND_SCENE := preload("res://scenes/board/pieces/second_piece.tscn")

@export var radius: float = 1340.0
@export var deck_stack_offset: Vector2 = Vector2(0, -2)

@onready var seas_container: Node2D = $Seas
@onready var deck_area: Area2D = $Seas/DeckArea
@onready var player_list: VBoxContainer = $UI/PlayerList
@onready var player_setup_popup: Control = $UI/PlayerSetupPopup
@onready var narration_box: PanelContainer = $UI/NarrationBox
@onready var piece_selection_panel: Control = $UI/PieceSelectionPanel
@onready var action_spots_container: Node2D = $ActionSpots
@onready var camera: Camera2D = $Camera2D

var _sea_tiles: Array = []
var _slot_order: Array = []
var _dealt_count: int = 0
var _total_seas: int = 0
var _has_started: bool = false

var _camera_base_position: Vector2

var _current_player_index: int = 0
var _current_sub_turn: int = 0  # 0 = premier choix, 1 = pièce restante forcée
var _selected_rank: int = -1
var _last_placed_rank: int = -1


func _ready() -> void:
	_sea_tiles = []
	player_list.position = Vector2(20, 20)
	_camera_base_position = camera.position

	for child in seas_container.get_children():
		if child.is_in_group("sea_tile"):
			_sea_tiles.append(child)

	_total_seas = _sea_tiles.size()

	for i in range(_sea_tiles.size()):
		var tile = _sea_tiles[i]
		tile.global_position = deck_area.global_position + deck_stack_offset * i
		tile.rotation_degrees = 0.0
		tile.z_index = i
		tile.back_sprite.visible = true
		tile.front_sprite.visible = false

	var board_center: Vector2 = global_position
	var slots: Array = []
	for i in range(_total_seas):
		var angle_degrees = 90.0 + i * (360.0 / _total_seas)
		var angle_rad = deg_to_rad(angle_degrees)
		slots.append({
			"global_position": board_center + radius * Vector2(cos(angle_rad), sin(angle_rad)),
			"rotation": angle_degrees + 90.0,
		})

	_slot_order = _sea_tiles.duplicate()
	_slot_order.shuffle()
	for i in range(_slot_order.size()):
		var tile = _slot_order[i]
		tile.set_meta("target_global_position", slots[i].global_position)
		tile.set_meta("target_rotation", slots[i].rotation)

	deck_area.deck_clicked.connect(_on_deck_clicked)
	deck_area.hover_entered.connect(_on_deck_hover_entered)
	deck_area.hover_exited.connect(_on_deck_hover_exited)

	GameFlow.players_changed.connect(_refresh_player_list)
	_refresh_player_list()

	if GameFlow.pending_setup_mode != "":
		deck_area.input_pickable = false
		player_setup_popup.player_confirmed.connect(_on_setup_player_confirmed)
		player_setup_popup.open_for_new_player(GameFlow.players.size() + 1, GameFlow.pending_setup_target_count)
	else:
		_start_dealing_phase()


func _on_setup_player_confirmed(player_name: String, color: String) -> void:
	GameFlow.add_player(player_name, color)
	if GameFlow.players.size() < GameFlow.pending_setup_target_count:
		player_setup_popup.open_for_new_player(GameFlow.players.size() + 1, GameFlow.pending_setup_target_count)
	else:
		GameFlow.pending_setup_mode = ""
		deck_area.input_pickable = true
		player_setup_popup.visible = false
		_start_dealing_phase()


func _start_dealing_phase() -> void:
	narration_box.say("Cliquez sur la pile pour distribuer les mers.")


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


func _on_deck_hover_entered() -> void:
	if not _has_started and _sea_tiles.size() > 0:
		_sea_tiles[-1].modulate = GameFlow.HOVER_TINT


func _on_deck_hover_exited() -> void:
	if _sea_tiles.size() > 0:
		_sea_tiles[-1].modulate = Color.WHITE


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

	var total_delay := (_slot_order.size() - 1) * FLIP_WAVE_DELAY + 0.3
	await get_tree().create_timer(total_delay).timeout
	_start_piece_placement_phase()


# --- Phase de placement des pièces ---

func _start_piece_placement_phase() -> void:
	_current_player_index = 0
	_current_sub_turn = 0
	for spot in action_spots_container.get_children():
		spot.spot_clicked.connect(_on_action_spot_clicked)
	piece_selection_panel.piece_selected.connect(_on_piece_selected)
	_shift_camera_for_selection(true)
	_begin_player_piece_turn()


func _begin_player_piece_turn() -> void:
	if _current_player_index >= GameFlow.players.size():
		_end_piece_placement_phase()
		return

	var player: Dictionary = GameFlow.players[_current_player_index]
	var color: Color = GameFlow.COLOR_VALUES[player["color"]]
	_selected_rank = -1

	if _current_sub_turn == 0:
		narration_box.say("Tour de %s : choisis la pièce à jouer (capitaine ou second)." % player["name"])
		piece_selection_panel.setup_for_player(color, -1)
	else:
		var forced_rank: int = GameFlow.PieceRank.SECOND if _last_placed_rank == GameFlow.PieceRank.CAPTAIN else GameFlow.PieceRank.CAPTAIN
		narration_box.say("Tour de %s : place ta dernière pièce." % player["name"])
		piece_selection_panel.setup_for_player(color, forced_rank)


func _on_piece_selected(rank: int) -> void:
	_selected_rank = rank


func _on_action_spot_clicked(spot: Node2D) -> void:
	if _selected_rank == -1:
		return

	var player: Dictionary = GameFlow.players[_current_player_index]
	var piece_scene: PackedScene = CAPTAIN_SCENE if _selected_rank == GameFlow.PieceRank.CAPTAIN else SECOND_SCENE
	var piece: Node2D = piece_scene.instantiate()
	piece.modulate = GameFlow.COLOR_VALUES[player["color"]]
	piece.scale = Vector2.ONE * GameFlow.PIECE_SCALE
	spot.add_piece(piece, player["color"], _selected_rank)

	_last_placed_rank = _selected_rank
	_selected_rank = -1

	if _current_sub_turn == 0:
		_current_sub_turn = 1
	else:
		_current_sub_turn = 0
		_current_player_index += 1
	_begin_player_piece_turn()


func _end_piece_placement_phase() -> void:
	narration_box.say("Placement terminé — la suite arrive bientôt.")
	_shift_camera_for_selection(false)


func _shift_camera_for_selection(active: bool) -> void:
	var shift_world := Vector2((SELECTION_PANEL_WIDTH / 2.0) / camera.zoom.x, 0)
	var target := _camera_base_position + shift_world if active else _camera_base_position
	var tween := create_tween()
	tween.tween_property(camera, "position", target, 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
