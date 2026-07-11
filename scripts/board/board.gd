extends Node2D

const DEAL_DELAY = 0.35
const DEAL_DURATION = 0.7
const FLIP_DELAY_AFTER_DEAL = 0.6
const FLIP_WAVE_DELAY = 0.12

const CAPTAIN_SCENE := preload("res://scenes/board/pieces/captain_piece.tscn")
const SECOND_SCENE := preload("res://scenes/board/pieces/second_piece.tscn")
const SEA_CARD_PILE_SCENE := preload("res://scenes/board/sea_card_pile.tscn")

const SEA_KEY_BY_NODE_NAME := {
	"SeaAbondance": "abondance",
	"SeaAzur": "azur",
	"SeaDeFeu": "feu",
	"SeaDeGlace": "glace",
	"SeaDeJade": "jade",
	"SeaMaudite": "maudite",
	"SeaSauvage": "sauvage",
}

@export var radius: float = 1340.0
@export var deck_stack_offset: Vector2 = Vector2(0, -2)

@onready var seas_container: Node2D = $Seas
@onready var deck_area: Area2D = $Seas/DeckArea
@onready var player_boards_panel: PanelContainer = $UI/PlayerBoardsPanel
@onready var player_rows: VBoxContainer = $UI/PlayerBoardsPanel/Rows
@onready var player_board_expanded: Control = $UI/PlayerBoardExpanded
@onready var player_setup_popup: Control = $UI/PlayerSetupPopup
@onready var narration_box: PanelContainer = $UI/NarrationBox
@onready var piece_selection_panel: Control = $UI/PieceSelectionPanel
@onready var action_spots_container: Node2D = $ActionSpots
@onready var camera: Camera2D = $Camera2D
@onready var sea_card_popup: Control = $UI/SeaCardPopup
@onready var card_piles_container: Node2D = $CardPiles

var _sea_tiles: Array = []
var _slot_order: Array = []
var _dealt_count: int = 0
var _total_seas: int = 0
var _has_started: bool = false
var _cards_enabled: bool = false

var _camera_base_position: Vector2
var _camera_base_zoom: Vector2

var _current_round: int = 0  # 0 = premier choix pour tous, 1 = pièce restante forcée pour tous
var _current_player_index: int = 0
var _selected_rank: int = -1
var _placed_rank_by_player: Dictionary = {}  # index joueur -> rang posé au tour 1


func _ready() -> void:
	_sea_tiles = []
	player_boards_panel.position = Vector2(20, 20)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = GameFlow.POPUP_BG_COLOR
	panel_style.set_corner_radius_all(GameFlow.POPUP_CORNER_RADIUS)
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	player_boards_panel.add_theme_stylebox_override("panel", panel_style)
	_camera_base_position = camera.position
	_camera_base_zoom = camera.zoom
	action_spots_container.z_index = 1

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
		var direction := Vector2(cos(angle_rad), sin(angle_rad))
		slots.append({
			"global_position": board_center + radius * direction,
			"rotation": angle_degrees + 90.0,
			"pile_position": board_center + (radius + GameFlow.CARD_PILE_RADIUS_OFFSET) * direction,
		})

	_slot_order = _sea_tiles.duplicate()
	_slot_order.shuffle()
	for i in range(_slot_order.size()):
		var tile = _slot_order[i]
		tile.set_meta("target_global_position", slots[i].global_position)
		tile.set_meta("target_rotation", slots[i].rotation)

		var pile: Node2D = SEA_CARD_PILE_SCENE.instantiate()
		card_piles_container.add_child(pile)
		pile.global_position = slots[i].pile_position
		pile.rotation_degrees = slots[i].rotation
		pile.sea_key = SEA_KEY_BY_NODE_NAME.get(tile.name, "")
		pile.pile_clicked.connect(_on_card_pile_clicked)

	sea_card_popup.card_resolved.connect(_on_sea_card_resolved)

	deck_area.deck_clicked.connect(_on_deck_clicked)
	deck_area.hover_entered.connect(_on_deck_hover_entered)
	deck_area.hover_exited.connect(_on_deck_hover_exited)

	GameFlow.players_changed.connect(_refresh_player_boards)
	_refresh_player_boards()

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
	narration_box.say(tr("Cliquez sur la pile pour distribuer les mers."))


func _refresh_player_boards() -> void:
	for child in player_rows.get_children():
		child.queue_free()
	for player in GameFlow.get_players_sorted_by_points():
		player_rows.add_child(_build_player_board_row(player))


func _build_player_board_row(player: Dictionary) -> Control:
	var color: Color = GameFlow.COLOR_VALUES[player["color"]]

	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = "%s — %d pts" % [player["name"], player["points"]]
	name_label.add_theme_color_override("font_color", color)
	entry.add_child(name_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var board_button := TextureButton.new()
	board_button.texture_normal = load(GameFlow.PLAYER_BOARD_TEXTURE)
	board_button.ignore_texture_size = true
	board_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	board_button.custom_minimum_size = Vector2(160, 107)
	board_button.pressed.connect(_on_player_board_pressed.bind(player["id"]))
	row.add_child(board_button)

	if player.get("has_own_parrot", true):
		row.add_child(_build_parrot_token(color, false))
	for other in GameFlow.players:
		if other.get("parrot_captured_by", -1) == player["id"]:
			row.add_child(_build_parrot_token(GameFlow.COLOR_VALUES[other["color"]], true))

	entry.add_child(row)
	return entry


func _build_parrot_token(base_color: Color, imprisoned: bool) -> Control:
	var token := PanelContainer.new()
	token.custom_minimum_size = Vector2(36, 36)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(18)
	style.bg_color = base_color.darkened(0.4) if imprisoned else base_color
	if imprisoned:
		style.border_color = Color.BLACK
		style.set_border_width_all(3)
	token.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = "🦜"
	label.horizontal_alignment = 1
	label.vertical_alignment = 1
	token.add_child(label)
	return token


func _on_player_board_pressed(player_id: int) -> void:
	for p in GameFlow.players:
		if p["id"] == player_id:
			player_board_expanded.show_player(p)
			return


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
		tile.z_index = 0
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


# --- Phase de placement des pièces : 2 manches globales ---

func _start_piece_placement_phase() -> void:
	_current_round = 0
	_current_player_index = 0
	_placed_rank_by_player.clear()

	for spot in action_spots_container.get_children():
		spot.spot_clicked.connect(_on_action_spot_clicked)
		spot.set_hover_enabled(true)
	piece_selection_panel.piece_selected.connect(_on_piece_selected)

	piece_selection_panel.show_for_placement_phase()
	_shift_camera_for_selection(true)
	_begin_player_piece_turn()


func _begin_player_piece_turn() -> void:
	if _current_player_index >= GameFlow.players.size():
		_current_player_index = 0
		_current_round += 1
		if _current_round > 1:
			_end_piece_placement_phase()
			return

	var player: Dictionary = GameFlow.players[_current_player_index]
	var color: Color = GameFlow.COLOR_VALUES[player["color"]]
	_selected_rank = -1

	if _current_round == 0:
		narration_box.say(tr("Tour de %s : choisis la pièce à jouer (capitaine ou second).") % player["name"])
		piece_selection_panel.setup_for_player(color, -1)
	else:
		var placed_rank: int = _placed_rank_by_player[_current_player_index]
		var forced_rank: int = GameFlow.PieceRank.SECOND if placed_rank == GameFlow.PieceRank.CAPTAIN else GameFlow.PieceRank.CAPTAIN
		narration_box.say(tr("Tour de %s : place ta dernière pièce.") % player["name"])
		piece_selection_panel.setup_for_player(color, forced_rank)


func _on_piece_selected(rank: int) -> void:
	_selected_rank = rank


func _on_action_spot_clicked(spot: Node2D) -> void:
	if _selected_rank == -1:
		return

	var player: Dictionary = GameFlow.players[_current_player_index]

	# Interdit de poser ses deux pièces sur la même case.
	if spot.has_player_piece(player["color"]):
		narration_box.say(tr("Tu ne peux pas poser tes deux pièces sur la même case."))
		return

	var piece_scene: PackedScene = CAPTAIN_SCENE if _selected_rank == GameFlow.PieceRank.CAPTAIN else SECOND_SCENE
	var piece: Node2D = piece_scene.instantiate()
	piece.modulate = GameFlow.COLOR_VALUES[player["color"]]
	piece.scale = Vector2.ONE * GameFlow.PIECE_SCALE
	spot.add_piece(piece, player["color"], _selected_rank)

	if _current_round == 0:
		_placed_rank_by_player[_current_player_index] = _selected_rank
	_selected_rank = -1
	_current_player_index += 1
	_begin_player_piece_turn()


func _end_piece_placement_phase() -> void:
	for spot in action_spots_container.get_children():
		spot.set_hover_enabled(false)
	narration_box.say(tr("Placement terminé — cliquez sur une pioche de mer pour y piocher une carte."))
	piece_selection_panel.hide_panel()
	_shift_camera_for_selection(false)
	_cards_enabled = true
	for pile in card_piles_container.get_children():
		pile.draw_enabled = true


func _on_card_pile_clicked(pile: Node2D) -> void:
	if not _cards_enabled:
		return
	var card: SeaCard = SeaDecks.draw_card(pile.sea_key)
	if card:
		sea_card_popup.show_card(card)


func _on_sea_card_resolved(card: SeaCard) -> void:
	narration_box.say(tr(card.title) + " — " + tr(card.description))


func _shift_camera_for_selection(active: bool) -> void:
	var target_pos := _camera_base_position + Vector2(GameFlow.CAMERA_SELECTION_SHIFT, 0) if active else _camera_base_position
	var target_zoom := GameFlow.CAMERA_SELECTION_ZOOM if active else _camera_base_zoom
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(camera, "position", target_pos, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "zoom", target_zoom, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
