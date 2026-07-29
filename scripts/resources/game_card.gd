class_name GameCard
extends Resource

## Définition d'une carte de jeu : île, port ou rencontre.
##
## L'icône de type et l'image de fond sont résolues automatiquement à partir
## de card_type et sea_key (voir CardArt) : pas besoin de les assigner à la
## main, il suffit d'ajouter les assets dans assets/art/cards en suivant la
## même convention de nom de fichier.
##
## activity_board référence la "planche" qui symbolise l'activité de la
## carte (jet de dés, etc). Plusieurs cartes peuvent partager la même
## ActivityBoard.
##
## possible_tracks : la ou les pistes (Exploration/Combat/Commerce, règle 3)
## où cette carte peut être rangée une fois l'activité réussie. Une carte
## multi-activité (ex: île amicale) déclare 2 pistes ; le joueur choisit
## alors celle liée à l'activité réellement effectuée (règle 10).

enum CardType { ILE, PORT, RENCONTRE }

## Numéro de la carte dans card_catalog.json (son index dans le tableau,
## qui correspond à la ligne du fichier Excel de référence). Sert
## uniquement de repère visuel temporaire tant que les visuels définitifs
## ne sont pas tous en place (cf GAME_RULES.txt section 14) : affiché en
## gros sur la pile et dans l'aperçu zoomé pour identifier une carte sans
## avoir à ouvrir card_catalog.json.
@export var id: int = -1

@export var card_type: CardType = CardType.RENCONTRE
@export var sea_key: String = ""
@export var activity_board: ActivityBoard
@export var title: String = ""
@export var description: String = ""
@export var possible_tracks: Array[String] = []  # "exploration" / "combat" / "commerce"

## Détail par piste ("exploration"/"commerce"/"combat") des icônes à
## afficher sur la planche d'activité : {"cost": [...], "reward": [...]}
## où chaque élément est {"icon": "bois", "amount": 1} (ou "icons": [...]
## quand plusieurs ressources sont interchangeables, ex: acier/toile).
## Alimenté depuis card_catalog.json, voir CardCatalog._load_definitions().
@export var activities: Dictionary = {}

## Texte brut de l'effet négatif (planche grise) si la carte en a un.
## Pas encore d'icônes dédiées (cf GAME_RULES.txt, section 14 [A FAIRE]).
@export var negative_effect: String = ""


func get_icon() -> Texture2D:
	return CardArt.get_icon(card_type)


func get_random_background() -> Texture2D:
	return CardArt.get_random_background(sea_key, card_type, title)


func get_planche_texture() -> Texture2D:
	return activity_board.texture if activity_board else null
