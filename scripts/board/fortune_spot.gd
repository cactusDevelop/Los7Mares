extends Node2D

## Jeton fortune posé sur le plateau pendant la phase d'intro. Pour l'instant
## ce script ne fait qu'afficher le jeton à sa position ; la prise du jeton
## par le dernier joueur (mécanique de tour) sera ajoutée plus tard.

@onready var token_sprite: Sprite2D = $TokenSprite

var is_taken: bool = false


## Retire visuellement le jeton du plateau (à appeler plus tard quand un
## joueur le prend en début de tour).
func take() -> void:
	is_taken = true
	visible = false
