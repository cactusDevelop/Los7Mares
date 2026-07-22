extends Node

signal finished

const CAPTAIN_SCENE := preload("res://scenes/board/pieces/captain_piece.tscn")
const SECOND_SCENE := preload("res://scenes/board/pieces/second_piece.tscn")
const DEBUG_TOTAL_ROUNDS := 7

var _board: Board
var _current_round: int = 0
var _current_player_index: int = 0
var _selected_rank: int = -1
var _placed_rank_by_player: Dictionary = {}
var _debug_round_index := 0
var _resolving_action := false
var _round_transitioning := false


func start(board: Board) -> void:
	_board = board
	_board.debug_skip_button.visible = GameFlow.is_debug_mode
	_current_round = 0
	_current_player_index = 0
	_placed_rank_by_player.clear()
	_resolving_action = false

	for spot in _board.action_spots_container.get_children():
		spot.clear_pieces()
		if not spot.spot_clicked.is_connected(_on_action_spot_clicked):
			spot.spot_clicked.connect(_on_action_spot_clicked)
		spot.set_hover_enabled(true)
	if not _board.piece_selection_panel.piece_selected.is_connected(_on_piece_selected):
		_board.piece_selection_panel.piece_selected.connect(_on_piece_selected)
	if not _board.piece_selection_panel.piece_drag_ended.is_connected(_on_piece_drag_ended):
		_board.piece_selection_panel.piece_drag_ended.connect(_on_piece_drag_ended)
	if not _board.piece_selection_panel.piece_drag_started.is_connected(_on_piece_drag_started):
		_board.piece_selection_panel.piece_drag_started.connect(_on_piece_drag_started)
	if not _board.piece_selection_panel.piece_drag_stopped.is_connected(_on_piece_drag_stopped):
		_board.piece_selection_panel.piece_drag_stopped.connect(_on_piece_drag_stopped)

	_begin_player_piece_turn()


## Affiche le panneau de sélection de pièce + recadre la caméra sur la zone
## de sélection uniquement quand un tour va effectivement suivre (si la
## phase se termine à la place, on reste sur la vue par défaut : cf le
## "return" avant ces lignes).
func _begin_player_piece_turn() -> void:
	if _current_player_index >= GameFlow.players.size():
		_current_player_index = 0
		_current_round += 1
		if _current_round > 1:
			_end_piece_placement_phase()
			return

	_board.piece_selection_panel.show_for_placement_phase()
	_shift_camera_for_selection(true)

	var player: Dictionary = GameFlow.players[_current_player_index]
	var color: Color = GameFlow.COLOR_VALUES[player["color"]]
	_selected_rank = -1

	if _current_round == 0:
		_board.narration_box.say_with_player(tr("Tour de %s : choisis la pièce à jouer (capitaine ou second)."), player)
		_board.piece_selection_panel.setup_for_player(color, -1)
	else:
		var placed_rank: int = _placed_rank_by_player[_current_player_index]
		var forced_rank: int = GameFlow.PieceRank.SECOND if placed_rank == GameFlow.PieceRank.CAPTAIN else GameFlow.PieceRank.CAPTAIN
		_board.narration_box.say_with_player(tr("Tour de %s : place ta dernière pièce."), player)
		_board.piece_selection_panel.setup_for_player(color, forced_rank)


func _on_piece_selected(rank: int) -> void:
	_selected_rank = rank


## Teinte toutes les cases d'action avec la couleur du joueur courant dès
## qu'il commence à draguer une pièce, pour bien montrer où elle va
## atterrir au survol (en plus du zoom habituel, cf action_spot.gd
## set_drag_hover_color).
func _on_piece_drag_started(_rank: int) -> void:
	var player: Dictionary = GameFlow.players[_current_player_index]
	var color: Color = GameFlow.COLOR_VALUES[player["color"]]
	for spot in _board.action_spots_container.get_children():
		spot.set_drag_hover_color(color)


## Retire la teinte de survol posée par _on_piece_drag_started, que le drag
## se soit terminé par une pose de pièce ou par un simple relâchement.
func _on_piece_drag_stopped() -> void:
	for spot in _board.action_spots_container.get_children():
		spot.set_drag_hover_color(null)


## Pose automatiquement la pièce du joueur courant sur la première case
## action libre (utilisé par le bouton debug "Passer"). Ne fait rien si une
## résolution d'action est déjà en cours (le bouton doit alors agir sur
## narration_box.skip() à la place, cf board.gd).
func force_skip() -> void:
	if _resolving_action or _round_transitioning or _current_player_index >= GameFlow.players.size():
		return
	if _selected_rank == -1:
		if _current_round == 0:
			_selected_rank = GameFlow.PieceRank.CAPTAIN
		else:
			var placed_rank: int = _placed_rank_by_player[_current_player_index]
			_selected_rank = GameFlow.PieceRank.SECOND if placed_rank == GameFlow.PieceRank.CAPTAIN else GameFlow.PieceRank.CAPTAIN

	var player: Dictionary = GameFlow.players[_current_player_index]
	for spot in _board.action_spots_container.get_children():
		if not spot.has_player_piece(player["color"]):
			_on_action_spot_clicked(spot)
			return


## Fin d'un drag démarré dans le panneau et relâché hors de celui-ci
## (piece_selection_panel.gd). On ne pose la pièce que si la souris (pas le
## point-fantôme) touche la collision d'une case au moment du relâchement,
## repéré via action_spot.is_hovering() (même état que l'effet de zoom).
func _on_piece_drag_ended(rank: int) -> void:
	var spot := _find_hovered_spot()
	if spot == null:
		return
	_selected_rank = rank
	_on_action_spot_clicked(spot)


func _find_hovered_spot() -> Node2D:
	for spot in _board.action_spots_container.get_children():
		if spot.is_hovering():
			return spot
	return null


func _on_action_spot_clicked(spot: Node2D) -> void:
	if _selected_rank == -1 or _resolving_action:
		return

	var player: Dictionary = GameFlow.players[_current_player_index]

	if spot.has_player_piece(player["color"]):
		_board.narration_box.say(tr("Tu ne peux pas poser tes deux pièces sur la même case."))
		return

	var piece_scene: PackedScene = CAPTAIN_SCENE if _selected_rank == GameFlow.PieceRank.CAPTAIN else SECOND_SCENE
	var piece: Node2D = piece_scene.instantiate()
	piece.modulate = GameFlow.COLOR_VALUES[player["color"]]
	piece.scale = Vector2.ONE * UiTheme.PIECE_SCALE
	spot.add_piece(piece, player["color"], _selected_rank)
	_board.narration_box.hide_box()

	if _current_round == 0:
		_placed_rank_by_player[_current_player_index] = _selected_rank
	_selected_rank = -1
	_board._autosave("pieces")

	# On quitte la vue "sélection de pièce" (zoom + panneau) dès que la pièce
	# est posée : la résolution d'action (ex. cliquer sur une mer pour le
	# déplacement) a besoin de la vue par défaut sur tout le plateau. On y
	# revient dans _begin_player_piece_turn() pour le joueur suivant.
	_board.piece_selection_panel.hide_panel()
	_shift_camera_for_selection(false)

	var spot_index: int = spot.get_index()
	_resolving_action = true
	await _board.action_resolution_phase.start(_board, player, spot_index)
	_resolving_action = false

	_current_player_index += 1
	_begin_player_piece_turn()


## Vrai une fois les DEBUG_TOTAL_ROUNDS manches de test écoulées (utilisé par
## board.gd pour arrêter la boucle du bouton debug "Passer").
func is_debug_finished() -> bool:
	return _debug_round_index >= DEBUG_TOTAL_ROUNDS


func _end_piece_placement_phase() -> void:
	for spot in _board.action_spots_container.get_children():
		spot.set_hover_enabled(false)
	_board.piece_selection_panel.hide_panel()
	_shift_camera_for_selection(false)

	if _board.debug_skip_to_pieces:
		_round_transitioning = true
		_debug_round_index += 1
		if _debug_round_index < DEBUG_TOTAL_ROUNDS:
			_board.narration_box.say(tr("Manche %d/%d terminée.") % [_debug_round_index, DEBUG_TOTAL_ROUNDS])
			await get_tree().create_timer(1.0).timeout
			_board.narration_box.hide_box()
			_board._start_round()
			start(_board)
		else:
			_board.narration_box.say(tr("Mode test : 7 tours de pose de pièces terminés."))
		_round_transitioning = false
		return

	_board.debug_skip_button.visible = false
	_board.narration_box.hide_box()
	finished.emit()


func _shift_camera_for_selection(active: bool) -> void:
	var target_pos := _board._camera_base_position + Vector2(UiTheme.CAMERA_SELECTION_SHIFT, 0) if active else _board._camera_base_position
	var target_zoom: Vector2 = UiTheme.CAMERA_SELECTION_ZOOM if active else _board._camera_base_zoom
	_board.tween_camera(target_pos, target_zoom, 0.5)


func resume(board: Board) -> void:
	_board = board
	_board.debug_skip_button.visible = GameFlow.is_debug_mode
	_placed_rank_by_player.clear()
	var total_pieces := 0
	for i in range(GameFlow.players.size()):
		var color: String = GameFlow.players[i]["color"]
		var count := 0
		var known_rank := -1
		for spot in _board.action_spots_container.get_children():
			for p in spot.get_pieces_snapshot():
				if p["color"] == color:
					count += 1
					known_rank = p["rank"]
		total_pieces += count
		if count == 1:
			_placed_rank_by_player[i] = known_rank

	var n: int = GameFlow.players.size()
	_current_round = 0 if total_pieces < n else 1
	_current_player_index = total_pieces if _current_round == 0 else total_pieces - n

	for spot in _board.action_spots_container.get_children():
		if not spot.spot_clicked.is_connected(_on_action_spot_clicked):
			spot.spot_clicked.connect(_on_action_spot_clicked)
		spot.set_hover_enabled(true)
	if not _board.piece_selection_panel.piece_selected.is_connected(_on_piece_selected):
		_board.piece_selection_panel.piece_selected.connect(_on_piece_selected)
	if not _board.piece_selection_panel.piece_drag_ended.is_connected(_on_piece_drag_ended):
		_board.piece_selection_panel.piece_drag_ended.connect(_on_piece_drag_ended)
	if not _board.piece_selection_panel.piece_drag_started.is_connected(_on_piece_drag_started):
		_board.piece_selection_panel.piece_drag_started.connect(_on_piece_drag_started)
	if not _board.piece_selection_panel.piece_drag_stopped.is_connected(_on_piece_drag_stopped):
		_board.piece_selection_panel.piece_drag_stopped.connect(_on_piece_drag_stopped)
	_begin_player_piece_turn()
