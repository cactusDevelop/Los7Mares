extends Node2D
class_name Board

const BOARD_THUMB_SIZE := Vector2(160, 107)
const PILE_THUMB_OFFSET := Vector2(0, 6)
const PLAYER_BOARDS_PANEL_MAX_HEIGHT_RATIO := 0.75

const SEA_CARD_PILE_SCENE := preload("res://scenes/board/sea_card_pile.tscn")
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

@onready var dealing_phase: Node = $DealingPhase
@onready var hideout_phase: Node = $HideoutPhase
@onready var piece_placement_phase: Node = $PiecePlacementPhase
@onready var card_draw_phase: Node = $CardDrawPhase

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

	dealing_phase.finished.connect(func(): hideout_phase.start(self))
	hideout_phase.finished.connect(func():
		_start_round()
		piece_placement_phase.start(self)
	)
	piece_placement_phase.finished.connect(func(): card_draw_phase.start(self))

	if debug_skip_to_pieces:
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
		get_tree().quit()


func _start_round() -> void:
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
