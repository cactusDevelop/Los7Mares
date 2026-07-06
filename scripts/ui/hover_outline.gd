extends Node2D

@export var box_size: Vector2 = Vector2(200, 280)
@export var color: Color = Color(1.0, 0.84, 0.0)
@export var line_width: float = 6.0


func _draw() -> void:
	var rect = Rect2(-box_size / 2.0, box_size)
	draw_rect(rect, color, false, line_width)
