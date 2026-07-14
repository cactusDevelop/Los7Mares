extends VBoxContainer
@onready var name_label: Label = $NameLabel
@onready var board_texture: TextureRect = $Row/BoardWrap/BoardTexture
@onready var tokens_container: HBoxContainer = $Row/TokensContainer

const BOARD_THUMB_SIZE := Vector2(160, 107)


func populate(player: Dictionary) -> void:
	name_label.text = "%s — %d pts" % [player["name"], player["points"]]
	name_label.add_theme_color_override("font_color", GameFlow.COLOR_VALUES[player["color"]])

	board_texture.texture = load(GameFlow.PLAYER_BOARD_TEXTURES.get(player["color"], GameFlow.PLAYER_BOARD_TEXTURES["jaune"]))
	board_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	board_texture.custom_minimum_size = BOARD_THUMB_SIZE

	for child in tokens_container.get_children():
		child.queue_free()

	if player.get("has_own_parrot", true):
		tokens_container.add_child(_build_parrot_token(player["color"], false))
	for other in GameFlow.players:
		if other.get("parrot_captured_by", -1) == player["id"]:
			tokens_container.add_child(_build_parrot_token(other["color"], true))
	if player.get("is_first_player", false):
		tokens_container.add_child(_build_marker_token())


func _build_parrot_token(color_name: String, imprisoned: bool) -> Control:
	var texture_rect := TextureRect.new()
	var path_template: String = GameFlow.PARROT_TEXTURE_PATH_PRISON if imprisoned else GameFlow.PARROT_TEXTURE_PATH
	texture_rect.texture = load(path_template % color_name)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.custom_minimum_size = Vector2(40, 40)
	return texture_rect


func _build_marker_token() -> Control:
	var texture_rect := TextureRect.new()
	texture_rect.texture = load(GameFlow.MARKER_TEXTURE_PATH)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.custom_minimum_size = Vector2(40, 40)
	return texture_rect
