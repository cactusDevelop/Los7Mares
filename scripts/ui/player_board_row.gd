extends VBoxContainer
signal pressed(player_id: int)

@onready var outer_wrap: Control = $Wrap
@onready var spin_wrap: Control = $Wrap/SpinWrap
@onready var name_label: Label = $Wrap/SpinWrap/NameLabel
@onready var row: Control = $Wrap/SpinWrap/Row
@onready var board_wrap: Control = $Wrap/SpinWrap/Row/BoardWrap
@onready var board_texture: TextureRect = $Wrap/SpinWrap/Row/BoardWrap/BoardTexture
@onready var tokens_wrap: Control = $Wrap/SpinWrap/Row/TokensWrap
@onready var tokens_container: HBoxContainer = $Wrap/SpinWrap/Row/TokensWrap/TokensContainer

const BOARD_THUMB_SIZE := Vector2(160, 107)
const TOKEN_BASE_SIZE := Vector2(40, 40)
## Espace vertical entre le nom du joueur et son plateau (dans le repère non
## tourné de SpinWrap, cf populate ci-dessous).
const NAME_ROW_SPACING := 4.0
## Espace horizontal entre le plateau et ses jetons (perroquets, marqueur doré).
const BOARD_TOKENS_SPACING := 8.0

var _player_id: int = -1


## thumb_size permet d'afficher ce plateau plus grand que les autres (le
## joueur actif, en bas de l'écran, cf board.gd _layout_player_boards).
## board_rotation_degrees fait pointer le "haut" de TOUT le bloc (nom +
## plateau + jetons) vers le centre de l'écran (0/90/180/-90 selon le côté,
## cf board.gd ROTATION_BY_SLOT).
##
## Avant, seules l'image du plateau et les jetons étaient tournés (et
## repositionnés/réordonnés au cas par cas selon le côté, cf
## _layout_row_direction) tandis que le nom du joueur restait fixe à l'écran :
## il ne suivait donc pas le plateau et ne pouvait pas être garanti "au-dessus"
## de celui-ci une fois tourné. Désormais on tourne SpinWrap dans son
## ensemble (nom + plateau + jetons en bloc), ce qui les fait tous tourner
## d'un coup : le nom reste au-dessus du plateau dans le repère LOCAL (non
## tourné) de ce bloc, donc toujours "au-dessus" du point de vue de ce joueur,
## quel que soit le côté où son plateau est affiché à l'écran.
##
## Note technique : on tourne SpinWrap, qui n'est PAS l'enfant direct d'un
## Container (son parent Wrap est un Control simple) : Godot réinitialise
## systématiquement la rotation des enfants directs d'un Container à chaque
## passe de mise en page (c'est pour ça que PlayerBoardRow lui-même, un
## VBoxContainer, ne peut contenir qu'un seul enfant simple - Wrap - jamais
## tourné directement). SpinWrap échappe à cette remise à zéro et garde donc
## sa rotation. Row, BoardWrap et TokensWrap sont ensuite positionnés à la
## main (Control simples, pas de Container) : plus besoin de réordonner quoi
## que ce soit selon le côté (cf ancien _layout_row_direction, supprimé),
## puisque c'est tout le bloc qui tourne désormais.
func populate(player: Dictionary, thumb_size: Vector2 = BOARD_THUMB_SIZE, board_rotation_degrees: float = 0.0) -> void:
	_player_id = player["id"]
	name_label.text = "%s — %d pts" % [player["name"], player["points"]]
	name_label.add_theme_color_override("font_color", GameFlow.COLOR_VALUES[player["color"]])
	name_label.rotation_degrees = 0.0
	var name_size: Vector2 = name_label.get_combined_minimum_size()
	name_label.size = name_size

	board_texture.texture = load(GameFlow.PLAYER_BOARD_TEXTURES.get(player["color"], GameFlow.PLAYER_BOARD_TEXTURES["jaune"]))
	board_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	board_texture.custom_minimum_size = thumb_size
	board_texture.size = thumb_size
	board_texture.rotation_degrees = 0.0
	board_texture.position = Vector2.ZERO
	board_wrap.position = Vector2.ZERO
	board_wrap.custom_minimum_size = thumb_size
	board_wrap.size = thumb_size
	board_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	if not board_wrap.gui_input.is_connected(_on_board_wrap_gui_input):
		board_wrap.gui_input.connect(_on_board_wrap_gui_input)

	for child in tokens_container.get_children():
		child.queue_free()

	var token_size: Vector2 = TOKEN_BASE_SIZE * (thumb_size.x / BOARD_THUMB_SIZE.x)
	if player.get("has_own_parrot", true):
		tokens_container.add_child(_build_parrot_token(player["color"], false, token_size))
	for other in GameFlow.players:
		if other.get("parrot_captured_by", -1) == player["id"]:
			tokens_container.add_child(_build_parrot_token(other["color"], true, token_size))
	if player.get("is_first_player", false):
		tokens_container.add_child(_build_marker_token(token_size))

	var tokens_min: Vector2 = tokens_container.get_combined_minimum_size()
	tokens_container.position = Vector2.ZERO
	tokens_container.size = tokens_min
	tokens_wrap.custom_minimum_size = tokens_min
	tokens_wrap.size = tokens_min
	tokens_wrap.position = Vector2(thumb_size.x + BOARD_TOKENS_SPACING, (thumb_size.y - tokens_min.y) / 2.0)

	# Plateau + jetons toujours côte à côte dans cet ordre, dans le repère
	# NON tourné du bloc (plus besoin de réordonner selon le côté : c'est
	# tout le bloc, nom compris, qui tourne désormais).
	var row_size := Vector2(thumb_size.x + BOARD_TOKENS_SPACING + tokens_min.x, maxf(thumb_size.y, tokens_min.y))
	row.position = Vector2(0, name_size.y + NAME_ROW_SPACING)
	row.size = row_size
	name_label.position = Vector2((row_size.x - name_size.x) / 2.0, 0)

	# Taille du bloc complet (nom + plateau/jetons) dans son propre repère non
	# tourné, puis rotation autour de son centre (pivot_offset).
	var unrotated_size := Vector2(maxf(name_size.x, row_size.x), name_size.y + NAME_ROW_SPACING + row_size.y)
	spin_wrap.size = unrotated_size
	spin_wrap.pivot_offset = unrotated_size / 2.0
	spin_wrap.rotation_degrees = board_rotation_degrees

	# À ±90°, le bloc tourné occupe une boîte largeur/hauteur inversée à
	# l'écran : Wrap (dont dépend get_combined_minimum_size() de ce
	# VBoxContainer, cf board.gd) doit refléter cette boîte tournée, pas la
	# taille non tournée de SpinWrap.
	var swapped: bool = int(round(board_rotation_degrees)) % 180 != 0
	var wrap_size: Vector2 = Vector2(unrotated_size.y, unrotated_size.x) if swapped else unrotated_size
	outer_wrap.custom_minimum_size = wrap_size
	outer_wrap.size = wrap_size
	# Centre SpinWrap dans Wrap : comme la rotation se fait autour de son
	# propre centre (pivot_offset ci-dessus), ce centrage reste correct quel
	# que soit l'angle.
	spin_wrap.position = (wrap_size - unrotated_size) / 2.0


func _on_board_wrap_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(_player_id)


func get_player_id() -> int:
	return _player_id


func _build_parrot_token(color_name: String, imprisoned: bool, token_size: Vector2 = TOKEN_BASE_SIZE) -> Control:
	var texture_rect := TextureRect.new()
	var path_template: String = GameFlow.PARROT_TEXTURE_PATH_PRISON if imprisoned else GameFlow.PARROT_TEXTURE_PATH
	texture_rect.texture = load(path_template % color_name)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.custom_minimum_size = token_size
	return texture_rect


func _build_marker_token(token_size: Vector2 = TOKEN_BASE_SIZE) -> Control:
	var texture_rect := TextureRect.new()
	texture_rect.texture = load(GameFlow.MARKER_TEXTURE_PATH)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.custom_minimum_size = token_size
	return texture_rect
