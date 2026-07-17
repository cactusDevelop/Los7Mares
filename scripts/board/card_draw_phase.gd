extends Node

var _board: Board
var _cards_enabled: bool = false


func start(board: Board) -> void:
	_board = board
	_cards_enabled = true
	for pile in _board.card_piles_container.get_children():
		pile.draw_enabled = true
		if not pile.pile_clicked.is_connected(_on_card_pile_clicked):
			pile.pile_clicked.connect(_on_card_pile_clicked)
	if not _board.sea_card_popup.card_resolved.is_connected(_on_sea_card_resolved):
		_board.sea_card_popup.card_resolved.connect(_on_sea_card_resolved)


func _on_card_pile_clicked(pile: Node2D) -> void:
	if not _cards_enabled:
		return
	var card: SeaCard = SeaDecks.draw_card(pile.sea_key)
	if card:
		_board.narration_box.hide_box()
		_board.sea_card_popup.show_card(card)


func _on_sea_card_resolved(card: SeaCard) -> void:
	_board.narration_box.say(tr(card.title) + " — " + tr(card.description))
	_board._autosave("cards")
