extends Control

## --- Position des éléments sur l'image du plateau joueur ---
## Toutes les coordonnées ci-dessous sont en PIXELS DE L'IMAGE D'ORIGINE
## (assets/art/board/plateau-joueur-jaune.png, 2716x1813), pas en pixels
## écran : le script convertit automatiquement selon la taille affichée.

const RESOURCE_SLOT_PIXELS: Array[Vector2] = [
	Vector2(2100, 1320), Vector2(2250, 1320), Vector2(2400, 1320),
	Vector2(2100, 1470), Vector2(2250, 1470), Vector2(2400, 1470),
	Vector2(2100, 1620), Vector2(2250, 1620), Vector2(2400, 1620),
]
## Zones (coin haut-gauche -> coin bas-droit) dans lesquelles les jetons
## Trésor / Fortune apparaissent à une position aléatoire.
const TREASURE_RECT_MIN := Vector2(150, 1000)
const TREASURE_RECT_MAX := Vector2(750, 1250)
const FORTUNE_RECT_MIN := Vector2(150, 1400)
const FORTUNE_RECT_MAX := Vector2(750, 1650)

const RESOURCE_CUBE_EDGE := 120.0
const SPECIAL_ICON_SIZE := Vector2(110, 110)
## Distance minimale visée (en pixels image) entre deux jetons du même type,
## pour limiter les superpositions sans les interdire totalement.
const SPECIAL_TOKEN_MIN_DISTANCE := 95.0
const SPECIAL_TOKEN_MAX_ATTEMPTS := 40

## --- Cohérence de la fausse perspective 3D ---
## La direction (UiTheme.DEPTH_DIRECTION) est définie une seule fois dans
## UiTheme pour rester identique partout dans le jeu (ressources, planches,
## jetons, bateaux...). Convention : la "matière"/l'épaisseur des objets
## s'étend vers le BAS-GAUCHE À L'ÉCRAN (comme une ombre portée), donc leur
## face du dessus/avant visible est repoussée vers le HAUT-DROITE. Les
## cubes de ressource DOIVENT utiliser la direction opposée à celle-ci.
## Épaisseur totale des jetons Fortune/Trésor, en pixels écran (~3px demandés).
const TOKEN_THICKNESS_PX := 3.0
const TOKEN_THICKNESS_LAYERS := 3
const TOKEN_EDGE_DARKEN := 0.45
## Hauteur du cube = fraction de son côté (edge), extrudée en sens opposé
## à DEPTH_DIRECTION pour rester cohérente avec les jetons.
const CUBE_EXTRUDE_RATIO := 0.22

const RESOURCE_CUBE_COLORS := {
	"wood": Color8(122, 74, 34),    # brun
	"steel": Color8(58, 62, 68),    # gris foncé
	"food": Color8(235, 140, 30),   # orange
	"rum": Color8(50, 200, 190),    # turquoise
	"wool": Color(1, 1, 1),         # blanc
}

const FORTUNE_TEXTURE := preload("res://assets/art/tokens/fortune.png")
const TREASURE_TEXTURE := preload("res://assets/art/tokens/tresor.png")

## Planches de coque (= points de vie), affichées dans le rectangle
## (900,1250)-(1950,1700) de l'image d'origine. Disposées en 2 rangées
## (4 puis 3) façon planches empilées. Ajuste ces positions si elles ne
## correspondent pas bien à la zone dessinée sur le plateau.
const PLANK_SLOT_PIXELS: Array[Vector2] = [
	Vector2(1030, 1360), Vector2(1310, 1360), Vector2(1590, 1360), Vector2(1870, 1360),
	Vector2(1170, 1590), Vector2(1450, 1590), Vector2(1730, 1590),
]
const PLANK_SIZE := Vector2(240, 80)
const PLANK_ROTATION_JITTER_DEG := 4.0  # légère inclinaison aléatoire pour un rendu moins rigide
const PLANK_REFLECTION_COUNT := 3
const PLANK_REFLECTION_LIGHTEN := 0.35
const PLANK_REFLECTION_ALPHA_MIN := 0.15
const PLANK_REFLECTION_ALPHA_MAX := 0.4

@onready var blocker: ColorRect = $Blocker
@onready var padding: MarginContainer = $Padding
@onready var title_label: Label = $Padding/Content/TitleLabel
@onready var board_texture: TextureRect = $Padding/Content/BoardArea/BoardStack/BoardTexture
@onready var resource_slots: Control = $Padding/Content/BoardArea/BoardStack/ResourceSlots
@onready var close_button: Button = $Padding/Content/CloseButton


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.color = Color(0, 0, 0, 0.7)
	board_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board_texture.stretch_mode = TextureRect.STRETCH_SCALE
	padding.add_theme_constant_override("margin_left", 0)
	padding.add_theme_constant_override("margin_right", 0)
	padding.add_theme_constant_override("margin_top", 60)
	padding.add_theme_constant_override("margin_bottom", 0)
	if close_button.text == "":
		close_button.text = tr("Retour")
	close_button.custom_minimum_size = Vector2(0, 64)
	close_button.pressed.connect(func(): visible = false)
	blocker.gui_input.connect(_on_blocker_gui_input)


func show_player(player: Dictionary) -> void:
	title_label.text = player["name"]
	title_label.add_theme_color_override("font_color", GameFlow.COLOR_VALUES[player["color"]])
	var texture_path: String = GameFlow.PLAYER_BOARD_TEXTURES.get(
		player["color"], GameFlow.PLAYER_BOARD_TEXTURES["jaune"]
	)
	board_texture.texture = load(texture_path)

	var viewport_size := get_viewport_rect().size
	blocker.size = viewport_size
	padding.position = Vector2.ZERO
	padding.size = viewport_size
	visible = true

	# Le BoardTexture doit avoir sa taille finale à jour avant de convertir
	# les coordonnées pixel -> écran : on attend une frame de layout.
	await get_tree().process_frame
	_refresh_resource_display(player)


## Place un cube coloré par unité de ressource simple (bois/acier/nourriture/
## rhum/laine) sur les cases d'inventaire, et des jetons Fortune/Trésor
## répartis aléatoirement dans leurs zones respectives.
func _refresh_resource_display(player: Dictionary) -> void:
	for child in resource_slots.get_children():
		child.queue_free()

	var units: Array[String] = []
	for res_type in GameFlow.RESOURCE_TYPES:
		for i in range(player["resources"].get(res_type, 0)):
			units.append(res_type)
	units = units.slice(0, RESOURCE_SLOT_PIXELS.size())

	var edge_local: float = _texture_length_to_local(RESOURCE_CUBE_EDGE)
	for i in range(units.size()):
		var cube := _build_cube_icon(RESOURCE_CUBE_COLORS.get(units[i], Color.MAGENTA), edge_local)
		resource_slots.add_child(cube)
		cube.position = _texture_to_local(RESOURCE_SLOT_PIXELS[i])

	_place_special_tokens_random(player, "treasure", TREASURE_TEXTURE, TREASURE_RECT_MIN, TREASURE_RECT_MAX)
	_place_special_tokens_random(player, "fortune", FORTUNE_TEXTURE, FORTUNE_RECT_MIN, FORTUNE_RECT_MAX)
	_place_hull_planks(player)


func _place_special_tokens_random(player: Dictionary, key: String, texture: Texture2D, rect_min: Vector2, rect_max: Vector2) -> void:
	var count: int = player["special_resources"].get(key, 0)
	var icon_size_local: Vector2 = _texture_size_to_local(SPECIAL_ICON_SIZE)
	var placed_pixels: Array[Vector2] = []
	for i in range(count):
		var pixel_pos := _pick_spaced_position(rect_min, rect_max, placed_pixels)
		placed_pixels.append(pixel_pos)
		var anchor: Vector2 = _texture_to_local(pixel_pos) - icon_size_local / 2.0
		_add_token_with_thickness(texture, anchor, icon_size_local)


## Empile plusieurs copies assombries du jeton, décalées vers le bas-gauche
## (DEPTH_DIRECTION), puis la copie en couleur normale au-dessus : donne une
## petite épaisseur au jeton au lieu d'un sprite plat.
func _add_token_with_thickness(texture: Texture2D, anchor: Vector2, icon_size: Vector2) -> void:
	var step: Vector2 = UiTheme.DEPTH_DIRECTION * (TOKEN_THICKNESS_PX / float(TOKEN_THICKNESS_LAYERS))
	for layer in range(TOKEN_THICKNESS_LAYERS, 0, -1):
		var edge := TextureRect.new()
		edge.texture = texture
		edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		edge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		edge.size = icon_size
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edge.modulate = Color(1, 1, 1).darkened(TOKEN_EDGE_DARKEN)
		resource_slots.add_child(edge)
		edge.position = anchor + step * layer

	var top := TextureRect.new()
	top.texture = texture
	top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.size = icon_size
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resource_slots.add_child(top)
	top.position = anchor


## Place les planches de coque du joueur (points de vie) sur des
## emplacements fixes (contrairement aux jetons Fortune/Trésor qui sont
## dispersés aléatoirement) : elles doivent rester lisibles pour compter les
## points de vie restants d'un coup d'œil.
func _place_hull_planks(player: Dictionary) -> void:
	var count: int = min(player.get("hull_planks", 0), PLANK_SLOT_PIXELS.size())
	var size_local: Vector2 = _texture_size_to_local(PLANK_SIZE)
	for i in range(count):
		var anchor: Vector2 = _texture_to_local(PLANK_SLOT_PIXELS[i])
		var plank := _build_plank_icon(_wood_color_variant(), size_local)
		resource_slots.add_child(plank)
		plank.position = anchor
		plank.rotation_degrees = randf_range(-PLANK_ROTATION_JITTER_DEG, PLANK_ROTATION_JITTER_DEG)


## Légère variation de teinte autour du brun bois de base, pour que les 7
## planches ne soient pas des clones parfaitement identiques (bois naturel).
func _wood_color_variant() -> Color:
	var base: Color = RESOURCE_CUBE_COLORS["wood"]
	var shift := randf_range(-0.1, 0.1)
	return base.lightened(shift) if shift > 0.0 else base.darkened(-shift)


## Construit une planche en fausse perspective 3D (même technique que
## _build_cube_icon : toit + 2 parois extrudées dans DEPTH_DIRECTION), avec
## en plus des veines de bois et deux clous aux extrémités pour un rendu
## plus réaliste qu'un simple rectangle plat.
func _build_plank_icon(base_color: Color, size: Vector2) -> Node2D:
	var half := size / 2.0
	var top_left := Vector2(-half.x, -half.y)
	var top_right := Vector2(half.x, -half.y)
	var bottom_right := Vector2(half.x, half.y)
	var bottom_left := Vector2(-half.x, half.y)

	# Épaisseur proportionnelle à la petite dimension (planche fine), pas au
	# côté comme pour les cubes de ressource.
	var extrude: Vector2 = -UiTheme.DEPTH_DIRECTION * size.y * CUBE_EXTRUDE_RATIO

	var top_color: Color = base_color.lightened(0.25)
	var left_wall_color: Color = base_color.darkened(0.15)
	var bottom_wall_color: Color = base_color.darkened(0.4)

	var plank := Node2D.new()

	var left_wall := Polygon2D.new()
	left_wall.polygon = PackedVector2Array([
		top_left, bottom_left, bottom_left + extrude, top_left + extrude
	])
	left_wall.color = left_wall_color
	plank.add_child(left_wall)

	var bottom_wall := Polygon2D.new()
	bottom_wall.polygon = PackedVector2Array([
		bottom_left, bottom_right, bottom_right + extrude, bottom_left + extrude
	])
	bottom_wall.color = bottom_wall_color
	plank.add_child(bottom_wall)

	var top_face := Polygon2D.new()
	top_face.polygon = PackedVector2Array([
		top_left + extrude, top_right + extrude, bottom_right + extrude, bottom_left + extrude
	])
	top_face.color = top_color
	plank.add_child(top_face)

	_add_wood_reflections(plank, half, extrude, top_color)

	return plank


## Trace quelques petits reflets clairs, semi-transparents, positionnés et
## inclinés aléatoirement sur le dessus de la planche, pour évoquer la
## lumière sur du bois verni plutôt que des veines dessinées à la main.
func _add_wood_reflections(plank: Node2D, half: Vector2, extrude: Vector2, top_color: Color) -> void:
	var reflection_color: Color = top_color.lightened(PLANK_REFLECTION_LIGHTEN)
	for i in range(PLANK_REFLECTION_COUNT):
		var center := Vector2(
			randf_range(-half.x * 0.7, half.x * 0.7),
			randf_range(-half.y * 0.6, half.y * 0.6)
		)
		var length := randf_range(half.x * 0.25, half.x * 0.55)
		var thickness := randf_range(2.0, 4.5)
		var angle := deg_to_rad(randf_range(-12.0, 12.0))
		var dir := Vector2(1, 0).rotated(angle)

		var line := Line2D.new()
		line.width = thickness
		line.antialiased = true
		line.default_color = Color(
			reflection_color.r, reflection_color.g, reflection_color.b,
			randf_range(PLANK_REFLECTION_ALPHA_MIN, PLANK_REFLECTION_ALPHA_MAX)
		)
		line.points = PackedVector2Array([
			center - dir * length * 0.5 + extrude,
			center + dir * length * 0.5 + extrude,
		])
		plank.add_child(line)


## Tire une position aléatoire dans le rectangle, en essayant de rester à au
## moins SPECIAL_TOKEN_MIN_DISTANCE des positions déjà choisies (échantillonnage
## par rejet). Si aucun essai ne satisfait la distance, garde le meilleur essai.
func _pick_spaced_position(rect_min: Vector2, rect_max: Vector2, existing: Array[Vector2]) -> Vector2:
	var best_pos := Vector2(randf_range(rect_min.x, rect_max.x), randf_range(rect_min.y, rect_max.y))
	var best_score := -1.0
	for attempt in range(SPECIAL_TOKEN_MAX_ATTEMPTS):
		var candidate := Vector2(randf_range(rect_min.x, rect_max.x), randf_range(rect_min.y, rect_max.y))
		if existing.is_empty():
			return candidate
		var min_dist := INF
		for p in existing:
			min_dist = min(min_dist, candidate.distance_to(p))
		if min_dist >= SPECIAL_TOKEN_MIN_DISTANCE:
			return candidate
		if min_dist > best_score:
			best_score = min_dist
			best_pos = candidate
	return best_pos


## Construit un cube en fausse perspective. La base (120x120, centrée sur la
## position donnée) N'EST PAS dessinée : elle touche le plateau, donc elle
## est cachée entre le plateau et le cube. On ne dessine que ce qui est
## réellement visible : le toit (translation exacte de la base, donc lui
## aussi un carré 120x120 non déformé) et les deux parois qui comblent la
## hauteur, dans le sens opposé à DEPTH_DIRECTION (cohérence avec les jetons).
func _build_cube_icon(base_color: Color, edge: float) -> Node2D:
	var half := edge / 2.0
	var top_left := Vector2(-half, -half)
	var top_right := Vector2(half, -half)
	var bottom_right := Vector2(half, half)
	var bottom_left := Vector2(-half, half)

	var extrude: Vector2 = -UiTheme.DEPTH_DIRECTION * edge * CUBE_EXTRUDE_RATIO

	var roof_color: Color = base_color.lightened(0.35)
	var left_wall_color: Color = base_color.darkened(0.15)
	var bottom_wall_color: Color = base_color.darkened(0.4)

	var cube := Node2D.new()

	# Paroi gauche : entre le bord gauche de la base (caché) et le bord
	# gauche du toit.
	var left_wall := Polygon2D.new()
	left_wall.polygon = PackedVector2Array([
		top_left, bottom_left, bottom_left + extrude, top_left + extrude
	])
	left_wall.color = left_wall_color
	cube.add_child(left_wall)

	# Paroi basse : entre le bord bas de la base (caché) et le bord bas du
	# toit. C'est la face la plus proche du joueur, donc la plus sombre.
	var bottom_wall := Polygon2D.new()
	bottom_wall.polygon = PackedVector2Array([
		bottom_left, bottom_right, bottom_right + extrude, bottom_left + extrude
	])
	bottom_wall.color = bottom_wall_color
	cube.add_child(bottom_wall)

	# Toit : simple translation de la base par l'extrusion, donc un carré
	# 120x120 non déformé lui aussi (juste décalé), pas la base elle-même.
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([
		top_left + extrude, top_right + extrude, bottom_right + extrude, bottom_left + extrude
	])
	roof.color = roof_color
	cube.add_child(roof)

	return cube


## Convertit une position en pixels de l'image d'origine vers une position
## locale dans BoardTexture / ResourceSlots (même rect), quelle que soit la
## taille affichée à l'écran.
func _texture_to_local(pixel_pos: Vector2) -> Vector2:
	if board_texture.texture == null:
		return pixel_pos
	return pixel_pos * (board_texture.size / board_texture.texture.get_size())


## Convertit une longueur (ex: un côté de cube) en pixels image vers sa
## longueur équivalente à l'écran.
func _texture_length_to_local(length_px: float) -> float:
	if board_texture.texture == null:
		return length_px
	var scale_factor: Vector2 = board_texture.size / board_texture.texture.get_size()
	return length_px * (scale_factor.x + scale_factor.y) / 2.0


## Convertit une taille (Vector2) en pixels image vers sa taille écran.
func _texture_size_to_local(size_px: Vector2) -> Vector2:
	if board_texture.texture == null:
		return size_px
	return size_px * (board_texture.size / board_texture.texture.get_size())


func _on_blocker_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		visible = false
