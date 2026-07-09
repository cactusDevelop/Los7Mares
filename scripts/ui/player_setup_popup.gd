extends Control

signal player_confirmed(player_name: String, color: String)

const TAKEN_COLOR := Color(0.45, 0.45, 0.45)
const SELECTED_BORDER := Color(1.0, 1.0, 1.0)
const PADDING := 24.0

@onready var blocker: ColorRect = $Blocker
@onready var padding_container: MarginContainer = $Padding
@onready var content: VBoxContainer = $Padding/Content
@onready var name_input: LineEdit = $Padding/Content/NameInput
@onready var color_row: HBoxContainer = $Padding/Content/ColorRow
@onready var confirm_button: Button = $Padding/Content/ConfirmButton
@onready var error_label: Label = $Padding/Content/ErrorLabel
@onready var title_label: Label = $Padding/Content/TitleLabel

var _selected_color: String = ""
var _color_buttons: Dictionary = {}
var _color_group := ButtonGroup.new()


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.color = Color(0, 0, 0, 0.5)

	var color_buttons := color_row.get_children()
	for i in range(GameFlow.COLORS.size()):
		var color_name: String = GameFlow.COLORS[i]
		var btn: Button = color_buttons[i]
		btn.custom_minimum_size = Vector2(48, 48)
		btn.toggle_mode = true
		btn.button_group = _color_group
		btn.text = ""
		btn.toggled.connect(_on_color_button_toggled.bind(color_name))
		btn.pressed.connect(_on_color_button_pressed.bind(color_name))
		_color_buttons[color_name] = btn

	confirm_button.pressed.connect(_on_confirm_pressed)
	name_input.text_submitted.connect(_on_name_submitted)
	error_label.visible = false


func open_for_new_player(player_number: int = 0, total_players: int = 0) -> void:
	name_input.text = ""
	_selected_color = ""
	for color_name in _color_buttons:
		var btn: Button = _color_buttons[color_name]
		btn.button_pressed = false
		btn.disabled = GameFlow.is_color_taken(color_name)
		_apply_button_style(btn, color_name, false)
	error_label.visible = false

	if total_players > 0:
		title_label.text = "JOUEUR %d / %d — CHOISIS UN NOM ET UNE COULEUR" % [player_number, total_players]
	else:
		title_label.text = "CHOISIS LE NOM DE TON EQUIPAGE ET LA COULEUR DE TA VOILE"

	_layout_popup()
	visible = true
	name_input.grab_focus()


func _layout_popup() -> void:
	var viewport_size := get_viewport_rect().size

	blocker.position = Vector2.ZERO
	blocker.size = viewport_size

	var min_size: Vector2 = padding_container.get_combined_minimum_size()
	min_size.x = max(min_size.x, 360 + PADDING * 2)
	min_size.y = max(min_size.y, 300 + PADDING * 2)
	padding_container.size = min_size
	padding_container.position = (viewport_size - min_size) / 2.0


func _apply_button_style(btn: Button, color_name: String, is_selected: bool) -> void:
	var base_color: Color = TAKEN_COLOR if GameFlow.is_color_taken(color_name) else GameFlow.COLOR_VALUES[color_name]

	var style := StyleBoxFlat.new()
	style.bg_color = base_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	if is_selected:
		style.border_width_left = 4
		style.border_width_top = 4
		style.border_width_right = 4
		style.border_width_bottom = 4
		style.border_color = SELECTED_BORDER

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("disabled", style)


func _on_color_button_toggled(is_pressed: bool, color_name: String) -> void:
	_apply_button_style(_color_buttons[color_name], color_name, is_pressed)


func _on_color_button_pressed(color_name: String) -> void:
	_selected_color = color_name


func _on_name_submitted(_text: String) -> void:
	_on_confirm_pressed()


func _on_confirm_pressed() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		_show_error("Entre un nom.")
		return
	if GameFlow.is_name_taken(player_name):
		_show_error("Ce nom est déjà pris.")
		return
	if _selected_color.is_empty():
		_show_error("Choisis une couleur.")
		return
	if GameFlow.is_color_taken(_selected_color):
		_show_error("Cette couleur est déjà prise.")
		return
	error_label.visible = false
	player_confirmed.emit(player_name, _selected_color)


func _show_error(message: String) -> void:
	error_label.text = message
	error_label.visible = true
