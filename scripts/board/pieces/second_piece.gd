extends Sprite2D

func _ready() -> void:
	if texture:
		centered = true
		offset = Vector2(0, -texture.get_height() / 2.0)
