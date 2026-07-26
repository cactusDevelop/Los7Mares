extends VBoxContainer
signal pressed(player_id: int)

@onready var name_label: Label = $NameLabel
@onready var board_wrap: Control = $Row/BoardWrap
@onready var board_texture: TextureRect = $Row/BoardWrap/BoardTexture
@onready var tokens_container: HBoxContainer = $Row/TokensContainer

const BOARD_THUMB_SIZE := Vector2(160, 107)
const TOKEN_BASE_SIZE := Vector2(40, 40)

var _player_id: int = -1


## thumb_size permet d'afficher ce plateau plus grand que les autres (le
## joueur actif, en bas de l'écran, cf board.gd _layout_player_boards).
## board_rotation_degrees fait pointer le "haut" du plateau vers le centre de
## l'écran (0/90/180/-90 selon le côté, cf board.gd ROTATION_BY_SLOT) : SEULE
## l'image tourne (pas le nom du joueur, ni les jetons, qui restent lisibles).
##
## Note technique : on tourne board_texture (enfant de board_wrap, un Control
## simple), PAS Row ni board_wrap eux-mêmes, car ce sont des enfants directs
## d'un Container (VBoxContainer/HBoxContainer) — Godot réinitialise
## systématiquement la rotation de ces enfants-là à chaque passe de mise en
## page. board_texture y échappe car son parent direct (board_wrap) n'est pas
## un Container.
func populate(player: Dictionary, thumb_size: Vector2 = BOARD_THUMB_SIZE, board_rotation_degrees: float = 0.0) -> void:
	_player_id = player["id"]
	name_label.text = "%s — %d pts" % [player["name"], player["points"]]
	name_label.add_theme_color_override("font_color", GameFlow.COLOR_VALUES[player["color"]])

	board_texture.texture = load(GameFlow.PLAYER_BOARD_TEXTURES.get(player["color"], GameFlow.PLAYER_BOARD_TEXTURES["jaune"]))
	board_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	board_texture.custom_minimum_size = thumb_size
	board_texture.size = thumb_size
	board_texture.pivot_offset = thumb_size / 2.0
	board_texture.rotation_degrees = board_rotation_degrees

	# À ±90°, le plateau occupe visuellement une boîte largeur/hauteur
	# inversée à l'écran : on agrandit board_wrap en conséquence, sinon son
	# clip_contents coupe l'image tournée. À 0°/180° la boîte ne change pas.
	var swapped: bool = int(round(board_rotation_degrees)) % 180 != 0
	var wrap_size: Vector2 = Vector2(thumb_size.y, thumb_size.x) if swapped else thumb_size
	board_wrap.custom_minimum_size = wrap_size
	board_wrap.size = wrap_size
	board_wrap.clip_contents = true
	board_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	board_texture.position = (wrap_size - thumb_size) / 2.0
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


func _on_board_wrap_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(_player_id)


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
