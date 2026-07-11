extends Control

## --- Position des cases sur l'image du plateau joueur ---
## Toutes les coordonnées ci-dessous sont exprimées en PIXELS DE L'IMAGE
## D'ORIGINE (assets/art/board/plateau-joueur-jaune.png, 2716x1813), PAS en
## pixels écran : le script les convertit automatiquement quel que soit
## l'agrandissement. Pour les régler :
##   1. Dans Godot, ouvre l'onglet "FileSystem", clique sur l'image.
##   2. En bas, l'aperçu affiche l'image ; survole chaque case d'inventaire
##      avec la souris : Godot affiche le pixel (x, y) sous le curseur
##      dans le panneau d'aperçu (ou utilise GIMP/Aperçu : la position du
##      curseur est affichée en bas de la fenêtre).
##   3. Remplace les valeurs ci-dessous, dans l'ordre que tu veux (l'ordre
##      ne change que l'ordre de remplissage des ressources).
const RESOURCE_SLOT_PIXELS: Array[Vector2] = [
	Vector2(400, 400), Vector2(700, 400), Vector2(1000, 400),
	Vector2(400, 700), Vector2(700, 700), Vector2(1000, 700),
	Vector2(400, 1000), Vector2(700, 1000), Vector2(1000, 1000),
]
const FORTUNE_SLOT_PIXEL := Vector2(2000, 400)
const TREASURE_SLOT_PIXEL := Vector2(2300, 400)
## Décalage (en pixels image) appliqué à chaque jeton empilé au même endroit,
## pour que plusieurs Fortune/Trésor ne se superposent pas parfaitement.
const SPECIAL_STACK_OFFSET := Vector2(20, -20)

const RESOURCE_SQUARE_SIZE := Vector2(90, 90)
const SPECIAL_ICON_SIZE := Vector2(110, 110)

const RESOURCE_SQUARE_COLORS := {
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


## Place un carré coloré par unité de ressource simple (bois/acier/nourriture/
## rhum/laine) sur les cases d'inventaire, et un jeton par Fortune/Trésor.
func _refresh_resource_display(player: Dictionary) -> void:
	for child in resource_slots.get_children():
		child.queue_free()

	var units: Array[String] = []
	for res_type in GameFlow.RESOURCE_TYPES:
		for i in range(player["resources"].get(res_type, 0)):
			units.append(res_type)
	units = units.slice(0, RESOURCE_SLOT_PIXELS.size())

	for i in range(units.size()):
		var square := ColorRect.new()
		square.color = RESOURCE_SQUARE_COLORS.get(units[i], Color.MAGENTA)
		square.size = RESOURCE_SQUARE_SIZE
		square.mouse_filter = Control.MOUSE_FILTER_IGNORE
		resource_slots.add_child(square)
		square.position = _texture_to_local(RESOURCE_SLOT_PIXELS[i]) - RESOURCE_SQUARE_SIZE / 2.0

	_place_special_tokens(player, "fortune", FORTUNE_TEXTURE, FORTUNE_SLOT_PIXEL)
	_place_special_tokens(player, "treasure", TREASURE_TEXTURE, TREASURE_SLOT_PIXEL)


func _place_special_tokens(player: Dictionary, key: String, texture: Texture2D, base_pixel: Vector2) -> void:
	var count: int = player["special_resources"].get(key, 0)
	for i in range(count):
		var icon := TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = SPECIAL_ICON_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		resource_slots.add_child(icon)
		icon.position = _texture_to_local(base_pixel) - SPECIAL_ICON_SIZE / 2.0 + SPECIAL_STACK_OFFSET * i


## Convertit une position en pixels de l'image d'origine vers une position
## locale dans BoardTexture (donc dans ResourceSlots, qui a le même rect),
## quelle que soit la taille affichée à l'écran.
func _texture_to_local(pixel_pos: Vector2) -> Vector2:
	if board_texture.texture == null:
		return pixel_pos
	var native_size: Vector2 = board_texture.texture.get_size()
	var scale_factor: Vector2 = board_texture.size / native_size
	return pixel_pos * scale_factor
