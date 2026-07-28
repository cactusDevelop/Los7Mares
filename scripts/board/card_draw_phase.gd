extends Node

## Au tout début de chaque tour (avant même la pose du capitaine et du
## second), la carte du dessus de chaque pile de mer se retourne
## automatiquement pour révéler son recto, avec un petit délai aléatoire par
## pile pour un effet de révélation naturel et échelonné. Cliquer ensuite sur
## une pile déjà révélée affiche le détail de sa carte en grand.

signal finished

const CARD_FRONT_FALLBACK := preload("res://assets/art/cards/carte-sauvage-ile.png")  # tant qu'aucun art n'existe pour une mer/type
const FLIP_DURATION := 0.6
const FLIP_RANDOM_DELAY_MIN := 0.0
const FLIP_RANDOM_DELAY_MAX := 0.5
const REDRAW_CARD_SCALE := 0.5

var _board: Board
var _revealed_cards: Dictionary = {}     # pile -> GameCard révélé ce tour-ci
var _revealed_textures: Dictionary = {}  # pile -> Texture2D de fond déjà tirée pour ce card
var _pending_pile: Node2D = null


## emit_finished=false (utilisé par le bouton debug "Piocher") : révèle les
## cartes normalement mais n'émet pas "finished", donc n'enchaîne PAS sur la
## pose de pièces (board.gd a connecté ce signal en permanence pour faire
## avancer la partie).
func start(board: Board, emit_finished: bool = true) -> void:
	_board = board
	if not _board.sea_card_popup.card_resolved.is_connected(_on_sea_card_resolved):
		_board.sea_card_popup.card_resolved.connect(_on_sea_card_resolved)

	# Maintenance (règle 7.1) : ne défausser QUE les cartes rencontre
	# restantes. Les cartes île/port déjà révélées restent en place (elles
	# ne sont retirées que lorsqu'une activité les consomme, via
	# action_resolution_phase / redraw_card_for_sea).
	for pile in _revealed_cards.keys().duplicate():
		var revealed: GameCard = _revealed_cards[pile]
		if revealed.card_type == GameCard.CardType.RENCONTRE:
			pile.draw_enabled = false
			pile.pop_top_card()
			pile.hide_id()
			SeaDecks.discard_card(revealed)
			_revealed_cards.erase(pile)
			_revealed_textures.erase(pile)

	var piles := _board.card_piles_container.get_children()
	var flip_duration: float = Settings.anim_duration(FLIP_DURATION)
	var flips_remaining := [0]

	for pile in piles:
		if not pile.pile_clicked.is_connected(_on_card_pile_clicked):
			pile.pile_clicked.connect(_on_card_pile_clicked)
		# Règle 7.2 : ne révéler une nouvelle carte que dans les mers qui
		# n'en ont pas encore (île/port conservées ci-dessus sont sautées).
		if _revealed_cards.has(pile):
			continue
		var card: GameCard = SeaDecks.draw_card(pile.sea_key)
		if card == null:
			continue
		_revealed_cards[pile] = card
		var front_texture: Texture2D = card.get_random_background()
		if front_texture == null:
			front_texture = CARD_FRONT_FALLBACK
		_revealed_textures[pile] = front_texture
		flips_remaining[0] += 1
		var delay: float = Settings.anim_duration(randf_range(FLIP_RANDOM_DELAY_MIN, FLIP_RANDOM_DELAY_MAX))
		var timer := get_tree().create_timer(delay)
		timer.timeout.connect(func():
			pile.flip_top_card(front_texture, flip_duration)
			pile.show_id(card.id)
			pile.draw_enabled = true
			flips_remaining[0] -= 1
			if flips_remaining[0] == 0:
				_finish_phase(emit_finished)
		)

	if flips_remaining[0] == 0:
		_finish_phase(emit_finished)


## Renvoie la GameCard actuellement révélée pour une mer donnée (utilisé par
## action_resolution_phase pour les actions île/port), ou null si la mer n'a
## pas de carte révélée (pioche+défausse vides) ou n'existe pas.
func get_current_revealed_card(sea_key: String) -> GameCard:
	for pile in _revealed_cards.keys():
		if pile.sea_key == sea_key:
			return _revealed_cards[pile]
	return null


## Consultation (facultative) du détail d'une carte déjà révélée sur sa pile.
## Toujours possible, même si des boutons de choix sont affichés dans
## narration_box (résolution d'action en cours) : on n'appelle alors PAS
## hide_box() pour ne pas effacer ces boutons sous un await en attente
## ailleurs (ex: action_resolution_phase). sea_card_popup est un panneau
## autonome (son propre fond + bouton RETOUR) qui n'interagit jamais avec
## narration_box.option_selected, donc l'ouvrir par-dessus un choix en
## attente ne casse rien : le joueur peut consulter la carte puis revenir
## cliquer le bouton toujours affiché.
func _on_card_pile_clicked(pile: Node2D) -> void:
	if _pending_pile != null or not _revealed_cards.has(pile):
		return
	_pending_pile = pile
	pile.hover_prompt.hide_prompt()
	if not _board.narration_box.has_options():
		_board.narration_box.hide_box()
	_board.sea_card_popup.show_card(_revealed_cards[pile], _revealed_textures[pile])


func _on_sea_card_resolved(_card: GameCard) -> void:
	_pending_pile = null


func _finish_phase(emit_finished: bool = true) -> void:
	if emit_finished:
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
		pile.hide_id()
		SeaDecks.discard_card(_revealed_cards[pile])
		_revealed_cards.erase(pile)
		_revealed_textures.erase(pile)

	var card: GameCard = SeaDecks.draw_card(sea_key)
	if card == null:
		return

	var back_path := "res://assets/art/cards/carte-%s-dos.png" % sea_key
	var back_texture: Texture2D = load(back_path) if ResourceLoader.exists(back_path) else preload("res://assets/art/cards/carte-sauvage-dos.png")
	var visual_card: Sprite2D = pile.add_visual_card(back_texture, Vector2.ZERO)
	visual_card.scale = Vector2.ONE * REDRAW_CARD_SCALE

	var front_texture: Texture2D = card.get_random_background()
	if front_texture == null:
		front_texture = CARD_FRONT_FALLBACK

	_revealed_cards[pile] = card
	_revealed_textures[pile] = front_texture
	pile.draw_enabled = true
	pile.flip_top_card(front_texture, Settings.anim_duration(FLIP_DURATION))
	pile.show_id(card.id)
