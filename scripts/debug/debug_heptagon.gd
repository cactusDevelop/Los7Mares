extends Node2D

## Dessine un heptagone régulier (7 côtés) avec un sommet pointant vers le
## nord (le haut de l'écran), utile comme repère visuel de debug.
## Décoche "Show Heptagon" dans l'Inspecteur (ou mets show_heptagon = false
## par code) pour ne plus l'afficher, sans avoir à supprimer le node.

@export var show_heptagon: bool = true:
	set(value):
		show_heptagon = value
		queue_redraw()

@export var radius: float = 1000.0:
	set(value):
		radius = value
		queue_redraw()

@export var color: Color = Color.RED

@export var line_width: float = 2.0


func _ready() -> void:
	# z_index max + non-relatif : peu importe où ce node est placé dans
	# l'arbre (même sous des sprites/UI ajoutés après lui), il se dessine
	# toujours par-dessus tout le reste du même CanvasLayer.
	z_index = 4096
	z_as_relative = false


func _draw() -> void:
	if not show_heptagon:
		return

	const SIDES := 7
	var points := PackedVector2Array()
	for i in range(SIDES + 1):
		# -PI/2 = vers le haut (nord) ; on part de là pour que le premier
		# sommet pointe bien vers le nord, puis on tourne de 360°/7 à chaque pas.
		var angle := -PI / 2.0 + i * TAU / SIDES
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	draw_polyline(points, color, line_width)
