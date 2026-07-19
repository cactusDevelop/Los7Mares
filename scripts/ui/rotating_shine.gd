extends Control

## Halo tournant en continu derrière un jeton (ex: jeton Fortune de
## l'annonce "Tour X"). Dessine des rayons de lumière semi-transparents,
## en alternance clairs/vides, qui pivotent autour du centre du Control.
## Ajouter ce node en enfant AVANT le sprite du jeton (ou avec un z_index
## inférieur) pour qu'il reste derrière.

@export var ray_count: int = 10
@export var ray_color: Color = Color(1.0, 0.9, 0.5, 0.35)
@export var rotation_speed: float = 0.18  # tours par seconde
@export var ray_width_ratio: float = 0.22  # largeur angulaire d'un rayon (fraction de l'écart entre 2 rayons)

var _angle: float = 0.0


func _process(delta: float) -> void:
	_angle += rotation_speed * TAU * delta
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size / 2.0
	var radius: float = max(size.x, size.y) / 2.0
	var half_width := (TAU / ray_count) * ray_width_ratio

	for i in range(ray_count):
		var a := _angle + i * (TAU / ray_count)
		var p1 := center
		var p2 := center + Vector2(cos(a - half_width), sin(a - half_width)) * radius
		var p3 := center + Vector2(cos(a + half_width), sin(a + half_width)) * radius
		draw_polygon(PackedVector2Array([p1, p2, p3]), PackedColorArray([ray_color]))
