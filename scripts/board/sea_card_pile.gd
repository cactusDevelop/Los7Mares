extends Node2D

## Pioche de cartes affichée à côté d'une mer sur le plateau. Les cartes
## restent face verso, visibles et empilées. Un clic sur la pile affiche en
## grand la carte du dessus sur fond noir (cf. SeaCardPopup), qui se retourne
## alors pour révéler son recto.

signal pile_clicked(pile: Node2D)

@onready var click_area: Area2D = $ClickArea
@onready var hover_prompt: Node2D = $HoverPrompt
@onready var cards_container: Node2D = $Cards

var sea_key: String = ""
var draw_enabled: bool = false


func _ready() -> void:
	click_area.mouse_entered.connect(_on_mouse_entered)
	click_area.mouse_exited.connect(_on_mouse_exited)
	click_area.input_event.connect(_on_input_event)


## Crée une carte visuelle (dos face visible) dans la pile, prête à être animée.
## Ne contient aucune information de jeu : sert uniquement à l'animation de distribution.
func add_visual_card(texture: Texture2D, stack_position: Vector2) -> Sprite2D:
	var card := Sprite2D.new()
	card.texture = texture
	card.centered = true
	cards_container.add_child(card)
	card.position = stack_position
	return card


## Sprite de la carte du dessus de la pile (celle qui sera révélée), sans la retirer.
func get_top_card_sprite() -> Sprite2D:
	if cards_container.get_child_count() == 0:
		return null
	return cards_container.get_child(cards_container.get_child_count() - 1)


## Retire visuellement la carte du dessus une fois qu'elle a été résolue
## (après fermeture du grand affichage).
func pop_top_card() -> void:
	var top := get_top_card_sprite()
	if top:
		top.queue_free()


func _on_mouse_entered() -> void:
	if draw_enabled:
		hover_prompt.show_prompt()


func _on_mouse_exited() -> void:
	hover_prompt.hide_prompt()


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not draw_enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pile_clicked.emit(self)


func restore_visual_stack(remaining_count: int, texture: Texture2D) -> void:
	for child in cards_container.get_children():
		child.queue_free()
	for i in range(remaining_count):
		var card := add_visual_card(texture, Vector2(0, -2) * i)
		card.scale = Vector2.ONE * 0.5
