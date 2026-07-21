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

enum CardType { ILE, PORT, RENCONTRE }

@export var card_type: CardType = CardType.RENCONTRE
@export var sea_key: String = ""
@export var activity_board: ActivityBoard
@export var title: String = ""
@export var description: String = ""


func get_icon() -> Texture2D:
	return CardArt.get_icon(card_type)


func get_random_background() -> Texture2D:
	return CardArt.get_random_background(sea_key, card_type)


func get_planche_texture() -> Texture2D:
	return activity_board.texture if activity_board else null
