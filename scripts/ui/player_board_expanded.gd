extends Control

@onready var blocker: ColorRect = $Blocker
@onready var padding: MarginContainer = $Padding
@onready var title_label: Label = $Padding/Content/TitleLabel
@onready var board_texture: TextureRect = $Padding/Content/BoardTexture
@onready var resources_grid: GridContainer = $Padding/Content/ResourcesGrid
@onready var close_button: Button = $Padding/Content/CloseButton


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.color = Color(0, 0, 0, 0.7)
	board_texture.custom_minimum_size = Vector2(640, 427)
	board_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	close_button.pressed.connect(func(): visible = false)


func show_player(player: Dictionary) -> void:
	title_label.text = player["name"]
	title_label.add_theme_color_override("font_color", GameFlow.COLOR_VALUES[player["color"]])
	board_texture.texture = load(GameFlow.PLAYER_BOARD_TEXTURE)

	for child in resources_grid.get_children():
		child.queue_free()
	for res_type in GameFlow.RESOURCE_TYPES + GameFlow.SPECIAL_RESOURCE_TYPES:
		var label := Label.new()
		label.text = GameFlow.RESOURCE_LABELS.get(res_type, res_type)
		resources_grid.add_child(label)
		var value_label := Label.new()
		var value: int = player["resources"].get(res_type, player["special_resources"].get(res_type, 0))
		value_label.text = str(value)
		resources_grid.add_child(value_label)

	var viewport_size := get_viewport_rect().size
	blocker.size = viewport_size
	var min_size: Vector2 = padding.get_combined_minimum_size()
	min_size.x = max(min_size.x, 700)
	padding.size = min_size
	padding.position = (viewport_size - min_size) / 2.0
	visible = true
