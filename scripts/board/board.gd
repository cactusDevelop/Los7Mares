extends Node2D
class_name Board

const BOARD_THUMB_SIZE := Vector2(160, 107)
const PILE_THUMB_OFFSET := Vector2(0, 6)
const PLAYER_BOARDS_PANEL_MAX_HEIGHT_RATIO := 0.75

const SEA_CARD_PILE_SCENE := preload("res://scenes/board/sea_card_pile.tscn")
const CAPTAIN_PIECE_SCENE := preload("res://scenes/board/pieces/captain_piece.tscn")
const SECOND_PIECE_SCENE := preload("res://scenes/board/pieces/second_piece.tscn")
const SEA_TOKEN_PILE_SCENE := preload("res://scenes/board/sea_token_pile.tscn")
const PLAYER_BOARD_ROW := preload("res://scenes/ui/player_board_row.tscn")

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
@export var hideout_radius: float = 1800.0
@export var fortune_radius: float = 780.0
@export var fortune_angle_start_degrees: float = -90.0
@export var deck_stack_offset: Vector2 = Vector2(0, -2)
@export var debug_skip_to_pieces: bool = false
## Échelle appliquée au sprite du jeton pour qu'il ait un rayon légèrement
## plus petit que celui de la tuile mer sur laquelle il repose. À ajuster
## dans l'inspecteur si besoin (sélectionner le noeud "Board").
@export var token_scale: float = 1.5
## Décalage de rayon appliqué à la position des jetons par rapport à celui
## des tuiles mer (négatif = plus proche du centre). Réglable dans
## l'inspecteur du noeud "Board".
@export var token_pile_radius_offset: float = -500.0

@onready var seas_container: Node2D = $Seas
@onready var deck_area: Area2D = $Seas/DeckArea
@onready var player_boards_panel: PanelContainer = $UI/PlayerBoardsPanel
@onready var player_boards_scroll: ScrollContainer = $UI/PlayerBoardsPanel/Scroll
@onready var player_rows: VBoxContainer = $UI/PlayerBoardsPanel/Scroll/Rows
@onready var player_boards_pile: Control = $UI/PlayerBoardsPile
@onready var player_boards_catcher: Control = $UI/PlayerBoardsCatcher
@onready var player_board_expanded: Control = $UI/PlayerBoardExpanded
@onready var player_setup_popup: Control = $UI/PlayerSetupPopup
@onready var narration_box: PanelContainer = $UI/NarrationBox
@onready var piece_selection_panel: Control = $UI/PieceSelectionPanel
@onready var action_spots_container: Node2D = $ActionSpots
@onready var hideout_spots_container: Node2D = $HideoutSpots
@onready var fortune_spots_container: Node2D = $FortuneSpots
@onready var camera: Camera2D = $Camera2D
@onready var sea_card_popup: Control = $UI/SeaCardPopup
@onready var card_piles_container: Node2D = $CardPiles
@onready var token_piles_container: Node2D = $TokenPiles

@onready var dealing_phase: Node = $DealingPhase
@onready var hideout_phase: Node = $HideoutPhase
@onready var piece_placement_phase: Node = $PiecePlacementPhase
@onready var card_draw_phase: Node = $CardDrawPhase
@onready var return_to_menu_button: Button = $UI/ReturnToMenuButton
@onready var return_to_menu_confirm: ConfirmationDialog = $UI/ReturnToMenuConfirm

var _sea_tiles: Array = []
var _slot_order: Array = []
var _total_seas: int = 0
var _has_started: bool = false

var _camera_base_position: Vector2
var _camera_base_zoom: Vector2


func _ready() -> void:
	_sea_tiles = []
	player_boards_panel.position = Vector2(20, 20)
	player_boards_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	player_boards_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	player_boards_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	player_boards_panel.position = Vector2(20, 20)
	player_boards_panel.reset_size()
	var panel_style := StyleBoxFlat.new()
	panel_style.set_corner_radius_all(UiTheme.POPUP_CORNER_RADIUS)
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	player_boards_panel.add_theme_stylebox_override("panel", panel_style)

	player_boards_pile.position = Vector2(20, 20)
	player_boards_pile.gui_input.connect(_on_player_boards_pile_gui_input)
	player_boards_catcher.gui_input.connect(_on_player_boards_catcher_gui_input)
	player_boards_panel.visible = false
	player_boards_catcher.visible = false
	player_boards_pile.visible = true

	_camera_base_position = camera.position
	_camera_base_zoom = camera.zoom
	action_spots_container.z_index = 1
	seas_container.z_index = 2
	token_piles_container.z_index = 3
	
	return_to_menu_button.pressed.connect(func(): return_to_menu_confirm.popup_centered())
	return_to_menu_confirm.confirmed.connect(func(): GameFlow.go_to_title())

	for child in seas_container.get_children():
		if child.is_in_group("sea_tile"):
			_sea_tiles.append(child)

	_total_seas = _sea_tiles.size()

	for i in range(_sea_tiles.size()):
		var tile = _sea_tiles[i]
		tile.global_position = deck_area.global_position + deck_stack_offset * i
		tile.rotation_degrees = 0.0
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
			"pile_position": board_center + (radius + UiTheme.CARD_PILE_RADIUS_OFFSET) * direction,
			"token_position": board_center + (radius + token_pile_radius_offset) * direction,
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
		pile.visible = false
		pile.modulate.a = 1.0

		var token_texture_path := "res://assets/art/tokens/jeton-%s.png" % pile.sea_key
		if pile.sea_key != "" and ResourceLoader.exists(token_texture_path):
			var token_pile: Node2D = SEA_TOKEN_PILE_SCENE.instantiate()
			token_piles_container.add_child(token_pile)
			token_pile.global_position = slots[i].token_position
			token_pile.setup(pile.sea_key, load(token_texture_path), token_scale, slots[i].rotation)
			token_pile.visible = false

	var hideout_spots := hideout_spots_container.get_children()
	var hideout_angle_offset := 180.0 / _total_seas
	for i in range(hideout_spots.size()):
		var h_angle_degrees = 90.0 + hideout_angle_offset + i * (360.0 / _total_seas)
		var h_angle_rad = deg_to_rad(h_angle_degrees)
		var h_direction := Vector2(cos(h_angle_rad), sin(h_angle_rad))
		hideout_spots[i].global_position = board_center + hideout_radius * h_direction
		hideout_spots[i].rotation_degrees = h_angle_degrees + 90.0
		hideout_spots[i].visible = false

	var fortune_spots := fortune_spots_container.get_children()
	for i in range(fortune_spots.size()):
		var f_angle_degrees = fortune_angle_start_degrees + i * (360.0 / _total_seas)
		var f_angle_rad = deg_to_rad(f_angle_degrees)
		var f_direction := Vector2(cos(f_angle_rad), sin(f_angle_rad))
		fortune_spots[i].global_position = board_center + fortune_radius * f_direction

	GameFlow.players_changed.connect(_refresh_player_boards)
	_refresh_player_boards()

	dealing_phase.finished.connect(func():
		_autosave("hideout")
		hideout_phase.start(self)
	)
	hideout_phase.finished.connect(func():
		_start_round()
		_autosave("pieces")
		piece_placement_phase.start(self)
	)
	piece_placement_phase.finished.connect(func():
		_autosave("cards")
		card_draw_phase.start(self)
	)

	if GameFlow.is_continuing:
		_restore_from_save()
	elif debug_skip_to_pieces:
		narration_box.hide_box()
		deck_area.visible = false
		deck_area.input_pickable = false
		for spot in hideout_spots_container.get_children():
			spot.visible = false
		_start_round()
		piece_placement_phase.start(self)
	elif GameFlow.pending_setup_mode != "":
		deck_area.input_pickable = false
		player_setup_popup.player_confirmed.connect(_on_setup_player_confirmed)
		player_setup_popup.open_for_new_player(GameFlow.players.size() + 1, GameFlow.pending_setup_target_count)
	else:
		dealing_phase.start(self)


func _on_setup_player_confirmed(player_name: String, color: String) -> void:
	GameFlow.add_player(player_name, color)
	if GameFlow.players.size() < GameFlow.pending_setup_target_count:
		player_setup_popup.open_for_new_player(GameFlow.players.size() + 1, GameFlow.pending_setup_target_count)
	else:
		GameFlow.pending_setup_mode = ""
		deck_area.input_pickable = true
		player_setup_popup.visible = false
		dealing_phase.start(self)


func _refresh_player_boards() -> void:
	for child in player_rows.get_children():
		child.queue_free()
	var players: Array[Dictionary] = GameFlow.get_players_sorted_by_points()
	for player in players:
		var row := PLAYER_BOARD_ROW.instantiate()
		player_rows.add_child(row)
		row.populate(player)
		row.pressed.connect(_on_player_board_pressed)
	_build_player_boards_pile(players)
	await get_tree().process_frame
	if player_boards_panel.visible:
		_clamp_player_boards_panel_height()
		player_boards_panel.reset_size()


func _build_player_boards_pile(players: Array) -> void:
	for child in player_boards_pile.get_children():
		child.queue_free()

	var count: int = players.size()
	for i in range(count):
		var thumb := TextureRect.new()
		var pile_board_path: String = GameFlow.PLAYER_BOARD_TEXTURES.get(
			players[i]["color"], GameFlow.PLAYER_BOARD_TEXTURES["jaune"]
		)
		thumb.texture = load(pile_board_path)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.custom_minimum_size = BOARD_THUMB_SIZE
		thumb.size = BOARD_THUMB_SIZE
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.position = PILE_THUMB_OFFSET * i
		player_boards_pile.add_child(thumb)

	var total_size: Vector2 = BOARD_THUMB_SIZE + PILE_THUMB_OFFSET * max(count - 1, 0)
	player_boards_pile.custom_minimum_size = total_size
	player_boards_pile.size = total_size


func _clamp_player_boards_panel_height() -> void:
	var max_height: float = get_viewport_rect().size.y * PLAYER_BOARDS_PANEL_MAX_HEIGHT_RATIO
	var content_min: Vector2 = player_rows.get_minimum_size()
	player_boards_scroll.custom_minimum_size = Vector2(content_min.x, min(content_min.y, max_height))


func _on_player_boards_pile_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_player_boards_panel()


func _on_player_boards_catcher_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_player_boards_panel()


func _open_player_boards_panel() -> void:
	player_boards_pile.visible = false
	player_boards_panel.visible = true
	player_boards_catcher.visible = true
	await get_tree().process_frame
	_clamp_player_boards_panel_height()
	player_boards_panel.reset_size()


func _close_player_boards_panel() -> void:
	player_boards_panel.visible = false
	player_boards_catcher.visible = false
	player_boards_pile.visible = true


func _on_player_board_pressed(player_id: int) -> void:
	for p in GameFlow.players:
		if p["id"] == player_id:
			player_board_expanded.show_player(p)
			return


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		GameFlow.save_players()
		get_tree().quit()


## 2 joueurs -> 1 jeton par pile ; 3-4 joueurs -> 2 jetons ; 5 joueurs -> 3 jetons.
func token_count_for_player_count(player_count: int) -> int:
	if player_count <= 2:
		return 1
	elif player_count <= 4:
		return 2
	return 3


func _start_round() -> void:
	GameFlow.round_number += 1
	if GameFlow.get_first_player_id() == -1:
		GameFlow.set_first_player(GameFlow.players[0]["id"])
	else:
		GameFlow.advance_first_player()

	var last_player_id: int = GameFlow.get_last_player_id()
	if last_player_id != -1:
		_take_fortune_token_for(last_player_id)


func _take_fortune_token_for(player_id: int) -> void:
	var spot: Node2D = null
	for s in fortune_spots_container.get_children():
		if not s.is_taken:
			spot = s
			break
	if spot == null:
		return

	spot.take()
	for p in GameFlow.players:
		if p["id"] == player_id:
			p["special_resources"]["fortune"] += 1
			break
	GameFlow.players_changed.emit()


func _serialize_state(phase: String) -> Dictionary:
	var sea_order: Array = []
	for tile in _slot_order:
		sea_order.append(SEA_KEY_BY_NODE_NAME.get(tile.name, ""))
	var action_spots_data: Array = []
	for spot in action_spots_container.get_children():
		action_spots_data.append(spot.get_pieces_snapshot())
	var hideouts_data: Array = []
	for spot in hideout_spots_container.get_children():
		hideouts_data.append(spot.owner_color if spot.is_taken else "")
	var fortune_data: Array = []
	for spot in fortune_spots_container.get_children():
		fortune_data.append(spot.is_taken)
	return {
		"phase": phase, "sea_order": sea_order, "action_spots": action_spots_data,
		"hideouts": hideouts_data, "fortune_taken": fortune_data,
		"deck_remaining": SeaDecks.get_remaining_counts(),
		"round_number": GameFlow.round_number,
	}

func _autosave(phase: String) -> void:
	GameFlow.autosave(_serialize_state(phase))

func _restore_from_save() -> void:
	var data: Dictionary = GameFlow.take_pending_board_data()
	if data.is_empty():
		dealing_phase.start(self)
		return

	deck_area.visible = false
	deck_area.input_pickable = false
	narration_box.hide_box()

	var board_center: Vector2 = global_position
	var slots: Array = []
	for i in range(_total_seas):
		var angle_degrees = 90.0 + i * (360.0 / _total_seas)
		var angle_rad = deg_to_rad(angle_degrees)
		var direction := Vector2(cos(angle_rad), sin(angle_rad))
		slots.append({
			"global_position": board_center + radius * direction,
			"rotation": angle_degrees + 90.0,
			"pile_position": board_center + (radius + UiTheme.CARD_PILE_RADIUS_OFFSET) * direction,
		})

	var name_to_tile := {}
	for tile in _sea_tiles:
		name_to_tile[SEA_KEY_BY_NODE_NAME.get(tile.name, "")] = tile

	_slot_order = []
	var saved_order: Array = data.get("sea_order", [])
	var deck_remaining: Dictionary = data.get("deck_remaining", {})
	for i in range(saved_order.size()):
		var tile = name_to_tile.get(saved_order[i])
		if tile == null:
			continue
		_slot_order.append(tile)
		tile.global_position = slots[i].global_position
		tile.rotation_degrees = slots[i].rotation
		tile.back_sprite.visible = false
		tile.front_sprite.visible = true

		var pile: Node2D = SEA_CARD_PILE_SCENE.instantiate()
		card_piles_container.add_child(pile)
		pile.global_position = slots[i].pile_position
		pile.rotation_degrees = slots[i].rotation
		pile.sea_key = saved_order[i]
		pile.visible = true
		pile.modulate.a = 1.0
		var remaining: int = deck_remaining.get(saved_order[i], 0)
		var back_path := "res://assets/art/cards/carte-%s-dos.png" % saved_order[i]
		var back_tex: Texture2D = load(back_path) if ResourceLoader.exists(back_path) else preload("res://assets/art/cards/carte-sauvage-dos.png")
		pile.restore_visual_stack(remaining, back_tex)

	SeaDecks.set_remaining(deck_remaining)
	GameFlow.round_number = data.get("round_number", GameFlow.round_number)

	var hideout_spots := hideout_spots_container.get_children()
	var hideouts_data: Array = data.get("hideouts", [])
	for i in range(hideout_spots.size()):
		if i < hideouts_data.size() and hideouts_data[i] != "":
			hideout_spots[i].visible = true
			hideout_spots[i].claim(hideouts_data[i], true)

	var fortune_spots := fortune_spots_container.get_children()
	var fortune_data: Array = data.get("fortune_taken", [])
	for i in range(fortune_spots.size()):
		if i < fortune_data.size() and fortune_data[i]:
			fortune_spots[i].take()

	var action_spots := action_spots_container.get_children()
	var action_data: Array = data.get("action_spots", [])
	for i in range(action_spots.size()):
		if i >= action_data.size():
			continue
		for piece_info in action_data[i]:
			var scene: PackedScene = CAPTAIN_PIECE_SCENE if piece_info["rank"] == GameFlow.PieceRank.CAPTAIN else SECOND_PIECE_SCENE
			var piece: Node2D = scene.instantiate()
			piece.modulate = GameFlow.COLOR_VALUES[piece_info["color"]]
			piece.scale = Vector2.ONE * UiTheme.PIECE_SCALE
			action_spots[i].add_piece(piece, piece_info["color"], piece_info["rank"], false)

	GameFlow.players_changed.connect(_refresh_player_boards)
	_refresh_player_boards()

	hideout_phase.finished.connect(func():
		_start_round()
		_autosave("pieces")
		piece_placement_phase.start(self)
	)
	piece_placement_phase.finished.connect(func():
		_autosave("cards")
		card_draw_phase.start(self)
	)

	match data.get("phase", "cards"):
		"hideout": hideout_phase.resume(self)
		"pieces": piece_placement_phase.resume(self)
		_: card_draw_phase.start(self)
