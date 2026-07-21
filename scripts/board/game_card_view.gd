extends Node2D

## Assemble visuellement une GameCard : fond, icône de type, planche
## d'activité. ActivityDetails est un emplacement vide pour plus tard (dés,
## chiffres, symboles), une fois ces assets disponibles.

@onready var background: Sprite2D = $Background
@onready var icon: Sprite2D = $Icon
@onready var planche: Sprite2D = $Planche
@onready var activity_details: Node2D = $ActivityDetails


func set_card(card: GameCard) -> void:
	background.texture = card.get_random_background()
	icon.texture = card.get_icon()
	planche.texture = card.get_planche_texture()
