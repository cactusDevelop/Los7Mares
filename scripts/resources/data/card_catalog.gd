class_name CardCatalog
extends RefCounted

## >>> LISTE DES CARTES : voir res://scripts/resources/data/card_catalog.json <
##
## Ce script ne contient plus que la logique de construction. Les données
## (une entrée par carte) vivent dans card_catalog.json, un simple tableau
## d'objets qu'on peut regénérer depuis le fichier Excel de référence sans
## toucher au GDScript. Chaque entrée :
##   - "sea"   : clé de la mer (voir SeaDecks.SEA_KEYS), détermine le pool
##               d'images de fond disponibles pour cette carte.
##   - "type"  : "ile" / "port" / "rencontre" (voir TYPE_STRINGS ci-dessous)
##   - "planche" : id d'une entrée de ACTIVITY_BOARDS (l'activité de la carte)
##   - "title" / "description" : texte affiché dans le popup de carte
##   - "tracks" : pistes possibles ("exploration" / "commerce" / "combat")
##
## Si "sea" ou "type" ne correspond à aucun asset pour l'instant, la carte
## est quand même construite (icône + planche affichées) mais son fond reste
## vide (get_random_background() retourne null) en attendant l'asset.

const CATALOG_PATH := "res://scripts/resources/data/card_catalog.json"

const ACTIVITY_BOARDS := {
	"rouge": "res://scripts/resources/data/activity_boards/activity_board_rouge.tres",
	"brune": "res://scripts/resources/data/activity_boards/activity_board_brune.tres",
	"bleue_brune": "res://scripts/resources/data/activity_boards/activity_board_bleue_brune.tres",
	"bleu": "res://scripts/resources/data/activity_boards/activity_board_bleu.tres",
	"bleu_gris": "res://scripts/resources/data/activity_boards/activity_board_bleu_gris.tres",
	"rouge_gris": "res://scripts/resources/data/activity_boards/activity_board_rouge_gris.tres",
	"bleu_rouge_gris": "res://scripts/resources/data/activity_boards/activity_board_bleu_rouge_gris.tres",
}

const TYPE_STRINGS := {
	"ile": GameCard.CardType.ILE,
	"port": GameCard.CardType.PORT,
	"rencontre": GameCard.CardType.RENCONTRE,
}


## Lit et parse card_catalog.json. Retourne un tableau vide (+ erreur dans
## la console) si le fichier est manquant ou mal formé.
static func _load_definitions() -> Array:
	if not FileAccess.file_exists(CATALOG_PATH):
		push_error("CardCatalog: fichier introuvable: %s" % CATALOG_PATH)
		return []

	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	var text := file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		push_error("CardCatalog: JSON invalide dans %s" % CATALOG_PATH)
		return []
	return parsed


## Construit les GameCard décrites dans card_catalog.json. Appelé par les
## systèmes de pioche/plateau qui ont besoin des cartes réelles du jeu.
static func build_cards() -> Array[GameCard]:
	var cards: Array[GameCard] = []
	var definitions: Array = _load_definitions()
	for i in range(definitions.size()):
		var def: Dictionary = definitions[i]
		var card := GameCard.new()
		card.id = i
		var type_key: String = def.get("type", "rencontre")
		card.card_type = TYPE_STRINGS.get(type_key, GameCard.CardType.RENCONTRE)
		card.sea_key = def.get("sea", "")
		card.title = def.get("title", "")
		card.description = def.get("description", "")
		card.activities = def.get("activities", {})
		card.negative_effect = def.get("negative_effect", "") if def.get("negative_effect") != null else ""
		var planche_id: String = def.get("planche", "")
		if ACTIVITY_BOARDS.has(planche_id):
			card.activity_board = load(ACTIVITY_BOARDS[planche_id])
		var tracks: Array[String] = []
		tracks.assign(def.get("tracks", []))
		card.possible_tracks = tracks
		cards.append(card)
	return cards
