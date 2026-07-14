extends VBoxContainer
@onready var name_label: Label = $NameLabel
@onready var board_texture: TextureRect = $Row/BoardWrap/BoardTexture
@onready var tokens_container: HBoxContainer = $Row/TokensContainer

func populate(player: Dictionary) -> void:
	name_label.text = "%s — %d pts" % [player["name"], player["points"]]
	name_label.add_theme_color_override("font_color", GameFlow.COLOR_VALUES[player["color"]])
	board_texture.texture = load(GameFlow.PLAYER_BOARD_TEXTURES[player["color"]])
	# ajout des jetons perroquet/marqueur dans tokens_container
