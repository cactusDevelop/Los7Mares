extends Node2D

const DEAL_DELAY = 0.35
const DEAL_DURATION = 0.7
const FLIP_DELAY_AFTER_DEAL = 0.6
const FLIP_WAVE_DELAY = 0.12
const BOARD_THUMB_SIZE := Vector2(160, 107)
const PIECE_DROP_HEIGHT := 220.0
const PIECE_DROP_DURATION := 0.35
const PILE_DROP_HEIGHT := 260.0
const PILE_DROP_DURATION := 0.6
const PILE_DROP_DELAY := 0.18
const CARD_START_JITTER := 0.35
const CARD_MIN_DROP_DURATION := 0.35
const CARDS_PER_PILE := 10
const CARD_STACK_OFFSET := Vector2(0, -2)
const CARD_PILE_STAGGER := 0.05
const PILE_THUMB_OFFSET := Vector2(14, 10)
const PILE_THUMB_ROTATION_DEG := 3.0
const PLAYER_BOARDS_PANEL_MAX_HEIGHT_RATIO := 0.75
const CARD_BACK_FALLBACK := preload("res://assets/art/cards/carte-sauvage-dos.png")
# Les images de cards/ ne sont pas pré-calibrées à l'échelle du monde comme
## celles de board/ : on les réduit avec ce facteur. Ajuste cette valeur
## jusqu'à obtenir la taille de carte voulue.
const CARD_VISUAL_SCALE := 0.5
var _card_back_cache: Dictionary = {}

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
@onready var player_boards_scroll: ScrollContainer = $UI/PlayerBoardsPanel/Scroll
@onready var player_rows: VBoxContainer = $UI/PlayerBoardsPanel/Scroll/Rows
@onready var player_boards_pile: Control = $UI/PlayerBoardsPile
@onready var player_boards_catcher: Control = $UI/PlayerBoardsCatcher
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
	player_boards_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	player_boards_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	player_boards_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	player_boards_panel.position = Vector2(20, 20)
	player_boards_panel.reset_size()
	var panel_style := StyleBoxFlat.new()
	panel_style.set_corner_radius_all(GameFlow.POPUP_CORNER_RADIUS)
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
		pile.visible = false
		pile.modulate.a = 1.0

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
	var players := GameFlow.get_players_sorted_by_points()
	for player in players:
		player_rows.add_child(_build_player_board_row(player))
	_build_player_boards_pile(players)
	await get_tree().process_frame
	player_boards_panel.reset_size()
	_clamp_player_boards_panel_height()


## Construit la pile de plateaux joueur (vue par défaut) : les vignettes se
## superposent avec un léger décalage/rotation pour donner un effet de pile
## de cartes. Un clic n'importe où sur la pile ouvre le panneau détaillé.
func _build_player_boards_pile(players: Array) -> void:
	for child in player_boards_pile.get_children():
		child.queue_free()

	var count: int = players.size()
	for i in range(count):
		var player: Dictionary = players[i]
		var thumb := TextureRect.new()
		thumb.texture = load(GameFlow.PLAYER_BOARD_TEXTURE)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.custom_minimum_size = BOARD_THUMB_SIZE
		thumb.size = BOARD_THUMB_SIZE
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.pivot_offset = BOARD_THUMB_SIZE / 2.0
		thumb.position = PILE_THUMB_OFFSET * i
		thumb.rotation_degrees = (i - float(count - 1) / 2.0) * PILE_THUMB_ROTATION_DEG
		player_boards_pile.add_child(thumb)

	var total_size: Vector2 = BOARD_THUMB_SIZE + PILE_THUMB_OFFSET * max(count - 1, 0)
	player_boards_pile.custom_minimum_size = total_size
	player_boards_pile.size = total_size


## Limite la hauteur du panneau détaillé (via son ScrollContainer) pour
## qu'il ne dépasse jamais l'écran, quel que soit le nombre de joueurs :
## au-delà, un scroll vertical apparaît.
func _clamp_player_boards_panel_height() -> void:
	var max_height: float = get_viewport_rect().size.y * PLAYER_BOARDS_PANEL_MAX_HEIGHT_RATIO
	var content_height: float = player_rows.get_combined_minimum_size().y
	player_boards_scroll.custom_minimum_size.y = min(content_height, max_height)


func _on_player_boards_pile_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_player_boards_panel()


func _on_player_boards_catcher_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_player_boards_panel()


func _open_player_boards_panel() -> void:
	_clamp_player_boards_panel_height()
	player_boards_pile.visible = false
	player_boards_panel.visible = true
	player_boards_catcher.visible = true


func _close_player_boards_panel() -> void:
	player_boards_panel.visible = false
	player_boards_catcher.visible = false
	player_boards_pile.visible = true


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

	var board_wrap := Control.new()
	board_wrap.custom_minimum_size = BOARD_THUMB_SIZE
	board_wrap.size = BOARD_THUMB_SIZE
	board_wrap.clip_contents = true
	board_wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	board_wrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	board_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	board_wrap.gui_input.connect(_on_board_wrap_gui_input.bind(player["id"]))

	var board_texture := TextureRect.new()
	board_texture.texture = load(GameFlow.PLAYER_BOARD_TEXTURE)
	board_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	board_texture.size = BOARD_THUMB_SIZE
	board_texture.custom_minimum_size = BOARD_THUMB_SIZE
	board_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_wrap.add_child(board_texture)
	row.add_child(board_wrap)

	if player.get("has_own_parrot", true):
		row.add_child(_build_parrot_token(player["color"], false))
	for other in GameFlow.players:
		if other.get("parrot_captured_by", -1) == player["id"]:
			row.add_child(_build_parrot_token(other["color"], true))

	entry.add_child(row)
	return entry


func _build_parrot_token(color_name: String, imprisoned: bool) -> Control:
	var texture_rect := TextureRect.new()
	var path_template: String = GameFlow.PARROT_TEXTURE_PATH_PRISON if imprisoned else GameFlow.PARROT_TEXTURE_PATH
	texture_rect.texture = load(path_template % color_name)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.custom_minimum_size = Vector2(40, 40)
	texture_rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	texture_rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return texture_rect


func _on_board_wrap_gui_input(event: InputEvent, player_id: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_player_board_pressed(player_id)


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
	await _drop_card_piles()
	_start_piece_placement_phase()


func _get_card_back_texture(sea_key: String) -> Texture2D:
		if _card_back_cache.has(sea_key):
				return _card_back_cache[sea_key]
		var path := "res://assets/art/cards/carte-%s-dos.png" % sea_key
		var texture: Texture2D = load(path) if ResourceLoader.exists(path) else CARD_BACK_FALLBACK
		_card_back_cache[sea_key] = texture
		return texture


func _drop_card_piles() -> void:
	var piles := card_piles_container.get_children()
	for pile in piles:
		pile.visible = true

	var total_delay := 0.0
	for round_i in range(CARDS_PER_PILE):
		for pile_i in range(piles.size()):
			var pile: Node2D = piles[pile_i]
			var stack_pos: Vector2 = CARD_STACK_OFFSET * round_i
			var card: Sprite2D = pile.add_visual_card(_get_card_back_texture(pile.sea_key), stack_pos)
			card.scale = Vector2.ONE * CARD_VISUAL_SCALE
			var target_global_pos: Vector2 = card.global_position
			card.global_position = target_global_pos - Vector2(0, PILE_DROP_HEIGHT)
			card.modulate.a = 0.0

			var jitter := randf_range(0.0, CARD_START_JITTER)
			var fall_duration: float = max(PILE_DROP_DURATION - jitter, CARD_MIN_DROP_DURATION)
			var start_delay := round_i * PILE_DROP_DELAY + pile_i * CARD_PILE_STAGGER + jitter
			var tween := create_tween()
			tween.tween_interval(start_delay)
			tween.tween_property(card, "global_position", target_global_pos, fall_duration)\
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(card, "modulate:a", 1.0, min(fall_duration * 0.7, fall_duration))

			total_delay = max(total_delay, start_delay + fall_duration)

	await get_tree().create_timer(total_delay).timeout


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
