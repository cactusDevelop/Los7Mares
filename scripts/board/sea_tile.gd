extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

var front_texture: Texture2D
var back_texture: Texture2D


func setup(front: Texture2D, back: Texture2D) -> void:
	front_texture = front
	back_texture = back
	sprite.texture = back_texture  # la carte commence face cachée (verso visible)


func flip_to_front(duration: float = 0.3) -> void:
	var tween = create_tween()
	tween.tween_property(sprite, "scale:x", 0.0, duration / 2.0)
	tween.tween_callback(func(): sprite.texture = front_texture)
	tween.tween_property(sprite, "scale:x", 1.0, duration / 2.0)
