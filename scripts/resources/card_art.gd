class_name CardArt
extends RefCounted

## Résout les textures d'une carte (icône de type, image de fond) à partir
## d'une convention de nommage dans assets/art/cards, pour ne pas avoir à
## lister chaque fichier à la main. Quand un nouvel asset
## "carte-{mer}-{suffixe}{n}.png" est ajouté, il est automatiquement pris en
## compte par get_background_pool()/get_random_background() sans toucher au
## code.

const CARDS_DIR := "res://assets/art/cards/"
const MAX_VARIANTS := 9  # nombre max de variantes numérotées cherchées (ex: recontre1..9)

const TYPE_ICON_PATHS := {
	GameCard.CardType.ILE: CARDS_DIR + "icon-ile.png",
	GameCard.CardType.PORT: CARDS_DIR + "icon-port.png",
	GameCard.CardType.RENCONTRE: CARDS_DIR + "icon-rencontre.png",
}

## Bases de nom de fichier possibles pour chaque type de carte. "recontre"
## reprend l'orthographe déjà utilisée dans les assets du dépôt.
const TYPE_NAME_BASES := {
	GameCard.CardType.ILE: ["ile"],
	GameCard.CardType.PORT: ["port", "marchand"],
	GameCard.CardType.RENCONTRE: ["recontre"],
}


static func get_icon(card_type: GameCard.CardType) -> Texture2D:
	var path: String = TYPE_ICON_PATHS.get(card_type, "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path)


## Retourne toutes les images de fond disponibles pour une mer + un type de
## carte donnés (ex: "sauvage" + RENCONTRE -> carte-sauvage-recontre1..5.png).
static func get_background_pool(sea_key: String, card_type: GameCard.CardType) -> Array[Texture2D]:
	var pool: Array[Texture2D] = []
	if sea_key == "":
		return pool
	for base in TYPE_NAME_BASES.get(card_type, []):
		var single_path := "%scarte-%s-%s.png" % [CARDS_DIR, sea_key, base]
		if ResourceLoader.exists(single_path):
			pool.append(load(single_path))
		for n in range(1, MAX_VARIANTS + 1):
			var numbered_path := "%scarte-%s-%s%d.png" % [CARDS_DIR, sea_key, base, n]
			if ResourceLoader.exists(numbered_path):
				pool.append(load(numbered_path))
	return pool


## Choisit une image de fond au hasard parmi celles disponibles. Retourne
## null si aucun asset ne correspond encore (mer/type pas encore illustré).
static func get_random_background(sea_key: String, card_type: GameCard.CardType) -> Texture2D:
	var pool := get_background_pool(sea_key, card_type)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]
