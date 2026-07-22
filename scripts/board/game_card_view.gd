class_name GameCardView
extends Node2D

## Assemble visuellement une GameCard : fond, icône de type, planche
## d'activité. ActivityDetails est un emplacement vide pour plus tard (dés,
## chiffres, symboles), une fois ces assets disponibles.
##
## Fond, icône et planche sont des Sprite2D affichés à leur taille native
## (pas de stretch/crop) : leurs transforms respectifs se règlent à l'oeil
## dans l'éditeur pour les aligner sur l'artwork du fond.

@onready var background: Sprite2D = $Background
@onready var icon: Sprite2D = $Icon
@onready var planche: Sprite2D = $Planche
@onready var activity_details: Node2D = $ActivityDetails


## background_override permet d'imposer une texture de fond précise (carte
## déjà révélée) plutôt que d'en tirer une au hasard.
func set_card(card: GameCard, background_override: Texture2D = null) -> void:
	background.texture = background_override if background_override else card.get_random_background()
	icon.texture = card.get_icon()
	planche.texture = card.get_planche_texture()


## Taille native (non mise à l'échelle) du fond de carte, utile pour calculer
## un scale d'ajustement (aspect-fit, sans crop) depuis l'extérieur.
func get_native_size() -> Vector2:
	return background.texture.get_size() if background.texture else Vector2.ZERO
