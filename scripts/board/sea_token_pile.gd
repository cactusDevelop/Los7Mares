extends Node2D

## Pile de jetons "mer" affichée au-dessus d'une tuile mer, avec un rayon
## légèrement plus petit que la tuile. Distribuée en même temps que les
## piles de cartes (cf. DealingPhase). Affiche le nombre de jetons restants
## et se grise quand la pile est vide.

const EMPTY_TINT := Color(0.35, 0.35, 0.35, 1.0)

@onready var token_sprite: Sprite2D = $TokenSprite
@onready var count_label: Label = $CountLabel

var sea_key: String = ""

var remaining_count: int = 0:
	set(value):
		remaining_count = max(value, 0)
		_update_display()


func _ready() -> void:
	_update_display()


## À appeler une fois à la création de la pile (positionnement + texture).
## p_rotation_degrees oriente uniquement le sprite du jeton vers le centre du
## plateau (comme les tuiles mer et les piles de cartes) ; le chiffre du
## compteur reste toujours droit.
func setup(p_sea_key: String, p_texture: Texture2D, p_token_scale: float, p_rotation_degrees: float = 0.0) -> void:
	sea_key = p_sea_key
	token_sprite.texture = p_texture
	token_sprite.scale = Vector2.ONE * p_token_scale
	token_sprite.rotation_degrees = p_rotation_degrees


## Retire un jeton de la pile (pour une mécanique future de prise de jeton).
## Retourne false si la pile est déjà vide.
func take_token() -> bool:
	if remaining_count <= 0:
		return false
	remaining_count -= 1
	return true


func _update_display() -> void:
	if not count_label:
		return
	count_label.text = str(remaining_count)
	modulate = EMPTY_TINT if remaining_count <= 0 else Color.WHITE
