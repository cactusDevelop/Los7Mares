extends Node

## Les piles de cartes de chaque mer restent visibles face verso. Le joueur
## clique sur une pile pour révéler en grand, sur fond noir, la carte du
## dessus (qui se retourne pour montrer son recto).

const CARD_FRONT_FALLBACK := preload("res://assets/art/cards/carte-sauvage1.png")

var _board: Board
var _cards_enabled: bool = false
var _front_texture_cache: Dictionary = {}
var _pending_pile: Node2D = null


func start(board: Board) -> void:
	_board = board
	_cards_enabled = true
	for pile in _board.card_piles_container.get_children():
		pile.draw_enabled = true
		if not pile.pile_clicked.is_connected(_on_card_pile_clicked):
			pile.pile_clicked.connect(_on_card_pile_clicked)
	if not _board.sea_card_popup.card_resolved.is_connected(_on_sea_card_resolved):
		_board.sea_card_popup.card_resolved.connect(_on_sea_card_resolved)


func _get_card_front_texture(sea_key: String) -> Texture2D:
	if _front_texture_cache.has(sea_key):
		return _front_texture_cache[sea_key]
	var path := "res://assets/art/cards/carte-%s-recto.png" % sea_key
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else CARD_FRONT_FALLBACK
	_front_texture_cache[sea_key] = texture
	return texture


func _on_card_pile_clicked(pile: Node2D) -> void:
	if not _cards_enabled or _pending_pile != null:
		return
	var top_sprite: Sprite2D = pile.get_top_card_sprite()
	if top_sprite == null:
		return
	var card: SeaCard = SeaDecks.draw_card(pile.sea_key)
	if card == null:
		return

	_pending_pile = pile
	pile.hover_prompt.hide_prompt()
	_board.narration_box.hide_box()
	_board.sea_card_popup.show_card(card, top_sprite.texture, _get_card_front_texture(pile.sea_key))


func _on_sea_card_resolved(_card: SeaCard) -> void:
	if _pending_pile:
		_pending_pile.pop_top_card()
		_pending_pile = null
	_board._autosave("cards")
