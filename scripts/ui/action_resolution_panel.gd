extends Control

## Panneau générique de choix utilisé par action_resolution_phase.gd : un
## titre + une liste de boutons dont le contenu change à chaque étape
## (ordre des actions, faire/décliner, nourriture/fortune, destinations de
## déplacement...). Construit entièrement en code, comme piece_selection_panel.gd.

signal option_selected(id: String)

const PANEL_WIDTH := 420.0
const BUTTON_HEIGHT := 56.0
const BUTTON_FONT_SIZE := 20

var background: PanelContainer
var box: VBoxContainer
var title_label: Label
var buttons_box: VBoxContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	background = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.POPUP_BG_COLOR
	style.set_corner_radius_all(UiTheme.POPUP_CORNER_RADIUS)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	background.add_theme_stylebox_override("panel", style)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)

	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	background.add_child(box)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	title_label.custom_minimum_size = Vector2(PANEL_WIDTH - 48, 0)
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title_label)

	buttons_box = VBoxContainer.new()
	buttons_box.add_theme_constant_override("separation", 10)
	box.add_child(buttons_box)

	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	background.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	size = Vector2(PANEL_WIDTH, background.size.y)
	position = Vector2((viewport_size.x - PANEL_WIDTH) / 2.0, viewport_size.y - background.size.y - 40.0)


## options: Array[{"id": String, "label": String}]
func set_title(text: String) -> void:
	title_label.text = text


func set_options(options: Array) -> void:
	for child in buttons_box.get_children():
		child.queue_free()
	for option in options:
		var btn := Button.new()
		btn.text = option["label"]
		btn.custom_minimum_size = Vector2(PANEL_WIDTH - 48, BUTTON_HEIGHT)
		btn.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
		btn.pressed.connect(_on_button_pressed.bind(option["id"]))
		buttons_box.add_child(btn)
	call_deferred("_layout")


func _on_button_pressed(id: String) -> void:
	option_selected.emit(id)


func show_panel() -> void:
	_layout()
	visible = true


func hide_panel() -> void:
	visible = false
