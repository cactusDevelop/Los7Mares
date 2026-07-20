extends Node2D

## Émis quand la tuile est cliquée alors que hover_enabled == true (utilisé
## par action_resolution_phase.gd pour choisir une destination de
## déplacement en cliquant directement sur une mer, cf hideout_spot.gd pour
## le même principe appliqué aux cachettes).
signal spot_clicked(spot: Node2D)

@onready var back_sprite: Sprite2D = $BackSprite
@onready var front_sprite: Sprite2D = $FrontSprite
@onready var click_area: Area2D = $ClickArea

## Clé de mer ("abondance", "azur", ...) assignée par board.gd une fois la
## tuile placée sur le plateau (cf SEA_KEY_BY_NODE_NAME).
var sea_key: String = ""
var hover_enabled: bool = false

var _front_original_scale_x: float


func _ready() -> void:
	_front_original_scale_x = front_sprite.scale.x
	front_sprite.visible = false
	back_sprite.visible = true
	click_area.mouse_entered.connect(_on_mouse_entered)
	click_area.mouse_exited.connect(_on_mouse_exited)
	click_area.input_event.connect(_on_input_event)


func _on_mouse_entered() -> void:
	if hover_enabled:
		front_sprite.modulate = Color(1.25, 1.25, 1.25)


func _on_mouse_exited() -> void:
	front_sprite.modulate = Color(1, 1, 1)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not hover_enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		spot_clicked.emit(self)


## Active/désactive le survol + le clic sur cette mer (activé uniquement
## pour les mers accessibles pendant l'action "déplacement").
func set_hover_enabled(enabled: bool) -> void:
	hover_enabled = enabled
	if not enabled:
		front_sprite.modulate = Color(1, 1, 1)


func flip_to_front(duration: float = 0.3) -> void:
	duration = Settings.anim_duration(duration)
	var tween = create_tween()
	tween.tween_property(back_sprite, "scale:x", 0.0, duration / 2.0)
	tween.tween_callback(func():
		back_sprite.visible = false
		front_sprite.visible = true
		front_sprite.scale.x = 0.0
	)
	tween.tween_property(front_sprite, "scale:x", _front_original_scale_x, duration / 2.0)
