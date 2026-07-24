class_name CardCatalog
extends RefCounted

## >>> FICHIER À ÉDITER POUR AJOUTER / MODIFIER LES CARTES DU JEU <
##
## Ajoute une entrée à DEFINITIONS pour chaque carte :
##   - "sea"   : clé de la mer (voir SeaDecks.SEA_KEYS), détermine le pool
##               d'images de fond disponibles pour cette carte.
##   - "type"  : GameCard.CardType.ILE / PORT / RENCONTRE
##   - "planche" : id d'une entrée de ACTIVITY_BOARDS (l'activité de la carte)
##   - "title" / "description" : texte affiché dans le popup de carte
##
## Exemple donné par l'énoncé : une carte rencontre, mer sauvage, planche
## rouge (activité "lancer 3 dés", détaillée plus tard sur l'ActivityBoard) :
##   {"sea": "sauvage", "type": GameCard.CardType.RENCONTRE, "planche": "rouge",
##    "title": "Navire fantôme", "description": "Un navire spectral vous encercle."}
##
## Si "sea" ou "type" ne correspond à aucun asset pour l'instant, la carte
## est quand même construite (icône + planche affichées) mais son fond reste
## vide (get_random_background() retourne null) en attendant l'asset.

const ACTIVITY_BOARDS := {
	"rouge": "res://scripts/resources/data/activity_boards/activity_board_rouge.tres",
	"brune": "res://scripts/resources/data/activity_boards/activity_board_brune.tres",
	"bleue_brune": "res://scripts/resources/data/activity_boards/activity_board_bleue_brune.tres",
}

const DEFINITIONS := [
	{
		"sea": "sauvage", "type": GameCard.CardType.RENCONTRE, "planche": "rouge",
		"title": "Navire fantôme", "description": "Un navire spectral vous encercle. Lancez 3 dés pour tenter de fuir.",
		"tracks": ["combat"],
	},
	{
		"sea": "sauvage", "type": GameCard.CardType.ILE, "planche": "brune",
		"title": "Île abandonnée", "description": "Une île silencieuse apparaît à l'horizon.",
		"tracks": ["exploration", "commerce"],  # île amicale : choix Exploration OU Commerce (règle 9)
	},
	{
		"sea": "sauvage", "type": GameCard.CardType.PORT, "planche": "bleue_brune",
		"title": "Petit port de pêcheurs", "description": "Vous accostez dans un port paisible.",
		"tracks": ["exploration", "commerce"],  # port périlleux : Matelotage + Commerce (règle 9)
	},
]


## Construit les GameCard décrites dans DEFINITIONS. Appelé par les systèmes
## de pioche/plateau qui ont besoin des cartes réelles du jeu.
static func build_cards() -> Array[GameCard]:
	var cards: Array[GameCard] = []
	for def: Dictionary in DEFINITIONS:
		var card := GameCard.new()
		card.card_type = def["type"]
		card.sea_key = def.get("sea", "")
		card.title = def.get("title", "")
		card.description = def.get("description", "")
		var planche_id: String = def.get("planche", "")
		if ACTIVITY_BOARDS.has(planche_id):
			card.activity_board = load(ACTIVITY_BOARDS[planche_id])
		card.possible_tracks.assign(def.get("tracks", []))
		cards.append(card)
	return cards
