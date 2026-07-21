extends Node

## Gère une pioche (et une défausse) de GameCard pour chacune des 7 mers,
## construites à partir de CardCatalog.DEFINITIONS.

signal card_drawn(sea_key: String, card: GameCard)

const SEA_KEYS: Array[String] = ["abondance", "azur", "feu", "glace", "jade", "maudite", "sauvage"]

var _decks: Dictionary = {}     # sea_key -> Array[GameCard] (pioche, dessus = fin du tableau)
var _discards: Dictionary = {}  # sea_key -> Array[GameCard] (défausse)


func _ready() -> void:
	_build_decks()


func _build_decks() -> void:
	var all_cards: Array[GameCard] = CardCatalog.build_cards()
	for sea_key in SEA_KEYS:
		var deck: Array[GameCard] = []
		for card in all_cards:
			if card.sea_key == sea_key:
				deck.append(card)
		deck.shuffle()
		_decks[sea_key] = deck
		_discards[sea_key] = []


## Pioche la carte du dessus pour une mer donnée. Remélange automatiquement
## la défausse si la pioche est vide. Retourne null si aucune carte n'est
## disponible du tout (pioche ET défausse vides — ex: pas encore de carte
## définie pour cette mer dans CardCatalog).
func draw_card(sea_key: String) -> GameCard:
	if not _decks.has(sea_key):
		return null
	if _decks[sea_key].is_empty():
		if _discards[sea_key].is_empty():
			return null
		_decks[sea_key] = _discards[sea_key].duplicate()
		_decks[sea_key].shuffle()
		_discards[sea_key].clear()

	var card: GameCard = _decks[sea_key].pop_back()
	card_drawn.emit(sea_key, card)
	return card


func discard_card(card: GameCard) -> void:
	if card and _discards.has(card.sea_key):
		_discards[card.sea_key].append(card)


func cards_remaining(sea_key: String) -> int:
	return _decks.get(sea_key, []).size()


func get_remaining_counts() -> Dictionary:
	var out := {}
	for k in SEA_KEYS:
		out[k] = _decks[k].size()
	return out


func set_remaining(counts: Dictionary) -> void:
	for k in counts.keys():
		var target: int = counts[k]
		while _decks.has(k) and _decks[k].size() > target and not _decks[k].is_empty():
			_decks[k].pop_back()
