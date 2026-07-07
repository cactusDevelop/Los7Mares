extends Node2D

@export var box_size: Vector2 = Vector2(200, 280)
@export var color: Color = Color(1.0, 0.84, 0.0)
@export var line_width: float = 12.0
@export var flat_top: bool = true  # true = hexagone à bord plat en haut/bas, false = pointe en haut/bas
## Si assigné (et que sa shape est une ConvexPolygonShape2D), le contour épouse
## exactement les points de cette shape au lieu de la formule hexagonale ci-dessous.
@export var card_shape: CollisionShape2D:
	set(value):
		card_shape = value
		queue_redraw()


func _draw() -> void:
	var points := _get_hexagon_points()
	if points.is_empty():
		return
	var closed_points := points.duplicate()
	closed_points.append(points[0])  # referme la forme
	draw_polyline(closed_points, color, line_width, true)
	# Arrondit les angles extérieurs en posant un disque sur chaque sommet.
	for p in points:
		draw_circle(p, line_width / 2.0, color)


func _get_hexagon_points() -> PackedVector2Array:
	if card_shape and card_shape.shape is ConvexPolygonShape2D:
		return _get_points_from_card_shape()
	return _get_default_hexagon_points()


func _get_points_from_card_shape() -> PackedVector2Array:
	var polygon_shape := card_shape.shape as ConvexPolygonShape2D
	var pts: PackedVector2Array = []
	for point in polygon_shape.points:
		var global_point: Vector2 = card_shape.to_global(point)
		pts.append(to_local(global_point))
	return pts


func _get_default_hexagon_points() -> PackedVector2Array:
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
