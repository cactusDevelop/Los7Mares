extends VBoxContainer
signal pressed(player_id: int)

@onready var name_label: Label = $NameLabel
@onready var row: BoxContainer = $Row
@onready var board_wrap: Control = $Row/BoardWrap
@onready var board_texture: TextureRect = $Row/BoardWrap/BoardTexture
@onready var tokens_wrap: Control = $Row/TokensWrap
@onready var tokens_container: HBoxContainer = $Row/TokensWrap/TokensContainer

const BOARD_THUMB_SIZE := Vector2(160, 107)
const TOKEN_BASE_SIZE := Vector2(40, 40)

var _player_id: int = -1


## thumb_size permet d'afficher ce plateau plus grand que les autres (le
## joueur actif, en bas de l'écran, cf board.gd _layout_player_boards).
## board_rotation_degrees fait pointer le "haut" du plateau vers le centre de
## l'écran (0/90/180/-90 selon le côté, cf board.gd ROTATION_BY_SLOT) : le
## plateau ET les jetons (perroquets, marqueur doré) tournent ensemble du
## même angle. Seul le nom du joueur reste toujours droit.
##
## Note technique : on tourne board_texture (enfant de board_wrap) et
## tokens_container (enfant de tokens_wrap), PAS Row, board_wrap ni
## tokens_wrap eux-mêmes, car Row est un Container (BoxContainer) — Godot
## réinitialise systématiquement la rotation des enfants directs d'un
## Container à chaque passe de mise en page. board_texture/tokens_container y
## échappent car leur parent direct (board_wrap/tokens_wrap) est un Control
## simple, pas un Container.
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
	_layout_row_direction(board_rotation_degrees)

	# À ±90°, le plateau occupe visuellement une boîte largeur/hauteur
	# inversée à l'écran : on agrandit board_wrap en conséquence, sinon son
	# clip_contents coupe l'image tournée. À 0°/180° la boîte ne change pas.
	var swapped: bool = int(round(board_rotation_degrees)) % 180 != 0
	var wrap_size: Vector2 = Vector2(thumb_size.y, thumb_size.x) if swapped else thumb_size
	board_wrap.custom_minimum_size = wrap_size
	board_wrap.size = wrap_size
	board_wrap.clip_contents = true
	board_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	board_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	board_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tokens_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tokens_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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

	# Les jetons tournent avec le plateau (même angle), pour la même raison
	# que board_texture : tokens_container est un enfant de tokens_wrap (un
	# Control simple, pas un Container), donc sa rotation n'est pas
	# réinitialisée par une passe de layout.
	var tokens_min: Vector2 = tokens_container.get_combined_minimum_size()
	tokens_container.size = tokens_min
	tokens_container.pivot_offset = tokens_min / 2.0
	tokens_container.rotation_degrees = board_rotation_degrees

	var tokens_wrap_size: Vector2 = Vector2(tokens_min.y, tokens_min.x) if swapped else tokens_min
	tokens_wrap.custom_minimum_size = tokens_wrap_size
	tokens_wrap.size = tokens_wrap_size
	tokens_wrap.clip_contents = true
	tokens_container.position = (tokens_wrap_size - tokens_min) / 2.0


## Oriente Row (BoxContainer) et l'ordre de BoardWrap/TokensContainer pour
## que perroquets + marqueur doré restent "à droite du plateau" dans le
## repère de RÉFÉRENCE du plateau (non tourné), même quand l'image affichée
## est tournée (cf ROTATION_BY_SLOT dans board.gd : slot "left" = 90°,
## "right" = -90°, "top" = 180°, "bottom" = 0°).
## Une direction "à droite" tournée du même angle que le plateau donne :
## à droite à 0° (bas), en dessous à 90° (gauche), au-dessus à -90° (droite),
## à gauche à 180° (haut). Ici on ne fait que choisir l'axe (vertical/
## horizontal) et l'ordre des deux enfants de Row ; la rotation des jetons
## eux-mêmes est gérée plus haut dans populate().
func _layout_row_direction(board_rotation_degrees: float) -> void:
	var angle: int = int(round(board_rotation_degrees)) % 360
	if angle < 0:
		angle += 360
	match angle:
		90: # slot "left" : jetons en dessous du plateau
			row.vertical = true
			row.move_child(board_wrap, 0)
		270: # slot "right" (-90°) : jetons au-dessus du plateau
			row.vertical = true
			row.move_child(tokens_wrap, 0)
		180: # slot "top" : jetons à gauche du plateau
			row.vertical = false
			row.move_child(tokens_wrap, 0)
		_: # 0°, slot "bottom" : jetons à droite du plateau
			row.vertical = false
			row.move_child(board_wrap, 0)


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
