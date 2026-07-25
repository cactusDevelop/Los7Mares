extends Control

## Popup classique (fond assombri + panneau centré) qui remplace l'ancien
## système "pile de plateaux qui s'expand" : elle liste chaque joueur avec
## son jet de dés du tirage au sort du 1er joueur (règle 5.7, dé combat +
## dé exploration). Ouverte via le bouton DiceResultsButton (cf board.gd).

@onready var blocker: ColorRect = $Blocker
@onready var padding: PanelContainer = $Padding
@onready var rows_container: VBoxContainer = $Padding/Margin/Content/Rows
@onready var close_button: Button = $Padding/Margin/Content/CloseButton


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.gui_input.connect(_on_blocker_gui_input)
	close_button.pressed.connect(_close)

	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.POPUP_BG_COLOR
	style.corner_radius_top_left = UiTheme.POPUP_CORNER_RADIUS
	style.corner_radius_top_right = UiTheme.POPUP_CORNER_RADIUS
	style.corner_radius_bottom_left = UiTheme.POPUP_CORNER_RADIUS
	style.corner_radius_bottom_right = UiTheme.POPUP_CORNER_RADIUS
	padding.add_theme_stylebox_override("panel", style)


func open_popup() -> void:
	for child in rows_container.get_children():
		child.queue_free()

	for player in GameFlow.get_players_sorted_by_points():
		var label := Label.new()
		var roll_text: String = GameFlow.describe_dice_roll(player.get("dice_roll", {}))
		if roll_text == "":
			roll_text = tr("En attente du tirage...")
		label.text = "%s — %s" % [player["name"], roll_text]
		label.add_theme_color_override("font_color", GameFlow.COLOR_VALUES[player["color"]])
		rows_container.add_child(label)

	visible = true
	await get_tree().process_frame
	_center_panel()


func _center_panel() -> void:
	var viewport_size := get_viewport_rect().size
	var panel_size: Vector2 = padding.get_combined_minimum_size()
	padding.position = ((viewport_size - panel_size) / 2.0).round()
	padding.size = panel_size


func _on_blocker_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _close() -> void:
	visible = false
