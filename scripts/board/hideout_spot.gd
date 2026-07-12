extends Node2D

## Emplacement de cachette autour du plateau central. Modelé sur action_spot.gd
## mais simplifié : un seul joueur peut prendre l'emplacement (pas d'empilement
## de pièces), et le retour visuel au survol utilise le contour (HoverOutline)
## plutôt qu'une teinte de case.

signal spot_clicked(spot: Node2D)

const CACHETTE_TEXTURE_PATH := "res://assets/art/board/cachette-%s.png"

@onready var case_sprite: Sprite2D = $CaseSprite
@onready var click_area: Area2D = $ClickArea
@onready var hover_prompt: Node2D = $HoverPrompt

var hover_enabled: bool = false
var is_taken: bool = false
var owner_color: String = ""


func _ready() -> void:
	click_area.mouse_entered.connect(_on_mouse_entered)
	click_area.mouse_exited.connect(_on_mouse_exited)
	click_area.input_event.connect(_on_input_event)


func _on_mouse_entered() -> void:
	if hover_enabled and not is_taken:
		hover_prompt.show_prompt()


func _on_mouse_exited() -> void:
	hover_prompt.hide_prompt()


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not hover_enabled or is_taken:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		spot_clicked.emit(self)


## Attribue définitivement cet emplacement à un joueur : affiche sa cachette
## colorée et désactive le survol/clic.
func claim(color: String) -> void:
	is_taken = true
	owner_color = color
	case_sprite.texture = load(CACHETTE_TEXTURE_PATH % color)
	case_sprite.modulate = Color(1, 1, 1, 1)
	set_hover_enabled(false)


func set_hover_enabled(enabled: bool) -> void:
	hover_enabled = enabled
	if not enabled:
		hover_prompt.hide_prompt()


## Change la couleur du contour affiché au survol (ex : couleur du joueur
## dont c'est le tour). Blanc par défaut tant que rien n'est précisé.
func set_outline_color(color: Color) -> void:
	hover_prompt.outline_color = color
