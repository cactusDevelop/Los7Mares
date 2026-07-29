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

## Bases de nom de fichier possibles pour chaque type de carte.
const TYPE_NAME_BASES := {
	GameCard.CardType.ILE: ["ile"],
	GameCard.CardType.PORT: ["port"],
}

## Les cartes RENCONTRE n'ont plus un nom de fichier générique ("recontre1..5")
## depuis leur renommage : chaque titre a maintenant son propre suffixe
## (ex: carte-glace-creature1.png, carte-glace-creature2.png). On résout donc
## la base à partir du titre de la carte plutôt que de son seul type.
const RENCONTRE_TITLE_BASES := {
	"Bateau pirate": ["pirate"],
	"Bateau marchand": ["marchand"],
	"Capitaine pirate": ["capitaine"],
	"Créature des mers": ["creature"],
	"Géant des mers": ["geant"],
	"Menace météo": ["meteo"],
	"Flotte marchande": ["flotte"],
}


static func get_icon(card_type: GameCard.CardType) -> Texture2D:
	var path: String = TYPE_ICON_PATHS.get(card_type, "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path)


## Retourne toutes les images de fond disponibles pour une mer + un type de
## carte donnés (ex: "glace" + RENCONTRE + "Créature des mers" ->
## carte-glace-creature1.png, carte-glace-creature2.png). Le titre n'est
## nécessaire que pour les cartes RENCONTRE (ile/port n'en ont pas besoin).
static func get_background_pool(
	sea_key: String, card_type: GameCard.CardType, title: String = ""
) -> Array[Texture2D]:
	var pool: Array[Texture2D] = []
	if sea_key == "":
		return pool
	var bases: Array = TYPE_NAME_BASES.get(card_type, [])
	if card_type == GameCard.CardType.RENCONTRE:
		bases = RENCONTRE_TITLE_BASES.get(title, [])
	for base in bases:
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
static func get_random_background(
	sea_key: String, card_type: GameCard.CardType, title: String = ""
) -> Texture2D:
	var pool := get_background_pool(sea_key, card_type, title)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]
