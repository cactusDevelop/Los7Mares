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
@onready var boat_markers_container: Node2D = $BoatMarkers

@onready var action_resolution_phase: Node = $ActionResolutionPhase

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
var _sea_marker_positions: Dictionary = {}  # sea_key -> Vector2 (position du jeton de bateau)
var _boat_markers: Dictionary = {}  # player_id -> Node2D (boat_piece détaché de la cachette)
var _boats_by_sea: Dictionary = {}  # sea_key -> Array[int] (ids des joueurs dont le bateau est sur cette mer, pour la répartition en cercle)

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
			"boat_position": board_center + (radius + token_pile_radius_offset + BOAT_MARKER_RADIUS_BONUS) * direction,
		})

	_slot_order = _sea_tiles.duplicate()
	_slot_order.shuffle()
	for i in range(_slot_order.size()):
		var tile = _slot_order[i]
		tile.set_meta("target_global_position", slots[i].global_position)
		tile.set_meta("target_rotation", slots[i].rotation)
		tile.sea_key = SEA_KEY_BY_NODE_NAME.get(tile.name, "")

		var pile: Node2D = SEA_CARD_PILE_SCENE.instantiate()
		card_piles_container.add_child(pile)
		pile.global_position = slots[i].pile_position
		pile.rotation_degrees = slots[i].rotation
		pile.sea_key = SEA_KEY_BY_NODE_NAME.get(tile.name, "")
		pile.visible = false
		pile.modulate.a = 1.0
		_sea_marker_positions[pile.sea_key] = slots[i].boat_position

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
		_autosave("cards")
		await piece_selection_panel.play_turn_announcement(GameFlow.round_number)
		card_draw_phase.start(self)
	)
	card_draw_phase.finished.connect(func():
		_autosave("pieces")
		piece_placement_phase.start(self)
	)
	piece_placement_phase.finished.connect(_on_round_finished)

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


## Appelé quand tous les joueurs ont posé et résolu leurs deux pièces
## (piece_placement_phase.finished) : enchaîne directement sur le tour
## suivant (nouvelles cartes de mer révélées, puis pose de pièces), ou
## termine la partie s'il ne reste plus aucun jeton sur les mers.
func _on_round_finished() -> void:
	_autosave("pieces")
	if _all_sea_tokens_taken():
		_end_game()
		return
	_start_round()
	await piece_selection_panel.play_turn_announcement(GameFlow.round_number)
	card_draw_phase.start(self)


func _all_sea_tokens_taken() -> bool:
	for pile in token_piles_container.get_children():
		if pile.remaining_count > 0:
			return false
	return true


## Fin de partie minimale : affiche le classement final. À étoffer plus
## tard avec un vrai écran de fin si besoin.
func _end_game() -> void:
	var ranking: Array[Dictionary] = GameFlow.get_players_sorted_by_points()
	var lines: PackedStringArray = []
	for i in range(ranking.size()):
		lines.append("%d. %s — %d pts" % [i + 1, ranking[i]["name"], ranking[i]["points"]])
	narration_box.say(tr("Partie terminée ! Classement final :\n") + "\n".join(lines))


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


## Index (0..6) de la cachette appartenant à un joueur, ou -1 si aucune.
func hideout_index_for_color(color: String) -> int:
	var spots := hideout_spots_container.get_children()
	for i in range(spots.size()):
		if spots[i].is_taken and spots[i].owner_color == color:
			return i
	return -1


## Chaque cachette est positionnée exactement entre deux mers voisines dans
## l'ordre circulaire _slot_order (cf. _ready : angle de la cachette i =
## angle de la mer i + un demi-pas). La cachette d'index i est donc toujours
## adjacente aux mers d'index i et i+1 de _slot_order.
func adjacent_seas_for_hideout(hideout_index: int) -> Array[String]:
	var n := _slot_order.size()
	if n == 0 or hideout_index < 0:
		var empty: Array[String] = []
		return empty
	var result: Array[String] = [
		SEA_KEY_BY_NODE_NAME.get(_slot_order[hideout_index].name, ""),
		SEA_KEY_BY_NODE_NAME.get(_slot_order[(hideout_index + 1) % n].name, ""),
	]
	return result


## Les deux mers voisines d'une mer donnée sur le cercle _slot_order.
func adjacent_seas_for_sea(sea_key: String) -> Array[String]:
	var n := _slot_order.size()
	var idx := -1
	for i in range(n):
		if SEA_KEY_BY_NODE_NAME.get(_slot_order[i].name, "") == sea_key:
			idx = i
			break
	if idx == -1:
		var empty: Array[String] = []
		return empty
	var result: Array[String] = [
		SEA_KEY_BY_NODE_NAME.get(_slot_order[(idx - 1 + n) % n].name, ""),
		SEA_KEY_BY_NODE_NAME.get(_slot_order[(idx + 1) % n].name, ""),
	]
	return result


## Retourne la tuile SeaTile (scripts/board/sea_tile.gd) correspondant à une
## clé de mer, pour activer son survol/clic (action "déplacement").
func get_sea_tile_by_key(sea_key: String) -> Node2D:
	for tile in _slot_order:
		if tile.sea_key == sea_key:
			return tile
	return null


func get_sea_marker_position(sea_key: String) -> Vector2:
	return _sea_marker_positions.get(sea_key, global_position)


## Déplace le bateau d'un joueur vers une mer (action "déplacement",
## action_resolution_phase.gd) : met à jour sa position logique et son
## marqueur visuel sur le plateau.
func move_player_boat(player: Dictionary, sea_key: String) -> void:
	var old_sea: String = player.get("boat_sea", "")
	player["boat_sea"] = sea_key
	_update_boat_marker(player, old_sea)
	GameFlow.players_changed.emit()


const BOAT_MARKER_SPREAD := 260.0
## Ajouté à token_pile_radius_offset pour que le bateau navigue plus loin du
## centre que les piles de jetons (sur la mer elle-même, pas entre mer et
## centre).
const BOAT_MARKER_RADIUS_BONUS := 480.0
const BOAT_SAIL_DURATION := 0.6

## Déplace le VRAI bateau du joueur (celui créé dans hideout_spot.gd, avec
## son effet d'épaisseur 3D) au lieu d'en recréer un nouveau à chaque fois :
## au premier déplacement, on le détache de sa cachette (detach_boat) puis
## on le reparente sur le plateau ; ensuite on anime juste sa position d'une
## mer à l'autre. Taille, couleur et effet 3D restent donc identiques à ce
## qu'affichait la cachette. old_sea permet de retirer le joueur de la liste
## d'occupation de la mer qu'il quitte, pour reformer son cercle.
func _update_boat_marker(player: Dictionary, old_sea: String = "") -> void:
	var sea_key: String = player.get("boat_sea", "")
	var pid: int = player["id"]
	if sea_key == "":
		return

	if old_sea != "" and old_sea != sea_key and _boats_by_sea.has(old_sea):
		_boats_by_sea[old_sea].erase(pid)
		_relayout_boats(old_sea)

	var list: Array = _boats_by_sea.get(sea_key, [])
	if not list.has(pid):
		list.append(pid)
	_boats_by_sea[sea_key] = list

	var piece: Node2D = _boat_markers.get(pid)
	if piece == null:
		var hideout_index: int = hideout_index_for_color(player["color"])
		if hideout_index == -1:
			return
		var spot = hideout_spots_container.get_children()[hideout_index]
		if spot.boat_piece == null:
			return
		piece = spot.detach_boat()
		piece.reparent(boat_markers_container, true)
		piece.z_index = 5
		_boat_markers[pid] = piece

	_relayout_boats(sea_key)


## Range en cercle (même principe que GameFlow.layout_positions_for_case
## pour les pièces sur les action spots, avec un espacement plus grand
## adapté à la taille des bateaux) tous les bateaux actuellement sur une
## même mer, pour qu'ils ne se superposent jamais.
func _relayout_boats(sea_key: String) -> void:
	var list: Array = _boats_by_sea.get(sea_key, [])
	if list.is_empty():
		return
	var center: Vector2 = get_sea_marker_position(sea_key)
	var offsets: Array[Vector2] = GameFlow.layout_positions_for_case(list.size(), BOAT_MARKER_SPREAD, Vector2.ZERO)
	for i in range(list.size()):
		var piece: Node2D = _boat_markers.get(list[i])
		if piece == null:
			continue
		var tween := create_tween()
		tween.tween_property(piece, "global_position", center + offsets[i], Settings.anim_duration(BOAT_SAIL_DURATION))\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Symétrique de detach_boat (hideout_spot.gd) : fait rentrer le bateau du
## joueur dans sa cachette (action "déplacement" quand la mer actuelle est
## adjacente à sa cachette). Reparente le VRAI bateau (garde son apparence)
## et l'anime vers la position d'origine à l'intérieur de la cachette ;
## celle-ci redevient ensuite capable de le détacher à nouveau normalement.
func move_boat_to_hideout(player: Dictionary) -> void:
	var old_sea: String = player.get("boat_sea", "")
	var pid: int = player["id"]
	player["boat_sea"] = ""

	if old_sea != "" and _boats_by_sea.has(old_sea):
		_boats_by_sea[old_sea].erase(pid)
		_relayout_boats(old_sea)

	var piece: Node2D = _boat_markers.get(pid)
	if piece == null:
		GameFlow.players_changed.emit()
		return
	var hideout_index: int = hideout_index_for_color(player["color"])
	if hideout_index == -1:
		GameFlow.players_changed.emit()
		return

	var spot = hideout_spots_container.get_children()[hideout_index]
	_boat_markers.erase(pid)
	piece.z_index = 0
	piece.reparent(spot, true)
	spot.boat_piece = piece

	var tween := create_tween()
	tween.tween_property(piece, "position", Vector2.ZERO, Settings.anim_duration(BOAT_SAIL_DURATION))\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
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
	var token_remaining: Dictionary = {}
	for token_pile in token_piles_container.get_children():
		token_remaining[token_pile.sea_key] = token_pile.remaining_count
	return {
		"phase": phase, "sea_order": sea_order, "action_spots": action_spots_data,
		"hideouts": hideouts_data, "fortune_taken": fortune_data,
		"deck_remaining": SeaDecks.get_remaining_counts(),
		"token_remaining": token_remaining,
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
			"token_position": board_center + (radius + token_pile_radius_offset) * direction,
			"boat_position": board_center + (radius + token_pile_radius_offset + BOAT_MARKER_RADIUS_BONUS) * direction,
		})

	# Les piles de jetons ont été créées dans _ready() selon un tirage aléatoire
	# qui n'a rien à voir avec l'ordre restauré ci-dessous : on les recrée donc
	# ici pour qu'elles soient positionnées sur la bonne mer et avec le bon
	# nombre de jetons restants.
	for child in token_piles_container.get_children():
		child.queue_free()

	var name_to_tile := {}
	for tile in _sea_tiles:
		name_to_tile[SEA_KEY_BY_NODE_NAME.get(tile.name, "")] = tile

	_slot_order = []
	var saved_order: Array = data.get("sea_order", [])
	var deck_remaining: Dictionary = data.get("deck_remaining", {})
	var token_remaining: Dictionary = data.get("token_remaining", {})
	for i in range(saved_order.size()):
		var tile = name_to_tile.get(saved_order[i])
		if tile == null:
			continue
		_slot_order.append(tile)
		tile.global_position = slots[i].global_position
		tile.rotation_degrees = slots[i].rotation
		tile.sea_key = saved_order[i]
		tile.back_sprite.visible = false
		tile.front_sprite.visible = true

		var pile: Node2D = SEA_CARD_PILE_SCENE.instantiate()
		card_piles_container.add_child(pile)
		pile.global_position = slots[i].pile_position
		pile.rotation_degrees = slots[i].rotation
		pile.sea_key = saved_order[i]
		pile.visible = true
		pile.modulate.a = 1.0
		_sea_marker_positions[pile.sea_key] = slots[i].boat_position
		var remaining: int = deck_remaining.get(saved_order[i], 0)
		var back_path := "res://assets/art/cards/carte-%s-dos.png" % saved_order[i]
		var back_tex: Texture2D = load(back_path) if ResourceLoader.exists(back_path) else preload("res://assets/art/cards/carte-sauvage-dos.png")
		pile.restore_visual_stack(remaining, back_tex)

		var token_texture_path := "res://assets/art/tokens/jeton-%s.png" % saved_order[i]
		if ResourceLoader.exists(token_texture_path):
			var token_pile: Node2D = SEA_TOKEN_PILE_SCENE.instantiate()
			token_piles_container.add_child(token_pile)
			token_pile.global_position = slots[i].token_position
			token_pile.setup(saved_order[i], load(token_texture_path), token_scale, slots[i].rotation)
			token_pile.visible = true
			# Rétrocompatibilité : si la sauvegarde ne contient pas encore
			# "token_remaining" (ancienne version), on retombe sur le nombre
			# de jetons initial correspondant au nombre de joueurs.
			token_pile.remaining_count = token_remaining.get(
				saved_order[i], token_count_for_player_count(GameFlow.players.size())
			)

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
	for p in GameFlow.players:
		_update_boat_marker(p)

	hideout_phase.finished.connect(func():
		_start_round()
		_autosave("cards")
		card_draw_phase.start(self)
	)
	card_draw_phase.finished.connect(func():
		_autosave("pieces")
		piece_placement_phase.start(self)
	)
	piece_placement_phase.finished.connect(_on_round_finished)

	match data.get("phase", "cards"):
		"hideout": hideout_phase.resume(self)
		"pieces": piece_placement_phase.resume(self)
		_: card_draw_phase.start(self)
