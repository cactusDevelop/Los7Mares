extends Node

signal finished

var _board: Board
var _hideout_turn_order: Array = []
var _hideout_turn_index: int = 0


func start(board: Board) -> void:
	_board = board
	_hideout_turn_order = range(GameFlow.players.size() - 1, -1, -1)
	_hideout_turn_index = 0

	for spot in _board.hideout_spots_container.get_children():
		spot.visible = true
		spot.spot_clicked.connect(_on_hideout_spot_clicked)

	_begin_hideout_turn()


func _begin_hideout_turn() -> void:
	if _hideout_turn_index >= _hideout_turn_order.size():
		_end_hideout_phase()
		return

	var player_index: int = _hideout_turn_order[_hideout_turn_index]
	var player: Dictionary = GameFlow.players[player_index]
	var color: Color = GameFlow.COLOR_VALUES[player["color"]]
	_board.narration_box.say_with_player(tr("Tour de %s : choisis l'emplacement de ta cachette."), player)
	for spot in _board.hideout_spots_container.get_children():
		spot.set_hover_enabled(not spot.is_taken)
		spot.set_outline_color(color)


func _on_hideout_spot_clicked(spot: Node2D) -> void:
	var player_index: int = _hideout_turn_order[_hideout_turn_index]
	var player: Dictionary = GameFlow.players[player_index]
	spot.claim(player["color"])
	_board.narration_box.hide_box()
	_hideout_turn_index += 1
	_board._autosave("hideout")
	_begin_hideout_turn()


func _end_hideout_phase() -> void:
	for spot in _board.hideout_spots_container.get_children():
		spot.set_hover_enabled(false)
	finished.emit()


func resume(board: Board) -> void:
	_board = board
	var claimed := 0
	for spot in _board.hideout_spots_container.get_children():
		if spot.is_taken:
			claimed += 1
	_hideout_turn_order = range(GameFlow.players.size() - 1, -1, -1)
	_hideout_turn_index = claimed
	for spot in _board.hideout_spots_container.get_children():
		spot.visible = true
		if not spot.spot_clicked.is_connected(_on_hideout_spot_clicked):
			spot.spot_clicked.connect(_on_hideout_spot_clicked)
	_begin_hideout_turn()
