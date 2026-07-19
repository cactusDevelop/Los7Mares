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


func start(board: Board) -> void:
	_board = board
	_current_round = 0
	_current_player_index = 0
	_placed_rank_by_player.clear()

	for spot in _board.action_spots_container.get_children():
		if not spot.spot_clicked.is_connected(_on_action_spot_clicked):
			spot.spot_clicked.connect(_on_action_spot_clicked)
		spot.set_hover_enabled(true)
	if not _board.piece_selection_panel.piece_selected.is_connected(_on_piece_selected):
		_board.piece_selection_panel.piece_selected.connect(_on_piece_selected)

	_board.piece_selection_panel.show_for_placement_phase()
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
		_board.narration_box.say_with_player(tr("Tour de %s : choisis la pièce à jouer (capitaine ou second)."), player)
		_board.piece_selection_panel.setup_for_player(color, -1)
	else:
		var placed_rank: int = _placed_rank_by_player[_current_player_index]
		var forced_rank: int = GameFlow.PieceRank.SECOND if placed_rank == GameFlow.PieceRank.CAPTAIN else GameFlow.PieceRank.CAPTAIN
		_board.narration_box.say_with_player(tr("Tour de %s : place ta dernière pièce."), player)
		_board.piece_selection_panel.setup_for_player(color, forced_rank)


func _on_piece_selected(rank: int) -> void:
	_selected_rank = rank


func _on_action_spot_clicked(spot: Node2D) -> void:
	if _selected_rank == -1:
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
	_current_player_index += 1
	_board._autosave("pieces")
	_begin_player_piece_turn()


func _end_piece_placement_phase() -> void:
	for spot in _board.action_spots_container.get_children():
		spot.set_hover_enabled(false)
	_board.piece_selection_panel.hide_panel()
	_shift_camera_for_selection(false)

	if _board.debug_skip_to_pieces:
		_debug_round_index += 1
		if _debug_round_index < DEBUG_TOTAL_ROUNDS:
			_board.narration_box.say(tr("Tour %d/%d terminé.") % [_debug_round_index, DEBUG_TOTAL_ROUNDS])
			await get_tree().create_timer(1.0).timeout
			_board.narration_box.hide_box()
			_board._start_round()
			start(_board)
		else:
			_board.narration_box.say(tr("Mode test : 7 tours de pose de pièces terminés."))
		return

	_board.narration_box.say(tr("Placement terminé — cliquez sur une pioche de mer pour y piocher une carte."))
	finished.emit()


func _shift_camera_for_selection(active: bool) -> void:
	var target_pos := _board._camera_base_position + Vector2(UiTheme.CAMERA_SELECTION_SHIFT, 0) if active else _board._camera_base_position
	var target_zoom: Vector2 = UiTheme.CAMERA_SELECTION_ZOOM if active else _board._camera_base_zoom
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_board.camera, "position", target_pos, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_board.camera, "zoom", target_zoom, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func resume(board: Board) -> void:
	_board = board
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
	_board.piece_selection_panel.show_for_placement_phase()
	_shift_camera_for_selection(true)
	_begin_player_piece_turn()
