extends PopupPanel

signal player_confirmed(player_name: String, color: String)

@onready var content: VBoxContainer = $Content
@onready var name_input: LineEdit = $Content/NameInput
@onready var color_row: HBoxContainer = $Content/ColorRow
@onready var confirm_button: Button = $Content/ConfirmButton
@onready var error_label: Label = $Content/ErrorLabel

var _selected_color: String = ""
var _color_buttons: Dictionary = {}
var _color_group := ButtonGroup.new()


func _ready() -> void:
	visible = false
	exclusive = true

	var color_buttons := color_row.get_children()
	for i in range(GameFlow.COLORS.size()):
		var color_name: String = GameFlow.COLORS[i]
		var btn: Button = color_buttons[i]
		btn.custom_minimum_size = Vector2(48, 48)
		btn.toggle_mode = true
		btn.button_group = _color_group
		btn.button_pressed = false
		btn.self_modulate = GameFlow.COLOR_VALUES[color_name]
		btn.modulate.a = 0.4  # non sélectionné = estompé
		btn.toggled.connect(_on_color_button_toggled.bind(color_name, btn))
		btn.pressed.connect(_on_color_button_pressed.bind(color_name))
		_color_buttons[color_name] = btn

	confirm_button.pressed.connect(_on_confirm_pressed)
	error_label.visible = false
	_layout_popup()


func open_for_new_player() -> void:
	name_input.text = ""
	_selected_color = ""
	for color_name in _color_buttons:
		var btn: Button = _color_buttons[color_name]
		btn.button_pressed = false
		btn.modulate.a = 0.4
	error_label.visible = false
	_layout_popup()
	popup_centered()


func _layout_popup() -> void:
	# Un PopupPanel (Window) ne s'ajuste pas tout seul à son contenu :
	# on force sa taille et celle du container interne.
	content.position = Vector2.ZERO
	var min_size: Vector2 = content.get_combined_minimum_size()
	min_size.x = max(min_size.x, 360)
	min_size.y = max(min_size.y, 300)
	content.size = min_size
	size = min_size


func _on_color_button_toggled(is_pressed: bool, color_name: String, btn: Button) -> void:
	btn.modulate.a = 1.0 if is_pressed else 0.4


func _on_color_button_pressed(color_name: String) -> void:
	_selected_color = color_name


func _on_confirm_pressed() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		_show_error("Entre un nom.")
		return
	if _selected_color.is_empty():
		_show_error("Choisis une couleur.")
		return
	if GameFlow.is_color_taken(_selected_color):
		_show_error("Cette couleur est déjà prise.")
		return
	error_label.visible = false
	player_confirmed.emit(player_name, _selected_color)
	hide()


func _show_error(message: String) -> void:
	error_label.text = message
	error_label.visible = true
