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

const RESOURCE_CUBE_COLORS := {
	"wood": Color8(122, 74, 34),    # brun
	"steel": Color8(58, 62, 68),    # gris foncé
	"food": Color8(235, 140, 30),   # orange
	"rum": Color8(50, 200, 190),    # turquoise
	"wool": Color(1, 1, 1),         # blanc
}

const FORTUNE_TEXTURE := preload("res://assets/art/tokens/fortune.png")
const TREASURE_TEXTURE := preload("res://assets/art/tokens/tresor.png")

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
	padding.add_theme_constant_override("margin_left", 24)
	padding.add_theme_constant_override("margin_right", 24)
	padding.add_theme_constant_override("margin_top", 24)
	padding.add_theme_constant_override("margin_bottom", 120)
	if close_button.text == "":
		close_button.text = tr("Retour")
	close_button.custom_minimum_size = Vector2(0, 64)
	close_button.pressed.connect(func(): visible = false)


func show_player(player: Dictionary) -> void:
	title_label.text = player["name"]
	title_label.add_theme_color_override("font_color", GameFlow.COLOR_VALUES[player["color"]])
	board_texture.texture = load(GameFlow.PLAYER_BOARD_TEXTURE)

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


func _place_special_tokens_random(player: Dictionary, key: String, texture: Texture2D, rect_min: Vector2, rect_max: Vector2) -> void:
	var count: int = player["special_resources"].get(key, 0)
	var icon_size_local: Vector2 = _texture_size_to_local(SPECIAL_ICON_SIZE)
	var placed_pixels: Array[Vector2] = []
	for i in range(count):
		var pixel_pos := _pick_spaced_position(rect_min, rect_max, placed_pixels)
		placed_pixels.append(pixel_pos)
		var icon := TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = icon_size_local
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		resource_slots.add_child(icon)
		icon.position = _texture_to_local(pixel_pos) - icon_size_local / 2.0


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


## Construit un petit cube isométrique (3 faces ombrées) centré sur (0, 0),
## pour donner un semblant de perspective 3D aux cubes de ressource.
func _build_cube_icon(base_color: Color, edge: float) -> Node2D:
	var s := edge / 2.0
	var top_point := Vector2(0, -s)
	var right_point := Vector2(s, -s / 2.0)
	var bottom_point := Vector2(0, s)
	var left_point := Vector2(-s, -s / 2.0)
	var bottom_right := Vector2(s, s / 2.0)
	var bottom_left := Vector2(-s, s / 2.0)
	var center := Vector2.ZERO

	var top_color: Color = base_color.lightened(0.35)
	var right_color: Color = base_color
	var left_color: Color = base_color.darkened(0.35)

	var cube := Node2D.new()

	var top_face := Polygon2D.new()
	top_face.polygon = PackedVector2Array([left_point, top_point, right_point, center])
	top_face.color = top_color
	cube.add_child(top_face)

	var right_face := Polygon2D.new()
	right_face.polygon = PackedVector2Array([center, right_point, bottom_right, bottom_point])
	right_face.color = right_color
	cube.add_child(right_face)

	var left_face := Polygon2D.new()
	left_face.polygon = PackedVector2Array([left_point, center, bottom_point, bottom_left])
	left_face.color = left_color
	cube.add_child(left_face)

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
