extends Node2D

## Scène de test isolée : parcourt toutes les cartes de CardCatalog pour
## ajuster rapidement le visuel (position des icônes/planche/badges) sans
## repasser par le menu ou le plateau. Lancer avec F6 (jouer la scène
## courante) pendant qu'on édite game_card_view.tscn / icon_badge.tscn.
##
## Flèches gauche/droite ou boutons Précédent/Suivant pour naviguer.

@onready var card_view: GameCardView = $GameCardView
@onready var title_label: Label = $CanvasLayer/UI/TitleLabel
@onready var index_label: Label = $CanvasLayer/UI/IndexLabel

var _cards: Array[GameCard] = []
var _index: int = 0


func _ready() -> void:
	_cards = CardCatalog.build_cards()
	_show_current()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right"):
		_next()
	elif event.is_action_pressed("ui_left"):
		_previous()


func _next() -> void:
	_index = (_index + 1) % _cards.size()
	_show_current()


func _previous() -> void:
	_index = (_index - 1 + _cards.size()) % _cards.size()
	_show_current()


func _show_current() -> void:
	var card := _cards[_index]
	card_view.set_card(card)
	title_label.text = "%s (%s)" % [card.title, card.sea_key]
	index_label.text = "%d / %d" % [_index + 1, _cards.size()]
