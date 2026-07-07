extends Node2D

@export var box_size: Vector2 = Vector2(200, 280)
@export var color: Color = Color(1.0, 0.84, 0.0)
@export var line_width: float = 12.0
@export var flat_top: bool = true  # true = hexagone à bord plat en haut/bas, false = pointe en haut/bas
## Rayon des coins arrondis (en pixels). Mettre à 0 pour des coins pointus.
@export var corner_radius: float = 40.0
## Si assigné, le contour épouse exactement le polygone de ce CollisionPolygon2D
## au lieu de la formule hexagonale par défaut.
@export var card_shape: CollisionPolygon2D:
	set(value):
		card_shape = value
		queue_redraw()


func _draw() -> void:
	var points := _get_hexagon_points()
	if points.size() < 3:
		return
	var rounded_points := _build_rounded_polygon(points, corner_radius)
	rounded_points.append(rounded_points[0])  # referme la forme
	draw_polyline(rounded_points, color, line_width, true)


func _get_hexagon_points() -> PackedVector2Array:
	if card_shape and card_shape.polygon.size() >= 3:
		return _get_points_from_card_shape()
	return _get_default_hexagon_points()


func _get_points_from_card_shape() -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for point in card_shape.polygon:
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


## Construit un contour où chaque coin de "points" est remplacé par un congé
## (arrondi) de rayon "radius", approximé par une courbe de Bézier quadratique.
func _build_rounded_polygon(points: PackedVector2Array, radius: float) -> PackedVector2Array:
	var result: PackedVector2Array = []
	var n := points.size()
	if radius <= 0.0:
		return points.duplicate()

	var segments := 10
	for i in range(n):
		var prev: Vector2 = points[(i - 1 + n) % n]
		var curr: Vector2 = points[i]
		var next: Vector2 = points[(i + 1) % n]

		var dir_to_prev := (prev - curr).normalized()
		var dir_to_next := (next - curr).normalized()

		# Le rayon ne peut pas dépasser la moitié de l'arête la plus courte adjacente.
		var r: float = min(radius, curr.distance_to(prev) * 0.5, curr.distance_to(next) * 0.5)

		var p1 := curr + dir_to_prev * r
		var p2 := curr + dir_to_next * r

		result.append(p1)
		for s in range(1, segments):
			var t := float(s) / float(segments)
			var a := p1.lerp(curr, t)
			var b := curr.lerp(p2, t)
			result.append(a.lerp(b, t))
		result.append(p2)

	return result
