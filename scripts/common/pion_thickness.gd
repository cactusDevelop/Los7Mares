class_name PionThickness

## Constantes PARTAGÉES par le plateau (captain_pion.gd/officer_pion.gd) et
## le panneau de sélection (pion_selection_panel.gd) : un seul endroit à
## modifier pour ajuster l'effet partout. thickness_px est TOUJOURS exprimé
## en pixels ÉCRAN (affichés), quelle que soit l'échelle du node porteur.
const THICKNESS_PX := 10.0
const LAYERS := 6
const EDGE_DARKEN := 0.5

## N'utilise PAS z_index (source de bugs d'affichage selon le type de node/
## contexte). À la place : le node "top" devient invisible via self_modulate
## (donc ses enfants restent visibles, eux, puisque self_modulate n'affecte
## que le dessin du node lui-même), et on lui ajoute des enfants dans
## l'ordre : ombres d'abord, copie visible ("front") en dernier. En Godot,
## à défaut de z_index, les enfants se dessinent dans leur ordre d'ajout :
## le dernier ajouté est donc garanti au-dessus, sans ambiguïté.
## Tous les enfants héritent automatiquement de la position, l'échelle et la
## teinte (modulate) de "top", donc aucune synchronisation manuelle requise.

## Sprite2D (contexte plateau/monde 2D).
static func add_to_sprite(top: Sprite2D) -> void:
	if LAYERS <= 0 or THICKNESS_PX <= 0.0:
		return
	top.self_modulate.a = 0.0

	# Compense l'échelle du node porteur pour que THICKNESS_PX reste des
	# pixels ÉCRAN (sans ça, un node à scale 0.6 rendrait l'épaisseur 0.6x
	# plus petite que prévu : c'est ce qui rendait l'effet trop petit sur
	# les pièces capitaine/second, mises à l'échelle par board.gd).
	var scale_x: float = top.scale.x if absf(top.scale.x) > 0.0001 else 1.0
	var scale_y: float = top.scale.y if absf(top.scale.y) > 0.0001 else 1.0
	var step_screen: Vector2 = UiTheme.DEPTH_DIRECTION * (THICKNESS_PX / float(LAYERS))
	var step_local := Vector2(step_screen.x / scale_x, step_screen.y / scale_y)
	var darken := Color(1, 1, 1).darkened(EDGE_DARKEN)

	for layer in range(LAYERS, 0, -1):
		var shadow := Sprite2D.new()
		shadow.texture = top.texture
		shadow.centered = top.centered
		shadow.offset = top.offset
		shadow.position = step_local * layer
		shadow.modulate = darken
		top.add_child(shadow)

	var front := Sprite2D.new()
	front.texture = top.texture
	front.centered = top.centered
	front.offset = top.offset
	top.add_child(front)


## N'importe quel Control (TextureRect, TextureButton...). `texture` et
## `size` (taille AFFICHÉE locale, ex: btn.custom_minimum_size) sont passés
## explicitement car un TextureButton n'expose pas .texture comme un
## TextureRect.
static func add_to_control(top: Control, texture: Texture2D, size: Vector2) -> void:
	if LAYERS <= 0 or THICKNESS_PX <= 0.0:
		return
	top.self_modulate.a = 0.0

	var step: Vector2 = UiTheme.DEPTH_DIRECTION * (THICKNESS_PX / float(LAYERS))
	var darken := Color(1, 1, 1).darkened(EDGE_DARKEN)

	for layer in range(LAYERS, 0, -1):
		var shadow := TextureRect.new()
		shadow.texture = texture
		shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		shadow.size = size
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shadow.position = step * layer
		shadow.modulate = darken
		top.add_child(shadow)

	var front := TextureRect.new()
	front.texture = texture
	front.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	front.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	front.size = size
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(front)
