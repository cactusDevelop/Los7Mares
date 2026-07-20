extends Node

## Au tout début de chaque tour (avant même la pose du capitaine et du
## second), la carte du dessus de chaque pile de mer se retourne
## automatiquement pour révéler son recto, avec un petit délai aléatoire par
## pile pour un effet de révélation naturel et échelonné. Cliquer ensuite sur
## une pile déjà révélée affiche le détail de sa carte en grand.

signal finished

const CARD_FRONT_FALLBACK := preload("res://assets/art/cards/carte-sauvage1.png")
const FLIP_DURATION := 0.6
const FLIP_RANDOM_DELAY_MIN := 0.0
const FLIP_RANDOM_DELAY_MAX := 0.5
const REDRAW_CARD_SCALE := 0.5

var _board: Board
var _front_texture_cache: Dictionary = {}
var _revealed_cards: Dictionary = {}  # pile -> SeaCard révélé ce tour-ci
var _pending_pile: Node2D = null


func start(board: Board) -> void:
	_board = board
	if not _board.sea_card_popup.card_resolved.is_connected(_on_sea_card_resolved):
		_board.sea_card_popup.card_resolved.connect(_on_sea_card_resolved)

	# Retire la carte révélée du tour précédent (le dos redevient visible en dessous).
	for pile in _revealed_cards.keys():
		pile.draw_enabled = false
		pile.pop_top_card()
		SeaDecks.discard_card(_revealed_cards[pile])
	_revealed_cards.clear()

	var piles := _board.card_piles_container.get_children()
	var flip_duration: float = Settings.anim_duration(FLIP_DURATION)
	var flips_remaining := 0

	for pile in piles:
		if not pile.pile_clicked.is_connected(_on_card_pile_clicked):
			pile.pile_clicked.connect(_on_card_pile_clicked)
		var card: SeaCard = SeaDecks.draw_card(pile.sea_key)
		if card == null:
			continue
		_revealed_cards[pile] = card
		flips_remaining += 1
		var delay: float = Settings.anim_duration(randf_range(FLIP_RANDOM_DELAY_MIN, FLIP_RANDOM_DELAY_MAX))
		var front_texture: Texture2D = _get_card_front_texture(pile.sea_key)
		var timer := get_tree().create_timer(delay)
		timer.timeout.connect(func():
			pile.flip_top_card(front_texture, flip_duration)
			pile.draw_enabled = true
			flips_remaining -= 1
			if flips_remaining == 0:
				_finish_phase()
		)

	if flips_remaining == 0:
		_finish_phase()


func _get_card_front_texture(sea_key: String) -> Texture2D:
	if _front_texture_cache.has(sea_key):
		return _front_texture_cache[sea_key]
	var path := "res://assets/art/cards/carte-%s-recto.png" % sea_key
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else CARD_FRONT_FALLBACK
	_front_texture_cache[sea_key] = texture
	return texture


## Consultation (facultative) du détail d'une carte déjà révélée sur sa pile.
func _on_card_pile_clicked(pile: Node2D) -> void:
	if _pending_pile != null or not _revealed_cards.has(pile):
		return
	_pending_pile = pile
	pile.hover_prompt.hide_prompt()
	_board.narration_box.hide_box()
	_board.sea_card_popup.show_card(_revealed_cards[pile], _get_card_front_texture(pile.sea_key))


func _on_sea_card_resolved(_card: SeaCard) -> void:
	_pending_pile = null


func _finish_phase() -> void:
	finished.emit()


## Utilisé par l'action "déplacement" (action_resolution_phase.gd) quand un
## joueur reste sur sa mer actuelle pour piocher une nouvelle carte : défausse
## la carte révélée de cette mer et en révèle une nouvelle à sa place.
func redraw_card_for_sea(sea_key: String) -> void:
	var pile: Node2D = null
	for p in _board.card_piles_container.get_children():
		if p.sea_key == sea_key:
			pile = p
			break
	if pile == null:
		return

	if _revealed_cards.has(pile):
		pile.pop_top_card()
		SeaDecks.discard_card(_revealed_cards[pile])
		_revealed_cards.erase(pile)

	var card: SeaCard = SeaDecks.draw_card(sea_key)
	if card == null:
		return

	var back_path := "res://assets/art/cards/carte-%s-dos.png" % sea_key
	var back_texture: Texture2D = load(back_path) if ResourceLoader.exists(back_path) else preload("res://assets/art/cards/carte-sauvage-dos.png")
	var visual_card: Sprite2D = pile.add_visual_card(back_texture, Vector2.ZERO)
	visual_card.scale = Vector2.ONE * REDRAW_CARD_SCALE

	_revealed_cards[pile] = card
	pile.draw_enabled = true
	pile.flip_top_card(_get_card_front_texture(sea_key), Settings.anim_duration(FLIP_DURATION))
