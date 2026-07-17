extends Node

## Gère une pioche (et une défausse) de SeaCard pour chacune des 7 mers.
## Contenu générique pour l'instant : à remplacer par les vraies cartes du
## jeu (cf. templates dans _build_generic_decks) une fois disponibles.

signal card_drawn(sea_key: String, card: SeaCard)

const SEA_KEYS: Array[String] = ["abondance", "azur", "feu", "glace", "jade", "maudite", "sauvage"]
const CARDS_PER_SEA := 6  # nombre de cartes générées par mer (placeholder)

var _decks: Dictionary = {}     # sea_key -> Array[SeaCard] (pioche, dessus = fin du tableau)
var _discards: Dictionary = {}  # sea_key -> Array[SeaCard] (défausse)


func _ready() -> void:
	_build_generic_decks()


func _build_generic_decks() -> void:
	var templates: Array[Dictionary] = [
		{"type": SeaCard.CardType.TRESOR, "title": "Coffre échoué", "description": "Vous trouvez un petit trésor caché sur cette mer."},
		{"type": SeaCard.CardType.RENCONTRE, "title": "Navire marchand", "description": "Un navire marchand vous propose un échange."},
		{"type": SeaCard.CardType.TEMPETE, "title": "Grain soudain", "description": "Une tempête menace votre équipage."},
		{"type": SeaCard.CardType.COMMERCE, "title": "Comptoir isolé", "description": "Un petit comptoir de commerce accepte vos marchandises."},
		{"type": SeaCard.CardType.RENCONTRE, "title": "Épave mystérieuse", "description": "Les restes d'un naufrage flottent non loin."},
		{"type": SeaCard.CardType.TRESOR, "title": "Perle rare", "description": "Une perle magnifique brille sous la surface."},
	]

	for sea_key in SEA_KEYS:
		var deck: Array[SeaCard] = []
		for i in range(CARDS_PER_SEA):
			var tpl: Dictionary = templates[i % templates.size()]
			var card := SeaCard.new()
			card.sea_key = sea_key
			card.type = tpl["type"]
			card.title = tpl["title"]
			card.description = tpl["description"]
			deck.append(card)
		deck.shuffle()
		_decks[sea_key] = deck
		_discards[sea_key] = []


## Pioche la carte du dessus pour une mer donnée. Remélange automatiquement
## la défausse si la pioche est vide. Retourne null si aucune carte n'est
## disponible du tout (pioche ET défausse vides).
func draw_card(sea_key: String) -> SeaCard:
	if not _decks.has(sea_key):
		return null
	if _decks[sea_key].is_empty():
		if _discards[sea_key].is_empty():
			return null
		_decks[sea_key] = _discards[sea_key].duplicate()
		_decks[sea_key].shuffle()
		_discards[sea_key].clear()

	var card: SeaCard = _decks[sea_key].pop_back()
	card_drawn.emit(sea_key, card)
	return card


func discard_card(card: SeaCard) -> void:
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
