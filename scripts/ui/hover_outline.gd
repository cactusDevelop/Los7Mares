extends Node2D

@export var box_size: Vector2 = Vector2(200, 280)
@export var color: Color = Color(1.0, 0.84, 0.0)
@export var line_width: float = 12.0
@export var flat_top: bool = true  # true = hexagone à bord plat en haut/bas, false = pointe en haut/bas


func _draw() -> void:
	var points := _get_hexagon_points()
	points.append(points[0])  # referme la forme
	draw_polyline(points, color, line_width, true)


func _get_hexagon_points() -> PackedVector2Array:
	var pts: PackedVector2Array = []
	var half_w = box_size.x / 2.0
	var half_h = box_size.y / 2.0

	if flat_top:
		pts.append(Vector2(-half_w * 0.5, -half_h))
		pts.append(Vector2(half_w * 0.5, -half_h))
		pts.append(Vector2(half_w, 0))
		pts.append(Vector2(half_w * 0.5, half_h))
		pts.append(Vector2(-half_w * 0.5, half_h))
		pts.append(Vector2(-half_w, 0))
	else:
		pts.append(Vector2(0, -half_h))
		pts.append(Vector2(half_w, -half_h * 0.5))
		pts.append(Vector2(half_w, half_h * 0.5))
		pts.append(Vector2(0, half_h))
		pts.append(Vector2(-half_w, half_h * 0.5))
		pts.append(Vector2(-half_w, -half_h * 0.5))

	return pts
