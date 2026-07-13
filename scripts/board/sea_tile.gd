extends Node2D

@onready var back_sprite: Sprite2D = $BackSprite
@onready var front_sprite: Sprite2D = $FrontSprite

var _front_original_scale_x: float


func _ready() -> void:
	_front_original_scale_x = front_sprite.scale.x
	front_sprite.visible = false
	back_sprite.visible = true


func flip_to_front(duration: float = 0.3) -> void:
	duration = GameFlow.anim_duration(duration)
	var tween = create_tween()
	tween.tween_property(back_sprite, "scale:x", 0.0, duration / 2.0)
	tween.tween_callback(func():
		back_sprite.visible = false
		front_sprite.visible = true
		front_sprite.scale.x = 0.0
	)
	tween.tween_property(front_sprite, "scale:x", _front_original_scale_x, duration / 2.0)
